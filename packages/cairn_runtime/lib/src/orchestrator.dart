import 'dart:convert';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';

import 'planner.dart';
import 'tool_registry.dart';

/// What the user is being asked to approve: a whole plan, or one tool call.
class ApprovalRequest {
  const ApprovalRequest({
    required this.taskId,
    required this.agentId,
    required this.kind,
    required this.description,
    this.toolId,
  });

  final String taskId;
  final String agentId;

  /// 'plan' | 'tool'
  final String kind;
  final String description;
  final String? toolId;
}

/// The UI (or a test) answers approval requests through this gate.
/// Returning false denies. A missing gate denies by default whenever the
/// agent's policy requires approval — headless runs never self-approve.
typedef ApprovalGate = Future<bool> Function(ApprovalRequest request);

/// Cooperative cancellation, checked between steps and before model calls.
class CancelToken {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;
}

/// The result of one orchestrated run.
class RunOutcome {
  const RunOutcome({
    required this.run,
    this.summary,
    this.failureReason,
    this.stepOutputs = const {},
  });

  final TaskRun run;

  /// The verification summary when the run completed.
  final String? summary;

  /// Why the run failed/was cancelled, when it did.
  final String? failureReason;

  /// Step id → textual output, for the console and for step chaining.
  final Map<String, String> stepOutputs;

  bool get succeeded => run.status == TaskStatus.completed;
}

/// Executes one agent on one instruction, end to end:
///
/// created → analyzing (normalize) → [awaitingApproval] → ready → running
/// (steps, with budgets, per-tool policy and bounded retries) → verifying
/// → completed | failed | cancelled.
///
/// Every transition and step outcome is journaled. Nothing here fabricates
/// success: a step counts only when its executor really returned success,
/// and the run completes only when the verification stage confirms the goal.
class Orchestrator {
  Orchestrator({
    required this.provider,
    required this.registry,
    Journal? journal,
    this.budget = const ExecutionBudget(),
    this.skillRegistry,
  }) : journal = journal ?? Journal();

  final ModelProvider provider;
  final ToolRegistry registry;
  final Journal journal;
  final ExecutionBudget budget;

  /// Skills available to agents on this device (blueprints reference them
  /// by id). An agent referencing an unknown skill fails loudly at run
  /// start rather than silently losing the skill.
  final SkillRegistry? skillRegistry;

  late final LanguagePipeline _pipeline = LanguagePipeline(provider);
  late final Planner _planner = Planner(provider);

  void _transition(TaskRun run, TaskStatus to) {
    final from = run.status;
    run.stateMachine.transition(to);
    journal.append('task.transition',
        taskId: run.id, data: {'from': from.name, 'to': to.name});
  }

  RunOutcome _fail(TaskRun run, String reason,
      {Map<String, String> outputs = const {}}) {
    journal.append('task.failed', taskId: run.id, data: {'reason': reason});
    return RunOutcome(run: run, failureReason: reason, stepOutputs: outputs);
  }

