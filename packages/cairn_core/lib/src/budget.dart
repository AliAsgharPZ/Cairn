/// Hard execution limits for one task run. Budgets stop execution; they never
/// merely slow it down, and they cannot be overridden by the model.
class ExecutionBudget {
  const ExecutionBudget({
    this.maxSteps = 25,
    this.maxModelCalls = 40,
    this.maxToolCalls = 40,
    this.maxWallClock = const Duration(minutes: 15),
    this.maxRetriesPerStep = 2,
  });

  final int maxSteps;
  final int maxModelCalls;
  final int maxToolCalls;
  final Duration maxWallClock;
  final int maxRetriesPerStep;

  Map<String, Object?> toJson() => {
        'maxSteps': maxSteps,
        'maxModelCalls': maxModelCalls,
        'maxToolCalls': maxToolCalls,
        'maxWallClockMs': maxWallClock.inMilliseconds,
        'maxRetriesPerStep': maxRetriesPerStep,
      };

  factory ExecutionBudget.fromJson(Map<String, Object?> json) => ExecutionBudget(
        maxSteps: (json['maxSteps'] as num?)?.toInt() ?? 25,
        maxModelCalls: (json['maxModelCalls'] as num?)?.toInt() ?? 40,
        maxToolCalls: (json['maxToolCalls'] as num?)?.toInt() ?? 40,
        maxWallClock: Duration(
            milliseconds: (json['maxWallClockMs'] as num?)?.toInt() ??
                const Duration(minutes: 15).inMilliseconds),
        maxRetriesPerStep: (json['maxRetriesPerStep'] as num?)?.toInt() ?? 2,
      );
}

/// Thrown when a budget limit is reached. [kind] is one of:
/// 'steps' | 'modelCalls' | 'toolCalls' | 'wallClock'.
class BudgetExceededException implements Exception {
  BudgetExceededException(this.kind, this.limit);
  final String kind;
  final int limit;
  @override
  String toString() => 'Budget exceeded: $kind (limit $limit)';
}

/// Counts consumption against an [ExecutionBudget]. The clock is injectable
/// so wall-clock behaviour is deterministically testable.
class BudgetTracker {
  BudgetTracker(this.budget, {DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc()),
        _startedAt = (clock ?? (() => DateTime.now().toUtc()))();

  final ExecutionBudget budget;
  final DateTime Function() _clock;
  final DateTime _startedAt;

  int _steps = 0;
  int _modelCalls = 0;
  int _toolCalls = 0;

  int get stepsUsed => _steps;
  int get modelCallsUsed => _modelCalls;
  int get toolCallsUsed => _toolCalls;
  Duration get elapsed => _clock().difference(_startedAt);

  void consumeStep() {
    if (_steps >= budget.maxSteps) {
      throw BudgetExceededException('steps', budget.maxSteps);
    }
    _steps++;
  }

  void consumeModelCall() {
    if (_modelCalls >= budget.maxModelCalls) {
      throw BudgetExceededException('modelCalls', budget.maxModelCalls);
    }
    _modelCalls++;
  }

  void consumeToolCall() {
    if (_toolCalls >= budget.maxToolCalls) {
      throw BudgetExceededException('toolCalls', budget.maxToolCalls);
    }
    _toolCalls++;
  }

  /// Throws if the wall-clock budget has been exhausted.
  void checkClock() {
    if (elapsed > budget.maxWallClock) {
      throw BudgetExceededException(
          'wallClock', budget.maxWallClock.inSeconds);
    }
  }
}
