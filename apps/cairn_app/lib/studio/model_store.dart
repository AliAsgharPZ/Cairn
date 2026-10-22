import 'dart:convert';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';

/// The owner's model definitions (v1.3): every model they create —
/// by role — lives in one JSON file under `<baseDir>/models/`.
/// Definitions are the ONLY model surface now: the one-tap
/// pre-trained smart models of v1.2 were removed at the owner's
/// direction; a model here points at any open-source model (Ollama)
/// or AI API the owner configures.
class ModelStore {
  ModelStore(this.baseDir);

  final Directory baseDir;

  File get _file => File('${baseDir.path}/models/definitions.json');

  Future<List<ModelDefinition>> list() async {
    if (!await _file.exists()) return const [];
    try {
      final decoded = jsonDecode(await _file.readAsString());
      return [
        for (final e in decoded as List)
          ModelDefinition.fromJson((e as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<ModelDefinition>> listOfRole(String role) async =>
      [for (final m in await list()) if (m.role == role) m];

  Future<ModelDefinition?> get(String id) async {
    for (final m in await list()) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The default model for a role (first created) — a flowchart
  /// step's "automatic" binding.
  Future<ModelDefinition?> firstOfRole(String role) async {
    final models = await listOfRole(role);
    return models.isEmpty ? null : models.first;
  }

  Future<void> save(ModelDefinition model) async {
    final models = [
      for (final m in await list())
        if (m.id != model.id) m,
      model,
    ];
    await _saveAll(models);
  }

  Future<void> delete(String id) async {
    await _saveAll([
      for (final m in await list())
        if (m.id != id) m,
    ]);
  }

  Future<void> _saveAll(List<ModelDefinition> models) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
        jsonEncode([for (final m in models) m.toJson()]),
        flush: true);
    await tmp.rename(_file.path);
  }

  /// Export/import of the whole model list as one JSON document —
  /// one of the export levels the owner asked for (alongside project
  /// export and the full backup).
  Future<String> exportJson() async =>
      const JsonEncoder.withIndent('  ')
          .convert([for (final m in await list()) m.toJson()]);

  /// Imports definitions; returns how many were added (ids that
  /// already exist are replaced, not duplicated).
  Future<int> importJson(String text) async {
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      throw const FormatException('expected a JSON list of models');
    }
    final existing = {for (final m in await list()) m.id: m};
    var count = 0;
    for (final e in decoded) {
      final def = ModelDefinition.fromJson((e as Map).cast<String, Object?>());
      existing[def.id] = def;
      count++;
    }
    await _saveAll(existing.values.toList());
    return count;
  }
}
