import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

void main() {
  group('TaskStateMachine', () {
    test('happy path: created → … → completed', () {
      final sm = TaskStateMachine();
      expect(sm.status, TaskStatus.created);
      sm.transition(TaskStatus.analyzing);
      sm.transition(TaskStatus.awaitingApproval);
      sm.transition(TaskStatus.ready);
      sm.transition(TaskStatus.running);
      sm.transition(TaskStatus.verifying);
      sm.transition(TaskStatus.completed);
      expect(sm.status, TaskStatus.completed);
      expect(sm.history, hasLength(7));
    });

    test('illegal transitions are rejected', () {
      final sm = TaskStateMachine();
      expect(() => sm.transition(TaskStatus.completed), throwsStateError);
      expect(() => sm.transition(TaskStatus.running), throwsStateError);
      expect(sm.status, TaskStatus.created); // unchanged
    });

    test('terminal states accept no further transitions', () {
      final sm = TaskStateMachine();
      sm.transition(TaskStatus.cancelled);
      expect(isTerminal(sm.status), isTrue);
      expect(() => sm.transition(TaskStatus.analyzing), throwsStateError);
    });

    test('pause and resume are legal from running', () {
      final sm = TaskStateMachine();
      sm.transition(TaskStatus.analyzing);
      sm.transition(TaskStatus.ready);
      sm.transition(TaskStatus.running);
      sm.transition(TaskStatus.paused);
      sm.transition(TaskStatus.running);
      expect(sm.status, TaskStatus.running);
    });

    test('retry loop: running → retrying → running', () {
      final sm = TaskStateMachine();
      sm.transition(TaskStatus.analyzing);
      sm.transition(TaskStatus.ready);
      sm.transition(TaskStatus.running);
      sm.transition(TaskStatus.retrying);
      sm.transition(TaskStatus.running);
      sm.transition(TaskStatus.verifying);
      sm.transition(TaskStatus.retrying);
      sm.transition(TaskStatus.running);
      expect(sm.status, TaskStatus.running);
    });

    test('JSON round-trip preserves history; corrupt history is rejected',
        () {
      final sm = TaskStateMachine();
      sm.transition(TaskStatus.analyzing);
      sm.transition(TaskStatus.ready);
      final restored = TaskStateMachine.fromJson(sm.toJson());
      expect(restored.status, TaskStatus.ready);
      expect(restored.history, hasLength(3));

      expect(
        () => TaskStateMachine.fromJson({
          'history': [
            {'status': 'created', 'at': '2026-01-01T00:00:00.000Z'},
            {'status': 'completed', 'at': '2026-01-01T00:01:00.000Z'},
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('TaskRun', () {
    test('JSON round-trip with steps', () {
      final run = TaskRun(
        projectId: 'p1',
        agentId: 'a1',
        instruction: 'خلاصه کن', // Persian instruction round-trip.
        steps: [
          TaskStep(description: 'read files', kind: 'tool', toolId: 'fs.read'),
          TaskStep(description: 'summarize', kind: 'model'),
        ],
      );
      run.stateMachine.transition(TaskStatus.analyzing);
      final restored = TaskRun.fromJson(run.toJson());
      expect(restored.instruction, 'خلاصه کن');
      expect(restored.steps, hasLength(2));
      expect(restored.steps.first.toolId, 'fs.read');
      expect(restored.status, TaskStatus.analyzing);
    });
  });
}
