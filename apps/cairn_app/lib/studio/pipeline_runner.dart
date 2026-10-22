import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';

import 'model_store.dart';

/// One executed flowchart step, for the trace UI. Kept SHORT by
/// design — the owner disliked the long texts of v1.2: one line of
/// output, one short note.
class ChainStepTrace {
  const ChainStepTrace({
    required this.role,
    required this.output,
    this.note,
    this.skipped = false,
  });

  final String role;
  final String output;
  final String? note;
  final bool skipped;
}

class ChainResult {
  const ChainResult({
    required this.traces,
    required this.finalText,
    required this.detectedLang,
    required this.intent,
  });

  final List<ChainStepTrace> traces;
  final String finalText;
  final String detectedLang;
  final String intent;
}

String _short(String text, [int max = 300]) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= max ? t : '${t.substring(0, max)}…';
}

/// Runs a project's FLOWCHART (v1.3): steps execute in the owner's
/// order; each step is a ROLE filled by the model definition bound
/// to it (or the first definition of that role). One text stream
/// flows through the steps; the interpreter and manager only set
/// state (intent, route) that later steps respect.
///
/// Everything is replaceable and honest: a step whose role has no
/// usable model says so in one short line and passes the text on —
/// nothing is ever fabricated.
class PipelineRunner {
  PipelineRunner({
    required this.models,
    required this.providerFor,
    required this.providerForAgent,
    required this.mediaFor,
    required this.registry,
    required this.skillRegistry,
    required this.outputsDir,
    required this.defaultLanguage,
    required this.languageName,
  });

  /// The studio UI's language code — the last-resort working
  /// language when neither the project nor the run names one.
  final String defaultLanguage;

  /// Resolves a language code to the name models are told
  /// ("German"); supplied from the app's language registry.
  final String Function(String code) languageName;

  final ModelStore models;

  /// A runnable chat provider for a model definition, or null.
  final ModelProvider? Function(ModelDefinition def) providerFor;

  /// Legacy path: a provider for a project agent blueprint.
  final ModelProvider? Function(AgentBlueprint agent) providerForAgent;

  /// A media adapter for a definition, or null when its source
  /// cannot serve media.
  final MediaProviders? Function(ModelDefinition def) mediaFor;

  final ToolRegistry registry;
  final SkillRegistry skillRegistry;
  final Directory outputsDir;

  Future<ChainResult> run({
    required AgentProject project,
    required String input,
    required Future<bool> Function(ApprovalRequest) approvalGate,
    CancelToken? cancelToken,
    String inputLang = '',
  }) async {
    final traces = <ChainStepTrace>[];
    final defs = await models.list();
    ModelDefinition? resolve(PipelineStep step) {
      if (step.modelDefId.isNotEmpty) {
        for (final d in defs) {
          if (d.id == step.modelDefId) return d;
        }
      }
      for (final d in defs) {
        if (d.role == step.role) return d;
      }
      return null;
    }

    var current = input;
    // Language state (v1.4): NO language pair is assumed anywhere.
    // The text's language starts as the run's declared input
    // language; translator steps move it to their configured target;
    // a step without a target uses the project's working language.
    var textLang = inputLang;
    final workingLang = project.language.isNotEmpty
        ? project.language
        : (inputLang.isNotEmpty ? inputLang : defaultLanguage);
    String? intent;
    String? route;
    var agentAnswered = false;

    for (final step in project.pipeline) {
      if (!step.enabled) continue;
      final def = resolve(step);
      switch (step.role) {
        case ModelRole.translator:
          final r = await _translate(
            traces,
            def,
            current,
            step: step,
            textLang: textLang,
            inputLang: inputLang,
            workingLang: workingLang,
          );
          current = r.$1;
          textLang = r.$2;
        case ModelRole.interpreter:
          intent = await _interpret(traces, def, current);
        case ModelRole.manager:
          route = await _manage(traces, def, current, intent);
        case ModelRole.agent:
          if (route == 'answer' || route == 'translate') {
            traces.add(ChainStepTrace(
              role: step.role,
              output: '',
              note: 'مدیر این درخواست را به ایجنت نفرستاد',
              skipped: true,
            ));
            break;
          }
          final out = await _agent(
              traces, def, project, current, approvalGate, cancelToken);
          if (out != null) {
            current = out;
            agentAnswered = true;
          }
        case ModelRole.llm || ModelRole.coder:
          if (route == 'agent' && agentAnswered) {
            traces.add(ChainStepTrace(
              role: step.role,
              output: '',
              note: 'ایجنت کار را انجام داد',
              skipped: true,
            ));
            break;
          }
          final out = await _complete(traces, def, project, current,
              coder: step.role == ModelRole.coder);
          if (out != null) current = out;
        case ModelRole.image || ModelRole.video || ModelRole.audio:
          final out = await _media(traces, def, step.role, current);
          if (out != null) current = out;
        default:
          traces.add(ChainStepTrace(
            role: step.role,
            output: '',
            note: 'نقش ناشناخته',
            skipped: true,
          ));
      }
    }
    return ChainResult(
      traces: traces,
      finalText: current,
      detectedLang: inputLang,
      intent: intent ?? '',
    );
  }

