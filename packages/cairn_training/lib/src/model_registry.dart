import 'dart:convert';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';

import 'model.dart';
import 'model_spec.dart';
import 'tokenizer.dart';

/// A model in the registry (Flow 2: model registry stage): metadata,
/// training metrics, and its checkpoint (weights + tokenizer), stored
/// as one JSON file per model under the registry directory.
class RegisteredModel {
  const RegisteredModel({
    required this.id,
    required this.name,
    required this.kind,
    required this.spec,
    required this.parameterCount,
    required this.capabilities,
    required this.metrics,
    required this.createdAtIso,
  });

  final String id;
  final String name;

  /// 'base' (pre-trained on raw texts) or 'instruct' (fine-tuned).
  final String kind;
  final ModelSpec spec;

  /// The trained model's TRUE parameter count.
  final int parameterCount;
  final List<String> capabilities;

  /// e.g. {epochs, finalLoss, validationPerplexity}
  final Map<String, Object?> metrics;
  final String createdAtIso;

  Map<String, Object?> metadataJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'spec': spec.toJson(),
        'parameterCount': parameterCount,
        'capabilities': capabilities,
        'metrics': metrics,
        'createdAtIso': createdAtIso,
      };

  factory RegisteredModel.fromMetadata(Map<String, Object?> json) =>
      RegisteredModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'base',
        spec: ModelSpec.fromJson(
            (json['spec'] as Map).cast<String, Object?>()),
        parameterCount: (json['parameterCount'] as num?)?.toInt() ?? 0,
        capabilities: (json['capabilities'] as List?)
                ?.map((e) => '$e')
                .toList() ??
            const [],
        metrics: (json['metrics'] as Map?)?.cast<String, Object?>() ?? const {},
        createdAtIso: json['createdAtIso'] as String? ?? '',
      );
}

/// File-backed model registry: `<dir>/<id>.model.json` containing the
/// metadata plus the full checkpoint (model weights + tokenizer).
class ModelRegistryStore {
  ModelRegistryStore(this.dir);

  final Directory dir;

  File _file(String id) => File('${dir.path}/$id.model.json');

  Future<RegisteredModel> register({
    required String name,
    required String kind,
    required NeuralLanguageModel model,
    required WordTokenizer tokenizer,
    required List<String> capabilities,
    required Map<String, Object?> metrics,
  }) async {
    await dir.create(recursive: true);
    final meta = RegisteredModel(
      id: newId(),
      name: name,
      kind: kind,
      spec: model.spec,
      parameterCount: model.parameterCount,
      capabilities: capabilities,
      metrics: metrics,
      createdAtIso: DateTime.now().toUtc().toIso8601String(),
    );
    final payload = {
      ...meta.metadataJson(),
      'checkpoint': {
        'model': model.toJson(),
        'tokenizer': tokenizer.toJson(),
      },
    };
    final tmp = File('${_file(meta.id).path}.tmp');
    await tmp.writeAsString(jsonEncode(payload), flush: true);
    await tmp.rename(_file(meta.id).path);
    return meta;
  }

  Future<List<RegisteredModel>> list() async {
    if (!await dir.exists()) return const [];
    final out = <RegisteredModel>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.model.json')) {
        final json = (jsonDecode(await entity.readAsString()) as Map)
            .cast<String, Object?>();
        out.add(RegisteredModel.fromMetadata(json));
      }
    }
    out.sort((a, b) => a.createdAtIso.compareTo(b.createdAtIso));
    return out;
  }

  /// Loads the full checkpoint for [id]; null when absent.
  Future<({NeuralLanguageModel model, WordTokenizer tokenizer, RegisteredModel meta})?>
      load(String id) async {
    final file = _file(id);
    if (!await file.exists()) return null;
    final json =
        (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
    final checkpoint =
        (json['checkpoint'] as Map).cast<String, Object?>();
    return (
      model: NeuralLanguageModel.fromJson(
          (checkpoint['model'] as Map).cast<String, Object?>()),
      tokenizer: WordTokenizer.fromJson(
          (checkpoint['tokenizer'] as Map).cast<String, Object?>()),
      meta: RegisteredModel.fromMetadata(json),
    );
  }

  Future<bool> delete(String id) async {
    final file = _file(id);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }
}
