import 'ids.dart';

/// One step of a project's processing CHAIN (v1.2) — the owner's
/// architecture made concrete: a project is not one agent in a box,
/// it is a line of specialized models and agents connected in order:
///
///   input → detect language → translate (if needed) → interpret →
///   manager routes → agent(s) do tasks / LLM answers → translate back
///
/// Each step names its kind and, where a model is involved, WHICH
/// model fills the slot ([modelRef] = a smart-model id from the
/// training store, or '' = the default for that kind / the project
/// agent's provider model). Any slot can later be re-pointed at a
/// bigger external model (e.g. Gemma via Ollama) without touching
/// the chain — that replaceability was the owner's explicit ask.
class PipelineStep {
  PipelineStep({
    String? id,
    required this.kind,
    this.modelRef = '',
    this.agentId = '',
    this.enabled = true,
  }) : id = id ?? newId();

  final String id;

  /// One of [PipelineKind].
  String kind;

  /// Smart-model id for model steps; '' = default binding.
  String modelRef;

  /// For kind 'agent': which of the project's agents runs.
  String agentId;

  bool enabled;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'modelRef': modelRef,
        'agentId': agentId,
        'enabled': enabled,
      };

  factory PipelineStep.fromJson(Map<String, Object?> json) => PipelineStep(
        id: json['id'] as String?,
        kind: json['kind'] as String? ?? PipelineKind.answer,
        modelRef: json['modelRef'] as String? ?? '',
        agentId: json['agentId'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
      );
}

/// The step kinds of the owner's chain, in their canonical order.
class PipelineKind {
  /// Head of the chain: detects the input language (fa/en).
  static const String detect = 'detect';

  /// Translates the input to English when it is not English.
  static const String translateIn = 'translateIn';

  /// Interprets the request: what does the user want (intent)?
  static const String interpret = 'interpret';

  /// The manager: routes by intent — task → agent step, question /
  /// chat → answer step, translate → the translation is the answer.
  /// A routing brain (rules over the interpreter's output), not a
  /// generative model; the UI says so plainly.
  static const String manage = 'manage';

  /// Runs one of the project's agents (tools, skills, memory).
  static const String agent = 'agent';

  /// Produces a text answer with the LLM slot.
  static const String answer = 'answer';

  /// Translates the final answer back to the user's language.
  static const String translateBack = 'translateBack';

  static const List<String> order = [
    detect,
    translateIn,
    interpret,
    manage,
    agent,
    answer,
    translateBack,
  ];
}

/// The default chain, exactly as the owner specified it (2026-10-22):
/// language detector at the head; translator when needed; an
/// interpreter; a manager that routes and schedules; an English LLM
/// for answers, translated back to Persian for the user; and the
/// project's agents for software work.
List<PipelineStep> defaultPipeline({String firstAgentId = ''}) => [
      PipelineStep(kind: PipelineKind.detect),
      PipelineStep(kind: PipelineKind.translateIn),
      PipelineStep(kind: PipelineKind.interpret),
      PipelineStep(kind: PipelineKind.manage),
      PipelineStep(kind: PipelineKind.agent, agentId: firstAgentId),
      PipelineStep(kind: PipelineKind.answer),
      PipelineStep(kind: PipelineKind.translateBack),
    ];