  Future<String?> _askModel(
    ModelDefinition def,
    ModelProvider provider, {
    required String system,
    required String user,
  }) async {
    final res = await provider.complete(
      ModelConfig(providerId: def.providerId, modelId: def.modelId),
      ModelRequest(messages: [
        if (system.isNotEmpty) ChatMessage(ChatRole.system, system),
        ChatMessage(ChatRole.user, user),
      ]),
    );
    return res.text;
  }

  /// One translator step. Returns the (possibly translated) text and
  /// the language the text is in afterwards. Language-agnostic: the
  /// target comes from the step ('input' = back to the language the
  /// user wrote in), else the project's working language. When the
  /// text is already in the target language the step honestly does
  /// nothing instead of burning a model call.
  Future<(String, String)> _translate(
    List<ChainStepTrace> traces,
    ModelDefinition? def,
    String text, {
    required PipelineStep step,
    required String textLang,
    required String inputLang,
    required String workingLang,
  }) async {
    var target = switch (step.toLang) {
      'input' => inputLang,
      '' => workingLang,
      final code => code,
    };
    if (target.isEmpty) target = workingLang;
    if (textLang.isNotEmpty && target == textLang) {
      traces.add(ChainStepTrace(
        role: ModelRole.translator,
        output: _short(text),
        note: 'متن همین حالا به زبان مقصد است',
      ));
      return (text, textLang);
    }
    final provider = def == null ? null : providerFor(def);
    if (def == null || provider == null) {
      traces.add(ChainStepTrace(
        role: ModelRole.translator,
        output: _short(text),
        note: 'مدل مترجمی وصل نیست',
      ));
      return (text, textLang);
    }
    final sourceCode = step.fromLang.isNotEmpty ? step.fromLang : textLang;
    final sourceName =
        sourceCode.isNotEmpty ? languageName(sourceCode) : 'the source language';
    try {
      final out = await _askModel(
        def,
        provider,
        system: 'Translate the following text from $sourceName to '
            '${languageName(target)}. Reply with the translation only.',
        user: text,
      );
      final result = (out ?? '').trim();
      traces.add(ChainStepTrace(
        role: ModelRole.translator,
        output: _short(result),
        note: 'با «${def.name}»',
      ));
      return result.isEmpty ? (text, textLang) : (result, target);
    } catch (e) {
      traces.add(ChainStepTrace(
        role: ModelRole.translator,
        output: _short(text),
        note: 'ترجمه ناموفق بود',
      ));
      return (text, textLang);
    }
  }

  Future<String> _interpret(
      List<ChainStepTrace> traces, ModelDefinition? def, String text) async {
    String intent = '';
    var viaModel = false;
    final provider = def == null ? null : providerFor(def);
    if (def != null && provider != null) {
      try {
        final out = await _askModel(
          def,
          provider,
          system:
              'Classify the user intent. Reply with exactly one word: question, task, chat, or translate.',
          user: text,
        );
        final word = (out ?? '').toLowerCase();
        for (final label in ['question', 'task', 'chat', 'translate']) {
          if (word.contains(label)) {
            intent = label;
            viaModel = true;
            break;
          }
        }
      } catch (_) {}
    }
    if (intent.isEmpty) {
      // Language-neutral fallback only (v1.4): a question mark in
      // any script means a question; everything else is treated as
      // a task (the manager/LLM steps still get their say). The old
      // Persian/English keyword rules are gone — no language pair is
      // assumed anywhere in the flow.
      intent =
          (text.contains('?') || text.contains('؟')) ? 'question' : 'task';
    }
    traces.add(ChainStepTrace(
      role: ModelRole.interpreter,
      output: intent,
      note: viaModel
          ? 'با «${def!.name}»'
          : (def == null ? 'مدل مفسری نیست — قانون ساده' : 'قانون ساده'),
    ));
    return intent;
  }

