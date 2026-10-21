import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:http/http.dart' as http;

/// Platform tools: filesystem, shell and HTTP. These execute **in-process**
/// wherever dart:io allows it (desktop, tests). On Windows the shipped app
/// delegates the same tool ids to the separate Tool Host process (M5);
/// on Android they operate inside the app sandbox. All of them are confined
/// to a root directory (the task working directory) and are sensitive,
/// except the read-only directory listing.
///
/// Path safety: every path is canonicalized and must stay under the root —
/// `..` escapes and symlinks pointing outside are refused.
abstract final class PlatformTools {
  /// [root] confines all filesystem tools. [httpClient] is injectable for
  /// tests.
  static List<Tool> all({required Directory root, http.Client? httpClient}) =>
      [
        FsListTool(root),
        FsReadTool(root),
        FsWriteTool(root),
        ShellRunTool(root),
        HttpGetTool(httpClient),
      ];
}

abstract class _FsTool extends Tool {
  _FsTool(this.root);
  final Directory root;

  late final Future<String> _rootCanonical =
      root.absolute.resolveSymbolicLinks();

  /// Resolves [path] (absolute, or relative to the root) to a canonical
  /// absolute path and refuses anything that escapes the root. Works for
  /// not-yet-existing paths too: `..` segments are collapsed lexically and
  /// the nearest existing ancestor is canonicalized through the filesystem,
  /// so symlink escapes are caught as well.
  Future<String> resolveUnderRoot(String path) async {
    final joined = path.startsWith(Platform.pathSeparator) ||
            (Platform.isWindows &&
                RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path))
        ? path
        : '${root.path}${Platform.pathSeparator}$path';
    final normalized = _normalizeLexically(joined);

    // Nearest existing ancestor (the path itself may not exist yet).
    var ancestor = normalized;
    final tail = <String>[];
    while (!await FileSystemEntity.isLink(ancestor) &&
        !await File(ancestor).exists() &&
        !await Directory(ancestor).exists()) {
      final parent = Directory(ancestor).parent.path;
      if (parent == ancestor) break;
      tail.insert(0, ancestor.substring(parent.length + 1));
      ancestor = parent;
    }
    var canonicalAncestor = await File(ancestor).absolute.resolveSymbolicLinks();
    final sep = Platform.pathSeparator;
    if (tail.isNotEmpty) {
      canonicalAncestor = '$canonicalAncestor$sep${tail.join(sep)}';
    }
    final rootCanonical = await _rootCanonical;
    if (canonicalAncestor != rootCanonical &&
        !canonicalAncestor.startsWith('$rootCanonical$sep')) {
      throw FsEscapeException(path);
    }
    return canonicalAncestor;
  }

  Future<File> fileUnderRoot(String path) async =>
      File(await resolveUnderRoot(path));

  Future<Directory> dirUnderRoot(String path) async =>
      Directory(await resolveUnderRoot(path));

  static String _normalizeLexically(String path) {
    final sep = Platform.pathSeparator;
    final isAbsolute = path.startsWith(sep);
    final out = <String>[];
    for (final seg in path.split(sep)) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(seg);
    }
    return '${isAbsolute ? sep : ''}${out.join(sep)}';
  }

  String requirePath(Map<String, Object?> input) {
    final p = input['path'];
    if (p is! String || p.trim().isEmpty) {
      throw const FormatException('a non-empty "path" input is required');
    }
    return p;
  }
}

/// A filesystem path tried to escape the tool root.
class FsEscapeException implements Exception {
  FsEscapeException(this.path);
  final String path;
  @override
  String toString() => 'path "$path" escapes the allowed root directory';
}

class FsListTool extends _FsTool {
  FsListTool(super.root);
  @override
  String get id => 'fs.list';
  @override
  String get description =>
      'Lists files and folders inside the working directory. Input: {"path": string (optional, default ".")}.';
  @override
  bool get sensitive => false;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    try {
      final dir = await dirUnderRoot((input['path'] as String?) ?? '.');
      if (!await dir.exists()) {
        return ToolResult.failure('directory does not exist: ${dir.path}');
      }
      final entries = await dir.list().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final lines = [
        for (final e in entries)
          '${e is Directory ? '[dir] ' : '      '}${e.path.substring(dir.path.length + 1)}',
      ];
      return ToolResult.success(
        lines.isEmpty ? '(empty directory)' : lines.join('\n'),
        data: {'count': entries.length},
      );
    } on FsEscapeException catch (e) {
      return ToolResult.failure('$e');
    }
  }
}

class FsReadTool extends _FsTool {
  FsReadTool(super.root);
  @override
  String get id => 'fs.read';
  @override
  String get description =>
      'Reads a UTF-8 text file inside the working directory (max 256 KB). Input: {"path": string}.';
  @override
  bool get sensitive => true;

