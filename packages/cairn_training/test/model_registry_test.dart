import 'dart:io';

import 'package:cairn_training/cairn_training.dart';
import 'package:test/test.dart';

void main() {
  group('NeuralLanguageModel training', () {
    final texts = [
      'the cat sits on the mat',
      'the dog runs in the park',
      'the cat runs on the mat',
      'the dog sits in the park',
      'the cat sits on the mat',
      'the dog runs in the park',
      'گربه روی فرش می نشیند',
      'گربه روی فرش می نشیند',
    ];
    late WordTokenizer tokenizer;
    late ModelSpec spec;

    setUp(() {
      tokenizer = WordTokenizer.train(texts);
      spec = ModelSpec(
        vocabSize: tokenizer.vocabSize,
        hiddenSize: 24,
        layers: 2,
        heads: 4,
        contextLength: 3,
      );
    });

    test('gradient descent genuinely reduces loss and perplexity', () {
      final model =
          NeuralLanguageModel.fresh(spec, SeededRandom(7));
      final lossBefore = model.evaluateLoss(texts, tokenizer);
      final losses = trainModel(
        model: model,
        texts: texts,
        tokenizer: tokenizer,
        epochs: 40,
        learningRate: 0.5,
        batchSize: 4,
        seed: 3,
      );
      final lossAfter = model.evaluateLoss(texts, tokenizer);
      expect(losses.last, lessThan(losses.first));
      expect(lossAfter, lessThan(lossBefore * 0.8));
      expect(ModelSpec.perplexity(lossAfter),
          lessThan(ModelSpec.perplexity(lossBefore)));
    });

    test('true parameter count equals the weight arrays', () {
      final model = NeuralLanguageModel.fresh(spec, SeededRandom(1));
      final expected = model.embeddings.length +
          model.w1.length +
          model.b1.length +
          model.w2.length +
          model.b2.length;
      expect(model.parameterCount, expected);
    });

    test('checkpoint round trip reproduces identical greedy generation',
        () {
      final model = NeuralLanguageModel.fresh(spec, SeededRandom(11));
      trainModel(
        model: model,
        texts: texts,
        tokenizer: tokenizer,
        epochs: 15,
        seed: 5,
      );
      final prompt = tokenizer.encode('the cat', eos: false);
      final before = model.generate(prompt, maxTokens: 6);
      final restored = NeuralLanguageModel.fromJson(model.toJson());
      final after = restored.generate(prompt, maxTokens: 6);
      expect(after, before);
      expect(before.length, lessThanOrEqualTo(6));
      for (final id in before) {
        expect(id, inInclusiveRange(0, spec.vocabSize - 1));
      }
    });

    test('instruction fine-tuning is continued training on formatted '
        'examples', () {
      final model = NeuralLanguageModel.fresh(spec, SeededRandom(13));
      trainModel(
          model: model, texts: texts, tokenizer: tokenizer, epochs: 5);
      const examples = [
        InstructionExample(prompt: 'سلام کن', completion: 'سلام دنیا'),
        InstructionExample(prompt: 'سلام کن', completion: 'سلام دنیا'),
      ];
      final instructTexts = [for (final e in examples) e.format()];
      // The tokenizer was trained on the base corpus only; rebuild one
      // that also knows the instruction vocabulary, as the real flow
      // does (tokenizer trains on all available text).
      final tok2 = WordTokenizer.train([...texts, ...instructTexts]);
      final spec2 = ModelSpec(
        vocabSize: tok2.vocabSize,
        hiddenSize: 24,
        layers: 2,
        heads: 4,
        contextLength: 3,
      );
      final model2 = NeuralLanguageModel.fresh(spec2, SeededRandom(13));
      final losses = trainModel(
        model: model2,
        texts: instructTexts,
        tokenizer: tok2,
        epochs: 30,
        seed: 9,
      );
      expect(losses.last, lessThan(losses.first));
    });
  });

  group('ModelRegistryStore', () {
    test('register → list → load → delete round trip', () async {
      final dir = await Directory.systemTemp.createTemp('cairn_registry');
      addTearDown(() => dir.delete(recursive: true));
      final store = ModelRegistryStore(dir);
      expect(await store.list(), isEmpty);

      final texts = ['the cat sits', 'the dog runs'];
      final tokenizer = WordTokenizer.train(texts);
      final spec = ModelSpec(
          vocabSize: tokenizer.vocabSize,
          hiddenSize: 16,
          layers: 1,
          heads: 2,
          contextLength: 2);
      final model = NeuralLanguageModel.fresh(spec, SeededRandom(2));
      trainModel(
          model: model, texts: texts, tokenizer: tokenizer, epochs: 3);

      final meta = await store.register(
        name: 'tiny-fa-en',
        kind: 'base',
        model: model,
        tokenizer: tokenizer,
        capabilities: const ['انگلیسی'],
        metrics: {'epochs': 3, 'finalLoss': 1.23},
      );
      expect(meta.parameterCount, model.parameterCount);

      final listed = await store.list();
      expect(listed.single.name, 'tiny-fa-en');
      expect(listed.single.capabilities, ['انگلیسی']);

      final loaded = await store.load(meta.id);
      expect(loaded, isNotNull);
      final prompt = tokenizer.encode('the', eos: false);
      expect(loaded!.model.generate(prompt, maxTokens: 3),
          model.generate(prompt, maxTokens: 3));

      expect(await store.delete(meta.id), isTrue);
      expect(await store.list(), isEmpty);
      expect(await store.delete(meta.id), isFalse);
    });
  });
}
