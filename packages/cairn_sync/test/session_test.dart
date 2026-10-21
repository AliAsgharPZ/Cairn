import 'dart:async';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_sync/cairn_sync.dart';
import 'package:test/test.dart';

SyncRecord rec(
  String id, {
  required String name,
  required Map<String, int> version,
  required Hlc at,
}) =>
    SyncRecord(
      entityId: id,
      kind: 'project',
      payload: {'name': name},
      version: VersionVector(Map.of(version)),
      updatedAt: at,
    );

Hlc h(int p, String d) => Hlc(physicalMs: p, logical: 0, deviceId: d);

PairedDevice paired(DeviceKeyPair other) => PairedDevice(
      identity: DeviceIdentity(
        deviceId: other.deviceId,
        publicKeyBytes: other.publicKeyBytes,
        displayName: 'peer',
      ),
      pairedAtIso: '2026-10-21T00:00:00Z',
    );

void main() {
  group('SyncSession', () {
    late DeviceKeyPair phone;
    late DeviceKeyPair pc;

    setUp(() async {
      phone = await DeviceKeyPair.generate();
      pc = await DeviceKeyPair.generate();
    });

    test('two paired devices exchange records and converge', () async {
      final phoneRecords = [
        rec('p1',
            name: 'phone edit',
            version: {'phone': 1},
            at: h(1000, phone.deviceId)),
        rec('only-phone',
            name: 'phone project',
            version: {'phone': 1},
            at: h(1000, phone.deviceId)),
      ];
      final pcRecords = [
        rec('p1',
            name: 'pc edit', version: {'pc': 1}, at: h(1500, pc.deviceId)),
        rec('only-pc',
            name: 'pc project',
            version: {'pc': 1},
            at: h(1500, pc.deviceId)),
      ];

      final a2b = StreamController<List<int>>();
      final b2a = StreamController<List<int>>();
      final phoneSession = SyncSession(
          local: phone, allowedPeers: [paired(pc)], localRecords: phoneRecords);
      final pcSession = SyncSession(
          local: pc, allowedPeers: [paired(phone)], localRecords: pcRecords);

      final results = await Future.wait([
        phoneSession.run(b2a.stream, a2b.sink),
        pcSession.run(a2b.stream, b2a.sink),
      ]).timeout(const Duration(seconds: 30));

      final phoneResult = results[0];
      final pcResult = results[1];
      expect(phoneResult.peerRecordCount, 2);
      expect(pcResult.peerRecordCount, 2);

      Map<String, Object?> byId(List<SyncRecord> rs) =>
          {for (final r in rs) r.entityId: r.payload['name']};
      // Convergence: identical merged state on both devices — the pc
      // edit of p1 (greater HLC) is canonical on both, and the phone
      // edit survives as the same deterministic conflict copy on both.
      expect(byId(phoneResult.merged), byId(pcResult.merged));
      expect(byId(phoneResult.merged)['p1'], 'pc edit');
      expect(byId(phoneResult.merged)['only-phone'], 'phone project');
      expect(byId(phoneResult.merged)['only-pc'], 'pc project');
      expect(phoneResult.conflictCopies.single.entityId,
          'conflict:p1:${phone.deviceId}');
      expect(pcResult.conflictCopies.single.entityId,
          phoneResult.conflictCopies.single.entityId);
    });

    test('an unpaired stranger is rejected before any record moves',
        () async {
      final stranger = await DeviceKeyPair.generate();
      final a2b = StreamController<List<int>>();
      final b2a = StreamController<List<int>>();

      // The phone expects the pc; a stranger shows up instead.
      final phoneSession = SyncSession(
          local: phone, allowedPeers: [paired(pc)], localRecords: const []);
      final strangerSession = SyncSession(
          local: stranger, allowedPeers: [paired(phone)], localRecords: const []);

      final phoneFuture = phoneSession.run(b2a.stream, a2b.sink);
      final strangerResult = strangerSession
          .run(a2b.stream, b2a.sink)
          .then<Object?>((_) => null, onError: (Object e) => e);

      await expectLater(phoneFuture, throwsStateError);
      // The stranger's side errors too (its auth cannot satisfy anyone /
      // the stream closes) — crucially it is an error, not a result.
      expect(await strangerResult, isNotNull);
    });
  });
}
