import 'dart:io';

/// Network presence detection, done honestly (v1.3 fix).
///
/// v1.2 counted ANY non-loopback IPv4 as "connected to a local
/// network" — including the CELLULAR interface (Android rmnet with a
/// 10.x CGNAT address). With Wi-Fi off and mobile data on, the app
/// cheerfully reported "connected to a local network" and showed a
/// cellular address as "your LAN address". The owner, standing there
/// connected to nothing, was right to call it broken.
///
/// The fix classifies every interface by name + address:
///  * [IfaceKind.lan] — Wi-Fi / Ethernet: a real local network where
///    discovery and pairing can reach the owner's other devices.
///  * [IfaceKind.cellular] — mobile data: internet, but NO local
///    network; other devices are not reachable through it.
///  * [IfaceKind.vpn] — Tailscale/WireGuard-style tunnels: reachable
///    peers, reported separately.
///  * [IfaceKind.other] — unrecognized (e.g. Windows GUID names):
///    counts as LAN only with a private address (desktop default).

enum IfaceKind { lan, cellular, vpn, other }

/// One address on one interface, classified.
class NetAddress {
  const NetAddress(this.ip, this.interfaceName, this.kind);

  final String ip;
  final String interfaceName;
  final IfaceKind kind;

  @override
  String toString() => '$ip ($interfaceName, ${kind.name})';
}

/// The device's overall local-network state.
enum LanState {
  /// No usable address at all.
  offline,

  /// Internet via mobile data only — no local network, so no
  /// discovery/pairing/sync with the owner's other devices.
  cellularOnly,

  /// A real local network (Wi-Fi/Ethernet, or a VPN tunnel) exists.
  lan,
}

/// Classifies an interface by its OS name. Pure and unit-tested —
/// this function is where "mobile data is not a LAN" is decided.
IfaceKind classifyInterfaceName(String name) {
  final n = name.toLowerCase();
  if (n.contains('rmnet') ||
      n.contains('ccmni') ||
      n.contains('pdp_ip') ||
      n.contains('wwan') ||
      n.contains('cellular') ||
      n.contains('mobile') ||
      n.startsWith('lte') ||
      n.contains('nr5g')) {
    return IfaceKind.cellular;
  }
  if (n.startsWith('tun') ||
      n.startsWith('tap') ||
      n.startsWith('wg') ||
      n.startsWith('utun') ||
      n.contains('tailscale') ||
      n.contains('wireguard') ||
      n.contains('vpn')) {
    return IfaceKind.vpn;
  }
  if (n.contains('wlan') ||
      n.contains('wifi') ||
      n.contains('wi-fi') ||
      n.contains('ethernet') ||
      n.startsWith('eth') ||
      n.startsWith('en') ||
      n.contains('local area')) {
    return IfaceKind.lan;
  }
  return IfaceKind.other;
}

bool _isPrivate(String ip) {
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!, b = parts[1]!;
  return a == 192 && b == 168 ||
      a == 10 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 100 && b >= 64 && b <= 127); // Tailscale CGNAT
}

bool _isLinkLocal(String ip) => ip.startsWith('169.254.');

/// Every classified non-loopback IPv4 address of this device.
Future<List<NetAddress>> classifiedAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: true,
  );
  return [
    for (final iface in interfaces)
      for (final addr in iface.addresses)
        if (!addr.isLoopback)
          NetAddress(
              addr.address, iface.name, classifyInterfaceName(iface.name)),
  ];
}

bool _isTailscaleRange(String ip) {
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  return parts[0] == 100 && parts[1]! >= 64 && parts[1]! <= 127;
}

/// Does an address put the device on a reachable local network?
///
/// v1.3.1 tightening, from the owner's second report ("connected to
/// nothing, still says connected"): a generic VPN tunnel (tun0 from
/// any VPN app) is NOT the owner's local network and no longer counts
/// on its own — only a Tailscale-style mesh address (100.64.0.0/10)
/// does, because those addresses name the owner's own devices.
bool isLanUsable(NetAddress a) {
  if (_isLinkLocal(a.ip)) return false; // no DHCP — half-broken
  return switch (a.kind) {
    IfaceKind.lan => true,
    IfaceKind.vpn => _isTailscaleRange(a.ip),
    IfaceKind.other => _isPrivate(a.ip),
    IfaceKind.cellular => false,
  };
}

/// The device's LAN state: offline / cellular-only / on a LAN.
Future<LanState> lanState() async {
  final all = await classifiedAddresses();
  if (all.any(isLanUsable)) return LanState.lan;
  if (all.any((a) => a.kind == IfaceKind.cellular && !_isLinkLocal(a.ip))) {
    return LanState.cellularOnly;
  }
  return LanState.offline;
}

/// LAN-usable IPv4 addresses (Wi-Fi/Ethernet/VPN only — NEVER the
/// cellular interface), best first. Empty means "not on a local
/// network", whatever mobile data says.
Future<List<String>> lanIpv4Addresses() async {
  final usable = [
    for (final a in await classifiedAddresses())
      if (isLanUsable(a)) a,
  ];
  usable.sort((a, b) => _rank(a).compareTo(_rank(b)));
  return [for (final a in usable) a.ip];
}

int _rank(NetAddress a) {
  final ip = a.ip;
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return 9;
  final x = parts[0]!, y = parts[1]!;
  var base = 5;
  if (x == 192 && y == 168) base = 0;
  if (x == 10) base = 1;
  if (x == 172 && y >= 16 && y <= 31) base = 2;
  if (x == 100 && y >= 64 && y <= 127) base = 3; // Tailscale
  if (a.kind == IfaceKind.vpn) base += 1; // prefer the physical LAN
  return base;
}

/// True when the device is on a real local network.
Future<bool> hasLanAddress() async => (await lanState()) == LanState.lan;

/// This device's primary LAN address, or null when not on a LAN.
Future<String?> primaryLanAddress() async {
  final all = await lanIpv4Addresses();
  return all.isEmpty ? null : all.first;
}
