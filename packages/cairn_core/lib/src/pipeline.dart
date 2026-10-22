import 'ids.dart';
import 'model_definition.dart';

/// One step of a project's FLOWCHART (v1.3; v1.2's fixed chain,
/// generalized per the owner's direction).
///
/// The owner defines the flowchart: steps are added, removed and
/// reordered freely. Each step names a ROLE ([ModelRole]); at run
/// time the step is executed by the model definition bound to it
/// ([modelDefId]), or by the default model of that role when unbound
/// ('' = automatic). Any open-source model or AI API can fill any
/// role — the flowchart never names a vendor.
class PipelineStep {
  PipelineStep({
    String? id,
    required this.role,
    this.modelDefId = '',
    this.enabled = true,
    this.fromLang = '',
    this.toLang = '',
  }) : id = id ?? newId();

  final String id;

  /// One of [ModelRole].
  String role;

  /// The bound [ModelDefinition] id; '' = automatic for the role.
  String modelDefId;

  bool enabled;

  /// Translator steps only (v1.4, language-agnostic flows): the
  /// source language code; '' = whatever language the text is in.
  String fromLang;

  /// Translator steps only: the target language code; '' = the
  /// project's language (or the input language when the project has
  /// none); the special value 'input' = back to the language the
  /// user wrote in. ANY language can be used — the registry lives in
  /// the app (built-ins + the owner's custom languages).
  String toLang;

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role,
        'modelDefId': modelDefId,
        'enabled': enabled,
        'fromLang': fromLang,
        'toLang': toLang,
      };

  factory PipelineStep.fromJson(Map<String, Object?> json) {
    // v1.2 steps stored kind/modelRef/agentId. Map them forward:
    // detect folded into the runner (language is detected internally
    // now, it is not a role), translateIn/translateBack both become
    // the translator role, answer becomes the LLM role.
    final legacyKind = json['kind'] as String?;
    var role = json['role'] as String? ?? '';
    if (role.isEmpty && legacyKind != null) {
      role = switch (legacyKind) {
        'translateIn' || 'translateBack' => ModelRole.translator,
        'interpret' => ModelRole.interpreter,
        'manage' => ModelRole.manager,
        'agent' => ModelRole.agent,
        'answer' => ModelRole.llm,
        'detect' => '',
        _ => ModelRole.llm,
      };
    }
    return PipelineStep(
      id: json['id'] as String?,
      role: role,
      modelDefId: (json['modelDefId'] as String?) ??
          (json['modelRef'] as String? ?? ''),
      enabled: json['enabled'] as bool? ?? true,
      fromLang: json['fromLang'] as String? ?? '',
      toLang: json['toLang'] as String? ?? '',
    );
  }

  /// v1.2 kind names, kept for the (few) places that still speak
  /// them during migration. New code uses [role].
  static const String kindDetect = 'detect';
}

/// The default flowchart (v1.3): the owner's line, expressed in
/// roles — interpreter understands, manager routes, the agent works,
/// the LLM answers, the translator carries text across languages at
/// both ends. Steps can be rearranged or removed by the owner.
List<PipelineStep> defaultPipeline() => [
      PipelineStep(role: ModelRole.translator),
      PipelineStep(role: ModelRole.interpreter),
      PipelineStep(role: ModelRole.manager),
      PipelineStep(role: ModelRole.agent),
      PipelineStep(role: ModelRole.llm),
      // The last translator step returns the answer to the language
      // the user wrote in ('input') — whatever language that is.
      PipelineStep(role: ModelRole.translator, toLang: 'input'),
    ];
