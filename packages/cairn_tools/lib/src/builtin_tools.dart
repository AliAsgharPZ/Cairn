import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';

import 'calc.dart';

/// Pure-Dart built-in tools that work identically on Android and Windows.
/// None of them is sensitive: they touch no files, no network, no shell.
/// Platform tools (fs/shell/http) are registered separately in M5 and are
/// sensitive by default.
abstract final class BuiltInTools {
  static List<Tool> all() => [
        ClockNowTool(),
        CalcEvalTool(),
        TextStatsTool(),
        TextTransformTool(),
        IdUuidTool(),
      ];

  /// A registry pre-populated with the built-ins.
  static ToolRegistry registry() => ToolRegistry(all());
}

/// Returns the current date/time (UTC ISO-8601 and local).
class ClockNowTool implements Tool {
  @override
  String get id => 'clock.now';
  @override
  String get description =>
      'Returns the current date and time (UTC and local) as ISO-8601.';
  @override
  bool get sensitive => false;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    final now = DateTime.now();
    return ToolResult.success(
      'UTC: ${now.toUtc().toIso8601String()} · Local: ${now.toIso8601String()}',
      data: {
        'utc': now.toUtc().toIso8601String(),
        'local': now.toIso8601String(),
        'epochMs': now.millisecondsSinceEpoch,
      },
    );
  }
}

/// Evaluates an arithmetic expression from input {"expression": "2*(3+4)"}.
class CalcEvalTool implements Tool {
  @override
  String get id => 'calc.eval';
  @override
  String get description =>
      'Evaluates an arithmetic expression (+ - * / % ^, parentheses). '
      'Input: {"expression": string}.';
  @override
  bool get sensitive => false;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    final expr = input['expression'];
    if (expr is! String || expr.trim().isEmpty) {
      return ToolResult.failure('calc.eval needs a non-empty "expression"');
    }
    try {
      final value = evaluateExpression(expr);
      return ToolResult.success(formatNumber(value), data: {'value': value});
    } on FormatException catch (e) {
      return ToolResult.failure('Invalid expression: ${e.message}');
    }
  }
}

/// Word/character statistics for a text.
class TextStatsTool implements Tool {
  @override
  String get id => 'text.stats';
  @override
  String get description =>
      'Counts words, characters and sentences and estimates reading time. '
      'Input: {"text": string}.';
  @override
  bool get sensitive => false;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    final text = input['text'];
    if (text is! String) {
      return ToolResult.failure('text.stats needs a string "text"');
    }
    final words =
        text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final chars = text.length;
    final charsNoSpaces = text.replaceAll(RegExp(r'\s'), '').length;
    final sentences =
        RegExp(r'[.!?…]+').allMatches(text).length + ((words > 0 && !RegExp(r'[.!?…]\s*$').hasMatch(text.trim())) ? 1 : 0);
    final readingMinutes = words == 0 ? 0.0 : words / 200.0;
    return ToolResult.success(
      '$words words · $chars characters · $sentences sentences · '
      '~${readingMinutes.toStringAsFixed(1)} min read',
      data: {
        'words': words,
        'characters': chars,
        'charactersNoSpaces': charsNoSpaces,
        'sentences': sentences,
        'readingMinutes': readingMinutes,
      },
    );
  }
}

/// Case/whitespace transforms for a text.
class TextTransformTool implements Tool {
  @override
  String get id => 'text.transform';
  @override
  String get description =>
      'Transforms text. Input: {"text": string, "op": '
      '"upper"|"lower"|"title"|"trim"|"reverse"}.';
  @override
  bool get sensitive => false;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    final text = input['text'];
    final op = input['op'];
    if (text is! String || op is! String) {
      return ToolResult.failure('text.transform needs "text" and "op"');
    }
    final out = switch (op) {
      'upper' => text.toUpperCase(),
      'lower' => text.toLowerCase(),
      'trim' => text.trim(),
      'reverse' => text.runes.toList().reversed.map(String.fromCharCode).join(),
      'title' => text.splitMapJoin(
          RegExp(r'\S+'),
          onMatch: (m) {
            final w = m[0]!;
            return w[0].toUpperCase() + w.substring(1).toLowerCase();
          },
        ),
      _ => null,
    };
    if (out == null) {
      return ToolResult.failure('Unknown op "$op"');
    }
    return ToolResult.success(out);
  }
}

/// Generates a fresh UUID v4.
class IdUuidTool implements Tool {
  @override
  String get id => 'id.uuid';
  @override
  String get description => 'Generates a random UUID v4 identifier.';
  @override
  bool get sensitive => false;

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    final id = newId();
    return ToolResult.success(id, data: {'uuid': id});
  }
}
