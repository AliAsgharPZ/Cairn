import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider.dart';

/// Media generation over an OpenAI-compatible API (v1.3): the image,
/// audio (voice/music) and video ROLES. Most open AI APIs — and an
/// increasing number of local servers — speak this shape:
///
///  * image:  POST {base}/images/generations → data[0].b64_json|url
///  * speech: POST {base}/audio/speech → raw audio bytes
///  * video:  POST {base}/videos → {id}; GET {base}/videos/{id} →
///    {status, url} polled by the caller.
///
/// This is plumbing, honestly labeled: whether a given provider
/// actually offers a given modality depends on the provider and the
/// model the owner configured. Failures surface as [ProviderException]
/// with the provider's own message — never as fake output.
class MediaProviders {
  MediaProviders({
    required this.apiKeyResolver,
    this.baseUrl = 'https://api.openai.com/v1',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final ApiKeyResolver apiKeyResolver;
  final String baseUrl;
  final http.Client _client;

  static const String providerId = 'openai-compatible';

  Future<Map<String, String>> _headers() async {
    final key = await apiKeyResolver();
    if (key == null || key.isEmpty) {
      throw ProviderException(
          providerId, 'No API key configured for this provider');
    }
    return {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
    };
  }

  /// Generates an image; returns bytes when the provider returns
  /// base64, or a URL the caller may download.
  Future<({List<int>? bytes, String? url})> generateImage({
    required String model,
    required String prompt,
    String size = '1024x1024',
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/images/generations'),
      headers: await _headers(),
      body: jsonEncode({
        'model': model,
        'prompt': prompt,
        'size': size,
        'n': 1,
        'response_format': 'b64_json',
      }),
    );
    if (res.statusCode != 200) {
      throw ProviderException(
          providerId, 'image generation failed: ${_bodyHint(res)}',
          statusCode: res.statusCode);
    }
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    final data = (json['data'] as List?) ?? const [];
    if (data.isEmpty) {
      throw ProviderException(providerId, 'image response had no data');
    }
    final first = (data.first as Map).cast<String, Object?>();
    final b64 = first['b64_json'] as String?;
    return (
      bytes: b64 == null ? null : base64Decode(b64),
      url: first['url'] as String?,
    );
  }

  /// Text-to-speech / audio generation; returns raw audio bytes
  /// (mp3 by default on OpenAI-shaped APIs).
  Future<List<int>> generateSpeech({
    required String model,
    required String input,
    String voice = 'alloy',
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/audio/speech'),
      headers: await _headers(),
      body: jsonEncode({'model': model, 'input': input, 'voice': voice}),
    );
    if (res.statusCode != 200) {
      throw ProviderException(providerId,
          'audio generation failed: ${_bodyHint(res)}',
          statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }

  /// Starts a video generation job; returns its id.
  Future<String> createVideo({
    required String model,
    required String prompt,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/videos'),
      headers: await _headers(),
      body: jsonEncode({'model': model, 'prompt': prompt}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw ProviderException(providerId,
          'video creation failed: ${_bodyHint(res)}',
          statusCode: res.statusCode);
    }
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) {
      throw ProviderException(providerId, 'video response had no id');
    }
    return id;
  }

  /// Polls a video job: status is the provider's own word
  /// ('queued'/'in_progress'/'completed'/'failed'…), url when done.
  Future<({String status, String? url})> videoStatus(String id) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/videos/$id'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) {
      throw ProviderException(providerId,
          'video status failed: ${_bodyHint(res)}',
          statusCode: res.statusCode);
    }
    final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
    return (
      status: (json['status'] as String?) ?? 'unknown',
      url: (json['video_url'] as String?) ?? (json['url'] as String?),
    );
  }

  static String _bodyHint(http.Response res) {
    try {
      final json = (jsonDecode(res.body) as Map).cast<String, Object?>();
      final error = json['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
    } catch (_) {}
    return 'HTTP ${res.statusCode}';
  }
}
