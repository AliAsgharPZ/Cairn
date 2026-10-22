import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_training/cairn_training.dart';

/// One executed chain step, for the trace UI: what went in, what
/// came out, and any honest note (fallback used, coverage, routing).
class ChainStepTrace {
  const ChainStepTrace({
    required this.kind,
    required this.output,
    this.note,
    this.skipped = false,
  });

  final String kind;
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

/// Runs a project's CHAIN (v1.2) end to end:
///
///   detect → translate-in → interpret → manage (route) →
///   agent work OR LLM answer → translate-back
///
/// Every model slot resolves the same way: the step's bound smart
/// model, else the newest trained model of that kind, else an
/// honest fallback that SAYS it is a fallback (script heuristic for
/// detection, passthrough for translation, keyword rules for
/// intent). A step provided by a real provider model (the agent's
/// translator role / main model) is used for translation and for
/// the answer — that is the slot a Gemma will later fill.
class PipelineRunner {
  PipelineRunner({
    required this.smartStore,
    required this.providerFor,
    required this.registry,
    required this.skillRegistry,
  });

  final SmartModelStore smartStore;

  /// Resolves a runnable provider for an agent (+ optional model
  /// override), or null when that provider is not configured.
  final ModelProvider? Function(AgentBlueprint agent,
      {ModelConfig? override}) providerFor;

  final ToolRegistry registry;
  final SkillRegistry skillRegistry;

  Future<SmartModel?> _smart(PipelineStep? step, String kind) async {
    if (step != null && step.modelRef.isNotEmpty) {
      final bound = await smartStore.get(step.modelRef);
      if (bound != null) return bound;
    }
    return smartStore.latestOfKind(kind);
  }

  PipelineStep? _step(AgentProject project, String kind) {
    for (final s in project.pipeline) {
      if (s.kind == kind) return s;
    }
    return null;
  }

  bool _on(AgentProject project, String kind) {
    final s = _step(project, kind);
    return s != null && s.enabled;
  }

