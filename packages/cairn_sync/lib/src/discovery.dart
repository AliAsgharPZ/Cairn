import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A Cairn peer seen on the local network via UDP broadcast
/// discovery. Reachability only — trust still comes from pairing
/// keys, never from discovery.
class DiscoveredPeer {
  const DiscoveredPeer({
    required this.deviceId,
    required this.displayName,
    required this.ip,
    required this.syncPort,
    required this.overflowPort,
    required this.lastSeen,
  });

  final String deviceId;
  final String displayName;
  final String ip;
  final int syncPort;
  final int overflowPort;
  final DateTime lastSeen;

  String get syncEndpoint => '$ip:$syncPort';
}

/// Peer discovery on the local network (UDP broadcast, port 47802).
///
/// Every running Cairn broadcasts a small JSON announcement every
/// few seconds and answers probes immediately, so a device that just
/// opened the app sees the others within seconds — no typing IP
/// addresses, no copy-pasting pairing codes. Announcements carry no
/// secrets (device id + name + ports); pairing still requires the
/// SAS-confirmed handshake in `pairing_link.dart`.
class PeerDiscovery {
  PeerDiscovery({
    required this.deviceId,
    required this.displayName,
    this.syncPort = 47800,
    this.overflowPort = 47801,
    this.port = 47802,
    this.announceEvery = const Duration(seconds: 3),
    this.peerTimeout = const Duration(seconds: 12),
  });

  final String deviceId;
  String displayName;
  final int syncPort;
  final int overflowPort;
  final int port;
  final Duration announceEvery;
  final Duration peerTimeout;

  RawDatagramSocket? _socket;
  Timer? _timer;
  final Map<String, DiscoveredPeer> _peers = {};
  final StreamController<List<DiscoveredPeer>> _changes =
      StreamController<List<DiscoveredPeer>>.broadcast();

  /// Extra unicast targets (loopback in tests; production uses
  /// broadcast plus re-announces to already-seen peers).
  final List<InternetAddress> extraTargets = [];

  /// Extra destination ports announcements/probes are also sent to.
  /// Production uses the single standard port; tests put two
  /// instances on ONE host, where two sockets sharing a port would
  /// load-balance datagrams between them instead of both receiving.
  final List<int> extraPorts = [];

  List<int> get _targetPorts => [port, ...extraPorts];

  List<DiscoveredPeer> get peers {
    final now = DateTime.now();
    return _peers.values
        .where((p) => now.difference(p.lastSeen) < peerTimeout)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  Stream<List<DiscoveredPeer>> get onPeersChanged => _changes.stream;

  Map<String, Object?> _announcement(String kind) => {
        'v': 1,
        'kind': kind,
        'deviceId': deviceId,
        'name': displayName,
        'syncPort': syncPort,
        'overflowPort': overflowPort,
      };

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: true,
    );
    socket.broadcastEnabled = true;
    _socket = socket;
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        _handle(dg);
      },
      // Send/receive errors (e.g. a sandbox or OS refusing broadcast)
      // surface on this stream; discovery must degrade silently,
      // never crash the app with an uncaught socket error.
      onError: (Object _) {},
    );
    _announce();
    _timer = Timer.periodic(announceEvery, (_) {
      _announce();
      _prune();
    });
  }

  void _handle(Datagram dg) => handlePacket(dg.data, dg.address);

  /// Packet processing, separated from the socket so the discovery
  /// LOGIC is unit-testable even where UDP itself is unavailable
  /// (the build sandbox drops UDP entirely; CI runners do not).
  void handlePacket(List<int> data, InternetAddress from) {
    Map<String, Object?> json;
    try {
      json = (jsonDecode(utf8.decode(data)) as Map).cast<String, Object?>();
    } catch (_) {
      return; // not a Cairn announcement — ignore
    }
    if (json['v'] != 1) return;
    final kind = json['kind'] as String? ?? '';
    final fromId = json['deviceId'] as String? ?? '';
    if (fromId.isEmpty || fromId == deviceId) return;
    if (kind == 'probe') {
      _announce(to: from);
      return;
    }
    if (kind != 'announce') return;
    final peer = DiscoveredPeer(
      deviceId: fromId,
      displayName: json['name'] as String? ?? '',
      ip: from.address,
      syncPort: (json['syncPort'] as num?)?.toInt() ?? 47800,
      overflowPort: (json['overflowPort'] as num?)?.toInt() ?? 47801,
      lastSeen: DateTime.now(),
    );
    final changed = _peers[fromId]?.ip != peer.ip ||
        _peers[fromId]?.displayName != peer.displayName;
    _peers[fromId] = peer;
    if (changed) _changes.add(peers);
  }

  void _announce({InternetAddress? to}) {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(jsonEncode(_announcement('announce')));
    final targets = <InternetAddress>[
      if (to != null) to,
      InternetAddress('255.255.255.255'),
      ...extraTargets,
      for (final p in _peers.values) InternetAddress(p.ip),
    ];
    for (final target in targets) {
      for (final p in _targetPorts) {
        try {
          socket.send(data, target, p);
        } catch (_) {
          // A dead target must never kill discovery.
        }
      }
    }
  }

  /// Ask the network "who is out there?" — peers answer at once
  /// instead of waiting for their next periodic announcement.
  void probe() {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(jsonEncode(_announcement('probe')));
    try {
      for (final p in _targetPorts) {
        socket.send(data, InternetAddress('255.255.255.255'), p);
        for (final t in extraTargets) {
          socket.send(data, t, p);
        }
      }
    } catch (_) {}
  }

  void _prune() {
    final before = _peers.length;
    final now = DateTime.now();
    _peers.removeWhere((_, p) => now.difference(p.lastSeen) >= peerTimeout);
    if (_peers.length != before) _changes.add(peers);
  }

  Future<void> close() async {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
    await _changes.close();
  }
}
