import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'framing.dart';
import 'identity.dart';
import 'pairing.dart';

// Overflow execution protocol (M8): a paired device may invoke tools
// on this device — one step at a time — after the same mutual-auth
// handshake as sync (key-signed nonces, paired devices only).
//
// DESTINATION-SIDE RE-VALIDATION (a hard design rule): the executing
// device never trusts the caller's claim that a call is allowed. The
// tool must be in this device's remote-allowlist, and sensitive tools
// are refused for remote execution unless this device's owner
// explicitly enabled them. The caller gets a plain error result —
// never a silent execution.

const String _authLabel = 'cairn-overflow-auth-v1';

/// One tool execution outcome, as exchanged on the wire.
class OverflowToolReply {
  const OverflowToolReply({required this.ok, required this.output});

  final bool ok;
  final String output;
}

/// Executes one allowed tool invocation locally (wired by the app to
/// its ToolRegistry).
typedef OverflowToolHandler = Future<OverflowToolReply> Function(
    String toolId, Map<String, Object?> arguments);

Future<void> _handshake({
  required DeviceKeyPair local,
  required List<PairedDevice> allowedPeers,
  required StreamIterator<Map<String, Object?>> iterator,
  required void Function(Map<String, Object?> message) send,
  required bool initiator,
}) async {
  Future<Map<String, Object?>> next(String what) async {
    if (!await iterator.moveNext()) {
      throw StateError('overflow session closed while waiting for $what');
    }
    return iterator.current;
  }

  final myNonce = secureRandomBytes(16);
  send({
    'type': 'hello',
    'deviceId': local.deviceId,
    'nonce': base64Encode(myNonce),
  });
  final hello = await next('hello');
  PairedDevice? peer;
  for (final candidate in allowedPeers) {
    if (candidate.identity.deviceId == hello['deviceId']) {
      peer = candidate;
      break;
    }
  }
  if (hello['type'] != 'hello' || peer == null) {
    throw StateError(
        'overflow authentication failed: unpaired peer ${hello['deviceId']}');
  }
  final peerNonce = base64Decode(hello['nonce'] as String);
  final signature = await local.sign([
    ...utf8.encode(_authLabel),
    ...peerNonce,
    ...utf8.encode(local.deviceId),
  ]);
  send({'type': 'auth', 'signature': base64Encode(signature)});
  final auth = await next('auth');
  if (auth['type'] != 'auth') {
    throw StateError('overflow authentication failed: expected auth');
  }
  final ok = await DeviceKeyPair.verify(
    peer.identity.publicKeyBytes,
    [
      ...utf8.encode(_authLabel),
      ...myNonce,
      ...utf8.encode(peer.identity.deviceId),
    ],
    base64Decode(auth['signature'] as String),
  );
  if (!ok) {
    throw StateError(
        'overflow authentication failed: peer could not prove its key');
  }
}

/// The executing (server) side of one overflow connection.
class OverflowServerSession {
  OverflowServerSession({
    required this.local,
    required this.allowedPeers,
    required this.allowedToolIds,
    required this.sensitiveToolIds,
    required this.handler,
    this.allowSensitiveRemote = false,
  });

  final DeviceKeyPair local;
  final List<PairedDevice> allowedPeers;

  /// Tools this device offers for remote execution at all.
  final Set<String> allowedToolIds;

  /// Subset of tools considered sensitive (refused remotely unless
  /// [allowSensitiveRemote] is enabled by this device's owner).
  final Set<String> sensitiveToolIds;
  final bool allowSensitiveRemote;
  final OverflowToolHandler handler;

