import 'dart:convert';

import 'corpora.dart';
import 'text_classifier.dart' show TextClassifier;

/// A small phrase-table translator (fa ↔ en), "trained" by building
/// its tables from parallel sentence pairs: exact sentence memory,
/// greedy longest-phrase matching, then a word lexicon fallback.
///
/// HONEST SCOPE — this is a teaching/small-domain translator: it
/// handles sentences like its training pairs and simple recombinations
/// of them. It is NOT a real translation model and the UI says so;
/// the chain's translator slot accepts a real model (e.g. Gemma via
/// Ollama, or any provider) whenever the owner connects one. The
/// slot, the pipeline and the replacement path are the deliverable;
/// this table is the always-available offline baseline.
class PhraseTranslator {
  PhraseTranslator._(this._faToEn, this._enToFa, this._lexFaEn, this._lexEnFa);

  final Map<String, String> _faToEn;
  final Map<String, String> _enToFa;
  final Map<String, String> _lexFaEn;
  final Map<String, String> _lexEnFa;

  static String _norm(String s) => TextClassifier.normalize(s)
      .replaceAll(RegExp(r'[؟?]'), '')
      .trim();

  /// Builds the tables from parallel pairs plus the core lexicon.
  factory PhraseTranslator.build(
    List<({String fa, String en})> pairs, {
    Map<String, String> lexiconFaEn = coreLexiconFaEn,
  }) {
    final faToEn = <String, String>{};
    final enToFa = <String, String>{};
    for (final p in pairs) {
      faToEn[_norm(p.fa)] = _norm(p.en);
      enToFa[_norm(p.en)] = _norm(p.fa);
    }
    return PhraseTranslator._(
      faToEn,
      enToFa,
      {for (final e in lexiconFaEn.entries) _norm(e.key): _norm(e.value)},
      {for (final e in lexiconFaEn.entries) _norm(e.value): _norm(e.key)},
    );
  }

  factory PhraseTranslator.bundled() =>
      PhraseTranslator.build(translationPairCorpus);

  /// How much of the input the tables actually covered (0..1) — the
  /// UI shows this so a mostly-passthrough "translation" is never
  /// dressed up as a real one.
  ({String text, double coverage}) translate(String input,
      {required bool toEnglish}) {
    final table = toEnglish ? _faToEn : _enToFa;
    final lexicon = toEnglish ? _lexFaEn : _lexEnFa;
    final normalized = _norm(input);
    final exact = table[normalized];
    if (exact != null) return (text: exact, coverage: 1.0);

    final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();
    final out = <String>[];
    var covered = 0;
    var i = 0;
    // Greedy longest-phrase scan (phrases up to 5 words).
    while (i < words.length) {
      String? hit;
      var hitLen = 0;
      for (var len = 5; len >= 2; len--) {
        if (i + len > words.length) continue;
        final phrase = words.sublist(i, i + len).join(' ');
        final t = table[phrase];
        if (t != null) {
          hit = t;
          hitLen = len;
          break;
        }
      }
      if (hit != null) {
        out.add(hit);
        covered += hitLen;
        i += hitLen;
        continue;
      }
      final word = words[i];
      final w = lexicon[word];
      if (w != null) {
        if (w.isNotEmpty) out.add(w);
        covered++;
      } else {
        out.add(word); // unknown: pass through, honestly uncovered
      }
      i++;
    }
    return (
      text: out.join(' '),
      coverage: words.isEmpty ? 0 : covered / words.length,
    );
  }

  Map<String, Object?> toJson() => {
        'faToEn': _faToEn,
        'enToFa': _enToFa,
        'lexFaEn': _lexFaEn,
        'lexEnFa': _lexEnFa,
      };

  factory PhraseTranslator.fromJson(Map<String, Object?> json) {
    Map<String, String> m(String key) => {
          for (final e in (json[key] as Map).entries) '${e.key}': '${e.value}',
        };
    return PhraseTranslator._(
        m('faToEn'), m('enToFa'), m('lexFaEn'), m('lexEnFa'));
  }

  String encode() => jsonEncode(toJson());
  static PhraseTranslator decode(String text) => PhraseTranslator.fromJson(
      (jsonDecode(text) as Map).cast<String, Object?>());
}
