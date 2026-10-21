import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_training/cairn_training.dart';

/// Serves a locally trained model (M9 registry) as a Cairn provider —
/// Flow 2's final stage: the registered model connects to the agent
/// runtime like any other provider.
///
/// Honest mechanics: the model is a small word-level LM. The last user
/// message becomes the prompt; the model CONTINUES the text. It does
/// not chat or reason like a hosted LLM, and the settings UI names it
/// accordingly («مدل محلی آموزش‌دیده»).
class LocalTrainedModelProvider implements ModelProvider {
  LocalTrainedModelProvider({required this.registry, this.modelId = ''});

  final ModelRegistryStore registry;

  /// The registered model to serve; when empty, the request's
  /// configured model id is used (the studio stores the registry id in
  /// the provider config's default model).
  final String modelId;

  ({NeuralLanguageModel model, WordTokenizer tokenizer})? _cache;
  String? _cacheId;

  @override
  String get id => 'local-trained';

  @override
  Future<ModelResponse> complete(
      ModelConfig config, ModelRequest request) async {
    final wanted = modelId.isNotEmpty ? modelId : config.modelId;
    if (wanted.isEmpty) {
      throw ProviderException(id, 'no trained model selected');
    }
    if (_cache == null || _cacheId != wanted) {
      final loaded = await registry.load(wanted);
      if (loaded == null) {
        throw ProviderException(id, 'trained model not found: $wanted');
      }
      _cache = (model: loaded.model, tokenizer: loaded.tokenizer);
      _cacheId = wanted;
    }
    final loaded = _cache!;

    var prompt = '';
    for (final message in request.messages.reversed) {
      if (message.role == ChatRole.user) {
        prompt = message.content;
        break;
      }
    }
    if (prompt.isEmpty && request.messages.isNotEmpty) {
      prompt = request.messages.last.content;
    }

    final promptIds = loaded.tokenizer.encode(prompt, eos: false);
    final generated = loaded.model.generate(
      promptIds,
      maxTokens: request.maxOutputTokens ?? 48,
      temperature: request.temperature ?? 0.8,
      rng: SeededRandom(DateTime.now().microsecondsSinceEpoch),
    );
    var text = loaded.tokenizer.decode(generated);
    text = text
        .replaceAll('<pad>', '')
        .replaceAll('<bos>', '')
        .replaceAll('<eos>', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return ModelResponse(
      text: text,
      usage: ModelUsage(
        promptTokens: promptIds.length,
        completionTokens: generated.length,
      ),
    );
  }
}