  static const int maxBytes = 256 * 1024;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    try {
      final file = await fileUnderRoot(requirePath(input));
      if (!await file.exists()) {
        return ToolResult.failure('file does not exist: ${input['path']}');
      }
      final length = await file.length();
      if (length > maxBytes) {
        return ToolResult.failure(
            'file is too large ($length bytes > $maxBytes)');
      }
      final text = await file.readAsString();
      return ToolResult.success(text, data: {'bytes': length});
    } on FsEscapeException catch (e) {
      return ToolResult.failure('$e');
    } on FormatException catch (e) {
      return ToolResult.failure(e.message);
    }
  }
}

class FsWriteTool extends _FsTool {
  FsWriteTool(super.root);
  @override
  String get id => 'fs.write';
  @override
  String get description =>
      'Writes a UTF-8 text file inside the working directory (creates parent folders). Input: {"path": string, "content": string}.';
  @override
  bool get sensitive => true;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    try {
      final content = input['content'];
      if (content is! String) {
        return ToolResult.failure('fs.write needs a string "content"');
      }
      final file = await fileUnderRoot(requirePath(input));
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
      return ToolResult.success('wrote ${content.length} chars to ${input['path']}',
          data: {'bytes': utf8.encode(content).length});
    } on FsEscapeException catch (e) {
      return ToolResult.failure('$e');
    } on FormatException catch (e) {
      return ToolResult.failure(e.message);
    }
  }
}

/// Runs one command (no shell interpolation — argv form only) inside the
/// root directory, with a timeout and truncated output.
class ShellRunTool extends Tool {
  ShellRunTool(this.root, {this.timeout = const Duration(seconds: 30)});

  final Directory root;
  final Duration timeout;

  @override
  String get id => 'shell.run';
  @override
  String get description =>
      'Runs a command with arguments (no shell). Input: {"command": string, "args": string[]}. Returns exit code and output.';
  @override
  bool get sensitive => true;

  static const int maxOutputChars = 20000;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    final command = input['command'];
    if (command is! String || command.trim().isEmpty) {
      return ToolResult.failure('shell.run needs a non-empty "command"');
    }
    final rawArgs = input['args'];
    final args = rawArgs is List ? rawArgs.map((e) => '$e').toList() : <String>[];
    try {
      final result = await Process.run(
        command,
        args,
        workingDirectory:
            (context.workingDirectory ?? root.path).toString(),
        runInShell: false,
      ).timeout(timeout);
      String truncate(Object? s) {
        final t = '$s';
        return t.length > maxOutputChars
            ? '${t.substring(0, maxOutputChars)}\n…[truncated]'
            : t;
      }

      final out = truncate(result.stdout).trimRight();
      final err = truncate(result.stderr).trimRight();
      final combined = [
        if (out.isNotEmpty) out,
        if (err.isNotEmpty) '[stderr] $err',
      ].join('\n');
      return ToolResult(
        ok: result.exitCode == 0,
        output: 'exit ${result.exitCode}${combined.isEmpty ? '' : '\n$combined'}',
        data: {'exitCode': result.exitCode},
      );
    } on TimeoutException {
      return ToolResult.failure('command timed out after ${timeout.inSeconds}s');
    } catch (e) {
      return ToolResult.failure('could not run "$command": $e');
    }
  }
}

/// HTTP GET with a size cap. Network tool: refused by the orchestrator when
/// the agent's policy disallows network.
class HttpGetTool extends Tool {
  HttpGetTool([http.Client? client]) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get id => 'http.get';
  @override
  String get description =>
      'Fetches a URL with HTTP GET (max 512 KB of body). Input: {"url": string}.';
  @override
  bool get sensitive => true;
  @override
  bool get requiresNetwork => true;

  static const int maxBytes = 512 * 1024;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    final url = input['url'];
    if (url is! String || url.trim().isEmpty) {
      return ToolResult.failure('http.get needs a non-empty "url"');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return ToolResult.failure('only http/https URLs are allowed');
    }
    try {
      final res = await _client
          .get(uri)
          .timeout(const Duration(seconds: 20));
      var body = res.body;
      var truncated = false;
      if (body.length > maxBytes) {
        body = body.substring(0, maxBytes);
        truncated = true;
      }
      return ToolResult(
        ok: res.statusCode >= 200 && res.statusCode < 300,
        output:
            'HTTP ${res.statusCode}\n$body${truncated ? '\n…[truncated]' : ''}',
        data: {'statusCode': res.statusCode},
      );
    } catch (e) {
      return ToolResult.failure('request failed: $e');
    }
  }
}
