import 'dart:math';

/// Dataset building for the training pathway (Flow 2 stages: collect →
/// clean → split). Cleaning is deterministic and reported honestly:
/// every dropped line is counted and the counts are shown to the user.

class DatasetStats {
  const DatasetStats({
    required this.rawCount,
    required this.droppedEmpty,
    required this.droppedShort,
    required this.droppedDuplicates,
    required this.keptCount,
  });

  final int rawCount;
  final int droppedEmpty;
  final int droppedShort;
  final int droppedDuplicates;
  final int keptCount;

  Map<String, Object?> toJson() => {
        'rawCount': rawCount,
        'droppedEmpty': droppedEmpty,
        'droppedShort': droppedShort,
        'droppedDuplicates': droppedDuplicates,
        'keptCount': keptCount,
      };
}

class Dataset {
  const Dataset({
    required this.train,
    required this.validation,
    required this.test,
    required this.stats,
  });

  final List<String> train;
  final List<String> validation;
  final List<String> test;
  final DatasetStats stats;
}

/// Normalizes whitespace for cleaning/dedup comparison. The kept text
/// preserves the original characters (only trimmed/collapsed ends).
String normalizeForKey(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// A deterministic PRNG (SplitMix64) so dataset splits and training
/// shuffles are identical on every device for a given seed — Dart's
/// own Random(seed) is not specified across platforms.
class SeededRandom {
  SeededRandom(int seed) : _state = seed & 0xFFFFFFFFFFFFFFFF;

  int _state;

  int nextUint64() {
    _state = (_state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF;
    var z = _state;
    z = ((z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF;
    z = ((z ^ (z >>> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF;
    return z ^ (z >>> 31);
  }

  /// Uniform double in [0, 1).
  double nextDouble() =>
      (nextUint64() >>> 11) * (1.0 / 9007199254740992.0); // 2^53

  int nextInt(int bound) => (nextDouble() * bound).floor();
}

/// Builds a cleaned, deterministically split dataset from raw lines.
///
/// - empty/whitespace-only lines are dropped (counted);
/// - lines shorter than [minLength] characters after trimming are
///   dropped (counted);
/// - duplicate lines (by whitespace/case-normalized key) are dropped
///   (counted), keeping the first occurrence;
/// - the survivors are shuffled with [seed] and split by ratio.
Dataset buildDataset(
  List<String> rawLines, {
  int minLength = 2,
  double validationRatio = 0.1,
  double testRatio = 0.1,
  int seed = 42,
}) {
  var droppedEmpty = 0;
  var droppedShort = 0;
  var droppedDuplicates = 0;
  final seen = <String>{};
  final kept = <String>[];

  for (final raw in rawLines) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      droppedEmpty++;
      continue;
    }
    if (trimmed.length < minLength) {
      droppedShort++;
      continue;
    }
    if (!seen.add(normalizeForKey(trimmed))) {
      droppedDuplicates++;
      continue;
    }
    kept.add(trimmed.replaceAll(RegExp(r'[ \t]+'), ' '));
  }

  final rng = SeededRandom(seed);
  final shuffled = List<String>.of(kept);
  for (var i = shuffled.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }

  final testCount = (shuffled.length * testRatio).round();
  final valCount = (shuffled.length * validationRatio).round();
  final test = shuffled.sublist(0, testCount);
  final validation = shuffled.sublist(testCount, testCount + valCount);
  final train = shuffled.sublist(testCount + valCount);

  return Dataset(
    train: train,
    validation: validation,
    test: test,
    stats: DatasetStats(
      rawCount: rawLines.length,
      droppedEmpty: droppedEmpty,
      droppedShort: droppedShort,
      droppedDuplicates: droppedDuplicates,
      keptCount: kept.length,
    ),
  );
}

/// One instruction-tuning example (Flow 2: instruction fine-tune stage).
class InstructionExample {
  const InstructionExample({required this.prompt, required this.completion});

  final String prompt;
  final String completion;

  Map<String, Object?> toJson() =>
      {'prompt': prompt, 'completion': completion};

  factory InstructionExample.fromJson(Map<String, Object?> json) =>
      InstructionExample(
        prompt: json['prompt'] as String? ?? '',
        completion: json['completion'] as String? ?? '',
      );

  /// The text form the LM trains on during fine-tuning.
  String format() => 'دستور: $prompt\nپاسخ: $completion';
}

final _rng = Random();

/// Shuffles a copy of [items] with [rng] (training-order shuffling —
/// platform RNG is fine here; reproducibility comes from the seed
/// the caller passes to the trainer, which uses [SeededRandom]).
List<T> shuffledCopy<T>(List<T> items, SeededRandom rng) {
  final out = List<T>.of(items);
  for (var i = out.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

Random get platformRandom => _rng;
