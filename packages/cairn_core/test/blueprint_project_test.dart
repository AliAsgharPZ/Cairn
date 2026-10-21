import 'dart:convert';

import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

AgentBlueprint sampleAgent() => AgentBlueprint(
      name: 'پژوهشگر', // Persian name on purpose: round-trip must be lossless.
      description: 'Research assistant',
      systemPrompt: 'You are careful and cite sources.',
      model: ModelConfig(
        providerId: 'openai-compatible',
        modelId: 'test-model-1',
        temperature: 0.4,
        maxOutputTokens: 1024,
      ),
      tools: [ToolBinding(toolId: 'fs.read', config: {'root': '/data'})],
      skillIds: ['summarize@1.0.0'],
    );

void main() {
  group('AgentBlueprint', () {
    test('JSON round-trip preserves all fields', () {
      final agent = sampleAgent();
      final restored = AgentBlueprint.fromJson(
          (jsonDecode(jsonEncode(agent.toJson())) as Map)
              .cast<String, Object?>());
      expect(restored.id, agent.id);
      expect(restored.name, 'پژوهشگر');
      expect(restored.model.providerId, 'openai-compatible');
      expect(restored.model.temperature, 0.4);
      expect(restored.tools.single.toolId, 'fs.read');
      expect(restored.tools.single.config['root'], '/data');
      expect(restored.skillIds, ['summarize@1.0.0']);
    });

    test('a well-formed blueprint validates clean', () {
      expect(sampleAgent().validate(), isEmpty);
    });

    test('validate flags empty name, missing model and bad temperature', () {
      final bad = AgentBlueprint(
        name: '  ',
        model: ModelConfig(providerId: '', modelId: '', temperature: 3.5),
      );
      final issues = bad.validate();
      expect(issues, contains('agent name must not be empty'));
      expect(issues, contains('model.providerId is required'));
      expect(issues, contains('model.modelId is required'));
      expect(issues, contains('model.temperature must be within [0, 2]'));
    });

    test('fromJson without a model object throws FormatException', () {
      expect(
        () => AgentBlueprint.fromJson({'name': 'x'}),
        throwsFormatException,
      );
    });
  });

  group('AgentProject', () {
    test('upsert and remove agents; JSON round-trip', () {
      final project = AgentProject(name: 'Studio test');
      final a = sampleAgent();
      final b = AgentBlueprint(
        name: 'Second',
        model: ModelConfig(providerId: 'ollama', modelId: 'llama3.1'),
      );
      project.upsertAgent(a);
      project.upsertAgent(b);
      expect(project.agents, hasLength(2));
      expect(project.agentById(b.id)?.name, 'Second');

      // Upserting the same id replaces, not duplicates.
      b.name = 'Second v2';
      project.upsertAgent(b);
      expect(project.agents, hasLength(2));
      expect(project.agentById(b.id)?.name, 'Second v2');

      final restored = AgentProject.fromJson(
          (jsonDecode(jsonEncode(project.toJson())) as Map)
              .cast<String, Object?>());
      expect(restored.agents, hasLength(2));
      expect(restored.validate(), isEmpty);

      expect(project.removeAgent(a.id), isTrue);
      expect(project.removeAgent(a.id), isFalse);
      expect(project.agents, hasLength(1));
    });

    test('validate reports duplicate agent ids', () {
      final a = sampleAgent();
      final dupe = AgentBlueprint(
        id: a.id,
        name: 'Dupe',
        model: ModelConfig(providerId: 'ollama', modelId: 'm'),
      );
      final project = AgentProject(name: 'p', agents: [a, dupe]);
      expect(project.validate(), contains('duplicate agent id: ${a.id}'));
    });
  });
}
