import 'ids.dart';

/// Task lifecycle states (master spec §4; identical on both devices).
enum TaskStatus {
  created,
  analyzing,
  awaitingApproval,
  ready,
  running,
  verifying,
  retrying,
  paused,
  completed,
  failed,
  cancelled,
}

/// The only legal transitions of the task state machine. Anything not listed
/// is rejected — a bug must never silently move a task through an impossible
/// path (e.g. created → completed).
const Map<TaskStatus, Set<TaskStatus>> kLegalTransitions = {
  TaskStatus.created: {TaskStatus.analyzing, TaskStatus.cancelled},
  TaskStatus.analyzing: {
    TaskStatus.awaitingApproval,
    TaskStatus.ready,
    TaskStatus.failed,
    TaskStatus.cancelled,
  },
  TaskStatus.awaitingApproval: {
    TaskStatus.ready,
    TaskStatus.cancelled,
  },
  TaskStatus.ready: {
    TaskStatus.running,
    TaskStatus.paused,
    TaskStatus.cancelled,
  },
  TaskStatus.running: {
    TaskStatus.verifying,
    TaskStatus.retrying,
    TaskStatus.paused,
    TaskStatus.failed,
    TaskStatus.cancelled,
  },
  TaskStatus.verifying: {
    TaskStatus.completed,
    TaskStatus.retrying,
    TaskStatus.failed,
  },
  TaskStatus.retrying: {
    TaskStatus.running,
    TaskStatus.failed,
    TaskStatus.cancelled,
  },
  TaskStatus.paused: {
    TaskStatus.ready,
    TaskStatus.running,
    TaskStatus.cancelled,
  },
  TaskStatus.completed: {},
  TaskStatus.failed: {},
  TaskStatus.cancelled: {},
};

bool canTransition(TaskStatus from, TaskStatus to) =>
    kLegalTransitions[from]?.contains(to) ?? false;

bool isTerminal(TaskStatus s) =>
    s == TaskStatus.completed || s == TaskStatus.failed || s == TaskStatus.cancelled;

class StatusChange {
  StatusChange(this.status, this.at);
  final TaskStatus status;
  final DateTime at;

  Map<String, Object?> toJson() =>
      {'status': status.name, 'at': at.toIso8601String()};

  factory StatusChange.fromJson(Map<String, Object?> json) => StatusChange(
        TaskStatus.values.asNameMap()[json['status']] ?? TaskStatus.created,
        DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now().toUtc(),
      );
}

/// Enforces the legal-transition table and records the full status history.
class TaskStateMachine {
  TaskStateMachine({DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc()),
        _history = [StatusChange(TaskStatus.created, DateTime.now().toUtc())];

  TaskStateMachine._(this._history, {DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final List<StatusChange> _history;

  TaskStatus get status => _history.last.status;
  List<StatusChange> get history => List.unmodifiable(_history);

  /// Moves to [next] if the transition is legal; throws [StateError] otherwise.
  void transition(TaskStatus next) {
    if (!canTransition(status, next)) {
      throw StateError('Illegal task transition: ${status.name} -> ${next.name}');
    }
    _history.add(StatusChange(next, _clock()));
  }

  Map<String, Object?> toJson() => {
        'history': _history.map((h) => h.toJson()).toList(),
      };

  factory TaskStateMachine.fromJson(Map<String, Object?> json) {
    final raw = (json['history'] as List? ?? const []);
    if (raw.isEmpty) return TaskStateMachine();
    final history = raw
        .map((e) => StatusChange.fromJson((e as Map).cast<String, Object?>()))
        .toList();
    // Validate the recorded history follows the legal table.
    for (var i = 1; i < history.length; i++) {
      if (!canTransition(history[i - 1].status, history[i].status)) {
        throw FormatException(
            'Corrupt task history: ${history[i - 1].status.name} -> ${history[i].status.name}');
      }
    }
    return TaskStateMachine._(history);
  }
}

enum StepStatus { pending, running, succeeded, failed, skipped }

/// One structured step of a task plan. [kind] selects the executor:
/// 'model' | 'tool' | 'verify' | 'note'.
class TaskStep {
  TaskStep({
    String? id,
    required this.description,
    this.kind = 'model',
    this.toolId,
    Map<String, Object?>? input,
    this.idempotencyKey,
  })  : id = id ?? newId(),
        input = input ?? const {};

  final String id;
  final String description;
  final String kind;
  final String? toolId;
  final Map<String, Object?> input;
  StepStatus status = StepStatus.pending;
  int attempts = 0;
  final String? idempotencyKey;
  String? lastError;

  Map<String, Object?> toJson() => {
        'id': id,
        'description': description,
        'kind': kind,
        if (toolId != null) 'toolId': toolId,
        'input': input,
        'status': status.name,
        'attempts': attempts,
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
        if (lastError != null) 'lastError': lastError,
      };

  factory TaskStep.fromJson(Map<String, Object?> json) {
    final step = TaskStep(
      id: json['id'] as String?,
      description: json['description'] as String? ?? '',
      kind: json['kind'] as String? ?? 'model',
      toolId: json['toolId'] as String?,
      input: (json['input'] as Map?)?.cast<String, Object?>() ?? const {},
      idempotencyKey: json['idempotencyKey'] as String?,
    );
    step.status =
        StepStatus.values.asNameMap()[json['status']] ?? StepStatus.pending;
    step.attempts = (json['attempts'] as num?)?.toInt() ?? 0;
    step.lastError = json['lastError'] as String?;
    return step;
  }
}

/// A single execution of an agent on one instruction, with its plan steps.
class TaskRun {
  TaskRun({
    String? id,
    required this.projectId,
    required this.agentId,
    required this.instruction,
    TaskStateMachine? stateMachine,
    List<TaskStep>? steps,
    DateTime? createdAt,
  })  : id = id ?? newId(),
        stateMachine = stateMachine ?? TaskStateMachine(),
        steps = steps ?? [],
        createdAt = createdAt ?? DateTime.now().toUtc();

  final String id;
  final String projectId;
  final String agentId;
  final String instruction;
  final TaskStateMachine stateMachine;
  final List<TaskStep> steps;
  final DateTime createdAt;

  TaskStatus get status => stateMachine.status;

  Map<String, Object?> toJson() => {
        'id': id,
        'projectId': projectId,
        'agentId': agentId,
        'instruction': instruction,
        'stateMachine': stateMachine.toJson(),
        'steps': steps.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory TaskRun.fromJson(Map<String, Object?> json) => TaskRun(
        id: json['id'] as String?,
        projectId: json['projectId'] as String? ?? '',
        agentId: json['agentId'] as String? ?? '',
        instruction: json['instruction'] as String? ?? '',
        stateMachine: json['stateMachine'] is Map
            ? TaskStateMachine.fromJson(
                (json['stateMachine'] as Map).cast<String, Object?>())
            : TaskStateMachine(),
        steps: (json['steps'] as List? ?? const [])
            .map((e) => TaskStep.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
