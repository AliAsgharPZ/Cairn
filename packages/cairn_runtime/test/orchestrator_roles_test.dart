import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:test/test.dart';

class _EchoTool extends Tool {
  @override
  String get id => 'test.echo';
  @override
  String get description => 'Echoes its input text back.';
  @override
  bool get sensitive => false;
  @override
  Future<ToolResult> run(
          Map<String, Object?> input, ToolContext context) async =>
      ToolResult.success('echo: ${input['text']}');
}

const _normalizeJson =
    '{"goal": "Do the thing", "language": "en", "inputs": [], "constraints": []}';
const _planToolStep =
    '{"steps": [{"description": "Echo hello", "kind": "tool", '
    '"toolId": "test.echo", "input": {"text": "hello"}}]}';
const _verifyDone = '{"done": true, "summary": "Goal achieved"}';

void main() {
  test('each Flow-1 stage runs on its own role model', () async {
    final provider = FakeModelProvider([_normalizeJson, _planToolStep, _verifyDone]);
    final orch = Orchestrator(
        provider: provider, registry: ToolRegistry([_EchoTool()]));
    final agent = AgentBlueprint(
      name: 'roles-agent',
      model: ModelConfig(providerId: 'fake', modelId: 'main-brain'),
      translatorModel:
          ModelConfig(providerId: 'ollama', modelId: 'gemma-translate'),
      verifierModel: ModelConfig(providerId: 'fake', modelId: 'checker'),
      policy: const PolicyConfig(approvalLevel: ApprovalLevel.none),
      tools: [ToolBinding(toolId: 'test.echo')],
    );
    final outcome = await orch.run(
        project: AgentProject(name: 'p'),
        agent: agent,
        instruction: 'Do the thing');
    expect(outcome.succeeded, isTrue);
    // Call order: normalize (translator) → plan (main) → verify (verifier).
    expect(provider.configs.map((c) => c.modelId).toList(),
        ['gemma-translate', 'main-brain', 'checker']);
    expect(provider.configs.first.providerId, 'ollama');
  });

  test('without role models every stage falls back to the main model',
      () async {
    final provider = FakeModelProvider([_normalizeJson, _planToolStep, _verifyDone]);
    final orch = Orchestrator(
        provider: provider, registry: ToolRegistry([_EchoTool()]));
    final agent = AgentBlueprint(
      name: 'plain-agent',
      model: ModelConfig(providerId: 'fake', modelId: 'only-model'),
      policy: const PolicyConfig(approvalLevel: ApprovalLevel.none),
      tools: [ToolBinding(toolId: 'test.echo')],
    );
    final outcome = await orch.run(
        project: AgentProject(name: 'p'),
        agent: agent,
        instruction: 'Do the thing');
    expect(outcome.succeeded, isTrue);
    expect(provider.configs.map((c) => c.modelId).toSet(), {'only-model'});
  });
}
