import 'dart:convert';
import 'dart:io';

import 'phrase_translator.dart';
import 'text_classifier.dart';

/// The kinds of "smart models" the chain pipeline binds to steps.
class SmartModelKind {
  static const String langDetect = 'langdetect';
  static const String intent = 'intent';
  static const String translator = 'translator';
}

/// One trained smart model on disk: a self-describing JSON file
/// under `<modelsDir>/smart/<id>.json` holding its kind, its honest
/// metrics (held-out accuracy / pair count) and its payload (a
/// [TextClassifier] or a [PhraseTranslator]).
class SmartModel {
  const SmartModel({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAtIso,
    required this.metrics,
    required this.payloadJson,
  });

  final String id;
  final String name;

  /// One of [SmartModelKind].
  final String kind;
  final String createdAtIso;

  /// e.g. {'accuracy': 0.97, 'examples': 168} for classifiers,
  /// {'pairs': 96} for translators.
  final Map<String, Object?> metrics;
  final Map<String, Object?> payloadJson;

  TextClassifier asClassifier() => TextClassifier.fromJson(payloadJson);
  PhraseTranslator asTranslator() => PhraseTranslator.fromJson(payloadJson);

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'createdAt': createdAtIso,
        'metrics': metrics,
        'payload': payloadJson,
      };

  factory SmartModel.fromJson(Map<String, Object?> json) => SmartModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        createdAtIso: json['createdAt'] as String? ?? '',
        metrics: (json['metrics'] as Map?)?.cast<String, Object?>() ?? {},
        payloadJson: (json['payload'] as Map).cast<String, Object?>(),
      );
}

/// File store for smart models. Ids are filename-sanitized the same
/// way the project store handles sync conflict ids (Windows-safe).
class SmartModelStore {
  SmartModelStore(this.modelsDir);

  final Directory modelsDir;

  Directory get _dir => Directory('${modelsDir.path}/smart');

  File _fileFor(String id) => File(
      '${_dir.path}/${id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.json');

  Future<List<SmartModel>> list() async {
    if (!await _dir.exists()) return const [];
    final models = <SmartModel>[];
    await for (final entity in _dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        models.add(SmartModel.fromJson(
            (jsonDecode(await entity.readAsString()) as Map)
                .cast<String, Object?>()));
      } catch (_) {
        // A corrupt model file must not break the whole list.
      }
    }
    models.sort((a, b) => b.createdAtIso.compareTo(a.createdAtIso));
    return models;
  }

  Future<List<SmartModel>> listOfKind(String kind) async =>
      [for (final m in await list()) if (m.kind == kind) m];

  Future<SmartModel?> get(String id) async {
    final file = _fileFor(id);
    if (!await file.exists()) return null;
    return SmartModel.fromJson(
        (jsonDecode(await file.readAsString()) as Map)
            .cast<String, Object?>());
  }

  /// The newest model of a kind — the chain's default binding when a
  /// step names a kind but no specific model.
  Future<SmartModel?> latestOfKind(String kind) async {
    final models = await listOfKind(kind);
    return models.isEmpty ? null : models.first;
  }

  Future<void> save(SmartModel model) async {
    await _dir.create(recursive: true);
    final file = _fileFor(model.id);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(model.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  Future<void> delete(String id) async {
    final file = _fileFor(id);
    if (await file.exists()) await file.delete();
  }
}
