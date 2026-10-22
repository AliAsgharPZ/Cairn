import 'dart:async';
import 'dart:io';

import 'framing.dart';
import 'identity.dart';
import 'pairing.dart';

/// LAN pairing (port 47803): devices that discovered each other pair
/// IN the network — no copy-pasted offer codes. The trust model is
/// unchanged from the paste flow: Ed25519 identities whose ids must
/// derive from their keys, and a 6-digit SAS that BOTH screens show
/// and BOTH owners confirm (computeSas sorts the keys and uses the
/// initiator's nonce, so both sides derive the identical code).
///
/// Wire flow (framed JSON):
///   initiator → responder : {type:'offer', offer}
///   responder (owner taps "pair") → initiator : {type:'offer', offer}
///   initiator (owner confirms the SAS matches) → responder : {type:'confirm'}
///   responder → initiator : {type:'paired'} — both sides persist.
const int kPairingPort = 47803;

class PairingRejectedException implements Exception {
  const PairingRejectedException([this.message = 'the other device declined']);
  final String message;
  @override
  String toString() => 'PairingRejectedException: $message';
}

/// An incoming pairing request on the responder side. The UI shows
/// [sas] and the peer's name, then calls [accept] or [reject].
class IncomingPairing {
  IncomingPairing._({
    required this.peerName,
    required this.peerDeviceId,
    required this.sas,
    required this.peerIp,
    required Completer<bool> decision,
  }) : _decision = decision;

  final String peerName;
  final String peerDeviceId;
  final String sas;
  final String peerIp;
  final Completer<bool> _decision;

  void accept() {
    if (!_decision.isCompleted) _decision.complete(true);
  }

  void reject() {
    if (!_decision.isCompleted) _decision.complete(false);
  }
}

class LanPairingServer {
  ServerSocket? _server;
  bool _busy = false;

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  Future<void> start({
    required DeviceKeyPair local,
    required String displayName,
    required List<String> Function() localEndpoints,
    required void Function(IncomingPairing) onIncoming,
    required void Function(PairedDevice) onPaired,
    int port = kPairingPort,
  }) async {
    if (_server != null) return;
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((socket) {
      _handle(
        socket,
        local: local,
        displayName: displayName,
        localEndpoints: localEndpoints,
        onIncoming: onIncoming,
        onPaired: onPaired,
      ).catchError((_) {
        socket.destroy();
      });
    });
  }

  Future<void> _handle(
    Socket socket, {
    required DeviceKeyPair local,
    required String displayName,
    required List<String> Function() localEndpoints,
    required void Function(IncomingPairing) onIncoming,
    required void Function(PairedDevice) onPaired,
  }) async {
    final peerIp = socket.remoteAddress.address;
    final messages = decodeFrames(socket).asBroadcastStream();
    try {
      final first = await messages.first.timeout(const Duration(seconds: 30));
      if (first['type'] != 'offer' || _busy) {
        socket.add(frameMessage({'type': 'rejected', 'reason': 'busy'}));
        await socket.flush();
        await socket.close();
        return;
      }
      _busy = true;
      final offer = PairingOffer.decode(first['offer'] as String);
      final session = await PairingSession.fromOffer(local: local, offer: offer);
      final decision = Completer<bool>();
      onIncoming(IncomingPairing._(
        peerName: offer.identity.displayName,
        peerDeviceId: offer.identity.deviceId,
        sas: session.sas,
        peerIp: peerIp,
        decision: decision,
      ));
      final accepted =
          await decision.future.timeout(const Duration(seconds: 90),
              onTimeout: () => false);
      if (!accepted) {
        socket.add(frameMessage({'type': 'rejected'}));
        await socket.flush();
        await socket.close();
        return;
      }
      final myOffer = PairingOffer(
        identity: DeviceIdentity(
          deviceId: local.deviceId,
          publicKeyBytes: local.publicKeyBytes,
          displayName: displayName,
        ),
        nonce: secureRandomBytes(16),
        endpoints: localEndpoints(),
      );
      socket.add(frameMessage({'type': 'offer', 'offer': myOffer.encode()}));
      await socket.flush();
      final confirm =
          await messages.first.timeout(const Duration(seconds: 90));
      if (confirm['type'] != 'confirm') {
        await socket.close();
        return;
      }
      final paired = PairedDevice(
        identity: offer.identity,
        pairedAtIso: DateTime.now().toUtc().toIso8601String(),
        endpoints: ['$peerIp:47800'],
      );
      onPaired(paired);
      socket.add(frameMessage({'type': 'paired'}));
      await socket.flush();
      await socket.close();
    } finally {
      _busy = false;
      socket.destroy();
    }
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
  }
}

/// The initiator side of LAN pairing.
class LanPairingClient {
  /// Runs the handshake against a responder listening at [host]:[port].
  /// [confirmSas] is called with the SAS and the responder's name
  /// once its offer arrives; return true only when the owner confirms
  /// the code matches the one on the other screen.
  static Future<PairedDevice> pair({
    required String host,
    int port = kPairingPort,
    required DeviceKeyPair local,
    required String displayName,
    required List<String> localEndpoints,
    required Future<bool> Function(String sas, String peerName) confirmSas,
  }) async {
    final socket = await Socket.connect(host, port,
        timeout: const Duration(seconds: 10));
    try {
      final messages = decodeFrames(socket).asBroadcastStream();
      final nonce = secureRandomBytes(16);
      final myOffer = PairingOffer(
        identity: DeviceIdentity(
          deviceId: local.deviceId,
          publicKeyBytes: local.publicKeyBytes,
          displayName: displayName,
        ),
        nonce: nonce,
        endpoints: localEndpoints,
      );
      socket.add(frameMessage({'type': 'offer', 'offer': myOffer.encode()}));
      await socket.flush();
      final reply =
          await messages.first.timeout(const Duration(seconds: 150));
      if (reply['type'] == 'rejected') {
        throw const PairingRejectedException();
      }
      if (reply['type'] != 'offer') {
        throw const FormatException('unexpected pairing reply');
      }
      final peerOffer = PairingOffer.decode(reply['offer'] as String);
      final claimedId =
          await deviceIdForPublicKey(peerOffer.identity.publicKeyBytes);
      if (claimedId != peerOffer.identity.deviceId) {
        throw const FormatException(
            'responder device id does not match its public key');
      }
      // Same inputs the responder hashed: both keys (sorted inside
      // computeSas) + the INITIATOR's nonce (mine).
      final sas = await computeSas(
        publicKeyA: local.publicKeyBytes,
        publicKeyB: peerOffer.identity.publicKeyBytes,
        nonce: nonce,
      );
      final confirmed = await confirmSas(sas, peerOffer.identity.displayName);
      if (!confirmed) {
        socket.add(frameMessage({'type': 'abort'}));
        await socket.flush();
        throw const PairingRejectedException('cancelled by the owner');
      }
      socket.add(frameMessage({'type': 'confirm'}));
      await socket.flush();
      final done = await messages.first.timeout(const Duration(seconds: 30));
      if (done['type'] != 'paired') {
        throw const FormatException('pairing did not complete');
      }
      return PairedDevice(
        identity: peerOffer.identity,
        pairedAtIso: DateTime.now().toUtc().toIso8601String(),
        endpoints: ['$host:47800'],
      );
    } finally {
      socket.destroy();
    }
  }
}
