import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

void main() {
  group('Skill', () {
    test('JSON round-trip preserves everything', () {
      final skill = Skill(
        name: 'Office Docs',
        description: 'Work with office documents',
        instructions: 'Prefer .docx output.',
        toolIds: ['fs.read', 'fs.write'],
        version: 3,
      );
      final back = Skill.fromJson(skill.toJson());
      expect(back.id, skill.id);
      expect(back.name, 'Office Docs');
      expect(back.description, 'Work with office documents');
      expect(back.instructions, 'Prefer .docx output.');
      expect(back.toolIds, ['fs.read', 'fs.write']);
      expect(back.version, 3);
    });

    test('validation flags empty names and duplicate tools', () {
      expect(Skill(name: '  ').validate(), isNotEmpty);
      expect(
        Skill(name: 'x', toolIds: ['a', 'a']).validate(),
        contains(contains('duplicate')),
      );
      expect(Skill(name: 'ok', toolIds: ['a']).validate(), isEmpty);
    });
  });

  group('SkillRegistry', () {
    test('register, lookup and requireAll', () {
      final a = Skill(name: 'A');
      final b = Skill(name: 'B');
      final registry = SkillRegistry([a, b]);
      expect(registry.lookup(a.id)?.name, 'A');
      expect(registry.requireAll([b.id, a.id]).map((s) => s.name), ['B', 'A']);
      expect(() => registry.requireAll(['missing-id']),
          throwsA(isA<FormatException>()));
      expect(() => registry.register(Skill(id: a.id, name: 'dup')),
          throwsArgumentError);
    });
  });
}