  Future<RunOutcome> run({
    required AgentProject project,
    required AgentBlueprint agent,
    required String instruction,
    ApprovalGate? approvalGate,
    CancelToken? cancelToken,
    String? workingDirectory,
  }) async {
    final tracker = BudgetTracker(budget);
    final task = TaskRun(
      projectId: project.id,
      agentId: agent.id,
      instruction: instruction,
    );
    journal.append('task.created',
        taskId: task.id, data: {'agentId': agent.id, 'instruction': instruction});
    // Flow-1 roles, resolved once: each stage runs on its own model
    // when the blueprint names one, else on the main model. Journaled
    // so the console shows exactly which model did what.
    final translatorModel = agent.translatorModel ?? agent.model;
    final verifierModel = agent.verifierModel ?? agent.model;
    journal.append('task.roles', taskId: task.id, data: {
      'main': '${agent.model.providerId}/${agent.model.modelId}',
      'translator': '${translatorModel.providerId}/${translatorModel.modelId}',
      'verifier': '${verifierModel.providerId}/${verifierModel.modelId}',
    });

    // ── Analyzing: normalize the instruction ──────────────────────────────
    _transition(task, TaskStatus.analyzing);
    final NormalizedInstruction normalized;
    try {
      tracker.consumeModelCall();
      normalized = await _pipeline.normalize(translatorModel, instruction);
    } on BudgetExceededException catch (e) {
      _transition(task, TaskStatus.failed);
      return _fail(task, 'Budget exceeded during analysis: ${e.kind}');
    } catch (e) {
      _transition(task, TaskStatus.failed);
      return _fail(task, 'Normalization failed: $e');
    }
    journal.append('task.normalized',
        taskId: task.id, data: normalized.toJson());

    // ── Planning ───────────────────────────────────────────────────────────
    // Resolve the agent's skills first: an unknown skill id fails the run
    // loudly instead of silently dropping the skill.
    final List<Skill> skills;
    try {
      skills = agent.skillIds.isEmpty
          ? const []
          : (skillRegistry ??
                  (throw const FormatException(
                      'agent references skills but no SkillRegistry is configured')))
              .requireAll(agent.skillIds);
    } on FormatException catch (e) {
      _transition(task, TaskStatus.failed);
      return _fail(task, 'Skill resolution failed: ${e.message}');
    }
    final allowedToolIds = <String>{
      for (final t in agent.tools) t.toolId,
      for (final s in skills) ...s.toolIds,
    };
    final List<TaskStep> steps;
    try {
      tracker.consumeModelCall();
      steps = await _planner.plan(
          agent: agent,
          instruction: normalized,
          registry: registry,
          skills: skills);
    } on BudgetExceededException catch (e) {
      _transition(task, TaskStatus.failed);
      return _fail(task, 'Budget exceeded during planning: ${e.kind}');
    } catch (e) {
      _transition(task, TaskStatus.failed);
      return _fail(task, 'Planning failed: $e');
    }
    task.steps.addAll(steps);
    journal.append('task.planned',
        taskId: task.id, data: {'steps': steps.length});

    // ── Plan approval (policy) ─────────────────────────────────────────────
    final needsApproval = switch (agent.policy.approvalLevel) {
      ApprovalLevel.all => true,
      ApprovalLevel.none => false,
      ApprovalLevel.sensitiveOnly => steps.any((s) =>
          s.kind == 'tool' &&
          (registry.lookup(s.toolId!)?.sensitive ?? false)),
    };
    if (needsApproval) {
      _transition(task, TaskStatus.awaitingApproval);
      journal.append('approval.requested',
          taskId: task.id, data: {'kind': 'plan'});
      final approved = approvalGate != null &&
          await approvalGate(ApprovalRequest(
            taskId: task.id,
            agentId: agent.id,
            kind: 'plan',
            description: normalized.goal,
          ));
      journal.append(approved ? 'approval.granted' : 'approval.denied',
          taskId: task.id, data: {'kind': 'plan'});
      if (!approved) {
        _transition(task, TaskStatus.cancelled);
        return RunOutcome(
            run: task, failureReason: 'Plan approval denied or unavailable');
      }
    }
    _transition(task, TaskStatus.ready);

    // ── Running: execute the steps ─────────────────────────────────────────
    _transition(task, TaskStatus.running);
    final outputs = <String, String>{};
    final context = ToolContext(
      projectId: project.id,
      agentId: agent.id,
      taskId: task.id,
      workingDirectory: workingDirectory,
    );

    for (final step in task.steps) {
      if (cancelToken?.isCancelled ?? false) {
        _transition(task, TaskStatus.cancelled);
        journal.append('task.cancelled',
            taskId: task.id, data: {'reason': 'cancelled by user'});
        return RunOutcome(
            run: task,
            failureReason: 'Cancelled by user',
            stepOutputs: outputs);
      }
      try {
        tracker.checkClock();
        tracker.consumeStep();
      } on BudgetExceededException catch (e) {
        step.status = StepStatus.skipped;
        _transition(task, TaskStatus.failed);
        return _fail(task, 'Budget exceeded: ${e.kind} (limit ${e.limit})',
            outputs: outputs);
      }

      final stepError = await _executeStep(
        task: task,
        step: step,
        agent: agent,
        tracker: tracker,
        approvalGate: approvalGate,
        context: context,
        outputs: outputs,
        allowedToolIds: allowedToolIds,
      );
      if (stepError != null) {
        _transition(task, TaskStatus.failed);
        return _fail(task, stepError, outputs: outputs);
      }
    }

    // ── Verifying ──────────────────────────────────────────────────────────
    _transition(task, TaskStatus.verifying);
    try {
      tracker.consumeModelCall();
      final res = await provider.complete(
        verifierModel,
        ModelRequest(messages: [
          ChatMessage(ChatRole.system, agent.systemPrompt),
          const ChatMessage(ChatRole.system,
              'You are the verification stage of an agent runtime. Given the '
              'goal and the step outputs, decide whether the goal is fully '
              'achieved. Respond with ONLY a JSON object: '
              '{"done": boolean, "summary": string}.'),
          ChatMessage(ChatRole.user,
              'Goal: ${normalized.goal}\n\nStep outputs:\n'
              '${outputs.entries.map((e) => '- ${e.value}').join('\n')}'),
        ]),
      );
      final raw = res.text.trim();
      final decoded =
          jsonDecode(raw.substring(raw.indexOf('{'), raw.lastIndexOf('}') + 1));
      if (decoded is! Map) {
        throw const FormatException('Verification JSON is not an object');
      }
      final done = decoded['done'] as bool? ?? false;
      final summary = decoded['summary'] as String? ?? '';
      if (!done) {
        _transition(task, TaskStatus.failed);
        return _fail(task, 'Verification rejected the result: $summary',
            outputs: outputs);
      }
      _transition(task, TaskStatus.completed);
      journal.append('task.completed',
          taskId: task.id, data: {'summary': summary});
      return RunOutcome(run: task, summary: summary, stepOutputs: outputs);
    } catch (e) {
      _transition(task, TaskStatus.failed);
      return _fail(task, 'Verification failed: $e', outputs: outputs);
    }
  }

