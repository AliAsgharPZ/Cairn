import 'dart:convert';
import 'dart:io';

import 'package:cairn_sync/cairn_sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage for the device key seed — the one true secret of sync.
/// Abstracted so tests use memory and the app uses the platform
/// secure store (Keychain / Keystore-backed).
abstract class SeedStore {
  Future<String?> read();
  Future<void> write(String value);
}

class MemorySeedStore implements SeedStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }
}

class SecureSeedStore implements SeedStore {
  SecureSeedStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _key = 'cairn_device_seed_v1';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// Loads this device's long-term key pair, generating and persisting
/// one on first run. The device id is stable for the life of the app
/// install (it derives from the key).
class DeviceIdentityService {
  DeviceIdentityService(this.seedStore);

  final SeedStore seedStore;
  DeviceKeyPair? _cached;

  Future<DeviceKeyPair> loadOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;
    final stored = await seedStore.read();
    if (stored != null) {
      return _cached = await DeviceKeyPair.fromSeed(base64Decode(stored));
    }
    final created = await DeviceKeyPair.generate();
    await seedStore.write(base64Encode(await created.extractSeed()));
    return _cached = created;
  }
}

/// The devices this device has paired with, persisted as JSON in the
/// app data directory (`paired_devices.json`).
class PairedDevicesStore {
  PairedDevicesStore(this.baseDir);

  final Directory baseDir;
  File get _file => File('${baseDir.path}/paired_devices.json');

  Future<List<PairedDevice>> list() async {
    if (!await _file.exists()) return const [];
    final decoded = jsonDecode(await _file.readAsString());
    return [
      for (final e in decoded as List)
        PairedDevice.fromJson((e as Map).cast<String, Object?>()),
    ];
  }

  Future<void> add(PairedDevice device) async {
    final devices = [
      for (final d in await list())
        if (d.identity.deviceId != device.identity.deviceId) d,
      device,
    ];
    await _save(devices);
  }

  Future<void> remove(String deviceId) async {
    final devices = [
      for (final d in await list())
        if (d.identity.deviceId != deviceId) d,
    ];
    await _save(devices);
  }

  Future<void> _save(List<PairedDevice> devices) async {
    await baseDir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
        jsonEncode([for (final d in devices) d.toJson()]),
        flush: true);
    await tmp.rename(_file.path);
  }
}

/// This device's display name for pairing, persisted locally.
class DeviceProfileStore {
  DeviceProfileStore(this.baseDir);

  final Directory baseDir;
  File get _file => File('${baseDir.path}/device_profile.json');

  Future<String> loadName() async {
    if (!await _file.exists()) return '';
    final json =
        (jsonDecode(await _file.readAsString()) as Map).cast<String, Object?>();
    return json['displayName'] as String? ?? '';
  }

  Future<void> saveName(String name) async {
    await baseDir.create(recursive: true);
    await _file.writeAsString(jsonEncode({'displayName': name}), flush: true);
  }
}

/// This device's owner-declared hardware specs for overflow routing.
/// CPU cores are measured (Platform.numberOfProcessors); RAM, free
/// disk and GPU presence are NOT reliably measurable from Dart on both
/// platforms, so the owner declares them — Cairn never fabricates
/// measurements it cannot make.
class DeviceSpecsStore {
  DeviceSpecsStore(this.baseDir);

  final Directory baseDir;
  File get _file => File('${baseDir.path}/device_specs.json');

  Future<({int ramMb, int freeDiskMb, bool hasGpu})> load() async {
    if (!await _file.exists()) {
      return (ramMb: 4096, freeDiskMb: 10000, hasGpu: false);
    }
    final json =
        (jsonDecode(await _file.readAsString()) as Map).cast<String, Object?>();
    return (
      ramMb: (json['ramMb'] as num?)?.toInt() ?? 4096,
      freeDiskMb: (json['freeDiskMb'] as num?)?.toInt() ?? 10000,
      hasGpu: json['hasGpu'] as bool? ?? false,
    );
  }

  Future<void> save(
      {required int ramMb,
      required int freeDiskMb,
      required bool hasGpu}) async {
    await baseDir.create(recursive: true);
    await _file.writeAsString(
        jsonEncode(
            {'ramMb': ramMb, 'freeDiskMb': freeDiskMb, 'hasGpu': hasGpu}),
        flush: true);
  }
}
