import 'dart:io';
import 'dart:isolate';

import 'package:cairn_training/cairn_training.dart';
import 'package:flutter/material.dart';

import '../ui/strings.dart';
import '../ui/tokens.dart';

/// The chain's small trainable models (v1.2): one-tap REAL training
/// of the language detector and the interpreter on the bundled
/// corpora, and one-tap building of the fa↔en phrase translator.
/// Each result is saved to the smart-model store with its honest
/// held-out metric, ready to bind to pipeline steps. Training runs
/// in an isolate so the UI never freezes.
class SmartModelsSection extends StatefulWidget {
  const SmartModelsSection({super.key, required this.baseDir});

  final Directory baseDir;

  @override
  State<SmartModelsSection> createState() => _SmartModelsSectionState();
}

class _SmartModelsSectionState extends State<SmartModelsSection> {
  List<SmartModel> _models = const [];
  bool _busy = false;
  String _status = '';

  SmartModelStore get _store =>
      SmartModelStore(Directory('${widget.baseDir.path}/models'));

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final models = await _store.list();
    if (mounted) setState(() => _models = models);
  }

  static ({List<double> losses, double heldOut, Map<String, Object?> payload})
      _trainClassifier(
    List<({String text, String label})> corpus,
    List<String> labels,
    int epochs,
  ) {
    // Deterministic 80/20 split: every 5th example is held out.
    final train = <({String text, String label})>[];
    final held = <({String text, String label})>[];
    for (var i = 0; i < corpus.length; i++) {
      (i % 5 == 4 ? held : train).add(corpus[i]);
    }
    final clf = TextClassifier(labels: labels);
    final losses = clf.train(train, epochs: epochs);
    final acc = clf.accuracy(held);
    // Final model: retrain on ALL data so nothing is wasted.
    final full = TextClassifier(labels: labels);
    full.train(corpus, epochs: epochs);
    return (losses: losses, heldOut: acc, payload: full.toJson());
  }

  Future<void> _train(String kind) async {
    final s = S.of(context);
    setState(() {
      _busy = true;
      _status = '…';
    });
    try {
      final isLang = kind == SmartModelKind.langDetect;
      final result = await Isolate.run(() => _trainClassifier(
            isLang ? langDetectCorpus : intentCorpus,
            isLang
                ? const ['fa', 'en']
                : const ['question', 'task', 'chat', 'translate'],
            isLang ? 40 : 60,
          ));
      final now = DateTime.now().toUtc();
      final model = SmartModel(
        id: '$kind:${now.millisecondsSinceEpoch}',
        name: isLang ? 'تشخیص زبان' : 'مفسر',
        kind: kind,
        createdAtIso: now.toIso8601String(),
        metrics: {
          'accuracy': result.heldOut,
          'examples': isLang ? langDetectCorpus.length : intentCorpus.length,
        },
        payloadJson: result.payload,
      );
      await _store.save(model);
      await _reload();
      if (mounted) {
        setState(() => _status =
            s.smartTrained('${(result.heldOut * 100).toStringAsFixed(0)}٪'));
      }
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _buildTranslator() async {
    final s = S.of(context);
    setState(() {
      _busy = true;
      _status = '…';
    });
    final translator = PhraseTranslator.bundled();
    final now = DateTime.now().toUtc();
    await _store.save(SmartModel(
      id: '${SmartModelKind.translator}:${now.millisecondsSinceEpoch}',
      name: 'مترجم فارسی↔انگلیسی',
      kind: SmartModelKind.translator,
      createdAtIso: now.toIso8601String(),
      metrics: {'pairs': translationPairCorpus.length},
      payloadJson: translator.toJson(),
    ));
    await _reload();
    if (mounted) {
      setState(() {
        _busy = false;
        _status = s.smartPairs(translationPairCorpus.length);
      });
    }
  }

  String _metricText(S s, SmartModel m) {
    if (m.kind == SmartModelKind.translator) {
      return s.smartMeta(m.kind, '${m.metrics['pairs'] ?? ''}');
    }
    final acc = (m.metrics['accuracy'] as num?) ?? 0;
    return s.smartMeta(m.kind, '${(acc * 100).toStringAsFixed(0)}٪');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.smartTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.xs),
        Text(s.smartHelp, style: theme.textTheme.bodySmall),
        const SizedBox(height: CairnSpacing.sm),
        Wrap(
          spacing: CairnSpacing.sm,
          runSpacing: CairnSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed:
                  _busy ? null : () => _train(SmartModelKind.langDetect),
              icon: const Icon(Icons.language),
              label: Text(s.trainLangDetect),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _train(SmartModelKind.intent),
              icon: const Icon(Icons.psychology_outlined),
              label: Text(s.trainIntent),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _buildTranslator,
              icon: const Icon(Icons.translate),
              label: Text(s.buildTranslator),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: CairnSpacing.sm),
          const LinearProgressIndicator(),
        ],
        if (_status.isNotEmpty) ...[
          const SizedBox(height: CairnSpacing.sm),
          Text(_status, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: CairnSpacing.sm),
        if (_models.isEmpty)
          Text(s.smartNone, style: theme.textTheme.bodySmall)
        else
          for (final m in _models)
            Card(
              child: ListTile(
                leading: Icon(switch (m.kind) {
                  SmartModelKind.langDetect => Icons.language,
                  SmartModelKind.intent => Icons.psychology_outlined,
                  _ => Icons.translate,
                }),
                title: Text(m.name),
                subtitle: Text(_metricText(s, m)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await _store.delete(m.id);
                    await _reload();
                  },
                ),
              ),
            ),
        const Divider(height: CairnSpacing.xxl),
      ],
    );
  }
}
