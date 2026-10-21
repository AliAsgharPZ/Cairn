import 'dart:async';

import 'package:cairn_runtime/cairn_runtime.dart';

import 'framing.dart';
import 'protocol.dart';

/// The Tool Host server: serves a [ToolRegistry] over the framed JSON-RPC
/// protocol. Runs inside the separate host process. Tool *failures* are
/// returned as normal results (`ok: false`); only protocol-level problems
/// (unknown method/tool, malformed params) become RPC errors.
class ToolHostServer {
  ToolHostServer({required this.tools});

  final ToolRegistry tools;

  /// Serves until [incoming] closes.
  Future<void> serve(
    Stream<List<int>> incoming,
    StreamSink<List<int>> outgoing,
  ) async {
    await for (final json in decodeMessages(incoming)) {
      final RpcRequest request;
      try {
        request = RpcRequest.fromJson(json);
      } catch (_) {
        continue; // Unparseable frame: no id to answer to; drop it.
      }
      final response = await _handle(request);
      outgoing.add(frameMessage(response.toJson()));
    }
  }

  Future<RpcResponse> _handle(RpcRequest request) async {
    switch (request.method) {
      case ToolHostMethods.ping:
        return RpcResponse(id: request.id, result: {
          'pong': true,
          'version': toolHostProtocolVersion,
        });
      case ToolHostMethods.capabilities:
        return RpcResponse(id: request.id, result: {
          'tools': [
            for (final t in tools.all)
              ToolDescriptor(
                id: t.id,
                description: t.description,
                sensitive: t.sensitive,
                requiresNetwork: t.requiresNetwork,
              ).toJson(),
          ],
        });
      case ToolHostMethods.invoke:
        final toolId = request.params['toolId'];
        final input = request.params['input'];
        if (toolId is! String || input is! Map) {
          return RpcResponse(
            id: request.id,
            error: const RpcError(RpcErrorCodes.invalidParams,
                'tool.invoke needs {toolId: string, input: object}'),
          );
        }
        final tool = tools.lookup(toolId);
        if (tool == null) {
          return RpcResponse(
            id: request.id,
            error: RpcError(
                RpcErrorCodes.toolNotFound, 'unknown tool "$toolId"'),
          );
        }
        try {
          final result = await tool.run(
            input.cast<String, Object?>(),
            ToolContext(
              projectId: request.params['projectId'] as String? ?? 'toolhost',
              agentId: request.params['agentId'] as String? ?? 'toolhost',
              taskId: request.params['taskId'] as String? ?? 'toolhost',
              workingDirectory:
                  request.params['workingDirectory'] as String?,
            ),
          );
          return RpcResponse(id: request.id, result: {
            'ok': result.ok,
            'output': result.output,
            'data': result.data,
          });
        } catch (e) {
          return RpcResponse(
            id: request.id,
            error: RpcError(RpcErrorCodes.internal, 'tool failed: $e'),
          );
        }
      default:
        return RpcResponse(
          id: request.id,
          error: RpcError(RpcErrorCodes.methodNotFound,
              'unknown method "${request.method}"'),
        );
    }
  }
}
