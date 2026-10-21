import 'dart:async';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_sync/cairn_sync.dart';
import 'package:test/test.dart';

// NOTE: this test needs real loopback TCP. It runs in CI; in sandboxes
// that block local process-to-process TCP by policy it cannot pass —
// that is an environment restriction, not a protocol failure (the
// session protocol itself is fully covered over in-memory streams in
// session_test.dart).
void main() {
  test('server and client sync over a real loopback socket', () async {
    final phone = await DeviceKeyPair.generate();
    final pc = await DeviceKeyPair.generate();

    PairedDevice paired(DeviceKeyPair other) => PairedDevice(
          identity: DeviceIdentity(
            deviceId: other.deviceId,
            publicKeyBytes: other.publicKeyBytes,
            displayName: 'peer',
          ),
          pairedAtIso: '2026-10-21T00:00:00Z',
        );

    SyncRecord rec(String id, String name) => SyncRecord(
          entityId: id,
          kind: 'project',
          payload: {'name': name},
          version: VersionVector({'x': 1}),
          updatedAt:
              Hlc(physicalMs: 1000, logical: 0, deviceId: phone.deviceId),
        );

    SyncSessionResult? serverResult;
    final server = SyncServer();
    await server.start(
      local: pc,
      allowedPeers: [paired(phone)],
      loadRecords: () async => [rec('from-pc', 'pc project')],
      onSync: (result) async => serverResult = result,
      port: 0,
    );
    addTearDown(server.close);

    final clientResult = await syncWithPeer(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      local: phone,
      peer: paired(pc),
      localRecords: [rec('from-phone', 'phone project')],
    );

    expect(clientResult.peerRecordCount, 1);
    expect(
        clientResult.merged.map((r) => r.entityId),
        containsAll(['from-pc', 'from-phone']));
    // The server side completed with the same merged state.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(serverResult, isNotNull);
    expect(
        serverResult!.merged.map((r) => r.entityId),
        containsAll(['from-pc', 'from-phone']));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
