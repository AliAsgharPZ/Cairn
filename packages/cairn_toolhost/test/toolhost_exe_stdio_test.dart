import 'dart:async';
import 'dart:io';

import 'package:cairn_toolhost/cairn_toolhost.dart';
import 'package:test/test.dart';

// Runtime proof of the SHIPPED Windows transport: the compiled
// cairn_tool_host.exe, spawned as a child process and spoken to over
// its stdio (framed JSON-RPC) — ping, capabilities, and a real tool
// invocation. CI's windows-build job compiles the exe and sets
// CAIRN_TOOLHOST_EXE; everywhere else this test no-ops (the protocol
// itself is covered cross-platform by the in-process stdio tests).
void main() {
  test('compiled Tool Host exe answers over stdio', () async {
    final exe = Platform.environment['CAIRN_TOOLHOST_EXE'];
    if (exe == null || exe.isEmpty) {
      // ignore: avoid_print
      print('CAIRN_TOOLHOST_EXE not set — exe stdio proof skipped');
      return;
    }
    final root = await Directory.systemTemp.createTemp('cairn_exe_test');
    addTearDown(() => root.delete(recursive: true));
    final process = await Process.start(exe, ['--root', root.path]);
    addTearDown(() => process.kill());
    unawaited(process.stderr.drain<void>());
    final client = ToolHostClient(
      incoming: process.stdout,
      outgoing: process.stdin,
    );
    await client.ping().timeout(const Duration(seconds: 15));
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
    process.kill();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
