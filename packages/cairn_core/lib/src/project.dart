import 'blueprint.dart';
import 'ids.dart';
import 'pipeline.dart';

/// Current project-file schema version.
const int kProjectSchemaVersion = 1;

/// An agent project: the unit the studio creates, saves, exports (as a
/// `.cairn.json` file / project ZIP) and syncs between the user's devices.
/// Contains one or more agent blueprints.
/// Something a project produced besides agents — today, a trained
/// model (Flow 2's hand-off, seen from the project's side); future
/// output kinds join through [kind]. [refId] points at the producing
/// system's record — for models, the model-registry id on the device
/// that trained it. Model files are device-local, so on another
/// device an output is an honest reference, not the weights.
class ProjectOutput {
  ProjectOutput({
    String? id,
    required this.kind,
    required this.name,
    required this.refId,
    DateTime? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now().toUtc();

  final String id;

  /// 'model' today.
  final String kind;
  final String name;
  final String refId;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'refId': refId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ProjectOutput.fromJson(Map<String, Object?> json) => ProjectOutput(
        id: json['id'] as String?,
        kind: json['kind'] as String? ?? 'model',
        name: json['name'] as String? ?? '',
        refId: json['refId'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

class AgentProject {
  AgentProject({
    String? id,
    required this.name,
    this.description = '',
    List<AgentBlueprint>? agents,
    List<ProjectOutput>? outputs,
    List<PipelineStep>? pipeline,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.schemaVersion = kProjectSchemaVersion,
    this.language = '',
  })  : id = id ?? newId(),
        agents = agents ?? [],
        outputs = outputs ?? [],
        pipeline = pipeline ?? [],
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  String name;
  String description;
  final List<AgentBlueprint> agents;

  /// What this project has produced (trained models). A project is
  /// not only a home for agents: training into a project records the
  /// model here.
  final List<ProjectOutput> outputs;

  /// The project's processing chain (v1.2): the connected line of
  /// models and agents a request flows through. Empty for pre-v1.2
  /// projects; the workspace offers to add the default chain.
  final List<PipelineStep> pipeline;

  final DateTime createdAt;
  DateTime updatedAt;
  final int schemaVersion;

  /// The project's working language code (v1.4) — the language the
  /// flowchart's models work in. '' = the language the user writes
  /// in (no fixed Persian/English assumption anywhere: any language
  /// from the app's registry, built-in or custom, can be chosen).
  String language;

  /// Records [output] on the project, replacing any earlier output of
  /// the same kind pointing at the same record (re-registering a
  /// model never duplicates its entry).
  void addOutput(ProjectOutput output) {
    outputs.removeWhere(
        (o) => o.kind == output.kind && o.refId == output.refId);
    outputs.add(output);
    updatedAt = DateTime.now().toUtc();
  }

  AgentBlueprint? agentById(String agentId) {
    for (final a in agents) {
      if (a.id == agentId) return a;
    }
    return null;
  }

  /// Inserts or replaces an agent (matched by id) and touches [updatedAt].
  void upsertAgent(AgentBlueprint agent) {
    final i = agents.indexWhere((a) => a.id == agent.id);
    if (i >= 0) {
      agents[i] = agent;
    } else {
      agents.add(agent);
    }
    updatedAt = DateTime.now().toUtc();
  }

  bool removeAgent(String agentId) {
    final before = agents.length;
    agents.removeWhere((a) => a.id == agentId);
    if (agents.length != before) {
      updatedAt = DateTime.now().toUtc();
      return true;
    }
    return false;
  }

  /// Project-level + per-agent validation issues; empty means valid.
  List<String> validate() {
    final issues = <String>[];
    if (name.trim().isEmpty) issues.add('project name must not be empty');
    if (schemaVersion != kProjectSchemaVersion) {
      issues.add('unsupported project schemaVersion: $schemaVersion');
    }
    final seen = <String>{};
    for (final a in agents) {
      if (!seen.add(a.id)) issues.add('duplicate agent id: ${a.id}');
      for (final issue in a.validate()) {
        issues.add('agent "${a.name}": $issue');
      }
    }
    return issues;
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'description': description,
        'agents': agents.map((a) => a.toJson()).toList(),
        'outputs': outputs.map((o) => o.toJson()).toList(),
        'pipeline': pipeline.map((p) => p.toJson()).toList(),
        'language': language,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AgentProject.fromJson(Map<String, Object?> json) => AgentProject(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        agents: (json['agents'] as List? ?? const [])
            .map((e) =>
                AgentBlueprint.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        outputs: (json['outputs'] as List? ?? const [])
            .map((e) =>
                ProjectOutput.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        pipeline: (json['pipeline'] as List? ?? const [])
            .map((e) =>
                PipelineStep.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        language: json['language'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        schemaVersion:
            (json['schemaVersion'] as num?)?.toInt() ?? kProjectSchemaVersion,
      );
}
