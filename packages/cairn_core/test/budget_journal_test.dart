import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

void main() {
  group('BudgetTracker', () {
    test('step budget: the (max+1)-th step throws', () {
      final tracker =
          BudgetTracker(const ExecutionBudget(maxSteps: 3));
      tracker.consumeStep();
      tracker.consumeStep();
      tracker.consumeStep();
      expect(tracker.stepsUsed, 3);
      expect(
        tracker.consumeStep,
        throwsA(isA<BudgetExceededException>()
            .having((e) => e.kind, 'kind', 'steps')),
      );
    });

    test('model-call and tool-call budgets are independent', () {
      final tracker = BudgetTracker(
          const ExecutionBudget(maxModelCalls: 1, maxToolCalls: 2));
      tracker.consumeModelCall();
      expect(tracker.consumeModelCall, throwsA(isA<BudgetExceededException>()));
      tracker.consumeToolCall();
      tracker.consumeToolCall();
      expect(tracker.consumeToolCall, throwsA(isA<BudgetExceededException>()));
      expect(tracker.modelCallsUsed, 1);
      expect(tracker.toolCallsUsed, 2);
    });

    test('wall-clock budget uses the injected clock', () {
      var now = DateTime.utc(2026, 1, 1, 12);
      final tracker = BudgetTracker(
        const ExecutionBudget(maxWallClock: Duration(minutes: 5)),
        clock: () => now,
      );
      tracker.checkClock(); // within budget
      now = now.add(const Duration(minutes: 6));
      expect(
        tracker.checkClock,
        throwsA(isA<BudgetExceededException>()
            .having((e) => e.kind, 'kind', 'wallClock')),
      );
    });
  });

  group('Journal', () {
    test('append assigns monotonic sequence numbers', () {
      final j = Journal();
      final e0 = j.append('task.created', taskId: 't1');
      final e1 = j.append('task.transition', taskId: 't1');
      final e2 = j.append('task.created', taskId: 't2');
      expect([e0.seq, e1.seq, e2.seq], [0, 1, 2]);
      expect(j.eventsForTask('t1'), hasLength(2));
      expect(j.length, 3);
    });

    test('JSONL round-trip preserves events and data', () {
      final j = Journal();
      j.append('step.finished',
          taskId: 't1', data: {'stepId': 's1', 'ok': true});
      j.append('task.transition', taskId: 't1', data: {'to': 'running'});
      final decoded = Journal.decodeJsonl(j.encodeJsonl());
      expect(decoded, hasLength(2));
      expect(decoded.first.kind, 'step.finished');
      expect(decoded.first.data['ok'], isTrue);
      expect(decoded.last.data['to'], 'running');
    });

    test('decodeJsonl rejects a sequence gap', () {
      const broken = '{"seq":0,"at":"2026-01-01T00:00:00.000Z","kind":"a","data":{}}\n'
          '{"seq":5,"at":"2026-01-01T00:00:01.000Z","kind":"b","data":{}}';
      expect(() => Journal.decodeJsonl(broken), throwsFormatException);
    });

    test('decodeJsonl rejects malformed JSON', () {
      expect(() => Journal.decodeJsonl('not json'), throwsFormatException);
    });
  });

  group('ids', () {
    test('newId produces distinct RFC4122 v4-shaped ids', () {
      final a = newId();
      final b = newId();
      expect(a, isNot(b));
      expect(a, matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('idempotency keys are stable per attempt', () {
      expect(idempotencyKey('t', 's', 1), idempotencyKey('t', 's', 1));
      expect(idempotencyKey('t', 's', 1),
          isNot(idempotencyKey('t', 's', 2)));
    });
  });
}
