import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

void main() {
  test('role models round-trip through JSON and stay optional', () {
    final agent = AgentBlueprint(
      name: 'a',
      model: ModelConfig(providerId: 'ollama', modelId: 'llama3.1'),
      translatorModel:
          ModelConfig(providerId: 'ollama', modelId: 'gemma3'),
      verifierModel:
          ModelConfig(providerId: 'openai-compatible', modelId: 'gpt-x'),
    );
    final back = AgentBlueprint.fromJson(agent.toJson());
    expect(back.model.modelId, 'llama3.1');
    expect(back.translatorModel?.modelId, 'gemma3');
    expect(back.verifierModel?.providerId, 'openai-compatible');
    expect(back.validate(), isEmpty);

    final plain = AgentBlueprint(
      name: 'b',
      model: ModelConfig(providerId: 'ollama', modelId: 'llama3.1'),
    );
    final plainBack = AgentBlueprint.fromJson(plain.toJson());
    expect(plainBack.translatorModel, isNull);
    expect(plainBack.verifierModel, isNull);
    expect(plainBack.validate(), isEmpty);
  });

  test('an incomplete role model fails validation loudly', () {
    final agent = AgentBlueprint(
      name: 'a',
      model: ModelConfig(providerId: 'ollama', modelId: 'llama3.1'),
      translatorModel: ModelConfig(providerId: 'ollama', modelId: ''),
    );
    expect(agent.validate(),
        contains('translatorModel.modelId is required'));
  });
}
