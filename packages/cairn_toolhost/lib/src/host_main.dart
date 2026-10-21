import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_tools/cairn_tools.dart';

import 'host.dart';

/// Entry point shared by the Tool Host executables: serves the built-in +
/// platform tools over stdio. On Windows the shipped host uses the same
/// protocol over a Named Pipe; stdio is the development/test transport.
///
/// Usage: `cairn_tool_host --root <workspace-dir>`
/// All framed protocol bytes go to stdout; diagnostics go to stderr only.
Future<void> runToolHost(List<String> args) async {
  String? rootPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--root' && i + 1 < args.length) rootPath = args[++i];
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
  stderr.writeln(
      'cairn tool host serving ${registry.all.length} tools, root=${root.path}');
  await ToolHostServer(tools: registry).serve(stdin, stdout);
}
