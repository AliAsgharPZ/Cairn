import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_tools/cairn_tools.dart';

import 'host.dart';
import 'named_pipe.dart';

/// Entry point shared by the Tool Host executables: serves the built-in +
/// platform tools over stdio, or — on Windows, when `--pipe <name>` is
/// given — over a Named Pipe (the shipped Windows transport).
///
/// Usage: `cairn_tool_host --root <workspace-dir> [--pipe <name>]`
/// All framed protocol bytes go to the transport; diagnostics go to
/// stderr only.
Future<void> runToolHost(List<String> args) async {
  String? rootPath;
  String? pipeName;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--root' && i + 1 < args.length) rootPath = args[++i];
    if (args[i] == '--pipe' && i + 1 < args.length) pipeName = args[++i];
  }
  final root = Directory(rootPath ?? Directory.current.path);
  if (!await root.exists()) {
    stderr.writeln('tool host root does not exist: ${root.path}');
    exitCode = 64;
    return;
  }
  final registry = ToolRegistry([
    ...BuiltInTools.all(),
    ...PlatformTools.all(root: root),
  ]);
  final server = ToolHostServer(tools: registry);
  if (pipeName != null) {
    stderr.writeln('cairn tool host serving ${registry.all.length} tools '
        'over named pipe $pipeName, root=${root.path}');
    final channel = await listenNamedPipe(pipeName);
    await server.serve(channel.stream, channel.sink);
    await channel.close();
    return;
  }
  stderr.writeln(
      'cairn tool host serving ${registry.all.length} tools, root=${root.path}');
  await server.serve(stdin, stdout);
}
