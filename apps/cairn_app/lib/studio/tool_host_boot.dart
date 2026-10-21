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
/// the Windows build), connect over a per-instance Named Pipe, verify
/// with a ping, and build the app's [ToolRegistry] from the host's
/// tools (the host serves the built-in + platform tools, so its set
/// REPLACES the local platform tools — duplicate ids are an error in
/// [ToolRegistry]).
///
/// Failure is never fatal and never hidden: any problem (exe missing,
/// pipe refused, ping timeout) kills the child process and falls back
/// to local tools with the reason in [ToolHostBoot.status].
Future<ToolHostBoot> bootWindowsToolHost({
  required Directory workspaceRoot,
}) async {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final hostExe = File('$exeDir/cairn_tool_host.exe');
  if (!await hostExe.exists()) {
    return const ToolHostBoot(
      status:
          'Tool Host ویندوز پیدا نشد (cairn_tool_host.exe کنار '
          'برنامه نیست) — ابزارها محلی اجرا می‌شن.',
      registry: null,
    );
  }
  Process? process;
  try {
    final pipeName = 'cairn-toolhost-$pid';
    process = await Process.start(hostExe.path, [
      '--root',
      workspaceRoot.path,
      '--pipe',
      pipeName,
    ]);
    // Drain stderr so a chatty host can never block on a full pipe.
    unawaited(process.stderr.drain<void>());
    unawaited(process.stdout.drain<void>());
    final channel = await connectNamedPipe(pipeName)
        .timeout(const Duration(seconds: 15));
    final client = ToolHostClient(
      incoming: channel.stream,
      outgoing: channel.sink,
    );
    await client.ping().timeout(const Duration(seconds: 10));
    final tools = await client.toolsFromCapabilities().timeout(
      const Duration(seconds: 10),
    );
    if (tools.isEmpty) {
      throw StateError('host reported no tools');
    }
    return ToolHostBoot(
      status:
          'Tool Host ویندوز وصله — ${tools.length} ابزار از پروسهٔ '
          'جدا (Named Pipe) اجرا می‌شن.',
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
