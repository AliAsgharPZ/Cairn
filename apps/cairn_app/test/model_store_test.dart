import 'dart:io';

import 'package:cairn_app/studio/backup_service.dart';
import 'package:cairn_app/studio/model_store.dart';
import 'package:cairn_core/cairn_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cairn_models_test');
  });
  tearDown(() => tmp.delete(recursive: true));

  test('model definitions save/list/export/import round trip', () async {
    final store = ModelStore(tmp);
    await store.save(ModelDefinition(
      id: 'm1',
      name: 'مترجم من',
      role: ModelRole.translator,
      providerId: 'ollama',
      modelId: 'gemma3',
      description: 'ترجمه فارسی و انگلیسی',
    ));
    await store.save(ModelDefinition(
      id: 'm2',
      name: 'ایجنت فیگما',
      role: ModelRole.agent,
      providerId: 'openai-compatible',
      modelId: 'gpt-4o-mini',
      targetSoftware: 'Figma',
      instructions: 'Design things.',
      lessons: [AgentLesson(title: 'درس یک', details: 'این‌طوری')],
    ));
    expect(await store.list(), hasLength(2));
    expect((await store.firstOfRole(ModelRole.agent))!.name, 'ایجنت فیگما');

    final json = await store.exportJson();
    final other = ModelStore(
        Directory('${tmp.path}/other')..createSync(recursive: true));
    final count = await other.importJson(json);
    expect(count, 2);
    final imported = await other.get('m2');
    expect(imported!.lessons.single.title, 'درس یک');
    expect(imported.effectiveInstructions, contains('درس یک'));

    await store.delete('m1');
    expect(await store.list(), hasLength(1));
  });

  test('full backup exports and restores the studio tree', () async {
    // Fake studio state.
    final projects = Directory('${tmp.path}/projects')..createSync();
    await File('${projects.path}/p1.json').writeAsString('{"id":"p1"}');
    final modelsDir = Directory('${tmp.path}/models')..createSync();
    await File('${modelsDir.path}/definitions.json')
        .writeAsString('[]');
    await File('${tmp.path}/paired_devices.json').writeAsString('[]');

    final backupFile = '${tmp.path}/backup.zip';
    await BackupService(tmp).exportTo(backupFile);
    expect(await File(backupFile).exists(), isTrue);

    // Wipe and restore into a fresh dir.
    final restored = Directory('${tmp.path}/restored')
      ..createSync(recursive: true);
    final count = await BackupService(restored).importFrom(backupFile);
    expect(count, greaterThanOrEqualTo(3));
    expect(await File('${restored.path}/projects/p1.json').readAsString(),
        '{"id":"p1"}');
    expect(
        await File('${restored.path}/paired_devices.json').exists(), isTrue);

    // A random zip is refused.
    final bogus = File('${tmp.path}/bogus.zip');
    await bogus.writeAsBytes(await File(backupFile).readAsBytes());
    final wrong = Directory('${tmp.path}/plain')
      ..createSync(recursive: true);
    await File('${wrong.path}/x.txt').writeAsString('hi');
    expect(
      () => BackupService(restored).importFrom('${wrong.path}/x.txt'),
      throwsA(anything),
    );
  });
}
