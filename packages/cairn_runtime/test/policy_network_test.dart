import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:test/test.dart';

class _NetTool extends Tool {
  @override
  String get id => 'net.probe';
  @override
  String get description => 'Network probe (test double).';
  @override
  bool get sensitive => false;
  @override
  bool get requiresNetwork => true;
  var ran = false;
  @override
  Future<ToolResult> run(
      Map<String, Object?> input, ToolContext context) async {
    ran = true;
    return ToolResult.success('probed');
  }
}

void main() {
  test('a network tool is refused when the agent policy forbids network',
      () async {
    final tool = _NetTool();
    final provider = FakeModelProvider([
      '{"goal": "Probe", "language": "en", "inputs": [], "constraints": []}',
      '{"steps": [{"description": "probe", "kind": "tool", "toolId": "net.probe", "input": {}}]}',
    ]);
    final orch =
        Orchestrator(provider: provider, registry: ToolRegistry([tool]));
    final agent = AgentBlueprint(
      name: 'a',
      model: ModelConfig(providerId: 'fake', modelId: 'm'),
      policy: const PolicyConfig(
          approvalLevel: ApprovalLevel.none, allowNetwork: false),
      tools: [ToolBinding(toolId: 'net.probe')],
    );
    final outcome = await orch.run(
        project: AgentProject(name: 'p'), agent: agent, instruction: 'Probe');
    expect(outcome.run.status, TaskStatus.failed);
    expect(outcome.failureReason, contains('policy forbids'));
    expect(tool.ran, isFalse);
  });
}
