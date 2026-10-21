import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:test/test.dart';

class _FakeTool implements Tool {
  _FakeTool({this.sensitive = false, this.failTimes = 0});
  @override
  String get id => 'test.echo';
  @override
  String get description => 'Echoes its input text back.';
  @override
  final bool sensitive;
  int failTimes;
  final List<Map<String, Object?>> calls = [];

  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    calls.add(input);
    if (failTimes > 0) {
      failTimes--;
      return ToolResult.failure('boom');
    }
    return ToolResult.success('echo: ${input['text']}');
  }
}

const _normalizeJson =
    '{"goal": "Do the thing", "language": "en", "inputs": [], "constraints": []}';
const _planModelStep =
    '{"steps": [{"description": "Write a greeting", "kind": "model"}]}';
const _planToolStep =
    '{"steps": [{"description": "Echo hello", "kind": "tool", '
    '"toolId": "test.echo", "input": {"text": "hello"}}]}';
const _verifyDone = '{"done": true, "summary": "Goal achieved"}';

AgentBlueprint _agent({
  ApprovalLevel approval = ApprovalLevel.none,
  List<ToolBinding> tools = const [],
}) =>
    AgentBlueprint(
      name: 'test-agent',
      model: ModelConfig(providerId: 'fake', modelId: 'm'),
      policy: PolicyConfig(approvalLevel: approval),
      tools: tools,
    );

final _project = AgentProject(name: 'p');

