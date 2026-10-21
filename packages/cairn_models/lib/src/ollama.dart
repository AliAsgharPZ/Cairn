import 'dart:convert';

import 'package:cairn_core/cairn_core.dart';
import 'package:http/http.dart' as http;

import 'provider.dart';

/// Adapter for a locally running Ollama server (the Windows local-inference
/// path of the approved architecture; also usable on any machine running
/// Ollama). No API key. A refused connection is reported as a
/// [ProviderException] — the runtime never silently swaps in another model.
class OllamaProvider implements ModelProvider {
  OllamaProvider({
    this.baseUrl = 'http://localhost:11434',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  String get id => 'ollama';

  @override
  Future<ModelResponse> complete(
      ModelConfig config, ModelRequest request) async {
    final temperature = request.temperature ?? config.temperature;
    final body = {
      'model': config.modelId,
      'stream': false,
      'messages': [
        for (final m in request.messages)
          {'role': m.role.name, 'content': m.content},
      ],
      if (temperature != null) 'options': {'temperature': temperature},
    };
    final http.Response res;
    try {
      res = await _client.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      throw ProviderException(
          id, 'Cannot reach Ollama at $baseUrl (is it running?): $e');
    }
    if (res.statusCode != 200) {
      throw ProviderException(
          id, res.body.length <= 300 ? res.body : '${res.body.substring(0, 300)}…',
          statusCode: res.statusCode);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw ProviderException(id, 'Malformed response: not a JSON object');
    }
    final content = (decoded['message'] as Map?)?['content'];
    if (content is! String) {
      throw ProviderException(id, 'Malformed response: no message content');
    }
    return ModelResponse(
      text: content,
      usage: ModelUsage(
        promptTokens: decoded['prompt_eval_count'] as int?,
        completionTokens: decoded['eval_count'] as int?,
      ),
    );
  }
}
