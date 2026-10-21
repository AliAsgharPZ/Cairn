import 'dart:convert';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';

/// File-backed storage for agent projects: one `<id>.cairn.json` file per
/// project inside `<baseDir>/projects/`. This is the real persistence layer of
/// the studio (create/save/load/delete) — the same JSON format that project
/// export and (later) sync operate on.
///
/// Writes are validated (an invalid project is never persisted) and atomic
/// (write to a temp file, then rename), so a crash mid-save cannot corrupt
/// the previous version of a project.
class ProjectStore {
  ProjectStore(this.baseDir);

  final Directory baseDir;

  Directory get _projectsDir => Directory('${baseDir.path}/projects');

  Future<void> _ensureDir() async {
    if (!await _projectsDir.exists()) {
      await _projectsDir.create(recursive: true);
    }
  }

  /// Maps an entity id to a filesystem-safe file name. Sync conflict
  /// copies carry ids like `conflict:<uuid>:<deviceId>` — the colons
  /// are illegal in Windows file names (CI caught this: errno 123),
  /// so anything outside [A-Za-z0-9._-] becomes '_'. Ids themselves
  /// are read back from file CONTENT (see [list]), so the mapping
  /// only needs to be deterministic, which it is.
  File _fileFor(String projectId) => File(
      '${_projectsDir.path}/${projectId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.cairn.json');

  /// Creates, validates and persists a new empty project.
  Future<AgentProject> createProject(String name,
      {String description = ''}) async {
    final project = AgentProject(name: name, description: description);
    await save(project);
    return project;
  }

  /// Persists [project]. Throws [FormatException] listing the validation
  /// issues if the project is not valid.
  Future<void> save(AgentProject project) async {
    final issues = project.validate();
    if (issues.isNotEmpty) {
      throw FormatException(
          'Refusing to save invalid project: ${issues.join('; ')}');
    }
    await _ensureDir();
    final target = _fileFor(project.id);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(project.toJson()),
        flush: true);
    await tmp.rename(target.path);
  }

  Future<AgentProject?> load(String projectId) async {
    final file = _fileFor(projectId);
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Project file is not a JSON object');
    }
    return AgentProject.fromJson(decoded.cast<String, Object?>());
  }

  /// All projects, most recently updated first. A corrupt file is surfaced as
  /// an error rather than silently skipped — data loss must be visible.
  Future<List<AgentProject>> list() async {
    await _ensureDir();
    final projects = <AgentProject>[];
    await for (final entity in _projectsDir.list()) {
      if (entity is File && entity.path.endsWith('.cairn.json')) {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) {
          throw FormatException('Corrupt project file: ${entity.path}');
        }
        projects.add(AgentProject.fromJson(decoded.cast<String, Object?>()));
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<bool> delete(String projectId) async {
    final file = _fileFor(projectId);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  Directory get _exportsDir => Directory('${baseDir.path}/exports');

  /// Exports [project] as a portable `.cairn.zip` into the exports folder
  /// and returns the file (share/transfer it to the other device).
  Future<File> exportProject(AgentProject project) =>
      ProjectArchive.exportProject(project, _exportsDir);

  /// All exported archives currently in the exports folder, newest first —
  /// the import dialog lists these.
  Future<List<File>> listExports() async {
    if (!await _exportsDir.exists()) return const [];
    final files = <File>[];
    await for (final entity in _exportsDir.list()) {
      if (entity is File &&
          entity.path.endsWith(ProjectArchive.fileExtension)) {
        files.add(entity);
      }
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Imports an archive picked from anywhere on the device. The file
  /// picker hands back bytes, not a dependable path (Android's SAF in
  /// particular), so the bytes are staged into the imports folder and
  /// then validated by [importArchive] exactly like a local file.
  /// This is the fix for the v1.0.0 import dead end, where the dialog
  /// only listed files already inside the app's private exports
  /// folder — a place the owner could never put a file.
  Future<AgentProject> importArchiveBytes(
      String fileName, List<int> bytes) async {
    final safeName = fileName.split(RegExp(r'[/\\]')).last;
    final dir = Directory('${baseDir.path}/imports');
    await dir.create(recursive: true);
    final staged = File('${dir.path}/$safeName');
    await staged.writeAsBytes(bytes, flush: true);
    return importArchive(staged);
  }

  /// Imports an archive file (validated by [ProjectArchive]) and persists
  /// it. If a project with the same id already exists, the import is kept
  /// as a copy with a fresh id — importing never silently overwrites.
  Future<AgentProject> importArchive(File zipFile) async {
    var project = await ProjectArchive.importProject(zipFile);
    if (await load(project.id) != null) {
      project = AgentProject(
        name: project.name,
        description: project.description,
        agents: List.of(project.agents),
        outputs: List.of(project.outputs),
        createdAt: project.createdAt,
        updatedAt: project.updatedAt,
        schemaVersion: project.schemaVersion,
      );
    }
    await save(project);
    return project;
  }
}
