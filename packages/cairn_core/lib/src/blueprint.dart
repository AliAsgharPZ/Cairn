import 'ids.dart';

/// Current blueprint schema version. Bumped only with a documented migration.
const int kBlueprintSchemaVersion = 1;

/// Which model an agent uses and how it is called.
class ModelConfig {
  ModelConfig({
    required this.providerId,
    required this.modelId,
    this.temperature,
    this.maxOutputTokens,
  });

  /// Provider adapter id, e.g. 'openai-compatible', 'anthropic', 'ollama'.
  final String providerId;

  /// Model identifier within the provider, e.g. 'gpt-…', 'llama3.1'.
  final String modelId;
  final double? temperature;
  final int? maxOutputTokens;

  Map<String, Object?> toJson() => {
        'providerId': providerId,
        'modelId': modelId,
        if (temperature != null) 'temperature': temperature,
        if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
      };

  factory ModelConfig.fromJson(Map<String, Object?> json) => ModelConfig(
        providerId: json['providerId'] as String? ?? '',
        modelId: json['modelId'] as String? ?? '',
        temperature: (json['temperature'] as num?)?.toDouble(),
        maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt(),
      );
}

/// Language-pipeline configuration of an agent (detect → translate →
/// normalize). Stages run over the agent's configured model by default.
class LanguageConfig {
  const LanguageConfig({
    this.primaryLanguage = 'auto',
    this.translateWhenNeeded = true,
  });

  /// 'auto' | 'fa' | 'en'
  final String primaryLanguage;
  final bool translateWhenNeeded;

  Map<String, Object?> toJson() => {
        'primaryLanguage': primaryLanguage,
        'translateWhenNeeded': translateWhenNeeded,
      };

  factory LanguageConfig.fromJson(Map<String, Object?> json) => LanguageConfig(
        primaryLanguage: json['primaryLanguage'] as String? ?? 'auto',
        translateWhenNeeded: json['translateWhenNeeded'] as bool? ?? true,
      );
}

/// When a tool call must stop and ask the user.
enum ApprovalLevel {
  /// Nothing is auto-approved; every tool call asks. (Strictest.)
  all,

  /// Only tools flagged sensitive/destructive ask.
  sensitiveOnly,

  /// Tool calls run without asking (budgets and hard blocks still apply).
  none,
}

class PolicyConfig {
  const PolicyConfig({
    this.approvalLevel = ApprovalLevel.sensitiveOnly,
    this.allowNetwork = true,
  });

  final ApprovalLevel approvalLevel;
  final bool allowNetwork;

  Map<String, Object?> toJson() => {
        'approvalLevel': approvalLevel.name,
        'allowNetwork': allowNetwork,
      };

  factory PolicyConfig.fromJson(Map<String, Object?> json) => PolicyConfig(
        approvalLevel: ApprovalLevel.values.asNameMap()[json['approvalLevel']] ??
            ApprovalLevel.sensitiveOnly,
        allowNetwork: json['allowNetwork'] as bool? ?? true,
      );
}

class MemoryConfig {
  const MemoryConfig({this.enabled = true, this.maxContextMessages = 40});

  final bool enabled;
  final int maxContextMessages;

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'maxContextMessages': maxContextMessages,
      };

  factory MemoryConfig.fromJson(Map<String, Object?> json) => MemoryConfig(
        enabled: json['enabled'] as bool? ?? true,
        maxContextMessages: (json['maxContextMessages'] as num?)?.toInt() ?? 40,
      );
}

/// A tool an agent is allowed to use, with per-agent configuration.
class ToolBinding {
  ToolBinding({required this.toolId, Map<String, Object?>? config})
      : config = config ?? const {};

  final String toolId;
  final Map<String, Object?> config;

  Map<String, Object?> toJson() => {'toolId': toolId, 'config': config};

  factory ToolBinding.fromJson(Map<String, Object?> json) => ToolBinding(
        toolId: json['toolId'] as String? ?? '',
        config: (json['config'] as Map?)?.cast<String, Object?>() ?? const {},
      );
}

/// The complete definition of one agent inside a project — the "blueprint"
/// the studio edits, the runtime executes, and sync replicates.
class AgentBlueprint {
  AgentBlueprint({
    String? id,
    required this.name,
    this.description = '',
    this.systemPrompt = '',
    required this.model,
    this.language = const LanguageConfig(),
    List<ToolBinding>? tools,
    List<String>? skillIds,
    this.memory = const MemoryConfig(),
    this.policy = const PolicyConfig(),
    this.schemaVersion = kBlueprintSchemaVersion,
  })  : id = id ?? newId(),
        tools = tools ?? [],
        skillIds = skillIds ?? [];

  final String id;
  String name;
  String description;
  String systemPrompt;
  ModelConfig model;
  LanguageConfig language;
  final List<ToolBinding> tools;
  final List<String> skillIds;
  MemoryConfig memory;
  PolicyConfig policy;
  final int schemaVersion;

  /// Returns human-readable problems with this blueprint; empty means valid.
  List<String> validate() {
    final issues = <String>[];
    if (id.isEmpty) issues.add('agent id must not be empty');
    if (name.trim().isEmpty) issues.add('agent name must not be empty');
    if (model.providerId.isEmpty) issues.add('model.providerId is required');
    if (model.modelId.isEmpty) issues.add('model.modelId is required');
    final t = model.temperature;
    if (t != null && (t < 0 || t > 2)) {
      issues.add('model.temperature must be within [0, 2]');
    }
    final mot = model.maxOutputTokens;
    if (mot != null && mot <= 0) {
      issues.add('model.maxOutputTokens must be positive');
    }
    if (memory.maxContextMessages < 1) {
      issues.add('memory.maxContextMessages must be >= 1');
    }
    for (final tool in tools) {
      if (tool.toolId.isEmpty) issues.add('tool binding with empty toolId');
    }
    if (schemaVersion != kBlueprintSchemaVersion) {
      issues.add('unsupported blueprint schemaVersion: $schemaVersion');
    }
    return issues;
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'description': description,
        'systemPrompt': systemPrompt,
        'model': model.toJson(),
        'language': language.toJson(),
        'tools': tools.map((t) => t.toJson()).toList(),
        'skillIds': skillIds,
        'memory': memory.toJson(),
        'policy': policy.toJson(),
      };

  factory AgentBlueprint.fromJson(Map<String, Object?> json) {
    final modelJson = json['model'];
    if (modelJson is! Map) {
      throw const FormatException('agent blueprint is missing "model"');
    }
    return AgentBlueprint(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      model: ModelConfig.fromJson(modelJson.cast<String, Object?>()),
      language: json['language'] is Map
          ? LanguageConfig.fromJson(
              (json['language'] as Map).cast<String, Object?>())
          : const LanguageConfig(),
      tools: (json['tools'] as List? ?? const [])
          .map((e) => ToolBinding.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
      skillIds:
          (json['skillIds'] as List? ?? const []).map((e) => e as String).toList(),
      memory: json['memory'] is Map
          ? MemoryConfig.fromJson((json['memory'] as Map).cast<String, Object?>())
          : const MemoryConfig(),
      policy: json['policy'] is Map
          ? PolicyConfig.fromJson((json['policy'] as Map).cast<String, Object?>())
          : const PolicyConfig(),
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ??
          kBlueprintSchemaVersion,
    );
  }
}
