import 'dart:math';
import 'dart:typed_data';

import 'dataset.dart';
import 'model_spec.dart';
import 'tokenizer.dart';

/// A small neural language model (Bengio-style NNLM) trained by real
/// gradient descent in pure Dart — Flow 2's train/checkpoint/evaluate
/// stages, at an honest scale:
///
///   context ids → embeddings (concat) → tanh hidden → softmax
///
/// It genuinely learns (training loss falls, perplexity improves,
/// checkpoints reproduce identical greedy generations). It is a
/// teaching-scale model — thousands to a few million parameters —
/// NOT a large language model, and Cairn says so wherever it is
/// presented. The same dataset/spec artifacts export for heavier
/// external training on the resource-rich peer.
class NeuralLanguageModel {
  NeuralLanguageModel._({
    required this.spec,
    required this.embeddings,
    required this.w1,
    required this.b1,
    required this.w2,
    required this.b2,
  });

  final ModelSpec spec;

  /// V×H token embeddings.
  final Float64List embeddings;

  /// H×(C·H) input→hidden weights.
  final Float64List w1;
  final Float64List b1;

  /// V×H hidden→logits weights.
  final Float64List w2;
  final Float64List b2;

  int get vocab => spec.vocabSize;
  int get hidden => spec.hiddenSize;
  int get context => spec.contextLength;

  /// The TRUE parameter count of THIS model (the NNLM's weight
  /// arrays) — deliberately separate from ModelSpec.parameterCount,
  /// which estimates a decoder transformer for export specs. The UI
  /// must show this number for in-app trained models.
  int get parameterCount =>
      embeddings.length + w1.length + b1.length + w2.length + b2.length;

  /// Xavier-initialized model.
  factory NeuralLanguageModel.fresh(ModelSpec spec, SeededRandom rng) {
    double init(int fanIn) {
      final limit = sqrt(6.0 / fanIn);
      return (rng.nextDouble() * 2 - 1) * limit;
    }

    final v = spec.vocabSize, h = spec.hiddenSize, c = spec.contextLength;
    return NeuralLanguageModel._(
      spec: spec,
      embeddings: Float64List.fromList(
          [for (var i = 0; i < v * h; i++) init(h)]),
      w1: Float64List.fromList(
          [for (var i = 0; i < h * c * h; i++) init(c * h)]),
      b1: Float64List(h),
      w2: Float64List.fromList(
          [for (var i = 0; i < v * h; i++) init(h)]),
      b2: Float64List(v),
    );
  }

  /// Forward pass: returns the hidden activations for [contextIds]
  /// (exactly [context] ids; left-pad with padId beforehand).
  Float64List _forward(List<int> contextIds, Float64List concatOut) {
    final h = hidden, c = context;
    for (var pos = 0; pos < c; pos++) {
      final token = contextIds[pos];
      final base = token * h;
      for (var j = 0; j < h; j++) {
        concatOut[pos * h + j] = embeddings[base + j];
      }
    }
    final hiddenOut = Float64List(h);
    final inDim = c * h;
    for (var i = 0; i < h; i++) {
      var sum = b1[i];
      final row = i * inDim;
      for (var j = 0; j < inDim; j++) {
        sum += w1[row + j] * concatOut[j];
      }
      hiddenOut[i] = _tanh(sum);
    }
    return hiddenOut;
  }

  static double _tanh(double x) {
    final e2x = exp(2 * x);
    return (e2x - 1) / (e2x + 1);
  }

  Float64List _logits(Float64List hiddenOut) {
    final v = vocab, h = hidden;
    final z = Float64List(v);
    for (var i = 0; i < v; i++) {
      var sum = b2[i];
      final row = i * h;
      for (var j = 0; j < h; j++) {
        sum += w2[row + j] * hiddenOut[j];
      }
      z[i] = sum;
    }
    return z;
  }

  static Float64List _softmax(Float64List z) {
    var maxZ = z[0];
    for (final value in z) {
      if (value > maxZ) maxZ = value;
    }
    final out = Float64List(z.length);
    var total = 0.0;
    for (var i = 0; i < z.length; i++) {
      out[i] = exp(z[i] - maxZ);
      total += out[i];
    }
    for (var i = 0; i < z.length; i++) {
      out[i] /= total;
    }
    return out;
  }

