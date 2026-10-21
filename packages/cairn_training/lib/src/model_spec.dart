import 'dart:math';

/// Transformer architecture specification (Flow 2: architecture &
/// size stage) with an honest parameter estimate, so the user sees
/// real numbers before choosing to train. This spec describes the
/// EXPORTED decoder-transformer configuration; the in-app trainer
/// (NeuralLanguageModel, an NNLM) uses vocabSize / hiddenSize /
/// contextLength and reports its own true parameter count.
///
/// Estimate formula (documented, standard decoder-only transformer):
/// - token embedding: vocab × hidden
/// - positional embedding: context × hidden
/// - per layer: attention QKVO = 4 × hidden², MLP = 8 × hidden²
///   (hidden→4·hidden→hidden), two LayerNorms = 4 × hidden
/// - final LayerNorm: 2 × hidden
/// - LM head: tied to the embedding (not double-counted)
class ModelSpec {
  const ModelSpec({
    required this.vocabSize,
    this.hiddenSize = 128,
    this.layers = 2,
    this.heads = 4,
    this.contextLength = 64,
  });

  final int vocabSize;
  final int hiddenSize;
  final int layers;
  final int heads;
  final int contextLength;

  List<String> validate() {
    final issues = <String>[];
    if (vocabSize < 5) issues.add('vocabSize must be at least 5');
    if (hiddenSize < 8) issues.add('hiddenSize must be at least 8');
    if (hiddenSize % heads != 0) {
      issues.add('hiddenSize must be divisible by heads');
    }
    if (layers < 1) issues.add('layers must be at least 1');
    if (contextLength < 4) issues.add('contextLength must be at least 4');
    return issues;
  }

  int get parameterCount {
    final embedding = vocabSize * hiddenSize;
    final positional = contextLength * hiddenSize;
    final perLayer =
        4 * hiddenSize * hiddenSize + // QKVO
            8 * hiddenSize * hiddenSize + // MLP up+down
            4 * hiddenSize; // two LayerNorms (weight+bias)
    final finalNorm = 2 * hiddenSize;
    return embedding + positional + layers * perLayer + finalNorm;
  }

  /// A human-readable size, e.g. "1.2M".
  String get parameterLabel {
    final p = parameterCount;
    if (p >= 1000000) return '${(p / 1000000).toStringAsFixed(1)}M';
    if (p >= 1000) return '${(p / 1000).toStringAsFixed(1)}K';
    return '$p';
  }

  /// Approximate in-memory weight size at float32 / float16.
  String memoryLabel() {
    final mb32 = parameterCount * 4 / (1024 * 1024);
    final mb16 = parameterCount * 2 / (1024 * 1024);
    return '${mb32.toStringAsFixed(1)} MB (fp32) / '
        '${mb16.toStringAsFixed(1)} MB (fp16)';
  }

  ModelSpec copyWith({int? vocabSize}) => ModelSpec(
        vocabSize: vocabSize ?? this.vocabSize,
        hiddenSize: hiddenSize,
        layers: layers,
        heads: heads,
        contextLength: contextLength,
      );

  Map<String, Object?> toJson() => {
        'vocabSize': vocabSize,
        'hiddenSize': hiddenSize,
        'layers': layers,
        'heads': heads,
        'contextLength': contextLength,
      };

  factory ModelSpec.fromJson(Map<String, Object?> json) => ModelSpec(
        vocabSize: (json['vocabSize'] as num).toInt(),
        hiddenSize: (json['hiddenSize'] as num?)?.toInt() ?? 128,
        layers: (json['layers'] as num?)?.toInt() ?? 2,
        heads: (json['heads'] as num?)?.toInt() ?? 4,
        contextLength: (json['contextLength'] as num?)?.toInt() ?? 64,
      );

  /// The capabilities a model project targets (Flow 2, first stage) —
  /// chosen by the user and stored with the project; evaluation reports
  /// against them.
  static const capabilityOptions = [
    'فارسی',
    'انگلیسی',
    'کدنویسی',
    'استدلال',
    'گفت‌وگو',
  ];

  static double _ln2 = log(2);

  /// Perplexity from mean cross-entropy (nats).
  static double perplexity(double meanLossNats) =>
      pow(e, meanLossNats).toDouble();

  static double get ln2 => _ln2;
}
