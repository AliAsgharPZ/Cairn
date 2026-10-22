import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// Full backup / restore (v1.3): one `.cairn-backup.zip` holding the
/// owner's whole studio state — projects, model definitions and
/// trained-model files, paired devices, generated outputs. This is
/// the top export level, above per-project export and per-model
/// export. API keys are NOT included (they live in the platform
/// secure store, by design, and never travel in files).
class BackupService {
  BackupService(this.baseDir);

  final Directory baseDir;

  static const _dirs = ['projects', 'models', 'outputs'];
  static const _files = ['paired_devices.json'];

  Future<File> exportTo(String outPath) async {
    final archive = Archive();
    final manifest = jsonEncode({
      'app': 'cairn-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    final manifestBytes = utf8.encode(manifest);
    archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    Future<void> addTree(String name) async {
      final dir = Directory('${baseDir.path}/$name');
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final rel = entity.path.substring(baseDir.path.length + 1);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
    }

    for (final d in _dirs) {
      await addTree(d);
    }
    for (final f in _files) {
      final file = File('${baseDir.path}/$f');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        archive.addFile(ArchiveFile(f, bytes.length, bytes));
      }
    }
    final encoded = ZipEncoder().encode(archive);
    final out = File(outPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(encoded, flush: true);
    return out;
  }

  /// Restores a backup over the current state (the UI confirms
  /// first). Returns the number of files restored. Throws
  /// [FormatException] when the file is not a Cairn backup.
  Future<int> importFrom(String path) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifest = archive.findFile('manifest.json');
    if (manifest == null) {
      throw const FormatException('not a Cairn backup (no manifest)');
    }
    final decoded =
        (jsonDecode(utf8.decode(manifest.content)) as Map).cast<String, Object?>();
    if (decoded['app'] != 'cairn-backup') {
      throw const FormatException('not a Cairn backup');
    }
    var count = 0;
    for (final file in archive.files) {
      if (file.name == 'manifest.json' || !file.isFile) continue;
      // Never let an archive write outside the studio directory.
      if (file.name.contains('..') || file.name.startsWith('/')) continue;
      final out = File('${baseDir.path}/${file.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(file.content, flush: true);
      count++;
    }
    return count;
  }
}
