import 'dart:async';
import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';

import 'framing.dart';
import 'protocol.dart';

/// Client for a Tool Host process. The app uses this on Windows, where
/// platform tools execute in the separate host process; the [Tool]
/// adapters produced by [toolsFromCapabilities] plug straight into the
/// runtime's [ToolRegistry], so the orchestrator cannot tell local and
/// host-executed tools apart — policy and approvals are enforced by the
/// orchestrator exactly the same way.
class ToolHostClient {
  ToolHostClient({
    required Stream<List<int>> incoming,
    required StreamSink<List<int>> outgoing,
  }) : _outgoing = outgoing {
    _subscription = decodeMessages(incoming).listen(_onMessage);
  }

  /// Connects to a host process over its stdio.
  factory ToolHostClient.stdio(Process process) => ToolHostClient(
        incoming: process.stdout,
        outgoing: process.stdin,
      );

  final StreamSink<List<int>> _outgoing;
  late final StreamSubscription<Map<String, Object?>> _subscription;
  final _pending = <int, Completer<RpcResponse>>{};
  var _nextId = 1;
  var _closed = false;

  void _onMessage(Map<String, Object?> json) {
    final response = RpcResponse.fromJson(json);
    _pending.remove(response.id)?.complete(response);
  }

  Future<RpcResponse> _call(String method,
      [Map<String, Object?> params = const {}]) async {
    if (_closed) throw StateError('ToolHostClient is closed');
    final id = _nextId++;
    final completer = Completer<RpcResponse>();
    _pending[id] = completer;
    _outgoing
        .add(frameMessage(RpcRequest(id: id, method: method, params: params).toJson()));
    return completer.future;
  }

  Future<void> ping() async {
    final res = await _call(ToolHostMethods.ping);
    if (res.isError) throw res.error!;
    if (res.result?['pong'] != true) {
      throw StateError('unexpected ping reply: ${res.result}');
    }
  }

  Future<List<ToolDescriptor>> capabilities() async {
    final res = await _call(ToolHostMethods.capabilities);
    if (res.isError) throw res.error!;
    final tools = res.result?['tools'] as List? ?? const [];
    return [
      for (final t in tools)
        ToolDescriptor.fromJson((t as Map).cast<String, Object?>()),
    ];
  }

  Future<ToolResult> invokeTool(
    String toolId,
    Map<String, Object?> input, {
    required String projectId,
    required String agentId,
    required String taskId,
  }) async {
    final res = await _call(ToolHostMethods.invoke, {
      'toolId': toolId,
      'input': input,
      'projectId': projectId,
      'agentId': agentId,
      'taskId': taskId,
    });
    if (res.isError) throw res.error!;
    final r = res.result!;
    return ToolResult(
      ok: r['ok'] as bool,
      output: r['output'] as String,
      data: (r['data'] as Map?)?.cast<String, Object?>(),
    );
  }

  /// Builds [Tool] adapters for every tool the host reports, so they can
  /// be registered in the app's [ToolRegistry].
  Future<List<Tool>> toolsFromCapabilities() async {
    final descriptors = await capabilities();
    return [
      for (final d in descriptors)
        _RemoteTool(descriptor: d, client: this),
    ];
  }

  Future<void> close() async {
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('client closed'));
    }
    _pending.clear();
    await _subscription.cancel();
    await _outgoing.close();
  }
}

class _RemoteTool extends Tool {
  _RemoteTool({required this.descriptor, required this.client});

  final ToolDescriptor descriptor;
  final ToolHostClient client;

  @override
  String get id => descriptor.id;
  @override
  String get description => descriptor.description;
  @override
  bool get sensitive => descriptor.sensitive;
  @override
  bool get requiresNetwork => descriptor.requiresNetwork;

  @override
  Future<ToolResult> run(
          Map<String, Object?> input, ToolContext context) =>
      client.invokeTool(
        id,
        input,
        projectId: context.projectId,
        agentId: context.agentId,
        taskId: context.taskId,
      );
}