  Future<String> _manage(List<ChainStepTrace> traces, ModelDefinition? def,
      String text, String? intent) async {
    String route = switch (intent) {
      'question' || 'chat' => 'answer',
      'translate' => 'translate',
      _ => 'agent',
    };
    var viaModel = false;
    final provider = def == null ? null : providerFor(def);
    if (def != null && provider != null && intent != null) {
      try {
        final out = await _askModel(
          def,
          provider,
          system:
              'You route requests. The interpreter said the intent is "$intent". Reply with exactly one word: AGENT (a software agent must do work), ANSWER (a language model should just answer), or TRANSLATE (the translation itself is the answer).',
          user: text,
        );
        final word = (out ?? '').toUpperCase();
        if (word.contains('TRANSLATE')) {
          route = 'translate';
          viaModel = true;
        } else if (word.contains('ANSWER')) {
          route = 'answer';
          viaModel = true;
        } else if (word.contains('AGENT')) {
          route = 'agent';
          viaModel = true;
        }
      } catch (_) {}
    }
    traces.add(ChainStepTrace(
      role: ModelRole.manager,
      output: switch (route) {
        'answer' => 'مسیر: پاسخ با مدل زبانی',
        'translate' => 'مسیر: خودِ ترجمه پاسخ است',
        _ => 'مسیر: انجام کار با ایجنت',
      },
      note: viaModel ? 'با «${def!.name}»' : 'از روی حرف مفسر',
    ));
    return route;
  }

  Future<String?> _agent(
    List<ChainStepTrace> traces,
    ModelDefinition? def,
    AgentProject project,
    String text,
    Future<bool> Function(ApprovalRequest) approvalGate,
    CancelToken? cancelToken,
  ) async {
    AgentBlueprint blueprint;
    ModelProvider? provider;
    String displayName;
    if (def != null) {
      displayName = def.name;
      provider = providerFor(def);
      blueprint = AgentBlueprint(
        id: def.id,
        name: def.name,
        description: def.description,
        systemPrompt: [
          if (def.targetSoftware.isNotEmpty)
            'You work with ${def.targetSoftware}.',
          def.effectiveInstructions,
        ].join('\n'),
        model: ModelConfig(providerId: def.providerId, modelId: def.modelId),
        tools: [for (final t in def.toolIds) ToolBinding(toolId: t)],
        policy: const PolicyConfig(
          approvalLevel: ApprovalLevel.sensitiveOnly,
          allowNetwork: true,
        ),
      );
    } else if (project.agents.isNotEmpty) {
      blueprint = project.agents.first;
      displayName = blueprint.name;
      provider = providerForAgent(blueprint);
    } else {
      traces.add(const ChainStepTrace(
        role: ModelRole.agent,
        output: '',
        note: 'هیچ ایجنتی تعریف نشده',
        skipped: true,
      ));
      return null;
    }
    if (provider == null) {
      traces.add(ChainStepTrace(
        role: ModelRole.agent,
        output: '',
        note: 'مدل «$displayName» وصل نیست',
        skipped: true,
      ));
      return null;
    }
    final orchestrator = Orchestrator(
      provider: provider,
      registry: registry,
      journal: Journal(),
      skillRegistry: skillRegistry,
    );
    try {
      final outcome = await orchestrator.run(
        project: project,
        agent: blueprint,
        instruction: text,
        approvalGate: approvalGate,
        cancelToken: cancelToken,
      );
      final out = outcome.summary ??
          outcome.stepOutputs.values
              .map((e) => e.toString())
              .where((t) => t.isNotEmpty)
              .join('\n');
      final result = out.isNotEmpty
          ? out
          : (outcome.failureReason ?? '(بدون خروجی)');
      traces.add(ChainStepTrace(
        role: ModelRole.agent,
        output: _short(result),
        note: '«$displayName» — ${outcome.run.status.name}',
      ));
      return result;
    } catch (e) {
      traces.add(ChainStepTrace(
        role: ModelRole.agent,
        output: '',
        note: 'اجرای ایجنت ناموفق بود',
      ));
      return null;
    }
  }

