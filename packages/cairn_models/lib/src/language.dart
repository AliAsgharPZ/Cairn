import 'dart:convert';

import 'package:cairn_core/cairn_core.dart';

import 'provider.dart';

/// Result of the (heuristic, local) language detection stage.
class LanguageDetection {
  const LanguageDetection(this.code, this.confidence);
  final String code;
  final double confidence;
}

/// Detects whether [text] is predominantly Persian/Arabic-script ('fa') or
/// Latin-script ('en') by codepoint ranges. Local and deterministic — no
/// model call is spent on detection.
LanguageDetection detectLanguage(String text) {
  var arabic = 0;
  var latin = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x0600 && rune <= 0x06FF) || // Arabic
        (rune >= 0xFB50 && rune <= 0xFDFF) || // Arabic Presentation Forms-A
        (rune >= 0xFE70 && rune <= 0xFEFF)) {
      // Arabic Presentation Forms-B
      arabic++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A)) {
      latin++;
    }
  }
  final total = arabic + latin;
  if (total == 0) return const LanguageDetection('en', 0.5);
  if (arabic == latin) return const LanguageDetection('en', 0.5);
  final fa = arabic > latin;
  return LanguageDetection(
      fa ? 'fa' : 'en', (fa ? arabic : latin) / total);
}

/// A user instruction after the normalization stage: the planner consumes
/// this structure, not raw chat text.
class NormalizedInstruction {
  const NormalizedInstruction({
    required this.goal,
    required this.language,
    this.inputs = const [],
    this.constraints = const [],
  });

  final String goal;
  final String language;
  final List<String> inputs;
  final List<String> constraints;

  Map<String, Object?> toJson() => {
        'goal': goal,
        'language': language,
        'inputs': inputs,
        'constraints': constraints,
      };

  factory NormalizedInstruction.fromJson(Map<String, Object?> json) =>
      NormalizedInstruction(
        goal: json['goal'] as String? ?? '',
        language: json['language'] as String? ?? 'en',
        inputs:
            (json['inputs'] as List? ?? const []).map((e) => '$e').toList(),
        constraints: (json['constraints'] as List? ?? const [])
            .map((e) => '$e')
            .toList(),
      );
}

/// The language pipeline (master spec §3): detect → translate (only when
/// needed) → normalize. Translation/normalization are model stages with
/// strict prompts; detection is local. Each stage is separately testable and
/// the model used is the agent's configured one unless overridden.
class LanguagePipeline {
  LanguagePipeline(this.provider);

  final ModelProvider provider;

  /// Translates [text] into [targetLanguage] ('fa' or 'en') using the model.
  Future<String> translate(
      ModelConfig config, String text, String targetLanguage) async {
    final target = targetLanguage == 'fa' ? 'Persian (Farsi)' : 'English';
    final res = await provider.complete(
      config,
      ModelRequest(messages: [
        ChatMessage(ChatRole.system,
            'You are a translation engine. Translate the user text into $target. '
            'Output ONLY the translation, preserving formatting, names, numbers and code.'),
        ChatMessage(ChatRole.user, text),
      ]),
    );
    return res.text.trim();
  }

  /// Normalizes a raw user instruction into a [NormalizedInstruction].
  /// Throws [FormatException] if the model does not return the required
  /// JSON structure — a malformed plan input must fail loudly, not guess.
  Future<NormalizedInstruction> normalize(
      ModelConfig config, String instruction) async {
    final detection = detectLanguage(instruction);
    final res = await provider.complete(
      config,
      ModelRequest(messages: [
        const ChatMessage(ChatRole.system,
            'You normalize a user instruction for an agent planner. '
            'Respond with ONLY a JSON object, no markdown fences, shaped as: '
            '{"goal": string, "language": "fa"|"en", "inputs": string[], "constraints": string[]}. '
            'Keep the goal in the user\'s original language.'),
        ChatMessage(ChatRole.user, instruction),
      ]),
    );
    final raw = res.text.trim();
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw FormatException(
          'Normalization did not return a JSON object: ${raw.length <= 120 ? raw : '${raw.substring(0, 120)}…'}');
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map) {
      throw const FormatException('Normalization JSON is not an object');
    }
    final normalized =
        NormalizedInstruction.fromJson(decoded.cast<String, Object?>());
    if (normalized.goal.isEmpty) {
      throw const FormatException('Normalization returned an empty goal');
    }
    // Detection is authoritative for the language tag when the model
    // disagrees with an obvious script signal.
    if (detection.confidence >= 0.8 &&
        normalized.language != detection.code) {
      return NormalizedInstruction(
        goal: normalized.goal,
        language: detection.code,
        inputs: normalized.inputs,
        constraints: normalized.constraints,
      );
    }
    return normalized;
  }
}
