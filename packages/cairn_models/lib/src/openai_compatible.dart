import 'dart:convert';

import 'package:cairn_core/cairn_core.dart';
import 'package:http/http.dart' as http;

import 'provider.dart';

/// Adapter for any OpenAI-compatible chat-completions endpoint
/// (OpenAI, Azure OpenAI, OpenRouter, local servers such as LM Studio, …).
///
/// The endpoint base URL is configurable per installation (app settings),
/// defaulting to OpenAI's. The API key is resolved per call via
/// [apiKeyResolver] and is never stored here.
class OpenAiCompatibleProvider implements ModelProvider {
  OpenAiCompatibleProvider({
    required this.apiKeyResolver,
    this.baseUrl = 'https://api.openai.com/v1',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final ApiKeyResolver apiKeyResolver;
  final String baseUrl;
  final http.Client _client;

  @override
  String get id => 'openai-compatible';

  @override
  Future<ModelResponse> complete(
      ModelConfig config, ModelRequest request) async {
    final key = await apiKeyResolver();
    if (key == null || key.isEmpty) {
      throw ProviderException(id, 'No API key configured for this provider');
    }
    final uri = Uri.parse('$baseUrl/chat/completions');
    final temperature = request.temperature ?? config.temperature;
    final maxTokens = request.maxOutputTokens ?? config.maxOutputTokens;
    final body = {
      'model': config.modelId,
      'messages': [
        for (final m in request.messages)
          {'role': m.role.name, 'content': m.content},
      ],
      if (temperature != null) 'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
    };
    final http.Response res;
    try {
      res = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw ProviderException(id, 'Network error: $e');
    }
    if (res.statusCode != 200) {
      throw ProviderException(id, _excerpt(res.body),
          statusCode: res.statusCode);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw ProviderException(id, 'Malformed response: not a JSON object');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw ProviderException(id, 'Malformed response: no choices');
    }
    final message = (choices.first as Map)['message'];
    final content = (message as Map?)?['content'];
    if (content is! String) {
      throw ProviderException(id, 'Malformed response: no message content');
    }
    final usage = decoded['usage'];
    return ModelResponse(
      text: content,
      usage: ModelUsage(
        promptTokens: usage is Map ? usage['prompt_tokens'] as int? : null,
        completionTokens:
            usage is Map ? usage['completion_tokens'] as int? : null,
      ),
    );
  }

  static String _excerpt(String body) =>
      body.length <= 300 ? body : '${body.substring(0, 300)}…';
}