  /// Builds (context, target) pairs from full token-id sequences.
  static List<(List<int>, int)> sequencesToSamples(List<List<int>> sequences,
      int context) {
    final samples = <(List<int>, int)>[];
    for (final ids in sequences) {
      for (var i = 1; i < ids.length; i++) {
        final ctx = <int>[];
        for (var k = i - context; k < i; k++) {
          ctx.add(k < 0 ? WordTokenizer.padId : ids[k]);
        }
        samples.add((ctx, ids[i]));
      }
    }
    return samples;
  }

  /// One SGD pass over [samples] (already shuffled by the caller).
  /// Returns the mean loss BEFORE the update of each batch — the
  /// standard training-loss reading.
  double trainEpoch(
    List<(List<int>, int)> samples, {
    required double learningRate,
    int batchSize = 8,
  }) {
    final v = vocab, h = hidden, c = context, inDim = c * h;
    final gE = Float64List(embeddings.length);
    final gW1 = Float64List(w1.length);
    final gb1 = Float64List(b1.length);
    final gW2 = Float64List(w2.length);
    final gb2 = Float64List(b2.length);
    final concat = Float64List(inDim);

    var totalLoss = 0.0;
    var batches = 0;

    for (var start = 0; start < samples.length; start += batchSize) {
      final end = min(samples.length, start + batchSize);
      final n = end - start;
      gE.fillRange(0, gE.length, 0);
      gW1.fillRange(0, gW1.length, 0);
      gb1.fillRange(0, gb1.length, 0);
      gW2.fillRange(0, gW2.length, 0);
      gb2.fillRange(0, gb2.length, 0);
      var batchLoss = 0.0;

      for (var s = start; s < end; s++) {
        final (contextIds, target) = samples[s];
        final hiddenOut = _forward(contextIds, concat);
        final probs = _softmax(_logits(hiddenOut));
        batchLoss += -log(max(probs[target], 1e-12));

        // dz = p - onehot(y)
        final dz = Float64List.fromList(probs);
        dz[target] -= 1.0;
        // Output layer grads.
        for (var i = 0; i < v; i++) {
          gb2[i] += dz[i];
          final row = i * h;
          for (var j = 0; j < h; j++) {
            gW2[row + j] += dz[i] * hiddenOut[j];
          }
        }
        // dh = W2ᵀ dz
        final dh = Float64List(h);
        for (var j = 0; j < h; j++) {
          var sum = 0.0;
          for (var i = 0; i < v; i++) {
            sum += w2[i * h + j] * dz[i];
          }
          dh[j] = sum;
        }
        // Through tanh.
        final dpre = Float64List(h);
        for (var j = 0; j < h; j++) {
          dpre[j] = dh[j] * (1 - hiddenOut[j] * hiddenOut[j]);
        }
        for (var i = 0; i < h; i++) {
          gb1[i] += dpre[i];
          final row = i * inDim;
          for (var j = 0; j < inDim; j++) {
            gW1[row + j] += dpre[i] * concat[j];
          }
        }
        // Into the embeddings of the context tokens.
        for (var pos = 0; pos < c; pos++) {
          final token = contextIds[pos];
          final embRow = token * h;
          for (var j = 0; j < h; j++) {
            var sum = 0.0;
            for (var i = 0; i < h; i++) {
              sum += w1[i * inDim + pos * h + j] * dpre[i];
            }
            gE[embRow + j] += sum;
          }
        }
      }

      final scale = learningRate / n;
      for (var i = 0; i < embeddings.length; i++) {
        embeddings[i] -= scale * gE[i];
      }
      for (var i = 0; i < w1.length; i++) {
        w1[i] -= scale * gW1[i];
      }
      for (var i = 0; i < b1.length; i++) {
        b1[i] -= scale * gb1[i];
      }
      for (var i = 0; i < w2.length; i++) {
        w2[i] -= scale * gW2[i];
      }
      for (var i = 0; i < b2.length; i++) {
        b2[i] -= scale * gb2[i];
      }
      totalLoss += batchLoss / n;
      batches++;
    }
    return batches == 0 ? 0 : totalLoss / batches;
  }

