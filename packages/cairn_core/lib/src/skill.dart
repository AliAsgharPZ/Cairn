import 'ids.dart';

/// A Cairn skill: a named, shareable capability bundle that can be
/// attached to agents (blueprints reference skills by id).
///
/// A skill contributes:
/// - [instructions]: guidance injected into the planning stage, and
/// - [toolIds]: tools the skill makes available to the agent.
///
/// Attaching a skill is an explicit act by the user in the editor, so a
/// skill's tools count as *declared* for the agent — but every tool call
/// still passes the agent's policy and approval gates unchanged. Skills
/// are plain JSON, so they sync and export exactly like projects.
class Skill {
  Skill({
    String? id,
    required this.name,
    this.description = '',
    this.instructions = '',
    List<String>? toolIds,
    this.version = 1,
  })  : id = id ?? newId(),
        toolIds = toolIds ?? [];

  final String id;
  String name;
  String description;

  /// Free-form guidance for the planner (may be empty).
  String instructions;

  /// Tool ids this skill makes available to agents that attach it.
  final List<String> toolIds;

  /// Skill format/content version, bumped by the author on changes.
  final int version;

  List<String> validate() {
    final issues = <String>[];
    if (id.isEmpty) issues.add('skill id must not be empty');
    if (name.trim().isEmpty) issues.add('skill name must not be empty');
    final seen = <String>{};
    for (final t in toolIds) {
      if (t.trim().isEmpty) issues.add('skill tool id must not be empty');
      if (!seen.add(t)) issues.add('duplicate tool id in skill: $t');
    }
    if (version < 1) issues.add('skill version must be >= 1');
    return issues;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'instructions': instructions,
        'toolIds': toolIds,
        'version': version,
      };

  factory Skill.fromJson(Map<String, Object?> json) => Skill(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        instructions: json['instructions'] as String? ?? '',
        toolIds: (json['toolIds'] as List?)?.map((e) => '$e').toList(),
        version: (json['version'] as num?)?.toInt() ?? 1,
      );
}

/// An id → [Skill] collection. Used by the runtime to resolve the skills
/// a blueprint references, and by the studio to manage installed skills.
class SkillRegistry {
  SkillRegistry([Iterable<Skill> skills = const []]) {
    for (final s in skills) {
      register(s);
    }
  }

  final Map<String, Skill> _skills = {};

  void register(Skill skill) {
    if (_skills.containsKey(skill.id)) {
      throw ArgumentError('Duplicate skill id: ${skill.id}');
    }
    _skills[skill.id] = skill;
  }

  Skill? lookup(String id) => _skills[id];
  bool contains(String id) => _skills.containsKey(id);
  List<Skill> get all => List.unmodifiable(_skills.values);

  /// Resolves [ids] to skills, failing loudly on the first unknown id —
  /// an agent referencing a missing skill must never silently lose it.
  List<Skill> requireAll(List<String> ids) {
    final resolved = <Skill>[];
    for (final id in ids) {
      final skill = _skills[id];
      if (skill == null) {
        throw FormatException('Unknown skill id: $id');
      }
      resolved.add(skill);
    }
    return resolved;
  }
}
