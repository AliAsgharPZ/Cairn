import 'tool_registry.dart';

/// A tool that executes on a paired peer device (compute overflow, M8).
/// From the orchestrator's point of view it is an ordinary [Tool] — the
/// plan, approval gates and journal apply unchanged; only the execution
/// site differs. The [executor] is wired to an authenticated overflow
/// connection (cairn_sync's OverflowClient) by the app.
///
/// The peer re-validates every invocation against its own policy
/// (allowlist + sensitive-tool rules): a refusal comes back as a normal
/// `ok == false` result, which the orchestrator handles like any tool
/// failure — it is never bypassed from this side.
class RemoteTool extends Tool {
  RemoteTool({
    required String id,
    required String description,
    bool sensitive = false,
    bool requiresNetwork = false,
    required this.executor,
  })  : _id = id,
        _description = description,
        _sensitive = sensitive,
        _requiresNetwork = requiresNetwork;

  final String _id;
  final String _description;
  final bool _sensitive;
  final bool _requiresNetwork;

  /// Runs the invocation on the peer and returns its result.
  final Future<ToolResult> Function(Map<String, Object?> input) executor;

  @override
  String get id => _id;

  @override
  String get description => _description;

  @override
  bool get sensitive => _sensitive;

  @override
  bool get requiresNetwork => _requiresNetwork;

  @override
  Future<ToolResult> run(
          Map<String, Object?> input, ToolContext context) =>
      executor(input);
}
