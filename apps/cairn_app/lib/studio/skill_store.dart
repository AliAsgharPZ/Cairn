import 'dart:convert';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';

/// File-backed storage for installed skills: one `<id>.skill.json` file
/// per skill inside `<baseDir>/skills/`. Same discipline as
/// [ProjectStore]: validated saves, atomic writes, corruption surfaced
/// rather than silently skipped. Skills are plain JSON so they travel
/// with exports and, later, sync.
class SkillStore {
  SkillStore(this.baseDir);

  final Directory baseDir;

  Directory get _skillsDir => Directory('${baseDir.path}/skills');

  Future<void> _ensureDir() async {
    if (!await _skillsDir.exists()) {
      await _skillsDir.create(recursive: true);
    }
  }

  /// Same filesystem-safe mapping as ProjectStore: sync conflict
  /// ids contain ':' which Windows file names forbid.
  File _fileFor(String skillId) => File(
      '${_skillsDir.path}/${skillId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.skill.json');

  /// Persists [skill]. Throws [FormatException] if the skill is invalid.
  Future<void> save(Skill skill) async {
    final issues = skill.validate();
    if (issues.isNotEmpty) {
      throw FormatException(
          'Refusing to save invalid skill: ${issues.join('; ')}');
    }
    await _ensureDir();
    final target = _fileFor(skill.id);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(skill.toJson()),
        flush: true);
    await tmp.rename(target.path);
  }

  Future<Skill?> load(String skillId) async {
    final file = _fileFor(skillId);
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Skill file is not a JSON object');
    }
    return Skill.fromJson(decoded.cast<String, Object?>());
  }

  /// All installed skills, ordered by name.
  Future<List<Skill>> list() async {
    await _ensureDir();
    final skills = <Skill>[];
    await for (final entity in _skillsDir.list()) {
      if (entity is File && entity.path.endsWith('.skill.json')) {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) {
          throw FormatException('Corrupt skill file: ${entity.path}');
        }
        skills.add(Skill.fromJson(decoded.cast<String, Object?>()));
      }
    }
    skills.sort((a, b) => a.name.compareTo(b.name));
    return skills;
  }

  Future<bool> delete(String skillId) async {
    final file = _fileFor(skillId);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  /// A runtime-ready registry of all installed skills.
  Future<SkillRegistry> registry() async => SkillRegistry(await list());
}