void main() {
  group('Orchestrator happy paths', () {
    test('model-step plan runs to completion with a full audit trail',
        () async {
      final provider = FakeModelProvider(
          [_normalizeJson, _planModelStep, 'Hello, world!', _verifyDone]);
      final journal = Journal();
      final orch = Orchestrator(
          provider: provider, registry: ToolRegistry(), journal: journal);
      final outcome = await orch.run(
          project: _project, agent: _agent(), instruction: 'Do the thing');

      expect(outcome.succeeded, isTrue);
      expect(outcome.summary, 'Goal achieved');
      expect(outcome.stepOutputs.values.single, 'Hello, world!');
      expect(outcome.run.stateMachine.history.map((c) => c.status.name),
          ['created', 'analyzing', 'ready', 'running', 'verifying', 'completed']);
      final kinds = journal.events.map((e) => e.kind).toList();
      expect(kinds, containsAllInOrder(['task.created', 'task.planned', 'task.completed']));
    });

    test('tool step executes the real tool and feeds its output onward',
        () async {
      final tool = _FakeTool();
      final provider =
          FakeModelProvider([_normalizeJson, _planToolStep, _verifyDone]);
      final orch = Orchestrator(
          provider: provider, registry: ToolRegistry([tool]));
      final outcome = await orch.run(
        project: _project,
        agent: _agent(tools: [ToolBinding(toolId: 'test.echo')]),
        instruction: 'Do the thing',
      );
      expect(outcome.succeeded, isTrue);
      expect(tool.calls.single['text'], 'hello');
      expect(outcome.stepOutputs.values.single, 'echo: hello');
    });

    test('a flaky step is retried through the retrying state and succeeds',
        () async {
      final tool = _FakeTool(failTimes: 1);
      final provider =
          FakeModelProvider([_normalizeJson, _planToolStep, _verifyDone]);
      final journal = Journal();
      final orch = Orchestrator(
          provider: provider, registry: ToolRegistry([tool]), journal: journal);
      final outcome = await orch.run(
        project: _project,
        agent: _agent(tools: [ToolBinding(toolId: 'test.echo')]),
        instruction: 'Do the thing',
      );
      expect(outcome.succeeded, isTrue);
      expect(outcome.run.steps.single.attempts, 2);
      expect(journal.events.map((e) => e.kind), contains('step.retrying'));
    });
  });

  group('Orchestrator policy and failure honesty', () {
    test('plan approval denied → run cancelled, nothing executed', () async {
      final provider = FakeModelProvider([_normalizeJson, _planModelStep]);
      final orch =
          Orchestrator(provider: provider, registry: ToolRegistry());
      final outcome = await orch.run(
        project: _project,
        agent: _agent(approval: ApprovalLevel.all),
        instruction: 'Do the thing',
        approvalGate: (_) async => false,
      );
      expect(outcome.run.status, TaskStatus.cancelled);
      expect(outcome.run.steps.single.status, StepStatus.pending);
    });

    test('sensitive tool denied at the tool gate → run fails, tool never ran',
        () async {
      final tool = _FakeTool(sensitive: true);
      final provider =
          FakeModelProvider([_normalizeJson, _planToolStep, _verifyDone]);
      final orch = Orchestrator(
          provider: provider, registry: ToolRegistry([tool]));
      final outcome = await orch.run(
        project: _project,
        agent: _agent(
          approval: ApprovalLevel.sensitiveOnly,
          tools: [ToolBinding(toolId: 'test.echo')],
        ),
        instruction: 'Do the thing',
        // Approve the plan, deny the sensitive tool call itself.
        approvalGate: (req) async => req.kind == 'plan',
      );
      expect(outcome.run.status, TaskStatus.failed);
      expect(outcome.failureReason, contains('Approval denied'));
      expect(tool.calls, isEmpty);
    });

    test('a plan naming an undeclared tool fails at planning', () async {
      final tool = _FakeTool();
      final provider = FakeModelProvider([_normalizeJson, _planToolStep]);
      final orch = Orchestrator(
          provider: provider, registry: ToolRegistry([tool]));
      final outcome = await orch.run(
          project: _project, agent: _agent(), instruction: 'Do the thing');
      expect(outcome.run.status, TaskStatus.failed);
      expect(outcome.failureReason, contains('does not declare'));
    });

    test('model-call budget exhaustion fails the run, never silently', () async {
      final provider = FakeModelProvider([_normalizeJson, _planModelStep]);
      final orch = Orchestrator(
        provider: provider,
        registry: ToolRegistry(),
        budget: const ExecutionBudget(maxModelCalls: 1),
      );
      final outcome = await orch.run(
          project: _project, agent: _agent(), instruction: 'Do the thing');
      expect(outcome.run.status, TaskStatus.failed);
      expect(outcome.failureReason, contains('Budget exceeded'));
    });

    test('verification rejection fails the run with its summary', () async {
      final provider = FakeModelProvider([
        _normalizeJson,
        _planModelStep,
        'draft',
        '{"done": false, "summary": "Output is off-topic"}',
      ]);
      final orch =
          Orchestrator(provider: provider, registry: ToolRegistry());
      final outcome = await orch.run(
          project: _project, agent: _agent(), instruction: 'Do the thing');
      expect(outcome.run.status, TaskStatus.failed);
      expect(outcome.failureReason, contains('off-topic'));
    });

    test('cancellation between steps stops the run as cancelled', () async {
      final token = CancelToken()..cancel();
      final provider = FakeModelProvider([_normalizeJson, _planModelStep]);
      final orch =
          Orchestrator(provider: provider, registry: ToolRegistry());
      final outcome = await orch.run(
        project: _project,
        agent: _agent(),
        instruction: 'Do the thing',
        cancelToken: token,
      );
      expect(outcome.run.status, TaskStatus.cancelled);
    });

    test('malformed plan JSON fails planning, no steps fabricated', () async {
      final provider =
          FakeModelProvider([_normalizeJson, 'no json here at all']);
      final orch =
          Orchestrator(provider: provider, registry: ToolRegistry());
      final outcome = await orch.run(
          project: _project, agent: _agent(), instruction: 'Do the thing');
      expect(outcome.run.status, TaskStatus.failed);
      expect(outcome.run.steps, isEmpty);
    });
  });
}
