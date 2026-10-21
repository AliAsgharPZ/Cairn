import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_training/cairn_training.dart';

import 'local_model_provider.dart';
import 'provider_settings.dart';

/// Builds the real [ModelProvider] adapter for a configured provider.
/// The API key is resolved lazily at call time from the secure store.
/// Local trained models need the [modelRegistry] to load checkpoints.
ModelProvider buildProvider(
  ProviderConfig config,
  ApiKeyStore keys, {
  ModelRegistryStore? modelRegistry,
}) {
  switch (config.providerId) {
    case 'openai-compatible':
      return OpenAiCompatibleProvider(
        apiKeyResolver: () => keys.read(config.providerId),
        baseUrl: config.baseUrl ?? 'https://api.openai.com/v1',
      );
    case 'anthropic':
      return AnthropicProvider(
        apiKeyResolver: () => keys.read(config.providerId),
        baseUrl: config.baseUrl ?? 'https://api.anthropic.com/v1',
      );
    case 'ollama':
      return OllamaProvider(baseUrl: config.baseUrl ?? 'http://localhost:11434');
    case 'local-trained':
      final registry = modelRegistry;
      if (registry == null) {
        throw ArgumentError(
            'local-trained models need the model registry in this context');
      }
      return LocalTrainedModelProvider(
        registry: registry,
        modelId: config.defaultModelId,
      );
    default:
      throw ArgumentError('Unknown provider adapter: ${config.providerId}');
  }
}

/// The adapter ids the studio knows how to configure, with display names.
const knownProviders = <String, String>{
  'openai-compatible': 'OpenAI-compatible',
  'anthropic': 'Anthropic',
  'ollama': 'Ollama (محلی)',
  'local-trained': 'مدل محلی آموزش‌دیدهٔ Cairn',
};
