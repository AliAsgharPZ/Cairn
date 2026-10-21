import 'dart:io';

import 'package:cairn_app/studio/project_store.dart';
import 'package:cairn_core/cairn_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectStore', () {
    late Directory tmp;
    late ProjectStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cairn_store_test');
      store = ProjectStore(tmp);
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('starts empty — no fabricated projects', () async {
      expect(await store.list(), isEmpty);
    });

    test('create → list → load round-trip through real files', () async {
      final project = await store.createProject('ایجنت اول');
      expect(project.id, isNotEmpty);

      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.name, 'ایجنت اول');

      final loaded = await store.load(project.id);
      expect(loaded?.name, 'ایجنت اول');
      expect(loaded?.agents, isEmpty);

      // The file really exists in the documented format.
      final file = File('${tmp.path}/projects/${project.id}.cairn.json');
      expect(await file.exists(), isTrue);
    });

    test('save persists agents added to the project', () async {
      final project = await store.createProject('p');
      project.upsertAgent(AgentBlueprint(
        name: 'a1',
        model: ModelConfig(providerId: 'ollama', modelId: 'llama3.1'),
      ));
      await store.save(project);
      final loaded = await store.load(project.id);
      expect(loaded?.agents.single.name, 'a1');
    });

    test('saving an invalid project is refused', () async {
      final bad = AgentProject(name: '   ');
      expect(store.save(bad), throwsFormatException);
    });

    test('delete removes the project; deleting twice reports false',
        () async {
      final project = await store.createProject('p');
      expect(await store.delete(project.id), isTrue);
      expect(await store.delete(project.id), isFalse);
      expect(await store.list(), isEmpty);
    });

    test('a corrupt project file surfaces as an error, not silence',
        () async {
      final dir = Directory('${tmp.path}/projects');
      await dir.create(recursive: true);
      await File('${dir.path}/broken.cairn.json').writeAsString('{oops');
      expect(store.list(), throwsFormatException);
    });
  });
}
