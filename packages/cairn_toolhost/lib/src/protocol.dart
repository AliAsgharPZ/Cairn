import 'dart:convert';

/// Wire protocol between the Cairn app and the Tool Host process.
///
/// Transport-agnostic: messages are JSON objects framed by a 4-byte
/// little-endian length prefix (see framing.dart). On Windows the
/// transport is a Named Pipe; in development and tests it is the host
/// process's stdio. The protocol is deliberately small:
///
/// - `host.ping`        → `{pong: true, version: 1}`
/// - `host.capabilities`→ `{tools: [{id, description, sensitive, requiresNetwork}]}`
/// - `tool.invoke`      → params `{toolId, input, projectId, agentId, taskId}`,
///                        result `{ok, output, data}` (a ToolResult).
abstract final class ToolHostMethods {
  static const String ping = 'host.ping';
  static const String capabilities = 'host.capabilities';
  static const String invoke = 'tool.invoke';
}

/// Protocol version spoken by this build.
const int toolHostProtocolVersion = 1;

class RpcRequest {
  const RpcRequest(
      {required this.id, required this.method, this.params = const {}});

  final int id;
  final String method;
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => {'id': id, 'method': method, 'params': params};

  factory RpcRequest.fromJson(Map<String, Object?> json) => RpcRequest(
        id: (json['id'] as num).toInt(),
        method: json['method'] as String,
        params: (json['params'] as Map?)?.cast<String, Object?>() ?? const {},
      );

  String encode() => jsonEncode(toJson());
}

class RpcError {
  const RpcError(this.code, this.message);
  final int code;
  final String message;

  Map<String, Object?> toJson() => {'code': code, 'message': message};

  factory RpcError.fromJson(Map<String, Object?> json) => RpcError(
      (json['code'] as num).toInt(), json['message'] as String? ?? 'error');

  @override
  String toString() => 'RpcError($code): $message';
}

/// JSON-RPC style error codes used by the Tool Host.
abstract final class RpcErrorCodes {
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int toolNotFound = -32001;
  static const int internal = -32603;
}

class RpcResponse {
  const RpcResponse({required this.id, this.result, this.error})
      : assert((result == null) != (error == null),
            'exactly one of result/error');

  final int id;
  final Map<String, Object?>? result;
  final RpcError? error;

  bool get isError => error != null;

  Map<String, Object?> toJson() => {
        'id': id,
        if (result != null) 'result': result,
        if (error != null) 'error': error!.toJson(),
      };

  factory RpcResponse.fromJson(Map<String, Object?> json) => RpcResponse(
        id: (json['id'] as num).toInt(),
        result: (json['result'] as Map?)?.cast<String, Object?>(),
        error: json['error'] == null
            ? null
            : RpcError.fromJson(
                (json['error'] as Map).cast<String, Object?>()),
      );
}

/// A tool descriptor as reported by `host.capabilities`.
class ToolDescriptor {
  const ToolDescriptor({
    required this.id,
    required this.description,
    required this.sensitive,
    required this.requiresNetwork,
  });

  final String id;
  final String description;
  final bool sensitive;
  final bool requiresNetwork;

  Map<String, Object?> toJson() => {
        'id': id,
        'description': description,
        'sensitive': sensitive,
        'requiresNetwork': requiresNetwork,
      };

  factory ToolDescriptor.fromJson(Map<String, Object?> json) =>
      ToolDescriptor(
        id: json['id'] as String,
        description: json['description'] as String? ?? '',
        sensitive: json['sensitive'] as bool? ?? false,
        requiresNetwork: json['requiresNetwork'] as bool? ?? false,
      );
}
