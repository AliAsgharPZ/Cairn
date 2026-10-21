import 'dart:async';
import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_toolhost/cairn_toolhost.dart';

/// Outcome of the Windows Tool Host boot attempt at app startup.
class ToolHostBoot {
  const ToolHostBoot({required this.status, this.registry});

  /// Plain-language status line, shown as a banner in the studio so
  /// the owner can SEE which mode the tools run in — never silent.
  final String status;

  /// Registry whose tools execute in the host process, or null when
  /// the boot failed and the app must use its local tools instead.
  final ToolRegistry? registry;
}

/// Windows startup wiring for the Tool Host (M5 tail): spawn the
/// bundled `cairn_tool_host.exe` (shipped next to `cairn_app.exe` by
/// the Windows build) as a child process, talk to it over its stdio
/// (the framed JSON-RPC protocol — the host writes nothing but
/// protocol frames to stdout; its diagnostics go to stderr), verify
/// with a ping, and build the app's [ToolRegistry] from the host's
/// tools (the host serves the built-in + platform tools, so its set
/// REPLACES the local platform tools — duplicate ids are an error in
/// [ToolRegistry]).
///
/// Transport note (2026-10-21): the shipped transport is the child
/// process's stdio. A Win32 Named Pipe transport also exists in
/// cairn_toolhost, but its Windows round-trip test repeatedly hung
/// in CI (runs 39635044715, 39653424975, 39658461234), so the pipe is
/// NOT used at runtime and is not claimed as verified; stdio is the
/// natural transport for a process the app itself spawns.
///
/// Failure is never fatal and never hidden: any problem (exe missing,
/// spawn refused, ping timeout) kills the child process and falls
/// back to local tools with the reason in [ToolHostBoot.status].
Future<ToolHostBoot> bootWindowsToolHost({
  required Directory workspaceRoot,
}) async {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final hostExe = File('$exeDir/cairn_tool_host.exe');
  if (!await hostExe.exists()) {
    return const ToolHostBoot(
      status: 'Tool Host ویندوز پیدا نشد (cairn_tool_host.exe کنار '
          'برنامه نیست) — ابزارها محلی اجرا می‌شن.',
      registry: null,
    );
  }
  Process? process;
  try {
    process = await Process.start(hostExe.path, [
      '--root',
      workspaceRoot.path,
    ]);
    // Drain stderr so a chatty host can never block on a full pipe.
    // Stdout is NOT drained: it carries the protocol frames.
    unawaited(process.stderr.drain<void>());
    final client = ToolHostClient(
      incoming: process.stdout,
      outgoing: process.stdin,
    );
    await client.ping().timeout(const Duration(seconds: 10));
    final tools = await client.toolsFromCapabilities().timeout(
      const Duration(seconds: 10),
    );
    if (tools.isEmpty) {
      throw StateError('host reported no tools');
    }
    return ToolHostBoot(
      status: 'Tool Host ویندوز وصله — ${tools.length} ابزار از پروسهٔ '
          'جدا اجرا می‌شن.',
      registry: ToolRegistry(tools),
    );
  } catch (e) {
    process?.kill();
    return ToolHostBoot(
      status: 'Tool Host ویندوز وصل نشد ($e) — ابزارها محلی اجرا می‌شن.',
      registry: null,
    );
  }
}
