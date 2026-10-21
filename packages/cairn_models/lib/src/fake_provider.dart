import 'package:cairn_core/cairn_core.dart';

import 'provider.dart';

/// A deterministic [ModelProvider] **for automated tests and offline
/// development only**. It is never registered as a product default: the
/// shipped studio requires a real configured provider (API key or Ollama)
/// and says so when none is configured.
///
/// Behaviour: returns scripted responses in order; when the script is
/// exhausted it throws [StateError], so a test that under-scripts its model
/// fails loudly instead of silently passing on fabricated output. Every
/// request is recorded in [requests] for assertions.
class FakeModelProvider implements ModelProvider {
  FakeModelProvider(List<String> scripted) : _scripted = List.of(scripted);

  final List<String> _scripted;
  final List<ModelRequest> requests = [];

  /// The [ModelConfig] of each call, in order — lets tests verify
  /// role routing (which model served normalize / plan / verify).
  final List<ModelConfig> configs = [];

  @override
  String get id => 'fake';

  @override
  Future<ModelResponse> complete(
      ModelConfig config, ModelRequest request) async {
    requests.add(request);
    configs.add(config);
    if (_scripted.isEmpty) {
      throw StateError(
          'FakeModelProvider script exhausted after ${requests.length} request(s)');
    }
    return ModelResponse(text: _scripted.removeAt(0));
  }
}
