import 'dart:async';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import 'provider_factory.dart';
import 'provider_settings.dart';

/// The live test console: run an agent of the selected project on an
/// instruction and watch the orchestrator work — state transitions, plan,
/// step executions, approvals and the verification verdict — streamed from
/// the run's real journal. Approvals are answered with a dialog; nothing
/// here simulates a run.
class TestConsoleScreen extends StatefulWidget {
  const TestConsoleScreen({
    super.key,
    required this.project,
    required this.registry,
    required this.providerConfigs,
    required this.keyStore,
    this.onOpenSettings,
  });

  final AgentProject? project;
  final ToolRegistry registry;
  final List<ProviderConfig> providerConfigs;
  final ApiKeyStore keyStore;
  final VoidCallback? onOpenSettings;

  @override
  State<TestConsoleScreen> createState() => _TestConsoleScreenState();
}

class _TestConsoleScreenState extends State<TestConsoleScreen> {
  final _instruction = TextEditingController();
  String? _agentId;
  bool _running = false;
  Journal? _journal;
  int _journalSeen = 0;
  RunOutcome? _outcome;
  String? _configError;
  CancelToken? _cancelToken;
  Timer? _poller;

  @override
  void dispose() {
    _instruction.dispose();
    _poller?.cancel();
    super.dispose();
  }

  AgentBlueprint? get _agent {
    final project = widget.project;
    if (project == null || project.agents.isEmpty) return null;
    return project.agentById(_agentId ?? '') ?? project.agents.first;
  }

  ProviderConfig? _configFor(AgentBlueprint agent) {
    for (final c in widget.providerConfigs) {
      if (c.providerId == agent.model.providerId) return c;
    }
    // Ollama has a sane local default; API providers must be configured
    // explicitly (they need a key), so there is no silent fallback for them.
    if (agent.model.providerId == 'ollama') {
      return const ProviderConfig(providerId: 'ollama');
    }
    return null;
  }

  Future<bool> _approvalGate(ApprovalRequest request) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(request.kind == 'plan'
            ? 'تأیید اجرای پلن'
            : 'تأیید فراخوانی ابزار'),
        content: Text(
          request.kind == 'plan'
              ? 'ایجنت می‌خواهد این هدف را اجرا کند:\n\n${request.description}'
              : 'ابزار «${request.toolId}» برای این گام لازم است:\n\n${request.description}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رد'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _run() async {
    final project = widget.project;
    final agent = _agent;
    if (project == null || agent == null) return;
    final instruction = _instruction.text.trim();
    if (instruction.isEmpty) {
      setState(() => _configError = 'اول یک دستور بنویس');
      return;
    }
    final config = _configFor(agent);
    if (config == null) {
      setState(() => _configError =
          'ارائه‌دهندهٔ «${agent.model.providerId}» پیکربندی نشده است. از بخش تنظیمات اضافه‌اش کن.');
      return;
    }
    final journal = Journal();
    final token = CancelToken();
    setState(() {
      _running = true;
      _journal = journal;
      _journalSeen = 0;
      _outcome = null;
      _configError = null;
      _cancelToken = token;
    });
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && _journal != null && _journal!.length != _journalSeen) {
        setState(() => _journalSeen = _journal!.length);
      }
    });

    final orchestrator = Orchestrator(
      provider: buildProvider(config, widget.keyStore),
      registry: widget.registry,
      journal: journal,
    );
    try {
      final outcome = await orchestrator.run(
        project: project,
        agent: agent,
        instruction: instruction,
        approvalGate: _approvalGate,
        cancelToken: token,
      );
      if (mounted) setState(() => _outcome = outcome);
    } catch (e) {
      if (mounted) {
        setState(() => _configError = 'خطای غیرمنتظره: $e');
      }
    } finally {
      _poller?.cancel();
      if (mounted) {
        setState(() {
          _running = false;
          _journalSeen = _journal?.length ?? 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = widget.project;
    if (project == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(CairnSpacing.xxl),
          child: Text('اول از بخش «پروژه‌ها» یک پروژه را باز کن.'),
        ),
      );
    }
    if (project.agents.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(CairnSpacing.xxl),
          child: Text('این پروژه هنوز ایجنتی ندارد؛ از «ویرایشگر ایجنت» یکی بساز.'),
        ),
      );
    }
    final agent = _agent!;
    final events = _journal?.events ?? const <JournalEvent>[];

    return Padding(
      padding: const EdgeInsets.all(CairnSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('کنسول تست', style: theme.textTheme.headlineMedium),
              const SizedBox(width: CairnSpacing.md),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: agent.id,
                  decoration: const InputDecoration(labelText: 'ایجنت'),
                  items: [
                    for (final a in project.agents)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _agentId = v),
                ),
              ),
            ],
          ),
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: CairnSpacing.xs),
            color: CairnColors.accentGold,
          ),
          const SizedBox(height: CairnSpacing.md),
          Text(
            'مدل: ${agent.model.providerId} / ${agent.model.modelId}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: CairnSpacing.sm),
          TextField(
            controller: _instruction,
            minLines: 2,
            maxLines: 4,
            enabled: !_running,
            decoration: const InputDecoration(
              labelText: 'دستور برای ایجنت',
              hintText: 'مثلاً: ساعت الان رو بگو و بعد ۱۲ × ۸ رو حساب کن',
            ),
          ),
          const SizedBox(height: CairnSpacing.sm),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: const Icon(Icons.play_arrow),
                label: const Text('اجرا'),
              ),
              const SizedBox(width: CairnSpacing.sm),
              if (_running)
                OutlinedButton.icon(
                  onPressed: () => _cancelToken?.cancel(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('لغو اجرا'),
                ),
              if (_configError != null) ...[
                const SizedBox(width: CairnSpacing.md),
                Expanded(
                  child: Text(_configError!,
                      style: const TextStyle(color: CairnColors.error)),
                ),
                if (_configError!.contains('پیکربندی نشده'))
                  TextButton(
                    onPressed: widget.onOpenSettings,
                    child: const Text('رفتن به تنظیمات'),
                  ),
              ],
            ],
          ),
          const SizedBox(height: CairnSpacing.md),
          if (_outcome != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CairnSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(CairnRadii.md),
              ),
              child: Text(
                _outcome!.succeeded
                    ? '✅ تکمیل شد — ${_outcome!.summary ?? ''}'
                    : '⛔ ${_outcome!.run.status.name} — ${_outcome!.failureReason ?? ''}',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          const SizedBox(height: CairnSpacing.sm),
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Text(
                      _running
                          ? 'در حال اجرا…'
                          : 'رویدادهای اجرا (پلن، گام‌ها، تأییدها) اینجا زنده نمایش داده می‌شوند.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final e = events[events.length - 1 - i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '#${e.seq} ${e.kind}  ${_summarize(e.data)}',
                          style: TextStyle(
                            fontFamily: CairnFonts.latin,
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _summarize(Map<String, Object?> data) {
    if (data.isEmpty) return '';
    final parts = <String>[];
    for (final entry in data.entries) {
      var v = '${entry.value}';
      if (v.length > 90) v = '${v.substring(0, 90)}…';
      parts.add('${entry.key}=$v');
    }
    return parts.join(' · ');
  }
}
