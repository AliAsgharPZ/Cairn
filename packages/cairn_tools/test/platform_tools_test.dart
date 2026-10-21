import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_tools/cairn_tools.dart';
import 'package:test/test.dart';

const _ctx = ToolContext(projectId: 'p', agentId: 'a', taskId: 't');

void main() {
  group('platform tools', () {
    late Directory root;
    late List<Tool> tools;

    Tool byId(String id) => tools.firstWhere((t) => t.id == id);

    setUp(() async {
      root = await Directory.systemTemp.createTemp('cairn_platform_test');
      tools = PlatformTools.all(root: root);
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('write → list → read round-trip inside the root', () async {
      final write = await byId('fs.write').run(
          {'path': 'notes/a.txt', 'content': 'سلام Cairn'}, _ctx);
      expect(write.ok, isTrue);

      final list = await byId('fs.list').run({'path': 'notes'}, _ctx);
      expect(list.ok, isTrue);
      expect(list.output, contains('a.txt'));

      final read = await byId('fs.read').run({'path': 'notes/a.txt'}, _ctx);
      expect(read.ok, isTrue);
      expect(read.output, 'سلام Cairn');
    });

    test('path escapes are refused for read and write', () async {
      final read =
          await byId('fs.read').run({'path': '../secret.txt'}, _ctx);
      expect(read.ok, isFalse);
      expect(read.output, contains('escapes'));
      final write = await byId('fs.write')
          .run({'path': '/etc/cairn-evil.txt', 'content': 'x'}, _ctx);
      expect(write.ok, isFalse);
    });

    test('reading a missing file fails cleanly', () async {
      final read = await byId('fs.read').run({'path': 'nope.txt'}, _ctx);
      expect(read.ok, isFalse);
      expect(read.output, contains('does not exist'));
    });

    test('shell.run executes an argv command and reports its exit code',
        () async {
      final ok = await byId('shell.run')
          .run({'command': 'echo', 'args': ['hello-cairn']}, _ctx);
      expect(ok.ok, isTrue);
      expect(ok.output, contains('hello-cairn'));
      expect(ok.data?['exitCode'], 0);

      final bad = await byId('shell.run')
          .run({'command': 'definitely-not-a-real-binary-xyz'}, _ctx);
      expect(bad.ok, isFalse);
    });

    test('http.get fetches from a local server and flags bad URLs', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((req) {
        req.response
          ..statusCode = 200
          ..write('body-from-server');
        req.response.close();
      });
      final tool = byId('http.get');
      expect(tool.requiresNetwork, isTrue);
      expect(tool.sensitive, isTrue);
      final res = await tool
          .run({'url': 'http://127.0.0.1:${server.port}/x'}, _ctx);
      expect(res.ok, isTrue);
      expect(res.output, contains('body-from-server'));
      final bad = await tool.run({'url': 'ftp://example.com/f'}, _ctx);
      expect(bad.ok, isFalse);
    });

    test('sensitivity flags match the platform-tool policy', () {
      expect(byId('fs.list').sensitive, isFalse);
      expect(byId('fs.read').sensitive, isTrue);
      expect(byId('fs.write').sensitive, isTrue);
      expect(byId('shell.run').sensitive, isTrue);
      expect(byId('http.get').sensitive, isTrue);
    });
  });
}
