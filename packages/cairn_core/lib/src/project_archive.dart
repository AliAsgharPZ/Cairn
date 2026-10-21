import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'project.dart';

/// Project export/import as a portable `.cairn.zip` archive.
///
/// Layout:
/// - `manifest.json` — `{format: "cairn-project", version: 1, projectId,
///   projectName, exportedAt}`; validated on import before anything else
///   is trusted.
/// - `project.cairn.json` — the canonical [AgentProject] JSON.
///
/// Import is strict: a foreign zip, a missing entry, a future format
/// version or a corrupt project payload all fail with [FormatException]
/// rather than producing a half-valid project. This archive is also the
/// unit the two devices exchange manually until sync (M7) lands.
abstract final class ProjectArchive {
  static const String formatId = 'cairn-project';
  static const int formatVersion = 1;
  static const String projectEntry = 'project.cairn.json';
  static const String manifestEntry = 'manifest.json';
  static const String fileExtension = '.cairn.zip';

  /// Exports [project] into [outDir] and returns the written file.
  /// [fileName] defaults to a sanitized project name.
  static Future<File> exportProject(
    AgentProject project,
    Directory outDir, {
    String? fileName,
  }) async {
    await outDir.create(recursive: true);
    final manifest = <String, Object?>{
      'format': formatId,
      'version': formatVersion,
      'projectId': project.id,
      'projectName': project.name,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    final projectBytes = utf8.encode(jsonEncode(project.toJson()));
    final archive = Archive()
      ..addFile(
          ArchiveFile(manifestEntry, manifestBytes.length, manifestBytes))
      ..addFile(
          ArchiveFile(projectEntry, projectBytes.length, projectBytes));
    final encoded = ZipEncoder().encode(archive);
    final file =
        File('${outDir.path}/${fileName ?? defaultFileName(project)}');
    await file.writeAsBytes(encoded, flush: true);
    return file;
  }

  /// Reads and validates an archive previously written by [exportProject].
  static Future<AgentProject> importProject(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('not a readable zip archive: $e');
    }
    final manifestFile = archive.findFile(manifestEntry);
    if (manifestFile == null) {
      throw const FormatException(
          'not a Cairn project archive (manifest.json missing)');
    }
    final Map<String, Object?> manifest;
    try {
      manifest = (jsonDecode(utf8.decode(manifestFile.content)) as Map)
          .cast<String, Object?>();
    } catch (e) {
      throw FormatException('corrupt manifest.json: $e');
    }
    if (manifest['format'] != formatId) {
      throw const FormatException(
          'not a Cairn project archive (unknown format)');
    }
    final version = (manifest['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw FormatException(
          'archive format version $version is newer than this app supports ($formatVersion)');
    }
    final projectFile = archive.findFile(projectEntry);
    if (projectFile == null) {
      throw const FormatException(
          'archive is missing project.cairn.json');
    }
    try {
      final json = (jsonDecode(utf8.decode(projectFile.content)) as Map)
          .cast<String, Object?>();
      return AgentProject.fromJson(json);
    } catch (e) {
      throw FormatException('corrupt project.cairn.json: $e');
    }
  }

  /// `my-agent-project.cairn.zip`-style file name for [project].
  static String defaultFileName(AgentProject project) {
    final slug = project.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final base = slug.isEmpty ? 'project-${project.id.substring(0, 8)}' : slug;
    return '$base$fileExtension';
  }
}
