import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cairn_app/studio/local_model_provider.dart';

void main() {
  group('LocalTrainedModelProvider', () {
    test('serves continuations from a registered trained model and '
        'fails honestly for unknown ids', () async {
      final dir = await Directory.systemTemp.createTemp('cairn_localprov');
      addTearDown(() => dir.delete(recursive: true));
      final registry = ModelRegistryStore(dir);

      final texts = ['the cat sits', 'the cat runs', 'the dog sits'];
      final tokenizer = WordTokenizer.train(texts);
      final spec = ModelSpec(
        vocabSize: tokenizer.vocabSize,
        hiddenSize: 16,
        layers: 1,
        heads: 2,
        contextLength: 2,
      );
      final model = NeuralLanguageModel.fresh(spec, SeededRandom(4));
      trainModel(
          model: model, texts: texts, tokenizer: tokenizer, epochs: 5);
      final meta = await registry.register(
        name: 'tiny',
        kind: 'base',
        model: model,
        tokenizer: tokenizer,
        capabilities: const [],
        metrics: const {},
      );

      final provider =
          LocalTrainedModelProvider(registry: registry, modelId: meta.id);
      expect(provider.id, 'local-trained');
      final response = await provider.complete(
        ModelConfig(providerId: 'local-trained', modelId: meta.id),
        const ModelRequest(
          messages: [ChatMessage(ChatRole.user, 'the cat')],
          maxOutputTokens: 6,
        ),
      );
      expect(response.usage.completionTokens, isNotNull);
      expect(response.usage.completionTokens!,
          lessThanOrEqualTo(6));

      final missing =
          LocalTrainedModelProvider(registry: registry, modelId: 'nope');
      await expectLater(
        missing.complete(
          ModelConfig(providerId: 'local-trained', modelId: 'nope'),
          const ModelRequest(
              messages: [ChatMessage(ChatRole.user, 'hi')]),
        ),
        throwsA(isA<ProviderException>()),
      );
    });
  });
}
