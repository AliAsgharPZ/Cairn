import 'dart:convert';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:flutter/material.dart';

import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'models_section.dart';
import 'project_store.dart';
import 'provider_settings.dart';

/// Model training (M9 / Flow 2): capabilities → data → cleaning report
/// → splits → tokenizer → architecture → REAL training (the in-app
/// NNLM, gradient descent in Dart) with live loss → checkpoint →
/// perplexity evaluation → instruction fine-tune → model registry →
/// serve as a Cairn provider / playground generation.
///
/// Scale honesty, shown in the UI: the in-app trainer builds SMALL
/// word-level models (thousands–millions of parameters). The dataset
/// and specs are the same artifacts an external trainer would consume
/// on the resource-rich peer; nothing here pretends to be an LLM.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({
    super.key,
    required this.baseDir,
    required this.registry,
    required this.settingsStore,
    this.onProvidersChanged,
    this.projectStore,
    this.toolRegistry,
  });

  final Directory baseDir;
  final ModelRegistryStore registry;
  final ProviderSettingsStore settingsStore;
  final VoidCallback? onProvidersChanged;

  /// When present, a trained model can be assigned a clear owner: the
  /// user picks «مدل مستقل» or one concrete agent (project + agent) and
  /// the model is wired as that agent's brain on registration.
  final ProjectStore? projectStore;

  /// The app's built-in tools, offered when creating agent models.
  final ToolRegistry? toolRegistry;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  final TextEditingController _nameController = TextEditingController(
    text: 'مدل من',
  );
  final TextEditingController _dataController = TextEditingController();
  final TextEditingController _instructController = TextEditingController();
  final TextEditingController _playController = TextEditingController();
  final Set<String> _capabilities = {'فارسی'};
  Dataset? _dataset;
  WordTokenizer? _tokenizer;
  NeuralLanguageModel? _model;
  List<double> _losses = const [];
  double? _perplexity;
  List<RegisteredModel> _models = const [];
  String? _selectedModelId;
  String _playOutput = '';
  String _status = '';
  bool _busy = false;
  int _hidden = 32;
  int _context = 3;
  int _epochs = 30;
  final double _lr = 0.5;

  /// Projects (for the «این مدل مال کیه؟» target picker) and the chosen
  /// target: null = standalone model in the registry; otherwise a
  /// `projectId/agentId` key — the model becomes that agent's brain.
  List<AgentProject> _projects = const [];
  String? _targetKey;

  @override
  void initState() {
    super.initState();
    _reloadModels();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final store = widget.projectStore;
    if (store == null) return;
    final projects = await store.list();
    if (mounted) setState(() => _projects = projects);
  }

  /// Human label for a target key: `output:<projectId>` reads as the
  /// project itself; `<projectId>/<agentId>` as that agent.
  String _targetLabel(String key) {
    if (key.startsWith('output:')) {
      final projectId = key.substring('output:'.length);
      for (final p in _projects) {
        if (p.id == projectId) return 'پروژهٔ «${p.name}»';
      }
      return key;
    }
    final parts = key.split('/');
    for (final p in _projects) {
      if (p.id != parts[0]) continue;
      final agent = p.agentById(parts[1]);
      if (agent != null) return 'ایجنت «${agent.name}» — پروژهٔ «${p.name}»';
    }
    return key;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dataController.dispose();
    _instructController.dispose();
    _playController.dispose();
    super.dispose();
  }

  Future<void> _reloadModels() async {
    final models = await widget.registry.list();
    if (mounted) {
      setState(() => _models = models);
    }
  }

  void _say(String message) {
    if (mounted) setState(() => _status = message);
  }

  /// The trained model's TRUE parameter count for the current choices
  /// (mirrors NeuralLanguageModel.parameterCount: embeddings + W1 +
  /// b1 + W2 + b2 — the model class itself is unit-tested on this).
  int get _trueParamCount {
    final v = _tokenizer?.vocabSize ?? 0;
    final h = _hidden, c = _context;
    return v * h + h * (c * h) + h + v * h + v;
  }

  String _paramLabel(int p) {
    if (p >= 1000000) return '${(p / 1000000).toStringAsFixed(1)}M';
    if (p >= 1000) return '${(p / 1000).toStringAsFixed(1)}K';
    return '$p';
  }

  void _buildDataset() {
    final lines = _dataController.text.split('\n').toList();
    final dataset = buildDataset(lines);
    final tokenizer = WordTokenizer.train([
      ...dataset.train,
      ...dataset.validation,
      ...dataset.test,
    ]);
    setState(() {
      _dataset = dataset;
      _tokenizer = tokenizer;
      _model = null;
      _losses = const [];
      _perplexity = null;
    });
    _say(
      'دیتاست ساخته شد: ${dataset.stats.keptCount} نمونهٔ تمیز ماند، '
      '${dataset.stats.droppedDuplicates} تکراری و '
      '${dataset.stats.droppedEmpty + dataset.stats.droppedShort} '
      'خالی/کوتاه حذف شد. واژگان: ${tokenizer.vocabSize}',
    );
  }

  Future<void> _train() async {
    final dataset = _dataset;
    final tokenizer = _tokenizer;
    if (dataset == null || tokenizer == null || dataset.train.isEmpty) {
      _say('اول دیتاست بساز (دادهٔ آموزشی خالی است).');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'در حال آموزش…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final spec = ModelSpec(
      vocabSize: tokenizer.vocabSize,
      hiddenSize: _hidden,
      layers: 2,
      heads: 4,
      contextLength: _context,
    );
    final model = NeuralLanguageModel.fresh(spec, SeededRandom(42));
    final losses = trainModel(
      model: model,
      texts: dataset.train,
      tokenizer: tokenizer,
      epochs: _epochs,
      learningRate: _lr,
      batchSize: 8,
      seed: 42,
    );
    if (!mounted) return;
    // Evaluate before registering so the registry entry also carries
    // the honest perplexity.
    double? ppl;
    final evalSet = dataset.test.isNotEmpty ? dataset.test : dataset.validation;
    if (evalSet.isNotEmpty) {
      ppl = ModelSpec.perplexity(model.evaluateLoss(evalSet, tokenizer));
    }
    setState(() {
      _model = model;
      _losses = losses;
      _perplexity = ppl;
    });
    // AUTO-SAVE: a trained model must never live only in RAM — the
    // owner lost finished models exactly that way (trained, switched
    // tab, model gone, register button dead). Register immediately,
    // select it, optionally wire it to its target agent, and say in
    // plain words where the model went.
    try {
      final meta = await widget.registry.register(
        name: _nameController.text.trim().isEmpty
            ? 'مدل بدون نام'
            : _nameController.text.trim(),
        kind: 'base',
        model: model,
        tokenizer: tokenizer,
        capabilities: _capabilities.toList(),
        metrics: {
          'epochs': _epochs,
          'finalLoss': losses.last,
          'perplexity': ?ppl,
        },
      );
      await _reloadModels();
      if (!mounted) return;
      setState(() {
        _selectedModelId = meta.id;
        _busy = false;
      });
      var where =
          'رفت توی قفسهٔ مدل‌ها (رجیستری) — پایین همین صفحه '
          'توی بخش ۵ می‌بینیش و توی «کنسول تست» هم می‌تونی به‌عنوان '
          'مدل انتخابش کنی.';
      final target = _targetKey;
      if (target != null) {
        final assigned = await _placeModel(target, meta);
        if (assigned != null) where = '$where $assigned';
      }
      _say(
        'آموزش تموم شد و مدل «${meta.name}» خودکار ذخیره شد '
        '(زیان: ${losses.first.toStringAsFixed(3)} ← '
        '${losses.last.toStringAsFixed(3)}). $where',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say(
        'آموزش تموم شد ولی ذخیرهٔ خودکار نشد: $e — دکمهٔ «ثبت در '
        'رجیستری» رو بزن تا دستی ذخیره بشه.',
      );
    }
  }

  /// Places a freshly registered model where the target picker said:
  /// `output:<projectId>` records it as that project's own output (a
  /// project can produce models, not only host agents);
  /// `<projectId>/<agentId>` ALSO wires it as that agent's brain.
  /// Either way the model is recorded in the project's outputs.
  /// Returns a plain-language sentence for the status line, or null
  /// if the project/agent is gone.
  Future<String?> _placeModel(String targetKey, RegisteredModel meta) async {
    final store = widget.projectStore;
    if (store == null) return null;
    if (targetKey.startsWith('output:')) {
      final project =
          await store.load(targetKey.substring('output:'.length));
      if (project == null) return null;
      project.addOutput(
          ProjectOutput(kind: 'model', name: meta.name, refId: meta.id));
      await store.save(project);
      return 'به‌عنوان خروجیِ ${_targetLabel(targetKey)} هم ثبتش کردم؛ '
          'توی صفحهٔ «پروژه‌ها» زیر اسم پروژه می‌بینیش.';
    }
    final parts = targetKey.split('/');
    if (parts.length != 2) return null;
    final project = await store.load(parts[0]);
    final agent = project?.agentById(parts[1]);
    if (project == null || agent == null) return null;
    agent.model = ModelConfig(providerId: 'local-trained', modelId: meta.id);
    project.upsertAgent(agent);
    project.addOutput(
        ProjectOutput(kind: 'model', name: meta.name, refId: meta.id));
    await store.save(project);
    return 'به‌عنوان مغزِ ${_targetLabel(targetKey)} هم وصلش کردم؛ از '
        'حالا اون ایجنت با همین مدل کار می‌کنه.';
  }

  /// Works on the just-trained model OR a model selected from the
  /// registry, and never fails silently: when something is missing it
  /// says exactly what to do (the old version simply stayed disabled
  /// with no explanation).
  Future<void> _evaluate() async {
    final src = await _selectedOrCurrent();
    if (src == null) {
      _say(
        'هنوز مدلی نداری — اول «شروع آموزش» رو بزن؛ وقتی آموزش تموم '
        'بشه مدل خودکار ذخیره می‌شه و ارزیابی هم روشن می‌شه.',
      );
      return;
    }
    final dataset = _dataset;
    if (dataset == null) {
      _say(
        'برای ارزیابی اول دیتاست رو بساز (بخش ۲) تا چند جمله برای '
        'امتحان‌گرفتن از مدل داشته باشیم.',
      );
      return;
    }
    final evalSet = dataset.test.isNotEmpty ? dataset.test : dataset.validation;
    if (evalSet.isEmpty) {
      _say('مجموعهٔ ارزیابی خالی است؛ دادهٔ بیشتری وارد کن.');
      return;
    }
    final loss = src.model.evaluateLoss(evalSet, src.tokenizer);
    setState(() => _perplexity = ModelSpec.perplexity(loss));
    _say(
      'ارزیابی روی ${evalSet.length} نمونه: زیان '
      '${loss.toStringAsFixed(3)} — پرپلکسیتی '
      '${_perplexity!.toStringAsFixed(2)} (هرچه کمتر، بهتر)',
    );
  }

  Future<void> _registerCurrent() async {
    final model = _model;
    final tokenizer = _tokenizer;
    if (model == null || tokenizer == null) {
      _say(
        _selectedModelId != null
            ? 'این مدل همین حالا توی رجیستری هست ✅ — پایین صفحه توی '
                  'بخش ۵ می‌بینیش. (مدل‌ها بعد از آموزش خودکار ذخیره می‌شن.)'
            : 'هنوز مدلی آموزش ندادی — اول داده بده و «شروع آموزش» رو '
                  'بزن؛ ذخیره بعد از آموزش خودکاره.',
      );
      return;
    }
    final meta = await widget.registry.register(
      name: _nameController.text.trim().isEmpty
          ? 'مدل بدون نام'
          : _nameController.text.trim(),
      kind: 'base',
      model: model,
      tokenizer: tokenizer,
      capabilities: _capabilities.toList(),
      metrics: {
        'epochs': _epochs,
        'finalLoss': _losses.isEmpty ? null : _losses.last,
        if (_perplexity != null) 'perplexity': _perplexity,
      },
    );
    await _reloadModels();
    setState(() => _selectedModelId = meta.id);
    var extra = '';
    final target = _targetKey;
    if (target != null) {
      final assigned = await _placeModel(target, meta);
      if (assigned != null) extra = ' $assigned';
    }
    _say(
      'مدل «${meta.name}» در رجیستری ثبت شد '
      '(${_paramLabel(meta.parameterCount)} پارامتر واقعی).$extra',
    );
  }

  Future<({NeuralLanguageModel model, WordTokenizer tokenizer})?>
  _selectedOrCurrent() async {
    if (_model != null && _tokenizer != null) {
      return (model: _model!, tokenizer: _tokenizer!);
    }
    final id = _selectedModelId;
    if (id == null) return null;
    final loaded = await widget.registry.load(id);
    if (loaded == null) return null;
    return (model: loaded.model, tokenizer: loaded.tokenizer);
  }

  Future<void> _fineTune() async {
    final base = await _selectedOrCurrent();
    if (base == null) {
      _say('اول یک مدل آموزش بده یا از رجیستری انتخاب کن.');
      return;
    }
    final examples = <InstructionExample>[];
    var skipped = 0;
    for (final line in _instructController.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final json = (jsonDecode(trimmed) as Map).cast<String, Object?>();
        final ex = InstructionExample.fromJson(json);
        if (ex.prompt.isEmpty || ex.completion.isEmpty) {
          skipped++;
        } else {
          examples.add(ex);
        }
      } catch (_) {
        skipped++;
      }
    }
    if (examples.isEmpty) {
      _say(
        'هیچ مثال دستوری معتبری پیدا نشد (هر خط یک JSON با prompt و '
        'completion).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = 'در حال فاین‌تیون…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final texts = [for (final e in examples) e.format()];
    final losses = trainModel(
      model: base.model,
      texts: texts,
      tokenizer: base.tokenizer,
      epochs: 20,
      learningRate: 0.3,
      batchSize: 4,
      seed: 7,
    );
    final meta = await widget.registry.register(
      name: '${_nameController.text.trim()} (دستوری)',
      kind: 'instruct',
      model: base.model,
      tokenizer: base.tokenizer,
      capabilities: _capabilities.toList(),
      metrics: {
        'stage': 'instruction-fine-tune',
        'examples': examples.length,
        'skippedLines': skipped,
        'finalLoss': losses.last,
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _reloadModels();
    _say(
      'فاین‌تیون تمام و «${meta.name}» ثبت شد '
      '(زیان ${losses.last.toStringAsFixed(3)}، $skipped خط نامعتبر).',
    );
  }

  Future<void> _playground() async {
    final id = _selectedModelId;
    if (id == null) {
      _say('یک مدل از رجیستری انتخاب کن.');
      return;
    }
    final loaded = await widget.registry.load(id);
    if (loaded == null) {
      _say('مدل پیدا نشد.');
      return;
    }
    final promptIds = loaded.tokenizer.encode(_playController.text, eos: false);
    final generated = loaded.model.generate(
      promptIds,
      maxTokens: 40,
      temperature: 0.8,
      rng: SeededRandom(DateTime.now().microsecondsSinceEpoch),
    );
    var text = loaded.tokenizer.decode(generated);
    text = text
        .replaceAll('<pad>', '')
        .replaceAll('<bos>', '')
        .replaceAll('<eos>', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    setState(() => _playOutput = text);
  }

  Future<void> _makeProvider(RegisteredModel model) async {
    final configs = await widget.settingsStore.load();
    final next = [
      for (final c in configs)
        if (!(c.providerId == 'local-trained' && c.defaultModelId == model.id))
          c,
      ProviderConfig(providerId: 'local-trained', defaultModelId: model.id),
    ];
    await widget.settingsStore.save(next);
    widget.onProvidersChanged?.call();
    _say(
      'پرووایدر کنسول برای «${model.name}» ساخته شد — در کنسول تست '
      'قابل انتخاب است.',
    );
  }

  /// The ready sample dataset (the same one the in-chat tutorial
  /// uses): ten simple greeting/helper sentences, one per line.
  void _fillSample() {
    _dataController.text = 'سلام خوبی\n'
        'سلام من اینجام\n'
        'تو کی هستی\n'
        'من یه دستیار مهربونم\n'
        'اسمت چیه\n'
        'اسم من کایرنه\n'
        'خداحافظ فردا می بینمت\n'
        'ممنون از کمکت\n'
        'خواهش می کنم دوست من\n'
        'امروز روز خوبیه';
    _say('مثال آماده رو گذاشتم — حالا دکمهٔ «ساخت دیتاست و توکن‌ساز» رو بزن.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final dataset = _dataset;
    return ListView(
      padding: const EdgeInsets.all(CairnSpacing.lg),
      children: [
        Text(s.training, style: theme.textTheme.headlineSmall),
        const SizedBox(height: CairnSpacing.md),
        ModelsSection(
          baseDir: widget.baseDir,
          settingsStore: widget.settingsStore,
          modelRegistry: widget.registry,
          toolIds: [
            for (final t in widget.toolRegistry?.all ?? const <Tool>[]) t.id,
          ],
        ),
        const SizedBox(height: CairnSpacing.xs),
        Text(s.trainIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: CairnSpacing.sm),
        ExpansionTile(
          leading: const Icon(Icons.lightbulb_outline),
          title: Text(s.trainGuideTitle),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CairnSpacing.md,
                0,
                CairnSpacing.md,
                CairnSpacing.md,
              ),
              child: Text(s.trainGuideBody),
            ),
          ],
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: CairnSpacing.sm),
          Text(
            _status,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: CairnColors.link,
            ),
          ),
        ],
        const SizedBox(height: CairnSpacing.lg),
        Text(s.tNameCapsTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.sm),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(labelText: s.tModelName),
        ),
        const SizedBox(height: CairnSpacing.sm),
        Wrap(
          spacing: 8,
          children: [
            for (final option in ModelSpec.capabilityOptions)
              FilterChip(
                label: Text(option),
                selected: _capabilities.contains(option),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _capabilities.add(option);
                  } else {
                    _capabilities.remove(option);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: CairnSpacing.sm),
        Text(s.tTargetTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: CairnSpacing.xs),
        DropdownButton<String?>(
          value: _targetKey,
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(s.tStandalone),
            ),
            for (final p in _projects) ...[
              DropdownMenuItem<String?>(
                value: 'output:${p.id}',
                child: Text(s.tOutputOf(p.name)),
              ),
              for (final a in p.agents)
                DropdownMenuItem<String?>(
                  value: '${p.id}/${a.id}',
                  child: Text(s.tBrainOf(a.name, p.name)),
                ),
            ],
          ],
          onChanged: (v) => setState(() => _targetKey = v),
        ),
        Text(
          _targetKey == null
              ? 'مدل مستقل می‌سازی: بعد از آموزش می‌ره توی قفسهٔ مدل‌ها '
                    '(رجیستری) و هر ایجنتی می‌تونه از کنسول تست یا '
                    'تنظیماتش انتخابش کنه.'
              : _targetKey!.startsWith('output:')
                  ? 'این پروژه فقط ایجنت نمی‌سازه — مدل هم خروجی می‌ده: '
                        'بعد از آموزش، مدل به‌عنوان خروجیِ '
                        '${_targetLabel(_targetKey!)} ثبت می‌شه.'
                  : 'بعد از آموزش، این مدل خودکار می‌شه مغزِ '
                        '${_targetLabel(_targetKey!)} و همونجا ذخیره می‌شه.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: CairnSpacing.lg),
        Text(
          s.tDataTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: CairnSpacing.sm),
        TextField(
          controller: _dataController,
          minLines: 6,
          maxLines: 12,
          decoration: InputDecoration(
            hintText: s.tDataHint,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: CairnSpacing.sm),
        Wrap(
          spacing: CairnSpacing.sm,
          runSpacing: CairnSpacing.xs,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _buildDataset,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(s.tBuildDataset),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _fillSample,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(s.trainSampleButton),
            ),
          ],
        ),
        if (dataset != null) ...[
          const SizedBox(height: CairnSpacing.sm),
          Text(
            'پاک‌سازی: از ${dataset.stats.rawCount} خط، '
            '${dataset.stats.keptCount} ماند '
            '(تکراری: ${dataset.stats.droppedDuplicates}، '
            'خالی: ${dataset.stats.droppedEmpty}، '
            'کوتاه: ${dataset.stats.droppedShort}) — '
            'تقسیم: آموزش ${dataset.train.length} / '
            'اعتبارسنجی ${dataset.validation.length} / '
            'آزمون ${dataset.test.length} — '
            'واژگان: ${_tokenizer?.vocabSize}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: CairnSpacing.lg),
        Text(s.tArchTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.sm),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<int>(
              value: _hidden,
              items: [
                DropdownMenuItem(value: 16, child: Text(s.tHidden(16))),
                DropdownMenuItem(value: 32, child: Text(s.tHidden(32))),
                DropdownMenuItem(value: 64, child: Text(s.tHidden(64))),
              ],
              onChanged: (v) => setState(() => _hidden = v ?? 32),
            ),
            DropdownButton<int>(
              value: _context,
              items: [
                DropdownMenuItem(value: 2, child: Text(s.tContext(2))),
                DropdownMenuItem(value: 3, child: Text(s.tContext(3))),
                DropdownMenuItem(value: 4, child: Text(s.tContext(4))),
                DropdownMenuItem(value: 6, child: Text(s.tContext(6))),
              ],
              onChanged: (v) => setState(() => _context = v ?? 3),
            ),
            DropdownButton<int>(
              value: _epochs,
              items: [
                DropdownMenuItem(value: 10, child: Text(s.tEpochs(10))),
                DropdownMenuItem(value: 30, child: Text(s.tEpochs(30))),
                DropdownMenuItem(value: 60, child: Text(s.tEpochs(60))),
              ],
              onChanged: (v) => setState(() => _epochs = v ?? 30),
            ),
            Text(
              'پارامتر واقعی مدل: ${_paramLabel(_trueParamCount)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: CairnSpacing.sm),
        Text(s.trainArchHelp, style: theme.textTheme.bodySmall),
        const SizedBox(height: CairnSpacing.sm),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _train,
              icon: const Icon(Icons.play_arrow),
              label: Text(s.tStart),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _evaluate,
              icon: const Icon(Icons.analytics_outlined),
              label: Text(s.tEvaluate),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _registerCurrent,
              icon: const Icon(Icons.save_outlined),
              label: Text(s.tRegister),
            ),
          ],
        ),
        const SizedBox(height: CairnSpacing.xs),
        Text(
          '💡 نگران ذخیره نباش: به‌محض این‌که آموزش تموم بشه، مدل '
          'خودکار توی رجیستری (بخش ۵، پایین همین صفحه) ذخیره می‌شه و '
          'می‌تونی توی کنسول تست انتخابش کنی. این دو دکمه همیشه قابل '
          'زدنن؛ اگه چیزی کم باشه خودشون می‌گن چی کار کنی.',
          style: theme.textTheme.bodySmall,
        ),
        if (_losses.isNotEmpty) ...[
          const SizedBox(height: CairnSpacing.sm),
          Text(
            'زیان آموزش: ${_losses.first.toStringAsFixed(3)} ← '
            '${_losses.last.toStringAsFixed(3)} '
            '(${_losses.length} دوره)',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (_perplexity != null) ...[
          const SizedBox(height: CairnSpacing.xs),
          Text(
            'پرپلکسیتی ارزیابی: ${_perplexity!.toStringAsFixed(2)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: CairnSpacing.lg),
        Text(
          s.tFinetuneTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: CairnSpacing.sm),
        TextField(
          controller: _instructController,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '{"prompt": "…", "completion": "…"}',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: CairnSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _fineTune,
            icon: const Icon(Icons.tune),
            label: Text(s.tFinetuneBtn),
          ),
        ),
        const SizedBox(height: CairnSpacing.lg),
        Text(s.tRegistryTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.sm),
        if (_models.isEmpty)
          Text(s.tNoModels, style: theme.textTheme.bodySmall),
        for (final model in _models)
          Card(
            child: ListTile(
              leading: Icon(
                model.kind == 'instruct'
                    ? Icons.chat_outlined
                    : Icons.psychology_outlined,
              ),
              title: Text(model.name),
              subtitle: Text(
                '${model.kind == 'instruct' ? 'دستوری' : 'پایه'} — '
                '${_paramLabel(model.parameterCount)} پارامتر'
                '${model.metrics['perplexity'] != null ? ' — پرپلکسیتی ${(model.metrics['perplexity'] as num).toStringAsFixed(2)}' : ''}'
                '${model.capabilities.isNotEmpty ? ' — ${model.capabilities.join('، ')}' : ''}',
              ),
              selected: _selectedModelId == model.id,
              onTap: () => setState(() => _selectedModelId = model.id),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'ساخت پرووایدر کنسول',
                    icon: const Icon(Icons.electrical_services_outlined),
                    onPressed: () => _makeProvider(model),
                  ),
                  IconButton(
                    tooltip: 'حذف مدل',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.registry.delete(model.id);
                      await _reloadModels();
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: CairnSpacing.lg),
        Text(
          s.tPlaygroundTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: CairnSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _playController,
                decoration: InputDecoration(
                  labelText: s.tSeedLabel,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: CairnSpacing.sm),
            FilledButton(onPressed: _playground, child: Text(s.tGenerate)),
          ],
        ),
        if (_playOutput.isNotEmpty) ...[
          const SizedBox(height: CairnSpacing.sm),
          SelectableText(_playOutput),
        ],
        const SizedBox(height: CairnSpacing.xl),
      ],
    );
  }
}
