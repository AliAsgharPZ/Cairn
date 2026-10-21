@TestOn('windows')
library;

import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_toolhost/cairn_toolhost.dart';
import 'package:cairn_tools/cairn_tools.dart';
import 'package:test/test.dart';

// The named-pipe round trip can only run on a real Windows machine;
// CI's windows-build job runs this file explicitly (see
// .github/workflows/windows-build.yml). On Linux it is skipped by the
// TestOn annotation — stdio + in-memory transports cover the protocol
// itself there.
void main() {
  test('ToolHost client <-> server over a real named pipe', () async {
    final root = await Directory.systemTemp.createTemp('cairn_pipe_test');
    addTearDown(() => root.delete(recursive: true));
    const pipeName = 'cairn-toolhost-test';

    final registry = ToolRegistry([
      ...BuiltInTools.all(),
      ...PlatformTools.all(root: root),
    ]);
    final serverChannelFuture = listenNamedPipe(pipeName);
    final serveFuture = serverChannelFuture.then((channel) =>
        ToolHostServer(tools: registry).serve(channel.stream, channel.sink));

    final clientChannel = await connectNamedPipe(pipeName);
    final client = ToolHostClient(
      incoming: clientChannel.stream,
      outgoing: clientChannel.sink,
    );

    await client.ping();
    final caps = await client.capabilities();
    expect(caps.map((c) => c.id), contains('calc.eval'));
    final result = await client.invokeTool(
      'calc.eval',
      {'expression': '6*7'},
      projectId: 'p',
      agentId: 'a',
      taskId: 't',
    );
    expect(result.ok, isTrue);
    expect(result.output, contains('42'));

    await client.close();
    await clientChannel.close();
    await serveFuture.timeout(const Duration(seconds: 20));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
