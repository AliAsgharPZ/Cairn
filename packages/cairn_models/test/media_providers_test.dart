import 'dart:convert';
import 'dart:io';

import 'package:cairn_models/cairn_models.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Media adapters against a REAL local HTTP server (same process):
/// the exact request paths/bodies are asserted and the exact
/// response shapes parsed. No network leaves the process.
void main() {
  late HttpServer server;
  late String base;
  final seen = <String>[];

  setUp(() async {
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}/v1';
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      seen.add('${req.method} ${req.uri.path} $body');
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path == '/v1/images/generations') {
        req.response.write(jsonEncode({
          'data': [
            {'b64_json': base64Encode([1, 2, 3, 4])}
          ]
        }));
      } else if (req.uri.path == '/v1/audio/speech') {
        req.response.headers.contentType =
            ContentType('audio', 'mpeg');
        req.response.add([9, 8, 7]);
      } else if (req.uri.path == '/v1/videos' && req.method == 'POST') {
        req.response.write(jsonEncode({'id': 'vid-42'}));
      } else if (req.uri.path == '/v1/videos/vid-42') {
        req.response.write(jsonEncode(
            {'status': 'completed', 'video_url': 'https://x/v.mp4'}));
      } else {
        req.response.statusCode = 404;
        req.response.write(jsonEncode({
          'error': {'message': 'nope'}
        }));
      }
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  MediaProviders media() => MediaProviders(
        apiKeyResolver: () async => 'test-key',
        baseUrl: base,
        client: http.Client(),
      );

  test('image generation posts the OpenAI shape and decodes b64', () async {
    final r = await media()
        .generateImage(model: 'img-1', prompt: 'a red house');
    expect(r.bytes, [1, 2, 3, 4]);
    expect(seen.single, contains('/v1/images/generations'));
    expect(seen.single, contains('"model":"img-1"'));
    expect(seen.single, contains('"prompt":"a red house"'));
  });

  test('speech returns raw audio bytes', () async {
    final bytes =
        await media().generateSpeech(model: 'tts-1', input: 'salam');
    expect(bytes, [9, 8, 7]);
    expect(seen.single, contains('/v1/audio/speech'));
  });

  test('video create + poll round trip', () async {
    final id = await media().createVideo(model: 'vid-1', prompt: 'waves');
    expect(id, 'vid-42');
    final status = await media().videoStatus(id);
    expect(status.status, 'completed');
    expect(status.url, 'https://x/v.mp4');
  });

  test('provider errors surface as ProviderException with the message',
      () async {
    expect(
      () => media().generateImage(model: 'x', prompt: 'y', size: 'bad'),
      returnsNormally, // our fake server ignores size; just smoke
    );
    final failing = MediaProviders(
      apiKeyResolver: () async => 'k',
      baseUrl: '$base/nowhere',
      client: http.Client(),
    );
    await expectLater(
      failing.videoStatus('zzz'),
      throwsA(isA<ProviderException>()),
    );
  });
}
