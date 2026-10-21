import 'dart:io';
import 'dart:typed_data';

import 'package:cairn_app/studio/device_identity.dart';
import 'package:cairn_sync/cairn_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceIdentityService', () {
    test('creates once, then reloads the same identity from the seed',
        () async {
      final store = MemorySeedStore();
      final first = await DeviceIdentityService(store).loadOrCreate();
      // A fresh service over the same store must restore, not regenerate.
      final second = await DeviceIdentityService(store).loadOrCreate();
      expect(second.deviceId, first.deviceId);
      expect(second.publicKeyBytes, first.publicKeyBytes);
    });
  });

  group('PairedDevicesStore', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cairn_paired_test');
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    PairedDevice device(String id, String name) => PairedDevice(
          identity: DeviceIdentity(
            deviceId: id,
            publicKeyBytes: Uint8List.fromList(List.filled(32, 7)),
            displayName: name,
          ),
          pairedAtIso: '2026-10-21T00:00:00Z',
        );

    test('add, list, replace and remove round-trip through the file',
        () async {
      final store = PairedDevicesStore(tmp);
      expect(await store.list(), isEmpty);
      await store.add(device('aaa', 'PC'));
      await store.add(device('bbb', 'Phone'));
      await store.add(device('aaa', 'PC renamed'));
      var devices = await store.list();
      expect(devices, hasLength(2));
      expect(
          devices.firstWhere((d) => d.identity.deviceId == 'aaa')
              .identity
              .displayName,
          'PC renamed');
      await store.remove('aaa');
      devices = await store.list();
      expect(devices.single.identity.deviceId, 'bbb');
    });
  });

  group('DeviceProfileStore', () {
    test('display name persists', () async {
      final tmp =
          await Directory.systemTemp.createTemp('cairn_profile_test');
      addTearDown(() => tmp.delete(recursive: true));
      final store = DeviceProfileStore(tmp);
      expect(await store.loadName(), '');
      await store.saveName('گوشی من');
      expect(await DeviceProfileStore(tmp).loadName(), 'گوشی من');
    });
  });
}
