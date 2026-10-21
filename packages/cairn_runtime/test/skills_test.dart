import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:test/test.dart';

class _EchoTool extends Tool {
  @override
  String get id => 'skill.echo';
  @override
  String get description => 'Echoes its input (test tool).';
  @override
  bool get sensitive => false;
  var calls = 0;
  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    calls++;
    return ToolResult.success('echo: ${input['text']}');
  }
}

const _normalizeJson =
    '{"goal": "Echo politely", "language": "en", "inputs": [], "constraints": []}';
const _planEchoStep =
    '{"steps": [{"description": "echo", "kind": "tool", "toolId": "skill.echo", "input": {"text": "hi"}}]}';
const _verifyDone = '{"done": true, "summary": "Goal achieved"}';

void main() {
  final skill = Skill(
    id: 'skill-echo',
    name: 'Echo Skill',
    instructions: 'Always echo politely.',
    toolIds: ['skill.echo'],
  );

  AgentBlueprint agent({List<String> skillIds = const []}) => AgentBlueprint(
        name: 'a',
        model: ModelConfig(providerId: 'fake', modelId: 'm'),
        policy: const PolicyConfig(
            approvalLevel: ApprovalLevel.none, allowNetwork: true),
        skillIds: skillIds,
      );

  test('a skill grants its tools and instructions to the agent', () async {
    final tool = _EchoTool();
    final provider =
        FakeModelProvider([_normalizeJson, _planEchoStep, _verifyDone]);
    final orch = Orchestrator(
      provider: provider,
      registry: ToolRegistry([tool]),
      skillRegistry: SkillRegistry([skill]),
    );
    final outcome = await orch.run(
      project: AgentProject(name: 'p'),
      agent: agent(skillIds: ['skill-echo']),
      instruction: 'Echo politely',
    );
    expect(outcome.succeeded, isTrue);
    expect(tool.calls, 1);
    // The skill's instructions must have reached the planning stage:
    final planRequest = provider.requests[1];
    final allText =
        planRequest.messages.map((m) => m.content).join('\n');
    expect(allText, contains('Always echo politely.'));
    expect(allText, contains('skill.echo'));
  });

  test('without the skill, the same plan is rejected as undeclared',
      () async {
    final tool = _EchoTool();
    final provider =
        FakeModelProvider([_normalizeJson, _planEchoStep, _verifyDone]);
    final orch = Orchestrator(
      provider: provider,
      registry: ToolRegistry([tool]),
      skillRegistry: SkillRegistry([skill]),
    );
    final outcome = await orch.run(
      project: AgentProject(name: 'p'),
      agent: agent(), // no skills attached
      instruction: 'Echo politely',
    );
    expect(outcome.run.status, TaskStatus.failed);
    expect(outcome.failureReason, contains('Planning failed'));
    expect(tool.calls, 0);
  });

  test('an unknown skill id fails the run loudly', () async {
    final provider =
        FakeModelProvider([_normalizeJson, _planEchoStep, _verifyDone]);
    final orch = Orchestrator(
      provider: provider,
      registry: ToolRegistry([_EchoTool()]),
      skillRegistry: SkillRegistry([skill]),
    );
    final outcome = await orch.run(
      project: AgentProject(name: 'p'),
      agent: agent(skillIds: ['no-such-skill']),
      instruction: 'Echo politely',
    );
    expect(outcome.run.status, TaskStatus.failed);
    expect(outcome.failureReason, contains('Skill resolution failed'));
    expect(outcome.failureReason, contains('no-such-skill'));
  });
}