  Future<void> run(
    Stream<List<int>> incoming,
    StreamSink<List<int>> outgoing,
  ) async {
    final iterator = StreamIterator(decodeFrames(incoming));
    void send(Map<String, Object?> message) =>
        outgoing.add(frameMessage(message));
    try {
      await _handshake(
        local: local,
        allowedPeers: allowedPeers,
        iterator: iterator,
        send: send,
        initiator: false,
      );
      // Invocation loop until the peer disconnects.
      while (await iterator.moveNext()) {
        final message = iterator.current;
        if (message['type'] != 'invoke') continue;
        final callId = message['callId'];
        final toolId = message['toolId'] as String;
        final arguments =
            (message['arguments'] as Map?)?.cast<String, Object?>() ?? {};
        final OverflowToolReply reply;
        if (!allowedToolIds.contains(toolId)) {
          reply = OverflowToolReply(
              ok: false,
              output: 'tool $toolId is not offered for remote execution '
                  'on this device');
        } else if (sensitiveToolIds.contains(toolId) &&
            !allowSensitiveRemote) {
          reply = OverflowToolReply(
              ok: false,
              output: 'tool $toolId is sensitive and remote execution of '
                  'sensitive tools is disabled on this device');
        } else {
          reply = await handler(toolId, arguments);
        }
        send({
          'type': 'result',
          'callId': callId,
          'ok': reply.ok,
          'output': reply.output,
        });
      }
    } finally {
      await iterator.cancel();
      await outgoing.close();
    }
  }
}

/// The calling (client) side of one overflow connection.
class OverflowClient {
  OverflowClient._(this._iterator, this._send);

  final StreamIterator<Map<String, Object?>> _iterator;
  final void Function(Map<String, Object?> message) _send;
  var _nextCallId = 1;

  static Future<OverflowClient> connect(
    Stream<List<int>> incoming,
    StreamSink<List<int>> outgoing, {
    required DeviceKeyPair local,
    required PairedDevice peer,
  }) async {
    final iterator = StreamIterator(decodeFrames(incoming));
    void send(Map<String, Object?> message) =>
        outgoing.add(frameMessage(message));
    await _handshake(
      local: local,
      allowedPeers: [peer],
      iterator: iterator,
      send: send,
      initiator: true,
    );
    return OverflowClient._(iterator, send);
  }

  /// Invokes [toolId] on the peer. A refusal by the peer's policy is a
  /// normal (ok == false) reply, not an exception.
  Future<OverflowToolReply> invoke(
      String toolId, Map<String, Object?> arguments) async {
    final callId = _nextCallId++;
    _send({
      'type': 'invoke',
      'callId': callId,
      'toolId': toolId,
      'arguments': arguments,
    });
    if (!await _iterator.moveNext()) {
      throw StateError('overflow session closed during invoke $toolId');
    }
    final message = _iterator.current;
    if (message['type'] != 'result' || message['callId'] != callId) {
      throw StateError('overflow protocol error: unexpected reply');
    }
    return OverflowToolReply(
      ok: message['ok'] as bool,
      output: message['output'] as String? ?? '',
    );
  }

  Future<void> close() => _iterator.cancel();
}

/// TCP listener for overflow sessions (LAN / Tailscale), mirroring the
/// sync server. Policy and handler come from the hosting app.
class OverflowServer {
  ServerSocket? _server;

  int get port => _server?.port ?? 0;

  Future<void> start({
    required DeviceKeyPair local,
    required List<PairedDevice> allowedPeers,
    required Set<String> allowedToolIds,
    required Set<String> sensitiveToolIds,
    required OverflowToolHandler handler,
    bool allowSensitiveRemote = false,
    int port = 47801,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((socket) async {
      final session = OverflowServerSession(
        local: local,
        allowedPeers: allowedPeers,
        allowedToolIds: allowedToolIds,
        sensitiveToolIds: sensitiveToolIds,
        handler: handler,
        allowSensitiveRemote: allowSensitiveRemote,
      );
      try {
        await session.run(socket, socket);
      } catch (_) {
        socket.destroy();
      }
    });
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
  }
}

/// Connects an [OverflowClient] to a peer's overflow server.
Future<OverflowClient> connectOverflow({
  required String host,
  required int port,
  required DeviceKeyPair local,
  required PairedDevice peer,
}) async {
  final socket = await Socket.connect(host, port);
  return OverflowClient.connect(socket, socket, local: local, peer: peer);
}
