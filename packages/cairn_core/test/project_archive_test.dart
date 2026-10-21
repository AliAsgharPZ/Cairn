import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectArchive', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cairn_archive_test');
    });
    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    AgentProject sample() => AgentProject(
          name: 'پروژهٔ نمونه',
          description: 'for export tests',
          agents: [
            AgentBlueprint(
              name: 'helper',
              model: ModelConfig(providerId: 'ollama', modelId: 'llama3.1'),
              systemPrompt: 'Be helpful.',
            ),
          ],
        );

    test('export → import round-trips the whole project', () async {
      final project = sample();
      final file = await ProjectArchive.exportProject(project, tmp);
      expect(await file.exists(), isTrue);
      expect(file.path, endsWith(ProjectArchive.fileExtension));

      final back = await ProjectArchive.importProject(file);
      expect(back.id, project.id);
      expect(back.name, project.name);
      expect(back.description, project.description);
      expect(back.agents, hasLength(1));
      expect(back.agents.single.name, 'helper');
      expect(back.agents.single.model.modelId, 'llama3.1');
    });

    test('a plain zip without a cairn manifest is refused', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('whatever.txt', 2, utf8.encode('hi')));
      final file = File('${tmp.path}/plain.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      expect(() => ProjectArchive.importProject(file),
          throwsA(isA<FormatException>()));
    });

    test('a non-zip file is refused', () async {
      final file = File('${tmp.path}/junk.cairn.zip')
        ..writeAsStringSync('this is not a zip');
      expect(() => ProjectArchive.importProject(file),
          throwsA(isA<FormatException>()));
    });

    test('an archive with a future format version is refused', () async {
      final manifest = utf8.encode(jsonEncode({
        'format': ProjectArchive.formatId,
        'version': ProjectArchive.formatVersion + 1,
        'projectId': 'x',
      }));
      final projectBytes = utf8.encode(jsonEncode(sample().toJson()));
      final archive = Archive()
        ..addFile(ArchiveFile(
            ProjectArchive.manifestEntry, manifest.length, manifest))
        ..addFile(ArchiveFile(
            ProjectArchive.projectEntry, projectBytes.length, projectBytes));
      final file = File('${tmp.path}/future.cairn.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      expect(() => ProjectArchive.importProject(file),
          throwsA(isA<FormatException>()));
    });

    test('an archive missing the project payload is refused', () async {
      final manifest = utf8.encode(jsonEncode({
        'format': ProjectArchive.formatId,
        'version': ProjectArchive.formatVersion,
        'projectId': 'x',
      }));
      final archive = Archive()
        ..addFile(ArchiveFile(
            ProjectArchive.manifestEntry, manifest.length, manifest));
      final file = File('${tmp.path}/nopayload.cairn.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      expect(() => ProjectArchive.importProject(file),
          throwsA(isA<FormatException>()));
    });
  });
}
