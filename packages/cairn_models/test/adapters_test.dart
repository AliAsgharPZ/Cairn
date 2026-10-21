import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:test/test.dart';

/// Spins up an in-process HTTP server that records the last request and
/// replies with [respond]. Same-process loopback only (test doubles for the
/// real network adapters — the adapters under test are the real code).
Future<(HttpServer, Map<String, Object?>)> _server(
    FutureOr<Map<String, Object?>?> Function(HttpRequest) respond) async {
  final captured = <String, Object?>{};
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    captured['path'] = req.uri.path;
    captured['auth'] = req.headers.value('authorization');
    captured['apiKey'] = req.headers.value('x-api-key');
    final body = await utf8.decoder.bind(req).join();
    captured['body'] = body.isEmpty ? null : jsonDecode(body);
    final out = await respond(req);
    req.response
      ..statusCode = (out?['__status'] as int?) ?? 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(out?..remove('__status')));
    await req.response.close();
  });
  return (server, captured);
}

final _config =
    ModelConfig(providerId: 'openai-compatible', modelId: 'test-model');
final _req = ModelRequest(messages: [
  const ChatMessage(ChatRole.system, 'Be terse.'),
  const ChatMessage(ChatRole.user, 'سلام'), // Persian through the wire.
]);

void main() {
  group('OpenAiCompatibleProvider', () {
    test('sends a well-formed request and parses the completion', () async {
      final (server, captured) = await _server((_) async => {
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'سلام! چطورم؟'}
              }
            ],
            'usage': {'prompt_tokens': 11, 'completion_tokens': 7},
          });
      addTearDown(server.close);
      final provider = OpenAiCompatibleProvider(
        apiKeyResolver: () async => 'sk-test-123',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
      );
      final res = await provider.complete(_config, _req);
      expect(res.text, 'سلام! چطورم؟');
      expect(res.usage.promptTokens, 11);
      expect(res.usage.completionTokens, 7);
      expect(captured['path'], '/v1/chat/completions');
      expect(captured['auth'], 'Bearer sk-test-123');
      final body = captured['body'] as Map;
      expect(body['model'], 'test-model');
      expect((body['messages'] as List).last['content'], 'سلام');
    });

    test('HTTP errors surface as ProviderException with the status',
        () async {
      final (server, _) = await _server((_) async =>
          {'__status': 401, 'error': {'message': 'bad key'}});
      addTearDown(server.close);
      final provider = OpenAiCompatibleProvider(
        apiKeyResolver: () async => 'sk-wrong',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
      );
      await expectLater(
        provider.complete(_config, _req),
        throwsA(isA<ProviderException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('missing API key fails before any network call', () async {
      final provider = OpenAiCompatibleProvider(
        apiKeyResolver: () async => null,
        baseUrl: 'http://127.0.0.1:1/v1',
      );
      await expectLater(
        provider.complete(_config, _req),
        throwsA(isA<ProviderException>()
            .having((e) => e.message, 'message', contains('API key'))),
      );
    });
  });

  group('AnthropicProvider', () {
    test('lifts system into the system field and parses text blocks',
        () async {
      final (server, captured) = await _server((_) async => {
            'content': [
              {'type': 'text', 'text': 'Hello '},
              {'type': 'text', 'text': 'world'},
            ],
            'usage': {'input_tokens': 5, 'output_tokens': 3},
          });
      addTearDown(server.close);
      final provider = AnthropicProvider(
        apiKeyResolver: () async => 'ak-1',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
      );
      final res = await provider.complete(
          ModelConfig(providerId: 'anthropic', modelId: 'claude-test'), _req);
      expect(res.text, 'Hello world');
      expect(res.usage.promptTokens, 5);
      expect(captured['apiKey'], 'ak-1');
      final body = captured['body'] as Map;
      expect(body['system'], 'Be terse.');
      expect((body['messages'] as List), hasLength(1)); // system removed
    });
  });

  group('OllamaProvider', () {
    test('parses chat response and eval counts', () async {
      final (server, captured) = await _server((_) async => {
            'message': {'role': 'assistant', 'content': 'done'},
            'prompt_eval_count': 9,
            'eval_count': 2,
          });
      addTearDown(server.close);
      final provider =
          OllamaProvider(baseUrl: 'http://127.0.0.1:${server.port}');
      final res = await provider.complete(
          ModelConfig(providerId: 'ollama', modelId: 'llama3.1'), _req);
      expect(res.text, 'done');
      expect(res.usage.promptTokens, 9);
      expect(captured['path'], '/api/chat');
    });

    test('an unreachable server is a ProviderException, not a silent swap',
        () async {
      // Bind then close a server to get a definitely-closed port.
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final provider = OllamaProvider(baseUrl: 'http://127.0.0.1:$port');
      await expectLater(
        provider.complete(
            ModelConfig(providerId: 'ollama', modelId: 'llama3.1'), _req),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  group('FakeModelProvider', () {
    test('plays the script in order, records requests, then throws',
        () async {
      final fake = FakeModelProvider(['one', 'two']);
      expect((await fake.complete(_config, _req)).text, 'one');
      expect((await fake.complete(_config, _req)).text, 'two');
      expect(fake.requests, hasLength(2));
      await expectLater(fake.complete(_config, _req), throwsStateError);
    });
  });
}
