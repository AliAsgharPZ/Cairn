/// A tool an agent can invoke. Tools are the only way an agent touches the
/// world; every call passes the policy engine and the budget first.
abstract class Tool {
  /// Stable id referenced by blueprints and plans, e.g. 'fs.read'.
  String get id;

  String get description;

  /// Whether calls need explicit user approval under
  /// [ApprovalLevel.sensitiveOnly] (destructive / external / costly tools).
  bool get sensitive;

  /// Whether the tool performs network access. The orchestrator refuses
  /// such tools when the agent's policy disallows network
  /// ([PolicyConfig.allowNetwork] == false).
  bool get requiresNetwork => false;

  Future<ToolResult> run(Map<String, Object?> input, ToolContext context);
}

class ToolResult {
  const ToolResult({required this.ok, required this.output, this.data});
  final bool ok;

  /// Human-readable output (shown in the test console and fed back to the
  /// model as the step result).
  final String output;
  final Map<String, Object?>? data;

  factory ToolResult.success(String output, {Map<String, Object?>? data}) =>
      ToolResult(ok: true, output: output, data: data);
  factory ToolResult.failure(String output) =>
      ToolResult(ok: false, output: output);
}

/// Execution context handed to a tool: who is running, in which project,
/// with what working directory (platform tools interpret it; pure-Dart
/// tools may ignore it).
class ToolContext {
  const ToolContext({
    required this.projectId,
    required this.agentId,
    required this.taskId,
    this.workingDirectory,
  });

  final String projectId;
  final String agentId;
  final String taskId;
  final String? workingDirectory;
}

/// Id-keyed registry of the tools available on this device/installation.
/// A plan step may only use a tool that is BOTH registered here AND declared
/// in the agent's blueprint.
class ToolRegistry {
  ToolRegistry([Iterable<Tool> tools = const []]) {
    for (final t in tools) {
      register(t);
    }
  }

  final Map<String, Tool> _tools = {};

  void register(Tool tool) {
    if (_tools.containsKey(tool.id)) {
      throw ArgumentError('Duplicate tool id: ${tool.id}');
    }
    _tools[tool.id] = tool;
  }

  Tool? lookup(String id) => _tools[id];
  bool contains(String id) => _tools.containsKey(id);
  List<Tool> get all => List.unmodifiable(_tools.values);
}
