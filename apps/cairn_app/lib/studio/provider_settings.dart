import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One configured model provider installation (an adapter + where it lives).
/// API keys are NOT part of this model — they live in the platform secure
/// store via [ApiKeyStore], keyed by provider id.
class ProviderConfig {
  const ProviderConfig({
    required this.providerId,
    this.baseUrl,
    this.defaultModelId = '',
  });

  /// Adapter id: 'openai-compatible' | 'anthropic' | 'ollama'.
  final String providerId;

  /// Custom endpoint (required for most OpenAI-compatible servers and for a
  /// non-default Ollama host); null means the adapter's built-in default.
  final String? baseUrl;

  /// Convenience default used to prefill the agent editor's model field.
  final String defaultModelId;

  Map<String, Object?> toJson() => {
        'providerId': providerId,
        if (baseUrl != null) 'baseUrl': baseUrl,
        'defaultModelId': defaultModelId,
      };

  factory ProviderConfig.fromJson(Map<String, Object?> json) =>
      ProviderConfig(
        providerId: json['providerId'] as String? ?? '',
        baseUrl: json['baseUrl'] as String?,
        defaultModelId: json['defaultModelId'] as String? ?? '',
      );
}

/// Persists provider configurations as JSON next to the projects.
/// (Keys are stored separately — see [ApiKeyStore].)
class ProviderSettingsStore {
  ProviderSettingsStore(this.baseDir);

  final Directory baseDir;

  File get _file => File('${baseDir.path}/providers.json');

  Future<List<ProviderConfig>> load() async {
    if (!await _file.exists()) return const [];
    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! List) {
      throw const FormatException('providers.json is not a list');
    }
    return decoded
        .whereType<Map>()
        .map((m) => ProviderConfig.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  Future<void> save(List<ProviderConfig> configs) async {
    await baseDir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert([for (final c in configs) c.toJson()]),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  Future<void> upsert(ProviderConfig config) async {
    final all = [...await load()];
    final i = all.indexWhere((c) => c.providerId == config.providerId);
    if (i >= 0) {
      all[i] = config;
    } else {
      all.add(config);
    }
    await save(all);
  }

  Future<void> remove(String providerId) async {
    final all = [...await load()]..removeWhere((c) => c.providerId == providerId);
    await save(all);
  }
}

/// API keys, held in the platform secure store (Android Keystore /
/// Windows DPAPI via flutter_secure_storage). Keys never enter project
/// files, settings JSON, journals, or logs.
abstract class ApiKeyStore {
  Future<String?> read(String providerId);
  Future<void> write(String providerId, String key);
  Future<void> delete(String providerId);
}

class SecureApiKeyStore implements ApiKeyStore {
  SecureApiKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String providerId) => 'cairn_api_key_$providerId';

  @override
  Future<String?> read(String providerId) =>
      _storage.read(key: _key(providerId));

  @override
  Future<void> write(String providerId, String key) =>
      _storage.write(key: _key(providerId), value: key);

  @override
  Future<void> delete(String providerId) =>
      _storage.delete(key: _key(providerId));
}

/// In-memory key store for tests (never used by the shipped app).
class MemoryApiKeyStore implements ApiKeyStore {
  final Map<String, String> _keys = {};

  @override
  Future<String?> read(String providerId) async => _keys[providerId];

  @override
  Future<void> write(String providerId, String key) async {
    _keys[providerId] = key;
  }

  @override
  Future<void> delete(String providerId) async {
    _keys.remove(providerId);
  }
}
