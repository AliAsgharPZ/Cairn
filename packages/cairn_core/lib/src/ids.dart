import 'dart:math';

final Random _rng = Random.secure();

/// Generates a random UUID v4 string (RFC 4122) using a CSPRNG.
String newId() {
  final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
  return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
      '${hex(4)}${hex(5)}-'
      '${hex(6)}${hex(7)}-'
      '${hex(8)}${hex(9)}-'
      '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
}

/// Generates an idempotency key for a task step: stable per (taskId, stepId,
/// attempt) so re-dispatch of the same attempt is recognisably the same work,
/// while a genuinely new attempt gets a new key.
String idempotencyKey(String taskId, String stepId, int attempt) =>
    'idem:$taskId:$stepId:$attempt';
