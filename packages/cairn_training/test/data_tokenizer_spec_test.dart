import 'package:cairn_training/cairn_training.dart';
import 'package:test/test.dart';

void main() {
  group('buildDataset', () {
    test('cleans, dedupes, counts honestly, and splits by ratio', () {
      final raw = [
        'سلام دنیا',
        '',
        '   ',
        'x', // too short
        'سلام دنیا', // exact duplicate
        'سلام   دنیا', // duplicate after normalization
        for (var i = 0; i < 20; i++) 'line number $i of the corpus',
      ];
      final ds = buildDataset(raw, validationRatio: 0.1, testRatio: 0.1);
      expect(ds.stats.rawCount, 26);
      expect(ds.stats.droppedEmpty, 2);
      expect(ds.stats.droppedShort, 1);
      expect(ds.stats.droppedDuplicates, 2);
      expect(ds.stats.keptCount, 21);
      expect(ds.train.length + ds.validation.length + ds.test.length, 21);
      expect(ds.test, hasLength(2));
      expect(ds.validation, hasLength(2));
      expect(ds.train, hasLength(17));
    });

    test('splits are deterministic for a seed', () {
      final raw = [for (var i = 0; i < 30; i++) 'sample text $i'];
      final a = buildDataset(raw, seed: 7);
      final b = buildDataset(raw, seed: 7);
      expect(a.train, b.train);
      expect(a.test, b.test);
    });
  });

  group('WordTokenizer', () {
    test('tokenizes Persian and Latin text with punctuation split', () {
      final tokens = WordTokenizer.tokenizeRaw('سلام، دنیا! hello 42');
      expect(tokens, contains('سلام'));
      expect(tokens, contains('،'));
      expect(tokens, contains('hello'));
      expect(tokens, contains('42'));
    });

    test('train → encode/decode round trip; OOV becomes <unk>', () {
      final tok = WordTokenizer.train(
          ['the cat sits', 'the dog runs', 'the cat runs']);
      expect(tok.vocabSize, greaterThan(4));
      final ids = tok.encode('the cat sits');
      expect(ids.first, WordTokenizer.bosId);
      expect(ids.last, WordTokenizer.eosId);
      expect(tok.decode(ids), contains('cat'));
      final oov = tok.encode('the elephant sits');
      expect(oov, contains(WordTokenizer.unkId));
    });

    test('vocab caps and JSON round trip', () {
      final texts = [for (var i = 0; i < 50; i++) 'word$i common text'];
      final tok = WordTokenizer.train(texts, maxVocab: 10);
      expect(tok.vocabSize, 10);
      final back = WordTokenizer.fromJson(tok.toJson());
      expect(back.encode('common text'), tok.encode('common text'));
    });
  });

  group('ModelSpec', () {
    test('parameter estimate matches the documented formula', () {
      const spec = ModelSpec(
          vocabSize: 100, hiddenSize: 16, layers: 2, heads: 4,
          contextLength: 8);
      // embedding 1600 + positional 128 + 2*(4*256 + 8*256 + 64) + 32
      expect(spec.parameterCount, 1600 + 128 + 2 * (1024 + 2048 + 64) + 32);
      expect(spec.parameterLabel, endsWith('K'));
    });

    test('validation catches indivisible heads; perplexity is exp(loss)',
        () {
      const bad = ModelSpec(vocabSize: 50, hiddenSize: 30, heads: 4);
      expect(bad.validate(), isNotEmpty);
      expect(ModelSpec.perplexity(0), 1.0);
      expect(ModelSpec.perplexity(1), closeTo(2.71828, 0.001));
    });
  });

  group('InstructionExample', () {
    test('formats and round-trips', () {
      const ex = InstructionExample(prompt: 'سلام کن', completion: 'سلام!');
      expect(ex.format(), contains('سلام کن'));
      expect(ex.format(), contains('سلام!'));
      final back = InstructionExample.fromJson(ex.toJson());
      expect(back.prompt, ex.prompt);
    });
  });
}
