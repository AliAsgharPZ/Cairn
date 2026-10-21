import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:test/test.dart';

final _config = ModelConfig(providerId: 'fake', modelId: 'm');

void main() {
  group('detectLanguage', () {
    test('Persian text → fa with high confidence', () {
      final d = detectLanguage('این متن فارسی است و برای آزمایش نوشته شده');
      expect(d.code, 'fa');
      expect(d.confidence, greaterThan(0.9));
    });

    test('English text → en', () {
      final d = detectLanguage('This is an English instruction for the agent');
      expect(d.code, 'en');
      expect(d.confidence, greaterThan(0.9));
    });

    test('empty / symbol-only text falls back to en at 0.5', () {
      final d = detectLanguage('12345 !!!');
      expect(d.code, 'en');
      expect(d.confidence, 0.5);
    });
  });

  group('LanguagePipeline.normalize', () {
    test('parses the model JSON into a NormalizedInstruction', () async {
      final fake = FakeModelProvider([
        '{"goal": "Summarize the report", "language": "en", '
            '"inputs": ["report.pdf"], "constraints": ["max 200 words"]}',
      ]);
      final pipeline = LanguagePipeline(fake);
      final n = await pipeline.normalize(_config, 'Summarize report.pdf');
      expect(n.goal, 'Summarize the report');
      expect(n.inputs, ['report.pdf']);
      expect(n.constraints, ['max 200 words']);
    });

    test('a confident script detection overrides a wrong model language tag',
        () async {
      final fake = FakeModelProvider([
        '{"goal": "خلاصه کردن گزارش", "language": "en", "inputs": [], "constraints": []}',
      ]);
      final pipeline = LanguagePipeline(fake);
      final n = await pipeline.normalize(
          _config, 'این گزارش را برای من خلاصه کن و نکات مهمش را بگو');
      expect(n.language, 'fa');
    });

    test('non-JSON model output fails loudly', () async {
      final fake = FakeModelProvider(['I cannot help with that']);
      final pipeline = LanguagePipeline(fake);
      await expectLater(
        pipeline.normalize(_config, 'do something'),
        throwsFormatException,
      );
    });
  });

  group('LanguagePipeline.translate', () {
    test('returns the model output trimmed', () async {
      final fake = FakeModelProvider(['  سلام دنیا  ']);
      final pipeline = LanguagePipeline(fake);
      expect(await pipeline.translate(_config, 'Hello world', 'fa'), 'سلام دنیا');
      // The stage prompt must name the target language.
      final system = fake.requests.single.messages.first.content;
      expect(system, contains('Persian'));
    });
  });
}
