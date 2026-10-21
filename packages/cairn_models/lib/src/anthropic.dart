import 'dart:convert';

import 'package:cairn_core/cairn_core.dart';
import 'package:http/http.dart' as http;

import 'provider.dart';

/// Adapter for Anthropic's Messages API. System messages are lifted into
/// the top-level `system` field, per Anthropic's contract. The API key is
/// resolved per call and never stored here.
class AnthropicProvider implements ModelProvider {
  AnthropicProvider({
    required this.apiKeyResolver,
    this.baseUrl = 'https://api.anthropic.com/v1',
    this.apiVersion = '2023-06-01',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final ApiKeyResolver apiKeyResolver;
  final String baseUrl;
  final String apiVersion;
  final http.Client _client;

  @override
  String get id => 'anthropic';

  @override
  Future<ModelResponse> complete(
      ModelConfig config, ModelRequest request) async {
    final key = await apiKeyResolver();
    if (key == null || key.isEmpty) {
      throw ProviderException(id, 'No API key configured for this provider');
    }
    final system = request.messages
        .where((m) => m.role == ChatRole.system)
        .map((m) => m.content)
        .join('\n');
    final messages = [
      for (final m in request.messages)
        if (m.role != ChatRole.system)
          {'role': m.role.name, 'content': m.content},
    ];
    final temperature = request.temperature ?? config.temperature;
    final body = {
      'model': config.modelId,
      'max_tokens': request.maxOutputTokens ?? config.maxOutputTokens ?? 1024,
      'messages': messages,
      if (system.isNotEmpty) 'system': system,
      if (temperature != null) 'temperature': temperature,
    };
    final http.Response res;
    try {
      res = await _client.post(
        Uri.parse('$baseUrl/messages'),
        headers: {
          'x-api-key': key,
          'anthropic-version': apiVersion,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw ProviderException(id, 'Network error: $e');
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
    final content = decoded['content'];
    if (content is! List) {
      throw ProviderException(id, 'Malformed response: no content blocks');
    }
    final text = content
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'])
        .whereType<String>()
        .join();
    final usage = decoded['usage'];
    return ModelResponse(
      text: text,
      usage: ModelUsage(
        promptTokens: usage is Map ? usage['input_tokens'] as int? : null,
        completionTokens: usage is Map ? usage['output_tokens'] as int? : null,
      ),
    );
  }
}
