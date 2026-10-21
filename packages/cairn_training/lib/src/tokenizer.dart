/// A Unicode word-level tokenizer (Flow 2: tokenization stage).
///
/// Tokens are runs of letters/digits (Unicode-aware, so Persian and
/// Arabic script tokenize correctly) or single punctuation characters.
/// This is an honest v1 tokenizer — word-level with an <unk> fallback,
/// NOT byte-pair encoding; out-of-vocabulary words map to <unk> and
/// that limitation is stated wherever the tokenizer is presented.
class WordTokenizer {
  WordTokenizer._(this.vocab, this.itos);

  static const int padId = 0;
  static const int unkId = 1;
  static const int bosId = 2;
  static const int eosId = 3;

  static const Map<int, String> _specials = {
    padId: '<pad>',
    unkId: '<unk>',
    bosId: '<bos>',
    eosId: '<eos>',
  };

  final Map<String, int> vocab;
  final List<String> itos;

  int get vocabSize => itos.length;

  static final RegExp _tokenPattern =
      RegExp(r'\p{L}+|\p{N}+|[^\s\p{L}\p{N}]', unicode: true);

  /// Splits text into raw tokens (no vocab mapping).
  static List<String> tokenizeRaw(String text) => [
        for (final m in _tokenPattern.allMatches(text)) m.group(0)!,
      ];

  /// Builds a vocabulary from [texts]: tokens with frequency >=
  /// [minFrequency], most frequent first, capped at [maxVocab]
  /// (including the 4 special tokens).
  factory WordTokenizer.train(
    Iterable<String> texts, {
    int maxVocab = 8000,
    int minFrequency = 1,
  }) {
    final freq = <String, int>{};
    for (final text in texts) {
      for (final token in tokenizeRaw(text)) {
        freq[token] = (freq[token] ?? 0) + 1;
      }
    }
    final sorted = freq.entries.where((e) => e.value >= minFrequency).toList()
      ..sort((a, b) {
        final byFreq = b.value.compareTo(a.value);
        return byFreq != 0 ? byFreq : a.key.compareTo(b.key);
      });
    final rebuilt = <String>[
      _specials[0]!,
      _specials[1]!,
      _specials[2]!,
      _specials[3]!,
    ];
    for (final e in sorted) {
      if (rebuilt.length >= maxVocab) break;
      rebuilt.add(e.key);
    }
    final vocab = <String, int>{
      for (var i = 0; i < rebuilt.length; i++) rebuilt[i]: i,
    };
    return WordTokenizer._(vocab, rebuilt);
  }

  /// Encodes text to token ids. Unknown tokens become <unk>.
  List<int> encode(String text, {bool bos = true, bool eos = true}) {
    return [
      if (bos) bosId,
      for (final token in tokenizeRaw(text)) vocab[token] ?? unkId,
      if (eos) eosId,
    ];
  }

  /// Decodes ids back to text (specials are rendered as-is so tests
  /// and debugging can see them).
  String decode(List<int> ids) {
    final parts = <String>[];
    for (final id in ids) {
      if (id < 0 || id >= itos.length) continue;
      parts.add(itos[id]);
    }
    return parts.join(' ');
  }

  Map<String, Object?> toJson() => {'itos': itos};

  factory WordTokenizer.fromJson(Map<String, Object?> json) {
    final itos = (json['itos'] as List).map((e) => '$e').toList();
    return WordTokenizer._(
      {for (var i = 0; i < itos.length; i++) itos[i]: i},
      itos,
    );
  }
}