  /// Mean next-token loss (nats) over [texts] — no updates.
  double evaluateLoss(List<String> texts, WordTokenizer tokenizer) {
    final sequences = [for (final t in texts) tokenizer.encode(t)];
    final samples = sequencesToSamples(sequences, context);
    if (samples.isEmpty) return double.nan;
    final concat = Float64List(context * hidden);
    var total = 0.0;
    for (final (contextIds, target) in samples) {
      final probs = _softmax(_logits(_forward(contextIds, concat)));
      total += -log(max(probs[target], 1e-12));
    }
    return total / samples.length;
  }

  /// Generates token ids continuing [promptIds].
  List<int> generate(
    List<int> promptIds, {
    required int maxTokens,
    double temperature = 0,
    SeededRandom? rng,
  }) {
    final out = <int>[];
    final history = List<int>.of(promptIds);
    final concat = Float64List(context * hidden);
    for (var step = 0; step < maxTokens; step++) {
      final ctx = <int>[];
      for (var k = history.length - context; k < history.length; k++) {
        ctx.add(k < 0 ? WordTokenizer.padId : history[k]);
      }
      final probs = _softmax(_logits(_forward(ctx, concat)));
      int next;
      if (temperature <= 0) {
        next = 0;
        for (var i = 1; i < probs.length; i++) {
          if (probs[i] > probs[next]) next = i;
        }
      } else {
        final r = (rng ?? SeededRandom(1234)).nextDouble();
        var cumulative = 0.0;
        next = probs.length - 1;
        for (var i = 0; i < probs.length; i++) {
          cumulative += pow(probs[i], 1.0 / temperature).toDouble();
          // (temperature applied below via re-normalized walk)
          if (r * _temperatureTotal(probs, temperature) <= cumulative) {
            next = i;
            break;
          }
        }
      }
      if (next == WordTokenizer.eosId) break;
      out.add(next);
      history.add(next);
    }
    return out;
  }

  static double _temperatureTotal(Float64List probs, double temperature) {
    var total = 0.0;
    for (final p in probs) {
      total += pow(p, 1.0 / temperature).toDouble();
    }
    return total;
  }

  // -- checkpoint serialization ------------------------------------------

  Map<String, Object?> toJson() => {
        'spec': spec.toJson(),
        'embeddings': embeddings.toList(),
        'w1': w1.toList(),
        'b1': b1.toList(),
        'w2': w2.toList(),
        'b2': b2.toList(),
      };

  factory NeuralLanguageModel.fromJson(Map<String, Object?> json) {
    Float64List read(String key) => Float64List.fromList(
        (json[key] as List).map((e) => (e as num).toDouble()).toList());
    return NeuralLanguageModel._(
      spec: ModelSpec.fromJson((json['spec'] as Map).cast<String, Object?>()),
      embeddings: read('embeddings'),
      w1: read('w1'),
      b1: read('b1'),
      w2: read('w2'),
      b2: read('b2'),
    );
  }
}

/// Trains [model] on [texts] for [epochs]; returns the per-epoch mean
/// losses. Used for BOTH the base-training and the instruction
/// fine-tune stages (fine-tuning = continued training on formatted
/// instruction texts, with its own checkpoint afterwards).
List<double> trainModel({
  required NeuralLanguageModel model,
  required List<String> texts,
  required WordTokenizer tokenizer,
  int epochs = 10,
  double learningRate = 0.5,
  int batchSize = 8,
  int seed = 42,
  void Function(int epoch, double loss)? onEpoch,
}) {
  final sequences = [for (final t in texts) tokenizer.encode(t)];
  final samples =
      NeuralLanguageModel.sequencesToSamples(sequences, model.context);
  final rng = SeededRandom(seed);
  final losses = <double>[];
  for (var epoch = 0; epoch < epochs; epoch++) {
    final shuffled = shuffledCopy(samples, rng);
    final loss = model.trainEpoch(shuffled,
        learningRate: learningRate, batchSize: batchSize);
    losses.add(loss);
    onEpoch?.call(epoch, loss);
  }
  return losses;
}
