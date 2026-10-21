import 'dart:async';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';

import 'identity.dart';
import 'pairing.dart';
import 'session.dart';

/// TCP transport for sync sessions. The same session runs over a LAN
/// socket at home or a Tailscale address away from home — the session
/// authenticates by long-term key, so the network itself needs no
/// trust and no TLS is required for integrity of identity (payloads
/// are the user's own project data on their own devices/networks).

/// Listens for sync sessions from paired devices.
class SyncServer {
  ServerSocket? _server;

  /// The actual bound port (meaningful after [start], e.g. when 0 was
  /// requested for an ephemeral port).
  int get port => _server?.port ?? 0;

  Future<void> start({
    required DeviceKeyPair local,
    required List<PairedDevice> allowedPeers,
    required Future<List<SyncRecord>> Function() loadRecords,
    required Future<void> Function(SyncSessionResult result) onSync,
    int port = 47800,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((socket) async {
      try {
        final records = await loadRecords();
        final session = SyncSession(
          local: local,
          allowedPeers: allowedPeers,
          localRecords: records,
        );
        final result = await session.run(socket, socket);
        await onSync(result);
      } catch (_) {
        // Unpaired or unauthenticated connection: drop it quietly.
        socket.destroy();
      }
    });
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
  }
}

/// Connects to a paired device and runs one sync session with it.
Future<SyncSessionResult> syncWithPeer({
  required String host,
  required int port,
  required DeviceKeyPair local,
  required PairedDevice peer,
  required List<SyncRecord> localRecords,
}) async {
  final socket = await Socket.connect(host, port);
  final session = SyncSession(
    local: local,
    allowedPeers: [peer],
    localRecords: localRecords,
  );
  return session.run(socket, socket);
}
