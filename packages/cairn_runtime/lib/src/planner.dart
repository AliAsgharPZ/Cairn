import 'dart:convert';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';

import 'tool_registry.dart';

/// Turns a normalized instruction into a structured, validated plan.
///
/// The planner is a model stage with a strict JSON contract. Its output is
/// never trusted blindly: every step is validated (kind, tool references)
/// against the agent's blueprint and the device tool registry before the
/// orchestrator may execute it. A malformed plan is a [FormatException],
/// not a guess.
class Planner {
  Planner(this.provider);

  final ModelProvider provider;

  Future<List<TaskStep>> plan({
    required AgentBlueprint agent,
    required NormalizedInstruction instruction,
    required ToolRegistry registry,
    List<Skill> skills = const [],
  }) async {
    // Effective declared tools: the blueprint's own tools plus the tools
    // contributed by its attached skills (attaching a skill is the user's
    // explicit declaration of those tools).
    final declaredTools = <String>{
      for (final t in agent.tools) t.toolId,
      for (final s in skills) ...s.toolIds,
    };
    final agentToolIds = agent.tools.map((t) => t.toolId).toSet();
    final toolList = <String>[
      for (final t in agent.tools)
        '- ${t.toolId}: ${registry.lookup(t.toolId)?.description ?? '(unavailable on this device)'}',
      for (final s in skills)
        for (final id in s.toolIds)
          if (!agentToolIds.contains(id))
            '- $id: ${registry.lookup(id)?.description ?? '(unavailable on this device)'} (via skill "${s.name}")',
    ].join('\n');
    final skillInstructions = skills
        .where((s) => s.instructions.trim().isNotEmpty)
        .map((s) => '## Skill: ${s.name}\n${s.instructions}')
        .join('\n\n');

    final res = await provider.complete(
      agent.model,
      ModelRequest(messages: [
        ChatMessage(ChatRole.system, agent.systemPrompt),
        if (skillInstructions.isNotEmpty)
          ChatMessage(ChatRole.system,
              'The agent has these skills attached. Follow their instructions when relevant:\n$skillInstructions'),
        ChatMessage(
          ChatRole.system,
          'You are the planning stage of an agent runtime. Break the goal into '
          'an ordered list of steps. Respond with ONLY a JSON object, no '
          'markdown fences, shaped as: {"steps": [{"description": string, '
          '"kind": "model"|"tool", "toolId": string|null, "input": object}]}. '
          '"model" steps are performed by you (the model) directly; "tool" '
          'steps invoke one of the declared tools. Use only these tools:\n'
          '${toolList.isEmpty ? '(none)' : toolList}',
        ),
        ChatMessage(ChatRole.user,
            'Goal: ${instruction.goal}\nLanguage: ${instruction.language}'),
      ]),
    );

    final raw = res.text.trim();
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Planner did not return a JSON object');
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map) {
      throw const FormatException('Plan JSON is not an object');
    }
    final rawSteps = decoded['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      throw const FormatException('Plan has no steps');
    }
    final steps = <TaskStep>[];
    for (final rawStep in rawSteps) {
      if (rawStep is! Map) {
        throw const FormatException('Plan step is not an object');
      }
      final kind = rawStep['kind'] as String? ?? 'model';
      if (kind != 'model' && kind != 'tool') {
        throw FormatException('Unknown step kind: $kind');
      }
      final toolId = rawStep['toolId'] as String?;
      if (kind == 'tool') {
        if (toolId == null || !declaredTools.contains(toolId)) {
          throw FormatException(
              'Plan uses tool "$toolId" which the agent does not declare');
        }
        if (!registry.contains(toolId)) {
          throw FormatException(
              'Plan uses tool "$toolId" which is not available on this device');
        }
      }
      steps.add(TaskStep(
        description: rawStep['description'] as String? ?? '',
        kind: kind,
        toolId: kind == 'tool' ? toolId : null,
        input: (rawStep['input'] as Map?)?.cast<String, Object?>() ?? const {},
      ));
    }
    return steps;
  }
}
