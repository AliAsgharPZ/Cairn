import 'dart:io';

import 'package:cairn_app/studio/skill_store.dart';
import 'package:cairn_core/cairn_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkillStore', () {
    late Directory tmp;
    late SkillStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cairn_skill_store_test');
      store = SkillStore(tmp);
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('starts empty — no fabricated skills', () async {
      expect(await store.list(), isEmpty);
    });

    test('save → list → load round-trip through real files', () async {
      final skill = Skill(
        name: 'Echo',
        instructions: 'Echo politely.',
        toolIds: ['calc.eval'],
      );
      await store.save(skill);
      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.name, 'Echo');
      final loaded = await store.load(skill.id);
      expect(loaded?.instructions, 'Echo politely.');
      expect(loaded?.toolIds, ['calc.eval']);
    });

    test('saving an invalid skill is refused', () async {
      expect(() => store.save(Skill(name: '  ')),
          throwsA(isA<FormatException>()));
    });

    test('delete removes the skill; deleting twice reports false',
        () async {
      final skill = Skill(name: 'Temp');
      await store.save(skill);
      expect(await store.delete(skill.id), isTrue);
      expect(await store.list(), isEmpty);
      expect(await store.delete(skill.id), isFalse);
    });

    test('registry() exposes the installed skills to the runtime', () async {
      final a = Skill(name: 'A', toolIds: ['fs.read']);
      await store.save(a);
      final registry = await store.registry();
      expect(registry.lookup(a.id)?.name, 'A');
      expect(registry.requireAll([a.id]), hasLength(1));
    });
  });
}
