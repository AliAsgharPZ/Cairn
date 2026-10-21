import 'dart:async';
import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_toolhost/cairn_toolhost.dart';
import 'package:cairn_tools/cairn_tools.dart';
import 'package:test/test.dart';

const _ctx = ToolContext(projectId: 'p', agentId: 'a', taskId: 't');

void main() {
  group('framing', () {
    test('decodes messages split at arbitrary chunk boundaries', () async {
      final bytes = frameMessage({'id': 1, 'method': 'host.ping'});
      final source = Stream.fromIterable([
        bytes.sublist(0, 2), // inside the length prefix
        bytes.sublist(2, 7),
        bytes.sublist(7),
      ]);
      final messages = await decodeMessages(source).toList();
      expect(messages, hasLength(1));
      expect(messages.single['method'], 'host.ping');
    });
  });

  group('client <-> server (in-memory transport)', () {
    late Directory root;
    late ToolHostClient client;
    late StreamController<List<int>> clientToServer;
    late StreamController<List<int>> serverToClient;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('cairn_toolhost_test');
      clientToServer = StreamController<List<int>>();
      serverToClient = StreamController<List<int>>();
      final registry = ToolRegistry([
        ...BuiltInTools.all(),
        ...PlatformTools.all(root: root),
      ]);
      unawaited(ToolHostServer(tools: registry)
          .serve(clientToServer.stream, serverToClient.sink));
      client = ToolHostClient(
        incoming: serverToClient.stream,
        outgoing: clientToServer.sink,
      );
    });

    tearDown(() async {
      await client.close();
      await root.delete(recursive: true);
    });

    test('ping answers', () async {
      await client.ping();
    });

    test('capabilities list the platform + built-in tools', () async {
      final caps = await client.capabilities();
      final ids = caps.map((c) => c.id).toSet();
      expect(ids,
          containsAll(['fs.read', 'fs.write', 'shell.run', 'http.get', 'calc.eval']));
      final http = caps.firstWhere((c) => c.id == 'http.get');
      expect(http.requiresNetwork, isTrue);
      expect(http.sensitive, isTrue);
    });

    test('tool.invoke round-trips a filesystem write + read', () async {
      final write = await client.invokeTool(
        'fs.write',
        {'path': 'rpc.txt', 'content': 'از طریق RPC'},
        projectId: 'p',
        agentId: 'a',
        taskId: 't',
      );
      expect(write.ok, isTrue);
      final read = await client.invokeTool(
        'fs.read',
        {'path': 'rpc.txt'},
        projectId: 'p',
        agentId: 'a',
        taskId: 't',
      );
      expect(read.ok, isTrue);
      expect(read.output, 'از طریق RPC');
    });

    test('remote tools plug into a ToolRegistry like local ones', () async {
      final remoteTools = await client.toolsFromCapabilities();
      final registry = ToolRegistry(remoteTools);
      final fsRead = registry.lookup('fs.read')!;
      expect(fsRead.sensitive, isTrue);
      final result = await fsRead.run({'path': 'missing.txt'}, _ctx);
      expect(result.ok, isFalse); // a tool failure, not an RPC error
    });
  });

  group('stdio end-to-end (real host process)', () {
    test('the host executable serves over stdio', () async {
      final root = await Directory.systemTemp.createTemp('cairn_host_stdio');
      addTearDown(() => root.delete(recursive: true));
      final process = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'bin/cairn_tool_host.dart', '--root', root.path],
      );
      addTearDown(() => process.kill());
      final client = ToolHostClient.stdio(process);
      addTearDown(client.close);

      await client.ping().timeout(const Duration(seconds: 60));
      final result = await client.invokeTool(
        'calc.eval',
        {'expression': '6*7'},
        projectId: 'p',
        agentId: 'a',
        taskId: 't',
      );
      expect(result.ok, isTrue);
      expect(result.output, contains('42'));
      process.kill();
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
