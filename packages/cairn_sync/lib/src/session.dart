import 'dart:async';
import 'dart:convert';

import 'package:cairn_core/cairn_core.dart';

import 'framing.dart';
import 'identity.dart';
import 'pairing.dart';

// The sync session protocol between two PAIRED devices.
//
// Framing is the same length-prefixed JSON as the Tool Host protocol
// (4-byte little-endian length + UTF-8 JSON). The exchange:
//
// 1. hello   — each side announces {deviceId, nonce}.
// 2. auth    — each side signs (label ‖ peer's nonce ‖ own deviceId)
//              with its long-term key; the peer verifies against the
//              PAIRED public key it stored during pairing. A device
//              that is not the paired peer (or cannot prove the key)
//              aborts the session before any record moves.
// 3. records — full record sets are exchanged (project-scale data;
//              delta exchange is a later optimization).
// 4. Each side merges locally with cairn_core's deterministic merger,
//              so both converge to identical state, then sends done.

const String _authLabel = 'cairn-sync-auth-v1';

/// The outcome of one completed sync session.
class SyncSessionResult {
  SyncSessionResult({
    required this.merged,
    required this.conflictCopies,
    required this.deletedIds,
    required this.peerRecordCount,
  });

  final List<SyncRecord> merged;
  final List<SyncRecord> conflictCopies;
  final List<String> deletedIds;
  final int peerRecordCount;
}

/// One side of a sync session. Run both peers' sessions concurrently
/// over a connected stream pair (a LAN socket, a Tailscale connection,
/// or an in-memory pair in tests).
class SyncSession {
  SyncSession({
    required this.local,
    required this.allowedPeers,
    required this.localRecords,
  });

  final DeviceKeyPair local;

  /// Devices paired with this one. The connecting peer must be in this
  /// list (matched by its announced device id) AND prove its key.
  final List<PairedDevice> allowedPeers;
  final List<SyncRecord> localRecords;

  Future<SyncSessionResult> run(
    Stream<List<int>> incoming,
    StreamSink<List<int>> outgoing,
  ) async {
    final iterator = StreamIterator(decodeFrames(incoming));

    Future<Map<String, Object?>> next(String what) async {
      if (!await iterator.moveNext()) {
        throw StateError('sync session closed while waiting for $what');
      }
      return iterator.current;
    }

    void send(Map<String, Object?> message) => outgoing.add(frameMessage(message));

    try {
      // 1. hello
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
            'sync authentication failed: unpaired peer ${hello['deviceId']}');
      }
      final pairedPeer = peer;
      final peerNonce = base64Decode(hello['nonce'] as String);

      // 2. auth: sign the peer's nonce; verify the peer's signature.
      final mySignature = await local.sign(
          [...utf8.encode(_authLabel), ...peerNonce, ...utf8.encode(local.deviceId)]);
      send({'type': 'auth', 'signature': base64Encode(mySignature)});
      final auth = await next('auth');
      if (auth['type'] != 'auth') {
        throw StateError('sync authentication failed: expected auth');
      }
      final peerSignature = base64Decode(auth['signature'] as String);
      final expectedMessage = [
        ...utf8.encode(_authLabel),
        ...myNonce,
        ...utf8.encode(pairedPeer.identity.deviceId),
      ];
      final ok = await DeviceKeyPair.verify(
          pairedPeer.identity.publicKeyBytes, expectedMessage, peerSignature);
      if (!ok) {
        throw StateError(
            'sync authentication failed: peer could not prove its key');
      }

      // 3. records exchange
      send({
        'type': 'records',
        'records': [for (final r in localRecords) r.toJson()],
      });
      final recordsMessage = await next('records');
      if (recordsMessage['type'] != 'records') {
        throw StateError('sync protocol error: expected records');
      }
      final remoteRecords = [
        for (final r in recordsMessage['records'] as List)
          SyncRecord.fromJson((r as Map).cast<String, Object?>()),
      ];

      // 4. merge locally (deterministic) and finish
      final result = mergeSyncRecords(
          local: localRecords, remote: remoteRecords);
      send({'type': 'done'});
      await next('done');
      return SyncSessionResult(
        merged: result.merged,
        conflictCopies: result.conflictCopies,
        deletedIds: result.deletedIds,
        peerRecordCount: remoteRecords.length,
      );
    } finally {
      await iterator.cancel();
      await outgoing.close();
    }
  }
}
