import 'dart:convert';
import 'dart:math';

/// A small text classifier trained by REAL gradient descent in pure
/// Dart (multinomial logistic regression over hashed character
/// n-grams + word features). This is the engine behind Cairn's
/// trainable "smart models":
///
///  * the LANGUAGE DETECTOR (chain head: fa/en),
///  * the INTERPRETER (intent: question / task / chat / translate).
///
/// Honest scope: classification over short texts is exactly what a
/// model of this size does WELL (language id and intent reach high
/// accuracy with modest data). It is not a language model and never
/// generates text.
class TextClassifier {
  TextClassifier({
    required this.labels,
    this.dims = 8192,
    this.nMin = 3,
    this.nMax = 5,
  }) : _weights = [
          for (var i = 0; i < labels.length; i++)
            List<double>.filled(dims, 0),
        ],
        _bias = List<double>.filled(labels.length, 0);

  TextClassifier._from(this.labels, this.dims, this.nMin, this.nMax,
      this._weights, this._bias);

  final List<String> labels;
  final int dims;
  final int nMin;
  final int nMax;
  final List<List<double>> _weights;
  final List<double> _bias;

  /// Shared normalization for Persian + English: lowercases, maps
  /// Arabic-script variants to Persian forms, drops diacritics,
  /// treats ZWNJ as a space, collapses whitespace.
  static String normalize(String text) {
    var t = text.toLowerCase();
    t = t
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ة', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('إ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('\u0640', '') // tatweel
        .replaceAll('\u200c', ' ') // ZWNJ
        .replaceAll(RegExp(r'[\u064b-\u0652]'), ''); // Arabic diacritics
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// Sparse feature vector: word unigrams (prefixed w:) + character
  /// n-grams over the space-padded text, hashed into [dims] buckets,
  /// L2-normalized. Character n-grams are what make language id work
  /// even on two-word inputs.
  Map<int, double> features(String text) {
    final t = normalize(text);
    final counts = <int, double>{};
    void add(String feature) {
      final h = _fnv1a(feature) % dims;
      counts[h] = (counts[h] ?? 0) + 1;
    }

    for (final word in t.split(' ')) {
      if (word.isNotEmpty) add('w:$word');
    }
    final padded = ' $t ';
    final runes = padded.runes.toList();
    for (var n = nMin; n <= nMax; n++) {
      for (var i = 0; i + n <= runes.length; i++) {
        add('c:${String.fromCharCodes(runes.sublist(i, i + n))}');
      }
    }
    var norm = 0.0;
    for (final v in counts.values) {
      norm += v * v;
    }
    norm = sqrt(max(norm, 1e-12));
    return {for (final e in counts.entries) e.key: e.value / norm};
  }

  static int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  List<double> _scores(Map<int, double> x) {
    final scores = List<double>.from(_bias);
    for (var l = 0; l < labels.length; l++) {
      final w = _weights[l];
      var sum = scores[l];
      x.forEach((i, v) => sum += w[i] * v);
      scores[l] = sum;
    }
    return scores;
  }

  static List<double> _softmax(List<double> scores) {
    final maxScore = scores.reduce(max);
    var sum = 0.0;
    final out = [for (final s in scores) exp(s - maxScore)];
    for (final v in out) {
      sum += v;
    }
    return [for (final v in out) v / sum];
  }

  /// Predicted label + its probability.
  ({String label, double confidence, Map<String, double> probabilities})
      predict(String text) {
    final probs = _softmax(_scores(features(text)));
    var best = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    return (
      label: labels[best],
      confidence: probs[best],
      probabilities: {
        for (var i = 0; i < labels.length; i++) labels[i]: probs[i]
      },
    );
  }

  /// Trains with shuffled SGD; returns the per-epoch mean losses so
  /// the UI can show learning honestly (loss must FALL).
  List<double> train(
    List<({String text, String label})> examples, {
    int epochs = 30,
    double learningRate = 0.6,
    double l2 = 1e-5,
    Random? random,
  }) {
    final rng = random ?? Random(42);
    final data = [
      for (final e in examples)
        (x: features(e.text), y: labels.indexOf(e.label)),
    ]..removeWhere((d) => d.y < 0);
    final losses = <double>[];
    for (var epoch = 0; epoch < epochs; epoch++) {
      data.shuffle(rng);
      var totalLoss = 0.0;
      for (final d in data) {
        final probs = _softmax(_scores(d.x));
        totalLoss += -log(max(probs[d.y], 1e-12));
        for (var l = 0; l < labels.length; l++) {
          final grad = probs[l] - (l == d.y ? 1.0 : 0.0);
          final w = _weights[l];
          d.x.forEach((i, v) {
            w[i] -= learningRate * (grad * v + l2 * w[i]);
          });
          _bias[l] -= learningRate * grad * 0.1;
        }
      }
      losses.add(totalLoss / max(data.length, 1));
    }
    return losses;
  }

  /// Fraction of [examples] predicted correctly — the number the UI
  /// shows as the model's accuracy on held-out data.
  double accuracy(List<({String text, String label})> examples) {
    if (examples.isEmpty) return 0;
    var correct = 0;
    for (final e in examples) {
      if (predict(e.text).label == e.label) correct++;
    }
    return correct / examples.length;
  }

  Map<String, Object?> toJson() => {
        'labels': labels,
        'dims': dims,
        'nMin': nMin,
        'nMax': nMax,
        'bias': _bias,
        'weights': [
          for (final w in _weights)
            {
              for (var i = 0; i < w.length; i++)
                if (w[i] != 0) '$i': w[i],
            },
        ],
      };

  factory TextClassifier.fromJson(Map<String, Object?> json) {
    final labels =
        (json['labels'] as List).map((e) => '$e').toList(growable: false);
    final dims = (json['dims'] as num).toInt();
    final weights = <List<double>>[];
    for (final sparse in (json['weights'] as List)) {
      final w = List<double>.filled(dims, 0);
      (sparse as Map).forEach((k, v) {
        w[int.parse('$k')] = (v as num).toDouble();
      });
      weights.add(w);
    }
    return TextClassifier._from(
      labels,
      dims,
      (json['nMin'] as num).toInt(),
      (json['nMax'] as num).toInt(),
      weights,
      (json['bias'] as List).map((e) => (e as num).toDouble()).toList(),
    );
  }

  String encode() => jsonEncode(toJson());
  static TextClassifier decode(String text) =>
      TextClassifier.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
}