  Future<String?> _complete(
    List<ChainStepTrace> traces,
    ModelDefinition? def,
    AgentProject project,
    String text, {
    required bool coder,
  }) async {
    final role = coder ? ModelRole.coder : ModelRole.llm;
    ModelProvider? provider;
    ModelConfig? config;
    String? name;
    String system = '';
    if (def != null) {
      provider = providerFor(def);
      config = ModelConfig(providerId: def.providerId, modelId: def.modelId);
      name = def.name;
      system = def.instructions;
    } else if (project.agents.isNotEmpty) {
      final agent = project.agents.first;
      provider = providerForAgent(agent);
      config = agent.model;
      name = agent.name;
      system = agent.systemPrompt;
    }
    if (provider == null || config == null) {
      traces.add(ChainStepTrace(
        role: role,
        output: '',
        note: 'مدلی برای این نقش وصل نیست',
        skipped: true,
      ));
      return null;
    }
    if (coder && !system.toLowerCase().contains('code')) {
      system =
          'You are a coding model: write clean, working code and brief explanations.\n$system';
    }
    try {
      final res = await provider.complete(
        config,
        ModelRequest(messages: [
          if (system.isNotEmpty) ChatMessage(ChatRole.system, system),
          ChatMessage(ChatRole.user, text),
        ]),
      );
      traces.add(ChainStepTrace(
        role: role,
        output: _short(res.text),
        note: 'با «$name»',
      ));
      return res.text;
    } catch (e) {
      traces.add(ChainStepTrace(
        role: role,
        output: '',
        note: 'مدل خطا داد',
      ));
      return null;
    }
  }

  Future<String?> _media(List<ChainStepTrace> traces, ModelDefinition? def,
      String role, String prompt) async {
    final media = def == null ? null : mediaFor(def);
    if (def == null || media == null) {
      traces.add(ChainStepTrace(
        role: role,
        output: '',
        note: 'مدلی برای این نقش وصل نیست',
        skipped: true,
      ));
      return null;
    }
    try {
      await outputsDir.create(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      if (role == ModelRole.image) {
        final r = await media.generateImage(model: def.modelId, prompt: prompt);
        if (r.bytes != null) {
          final file = File('${outputsDir.path}/image-$stamp.png');
          await file.writeAsBytes(r.bytes!, flush: true);
          traces.add(ChainStepTrace(
            role: role,
            output: '🖼 ${file.path}',
            note: 'با «${def.name}»',
          ));
          return 'تصویر ساخته شد و ذخیره شد: ${file.path}';
        }
        traces.add(ChainStepTrace(
          role: role,
          output: '🖼 ${r.url ?? ''}',
          note: 'با «${def.name}»',
        ));
        return 'تصویر ساخته شد: ${r.url}';
      }
      if (role == ModelRole.audio) {
        final bytes =
            await media.generateSpeech(model: def.modelId, input: prompt);
        final file = File('${outputsDir.path}/audio-$stamp.mp3');
        await file.writeAsBytes(bytes, flush: true);
        traces.add(ChainStepTrace(
          role: role,
          output: '🔊 ${file.path}',
          note: 'با «${def.name}»',
        ));
        return 'صدا ساخته شد و ذخیره شد: ${file.path}';
      }
      // video: create + a bounded poll
      final id = await media.createVideo(model: def.modelId, prompt: prompt);
      var status = 'queued';
      String? url;
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final s = await media.videoStatus(id);
        status = s.status;
        url = s.url;
        if (status == 'completed' || status == 'failed') break;
      }
      traces.add(ChainStepTrace(
        role: role,
        output: url != null ? '🎬 $url' : '🎬 وضعیت: $status',
        note: 'با «${def.name}»',
      ));
      return url != null
          ? 'ویدیو ساخته شد: $url'
          : 'ساخت ویدیو شروع شد و هنوز آماده نیست (وضعیت: $status)';
    } catch (e) {
      traces.add(ChainStepTrace(
        role: role,
        output: '',
        note: 'ساخت ناموفق بود: ${_short('$e', 120)}',
      ));
      return null;
    }
  }
}
