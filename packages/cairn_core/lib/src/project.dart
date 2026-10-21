import 'blueprint.dart';
import 'ids.dart';

/// Current project-file schema version.
const int kProjectSchemaVersion = 1;

/// An agent project: the unit the studio creates, saves, exports (as a
/// `.cairn.json` file / project ZIP) and syncs between the user's devices.
/// Contains one or more agent blueprints.
class AgentProject {
  AgentProject({
    String? id,
    required this.name,
    this.description = '',
    List<AgentBlueprint>? agents,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.schemaVersion = kProjectSchemaVersion,
  })  : id = id ?? newId(),
        agents = agents ?? [],
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  String name;
  String description;
  final List<AgentBlueprint> agents;
  final DateTime createdAt;
  DateTime updatedAt;
  final int schemaVersion;

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
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        schemaVersion:
            (json['schemaVersion'] as num?)?.toInt() ?? kProjectSchemaVersion,
      );
}