  static bool _looksPersian(String text) {
    var arabic = 0, latin = 0;
    for (final r in text.runes) {
      if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0xFB50 && r <= 0xFEFF)) {
        arabic++;
      } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
        latin++;
      }
    }
    return arabic >= latin && arabic > 0;
  }

  Future<ChainResult> run({
    required AgentProject project,
    required String input,
    required Future<bool> Function(ApprovalRequest) approvalGate,
    CancelToken? cancelToken,
  }) async {
    final traces = <ChainStepTrace>[];
    final agentStep = _step(project, PipelineKind.agent);
    final agent = (agentStep != null && agentStep.agentId.isNotEmpty
            ? project.agentById(agentStep.agentId)
            : null) ??
        (project.agents.isEmpty ? null : project.agents.first);

    // ---- 1) detect ----
    var lang = 'en';
    if (_on(project, PipelineKind.detect)) {
      final model = await _smart(
          _step(project, PipelineKind.detect), SmartModelKind.langDetect);
      if (model != null) {
        final p = model.asClassifier().predict(input);
        lang = p.label;
        traces.add(ChainStepTrace(
          kind: PipelineKind.detect,
          output: lang == 'fa' ? 'فارسی (fa)' : 'English (en)',
          note: 'مدل آموزش‌دیده «${model.name}» — اطمینان '
              '${(p.confidence * 100).toStringAsFixed(0)}٪',
        ));
      } else {
        lang = _looksPersian(input) ? 'fa' : 'en';
        traces.add(ChainStepTrace(
          kind: PipelineKind.detect,
          output: lang == 'fa' ? 'فارسی (fa)' : 'English (en)',
          note: 'مدل آموزش‌دیده‌ای وصل نیست — تشخیص ساده از روی خط متن',
        ));
      }
    } else {
      lang = _looksPersian(input) ? 'fa' : 'en';
      traces.add(const ChainStepTrace(
          kind: PipelineKind.detect, output: '', skipped: true));
    }

    var working = input;

    // ---- 2) translate in ----
    if (_on(project, PipelineKind.translateIn)) {
      if (lang == 'fa') {
        working = await _translate(
          traces,
          kind: PipelineKind.translateIn,
          step: _step(project, PipelineKind.translateIn),
          text: working,
          toEnglish: true,
          agent: agent,
        );
      } else {
        traces.add(ChainStepTrace(
          kind: PipelineKind.translateIn,
          output: working,
          note: 'متن از اول انگلیسی است — ترجمه لازم نبود',
        ));
      }
    }

    // ---- 3) interpret ----
    var intent = 'task';
    if (_on(project, PipelineKind.interpret)) {
      final model = await _smart(
          _step(project, PipelineKind.interpret), SmartModelKind.intent);
      if (model != null) {
        final p = model.asClassifier().predict(working);
        intent = p.label;
        traces.add(ChainStepTrace(
          kind: PipelineKind.interpret,
          output: intent,
          note: 'مدل مفسر «${model.name}» — اطمینان '
              '${(p.confidence * 100).toStringAsFixed(0)}٪',
        ));
      } else {
        final lower = working.toLowerCase();
        if (lower.contains('translate') || working.contains('ترجمه')) {
          intent = 'translate';
        } else if (working.contains('?') || working.contains('؟')) {
          intent = 'question';
        } else if (RegExp(r'^(سلام|hello|hi|hey|سلامم)').hasMatch(lower.trim())) {
          intent = 'chat';
        } else {
          intent = 'task';
        }
        traces.add(ChainStepTrace(
          kind: PipelineKind.interpret,
          output: intent,
          note: 'مدل مفسر آموزش‌دیده‌ای وصل نیست — قانون‌های سادهٔ کلیدواژه‌ای',
        ));
      }
    }

    // ---- 4) manage (routing) ----
    final route = switch (intent) {
      'question' || 'chat' => 'answer',
      'translate' => 'translate',
      _ => 'agent',
    };
    traces.add(ChainStepTrace(
      kind: PipelineKind.manage,
      output: switch (route) {
        'answer' => 'ارجاع به مدل پاسخ (LLM)',
        'translate' => 'خودِ ترجمه پاسخ است',
        _ => 'ارجاع به ایجنت',
      },
      note: 'مدیر از روی برداشت مفسر مسیر را انتخاب کرد',
    ));

    // ---- 5/6) agent or answer ----
    var answer = '';
    if (route == 'translate') {
      answer = working;
    } else if (route == 'agent' && _on(project, PipelineKind.agent)) {
      if (agent == null) {
        traces.add(const ChainStepTrace(
          kind: PipelineKind.agent,
          output: '',
          note: 'پروژه ایجنتی ندارد',
          skipped: true,
        ));
        answer = working;
      } else if (providerFor(agent) == null) {
        traces.add(ChainStepTrace(
          kind: PipelineKind.agent,
          output: '',
          note: 'مدل ایجنت «${agent.name}» پیکربندی نشده — از تنظیمات یک '
              'پرووایدر وصل کن (یا Ollama را روشن کن).',
          skipped: true,
        ));
        answer = '';
      } else {
        final journal = Journal();
        final orchestrator = Orchestrator(
          provider: providerFor(agent)!,
          registry: registry,
          journal: journal,
          skillRegistry: skillRegistry,
        );
        try {
          final outcome = await orchestrator.run(
            project: project,
            agent: agent,
            instruction: working,
            approvalGate: approvalGate,
            cancelToken: cancelToken,
          );
          answer = outcome.summary ??
              outcome.stepOutputs.values
                  .map((e) => e.toString())
                  .where((t) => t.isNotEmpty)
                  .join('\n');
          if (answer.isEmpty) {
            answer = outcome.failureReason ?? '(بدون خروجی)';
          }
          traces.add(ChainStepTrace(
            kind: PipelineKind.agent,
            output: answer,
            note: 'ایجنت «${agent.name}» اجرا شد — وضعیت: ${outcome.run.status.name}',
          ));
        } catch (e) {
          traces.add(ChainStepTrace(
            kind: PipelineKind.agent,
            output: '',
            note: 'اجرای ایجنت ناموفق بود: $e',
          ));
          answer = '';
        }
      }
    } else if (route == 'answer' && _on(project, PipelineKind.answer)) {
      if (agent == null) {
        traces.add(const ChainStepTrace(
          kind: PipelineKind.answer,
          output: '',
          note: 'مدلی برای پاسخ وصل نیست',
          skipped: true,
        ));
      } else {
        final provider = providerFor(agent);
        if (provider == null) {
          traces.add(ChainStepTrace(
            kind: PipelineKind.answer,
            output: '',
            note: 'پرووایدر مدل «${agent.name}» پیکربندی نشده — '
                'از تنظیمات وصلش کن (یا Ollama را روشن کن).',
          ));
        } else {
          try {
            final res = await provider.complete(
              agent.model,
              ModelRequest(messages: [
                if (agent.systemPrompt.isNotEmpty)
                  ChatMessage(ChatRole.system, agent.systemPrompt),
                ChatMessage(ChatRole.user, working),
              ]),
            );
            answer = res.text;
            traces.add(ChainStepTrace(
              kind: PipelineKind.answer,
              output: answer,
              note: 'مدل پاسخ: ${agent.model.providerId}/${agent.model.modelId}',
            ));
          } catch (e) {
            traces.add(ChainStepTrace(
              kind: PipelineKind.answer,
              output: '',
              note: 'مدل پاسخ خطا داد: $e',
            ));
          }
        }
      }
    }

    // ---- 7) translate back ----
    var finalText = answer;
    if (_on(project, PipelineKind.translateBack)) {
      if (lang == 'fa' && answer.isNotEmpty) {
        finalText = await _translate(
          traces,
          kind: PipelineKind.translateBack,
          step: _step(project, PipelineKind.translateBack),
          text: answer,
          toEnglish: false,
          agent: agent,
        );
      } else {
        traces.add(ChainStepTrace(
          kind: PipelineKind.translateBack,
          output: finalText,
          note: lang == 'fa' ? 'پاسخی برای ترجمه نبود' : 'زبان کاربر انگلیسی است',
        ));
      }
    }

    return ChainResult(
      traces: traces,
      finalText: finalText,
      detectedLang: lang,
      intent: intent,
    );
  }

  /// Translation via the bound smart translator; falls back to the
  /// agent's provider model (its translator role when set); falls
  /// back to passthrough — each path labeled in the trace.
  Future<String> _translate(
    List<ChainStepTrace> traces, {
    required String kind,
    required PipelineStep? step,
    required String text,
    required bool toEnglish,
    required AgentBlueprint? agent,
  }) async {
    final model = await _smart(step, SmartModelKind.translator);
    if (model != null) {
      final r = model.asTranslator().translate(text, toEnglish: toEnglish);
      traces.add(ChainStepTrace(
        kind: kind,
        output: r.text,
        note: 'مترجم جدولی «${model.name}» — پوشش واژه‌ها: '
            '${(r.coverage * 100).toStringAsFixed(0)}٪'
            '${r.coverage < 0.6 ? ' (کم است؛ برای ترجمهٔ واقعی مدل بزرگ وصل کن)' : ''}',
      ));
      return r.text;
    }
    if (agent != null) {
      final override = agent.translatorModel;
      final provider = providerFor(agent, override: override);
      if (provider != null) {
        try {
          final res = await provider.complete(
            override ?? agent.model,
            ModelRequest(messages: [
              ChatMessage(
                ChatRole.system,
                toEnglish
                    ? 'Translate the following text to English. Reply with the translation only.'
                    : 'Translate the following text to Persian. Reply with the translation only.',
              ),
              ChatMessage(ChatRole.user, text),
            ]),
          );
          traces.add(ChainStepTrace(
            kind: kind,
            output: res.text,
            note: 'ترجمه با مدل پرووایدر (${(override ?? agent.model).providerId})',
          ));
          return res.text;
        } catch (_) {
          // fall through to passthrough
        }
      }
    }
    traces.add(ChainStepTrace(
      kind: kind,
      output: text,
      note: 'مترجمی وصل نیست — متن بدون ترجمه رد شد',
    ));
    return text;
  }
}