  /// Executes one step with bounded retries. Returns null on success, or the
  /// failure reason. Retrying passes through the retrying state so observers
  /// see exactly what the runtime is doing.
  Future<String?> _executeStep({
    required TaskRun task,
    required TaskStep step,
    required AgentBlueprint agent,
    required BudgetTracker tracker,
    required ApprovalGate? approvalGate,
    required ToolContext context,
    required Map<String, String> outputs,
    required Set<String> allowedToolIds,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      step.attempts = attempt;
      step.status = StepStatus.running;
      final key = idempotencyKey(task.id, step.id, attempt);
      journal.append('step.started', taskId: task.id, data: {
        'stepId': step.id,
        'kind': step.kind,
        if (step.toolId != null) 'toolId': step.toolId,
        'attempt': attempt,
        'idempotencyKey': key,
      });
      try {
        final output = await _executeStepOnce(
          task: task,
          step: step,
          agent: agent,
          tracker: tracker,
          approvalGate: approvalGate,
          context: context,
          outputs: outputs,
          allowedToolIds: allowedToolIds,
        );
        step.status = StepStatus.succeeded;
        outputs[step.id] = output;
        journal.append('step.succeeded',
            taskId: task.id, data: {'stepId': step.id, 'attempt': attempt});
        return null;
      } catch (e) {
        step.lastError = '$e';
        journal.append('step.failed', taskId: task.id, data: {
          'stepId': step.id,
          'attempt': attempt,
          'error': '$e',
        });
        if (e is _ApprovalDenied) return 'Approval denied: $e';
        if (e is BudgetExceededException) {
          step.status = StepStatus.failed;
          return 'Budget exceeded: ${e.kind} (limit ${e.limit})';
        }
        if (attempt > budget.maxRetriesPerStep) {
          step.status = StepStatus.failed;
          return 'Step "${step.description}" failed after $attempt attempt(s): $e';
        }
        _transition(task, TaskStatus.retrying);
        journal.append('step.retrying',
            taskId: task.id, data: {'stepId': step.id, 'nextAttempt': attempt + 1});
        _transition(task, TaskStatus.running);
      }
    }
  }

  Future<String> _executeStepOnce({
    required TaskRun task,
    required TaskStep step,
    required AgentBlueprint agent,
    required BudgetTracker tracker,
    required ApprovalGate? approvalGate,
    required ToolContext context,
    required Map<String, String> outputs,
    required Set<String> allowedToolIds,
  }) async {
    if (step.kind == 'tool') {
      final tool = registry.lookup(step.toolId!);
      if (tool == null) {
        throw StateError('Tool "${step.toolId}" is not available on this device');
      }
      if (!allowedToolIds.contains(tool.id)) {
        throw StateError(
            'Tool "${tool.id}" is not declared by this agent or its skills');
      }
      if (tool.requiresNetwork && !agent.policy.allowNetwork) {
        throw StateError(
            'Tool "${tool.id}" needs network access, which this agent\'s policy forbids');
      }
      if (tool.sensitive && agent.policy.approvalLevel != ApprovalLevel.none) {
        journal.append('approval.requested',
            taskId: task.id, data: {'kind': 'tool', 'toolId': tool.id});
        final approved = approvalGate != null &&
            await approvalGate(ApprovalRequest(
              taskId: task.id,
              agentId: agent.id,
              kind: 'tool',
              description: step.description,
              toolId: tool.id,
            ));
        journal.append(approved ? 'approval.granted' : 'approval.denied',
            taskId: task.id, data: {'kind': 'tool', 'toolId': tool.id});
        if (!approved) throw _ApprovalDenied('tool ${tool.id}');
      }
      tracker.consumeToolCall();
      final result = await tool.run(step.input, context);
      if (!result.ok) {
        throw StateError('Tool ${tool.id} failed: ${result.output}');
      }
      return result.output;
    }

    // Model step: the model performs the step, seeing prior outputs.
    tracker.consumeModelCall();
    final prior = outputs.isEmpty
        ? ''
        : '\n\nResults of previous steps:\n${outputs.values.map((v) => '- $v').join('\n')}';
    final res = await provider.complete(
      agent.model,
      ModelRequest(messages: [
        ChatMessage(ChatRole.system, agent.systemPrompt),
        ChatMessage(ChatRole.user, '${step.description}$prior'),
      ]),
    );
    return res.text;
  }
}

class _ApprovalDenied implements Exception {
  _ApprovalDenied(this.what);
  final String what;
  @override
  String toString() => 'approval denied for $what';
}
