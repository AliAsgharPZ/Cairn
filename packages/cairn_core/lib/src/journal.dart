import 'dart:convert';

/// One entry of the append-only event journal: the audit trail and the source
/// from which task state is materialised (and later, what sync replicates).
class JournalEvent {
  JournalEvent({
    required this.seq,
    required this.at,
    required this.kind,
    this.taskId,
    Map<String, Object?>? data,
  }) : data = data ?? const {};

  /// Monotonic sequence number within one journal (0-based).
  final int seq;
  final DateTime at;

  /// Event kind, e.g. 'task.created', 'task.transition', 'step.finished'.
  final String kind;
  final String? taskId;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'seq': seq,
        'at': at.toIso8601String(),
        'kind': kind,
        if (taskId != null) 'taskId': taskId,
        'data': data,
      };

  factory JournalEvent.fromJson(Map<String, Object?> json) => JournalEvent(
        seq: (json['seq'] as num?)?.toInt() ?? -1,
        at: DateTime.tryParse(json['at'] as String? ?? '') ??
            DateTime.now().toUtc(),
        kind: json['kind'] as String? ?? '',
        taskId: json['taskId'] as String?,
        data: (json['data'] as Map?)?.cast<String, Object?>() ?? const {},
      );
}

/// In-memory journal with JSONL serialisation (one event per line), the
/// durable format used by the storage layer.
class Journal {
  Journal({DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final List<JournalEvent> _events = [];

  List<JournalEvent> get events => List.unmodifiable(_events);
  int get length => _events.length;

  JournalEvent append(String kind,
      {String? taskId, Map<String, Object?> data = const {}}) {
    final event = JournalEvent(
      seq: _events.length,
      at: _clock(),
      kind: kind,
      taskId: taskId,
      data: data,
    );
    _events.add(event);
    return event;
  }

  List<JournalEvent> eventsForTask(String taskId) =>
      _events.where((e) => e.taskId == taskId).toList();

  String encodeJsonl() =>
      _events.map((e) => jsonEncode(e.toJson())).join('\n');

  /// Parses JSONL produced by [encodeJsonl]. Throws [FormatException] on a
  /// malformed line or a broken sequence (gap/dup) — a corrupt journal must
  /// fail loudly, never silently lose history.
  static List<JournalEvent> decodeJsonl(String text) {
    final events = <JournalEvent>[];
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
    for (final line in lines) {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('journal line is not a JSON object');
      }
      final event = JournalEvent.fromJson(decoded.cast<String, Object?>());
      if (event.seq != events.length) {
        throw FormatException(
            'journal sequence broken: expected ${events.length}, got ${event.seq}');
      }
      events.add(event);
    }
    return events;
  }
}
