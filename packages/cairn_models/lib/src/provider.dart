import 'package:cairn_core/cairn_core.dart';

enum ChatRole { system, user, assistant }

class ChatMessage {
  const ChatMessage(this.role, this.content);
  final ChatRole role;
  final String content;

  Map<String, Object?> toJson() => {'role': role.name, 'content': content};
}

class ModelRequest {
  const ModelRequest({
    required this.messages,
    this.temperature,
    this.maxOutputTokens,
  });

  final List<ChatMessage> messages;
  final double? temperature;
  final int? maxOutputTokens;
}

class ModelUsage {
  const ModelUsage({this.promptTokens, this.completionTokens});
  final int? promptTokens;
  final int? completionTokens;
}

class ModelResponse {
  const ModelResponse({required this.text, this.usage = const ModelUsage()});
  final String text;
  final ModelUsage usage;
}

/// A model provider failed (transport, HTTP status, or malformed payload).
/// Carries the provider id and, when known, the HTTP status — never secrets.
class ProviderException implements Exception {
  ProviderException(this.providerId, this.message, {this.statusCode});
  final String providerId;
  final String message;
  final int? statusCode;
  @override
  String toString() =>
      'ProviderException($providerId${statusCode != null ? ', HTTP $statusCode' : ''}): $message';
}

/// A chat-completion provider. Implementations are real network adapters,
/// except [FakeModelProvider]-style test doubles which live in fake_provider.dart
/// and are never wired as a product default.
abstract class ModelProvider {
  /// Matches [ModelConfig.providerId] values this adapter serves.
  String get id;

  Future<ModelResponse> complete(ModelConfig config, ModelRequest request);
}

/// Resolves the API key for a provider at call time. Keys live in the
/// platform secure store (Keystore/DPAPI) — never in this package, never in
/// project files, never in logs.
typedef ApiKeyResolver = Future<String?> Function();
