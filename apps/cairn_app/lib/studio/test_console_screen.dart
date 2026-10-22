import 'dart:async';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_sync/cairn_sync.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:flutter/material.dart';

import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'device_identity.dart';
import 'pipeline_runner.dart';
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
    this.skillRegistry,
    this.modelRegistry,
    this.seedStore,
    this.baseDir,
  });

  final AgentProject? project;
  final ToolRegistry registry;
  final List<ProviderConfig> providerConfigs;
  final ApiKeyStore keyStore;
  final VoidCallback? onOpenSettings;

  /// Installed skills, handed to the orchestrator so agents can use the
  /// skills they reference (unknown ids fail the run loudly).
  final SkillRegistry? skillRegistry;

  /// Registry of locally trained models (for 'local-trained' provider
  /// configs); null disables that adapter in this context.
  final ModelRegistryStore? modelRegistry;

  /// Identity + storage for multi-device load balancing (paired
  /// devices, declared specs). Null disables balancing in this
  /// context; the plain local registry is used instead.
  final SeedStore? seedStore;
  final Directory? baseDir;

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
  bool _providerError = false;
  CancelToken? _cancelToken;
  Timer? _poller;

  /// Multi-directional load balancing for this run's tool steps.
  bool _balance = true;
  String? _balanceNote;

  // Chain mode (v1.2): run the project's whole pipeline.
  bool _chainMode = false;
  final _chainInput = TextEditingController();
  bool _chainRunning = false;
  ChainResult? _chainResult;
  String? _chainError;

  ProviderConfig? _configForProviderId(String providerId) {
    for (final c in widget.providerConfigs) {
      if (c.providerId == providerId) return c;
    }
    if (providerId == 'ollama') {
      return const ProviderConfig(providerId: 'ollama');
    }
    return null;
  }

  ModelProvider? _chainProviderFor(AgentBlueprint agent,
      {ModelConfig? override}) {
    final config = _configForProviderId((override ?? agent.model).providerId);
    if (config == null) return null;
    return buildProvider(config, widget.keyStore,
        modelRegistry: widget.modelRegistry);
  }

  Future<void> _runChain() async {
    final project = widget.project;
    final baseDir = widget.baseDir;
    if (project == null || baseDir == null) return;
    final input = _chainInput.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _chainRunning = true;
      _chainResult = null;
      _chainError = null;
    });
    try {
      final runner = PipelineRunner(
        smartStore: SmartModelStore(Directory('${baseDir.path}/models')),
        providerFor: _chainProviderFor,
        registry: widget.registry,
        skillRegistry: widget.skillRegistry ?? SkillRegistry(const []),
      );
      final result = await runner.run(
        project: project,
        input: input,
        approvalGate: _approvalGate,
      );
      if (mounted) setState(() => _chainResult = result);
    } catch (e) {
      if (mounted) setState(() => _chainError = '$e');
    }
    if (mounted) setState(() => _chainRunning = false);
  }

  List<Widget> _chainWidgets(ThemeData theme, S s) {
    final result = _chainResult;
    return [
      TextField(
        controller: _chainInput,
        minLines: 2,
        maxLines: 4,
        enabled: !_chainRunning,
        decoration: InputDecoration(
          labelText: s.runChain,
          hintText: s.chainInputHint,
        ),
      ),
      const SizedBox(height: CairnSpacing.sm),
      Row(
        children: [
          FilledButton.icon(
            onPressed: _chainRunning ? null : _runChain,
            icon: const Icon(Icons.play_arrow),
            label: Text(s.chainRunButton),
          ),
          if (_chainRunning) ...[
            const SizedBox(width: CairnSpacing.md),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          if (_chainError != null) ...[
            const SizedBox(width: CairnSpacing.md),
            Expanded(
              child: Text(_chainError!,
                  style: const TextStyle(color: CairnColors.error)),
            ),
          ],
        ],
      ),
      const SizedBox(height: CairnSpacing.md),
      Expanded(
        child: result == null
            ? Center(
                child: Text(s.chainHelp,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center),
              )
            : ListView(
                children: [
                  for (final t in result.traces)
                    if (!t.skipped || t.note != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(CairnSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.stepTitle(t.kind),
                                  style: theme.textTheme.titleSmall),
                              if (t.output.isNotEmpty) ...[
                                const SizedBox(height: CairnSpacing.xs),
                                Text(t.output),
                              ],
                              if (t.note != null) ...[
                                const SizedBox(height: CairnSpacing.xs),
                                Text(t.note!,
                                    style: theme.textTheme.bodySmall),
                              ],
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: CairnSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(CairnSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(CairnRadii.md),
                    ),
                    child: Text(result.finalText,
                        style: theme.textTheme.bodyLarge),
                  ),
                ],
              ),
      ),
    ];
  }

  @override
  void dispose() {
    _instruction.dispose();
    _chainInput.dispose();
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
    final s = S.of(context);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(request.kind == 'plan'
            ? s.cApprovePlan
            : s.cApproveTool),
        content: Text(
          request.kind == 'plan'
              ? s.cPlanBody(request.description)
              : s.cToolBody(request.toolId, request.description),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cReject),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.cApprove),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _run() async {
    final s = S.of(context);
    final project = widget.project;
    final agent = _agent;
    if (project == null || agent == null) return;
    final instruction = _instruction.text.trim();
    if (instruction.isEmpty) {
      setState(() => _configError = s.cWriteInstructionFirst);
      return;
    }
    final config = _configFor(agent);
    if (config == null) {
      setState(() {
        _providerError = true;
        _configError = s.cProviderNotConfigured(agent.model.providerId);
      });
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
      _providerError = false;
      _cancelToken = token;
    });
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && _journal != null && _journal!.length != _journalSeen) {
        setState(() => _journalSeen = _journal!.length);
      }
    });

    final balanced = await _prepareBalancedRegistry();
    if (mounted) setState(() => _balanceNote = balanced?.note);

    final orchestrator = Orchestrator(
      provider: buildProvider(config, widget.keyStore,
          modelRegistry: widget.modelRegistry),
      registry: balanced?.registry ?? widget.registry,
      journal: journal,
      skillRegistry: widget.skillRegistry,
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
        setState(() => _configError = s.cUnexpectedError('$e'));
      }
    } finally {
      if (balanced != null) {
        for (final client in balanced.clients) {
          await client.close();
        }
      }
      _poller?.cancel();
      if (mounted) {
        setState(() {
          _running = false;
          _journalSeen = _journal?.length ?? 0;
        });
      }
    }
  }

  /// Builds the run's effective tool registry with multi-directional
  /// load balancing: every tool that a reachable paired peer also
  /// offers is wrapped so each call is placed by the LoadBalancer —
  /// any device may serve any other, steps split across the capable
  /// devices, local network first and internet last. Returns null
  /// when balancing is off or no peer is reachable; the plain local
  /// registry then runs the agent, unchanged.
  String _balanceNoteFor(int n) => S.of(context).cBalanceNote(n);

  Future<({ToolRegistry registry, List<OverflowClient> clients, String note})?>
      _prepareBalancedRegistry() async {
    if (!_balance || widget.seedStore == null || widget.baseDir == null) {
      return null;
    }
    final identity =
        await DeviceIdentityService(widget.seedStore!).loadOrCreate();
    final paired = await PairedDevicesStore(widget.baseDir!).list();
    if (paired.isEmpty) return null;
    final specs = await DeviceSpecsStore(widget.baseDir!).load();
    final localCaps = DeviceCapabilities(
      deviceId: identity.deviceId,
      cpuCores: Platform.numberOfProcessors,
      ramMb: specs.ramMb,
      freeDiskMb: specs.freeDiskMb,
      hasGpu: specs.hasGpu,
      toolIds: widget.registry.all.map((t) => t.id).toSet(),
    );
    final clients = <String, OverflowClient>{};
    final peerCaps = <String, DeviceCapabilities>{};
    final peerHosts = <String, String>{};
    for (final peer in paired) {
      if (peer.endpoints.isEmpty) continue;
      final host = peer.endpoints.first;
      try {
        final client = await connectOverflow(
          host: host,
          port: 47801,
          local: identity,
          peer: peer,
        ).timeout(const Duration(seconds: 5));
        final caps = await client
            .fetchCapabilities()
            .timeout(const Duration(seconds: 5));
        if (caps == null) {
          await client.close();
          continue;
        }
        clients[caps.deviceId] = client;
        peerCaps[caps.deviceId] = caps;
        peerHosts[caps.deviceId] = host;
      } catch (_) {
        // Unreachable peer: simply not a candidate for this run.
      }
    }
    if (clients.isEmpty) return null;
    final tracker = LoadTracker();
    Future<List<DeviceCandidate>> candidates() async => [
          DeviceCandidate(
            caps: localCaps,
            link: LinkKind.local,
            load: tracker.of(identity.deviceId),
          ),
          for (final e in peerCaps.entries)
            DeviceCandidate(
              caps: e.value,
              link: classifyHost(peerHosts[e.key]!),
              load: tracker.of(e.key),
            ),
        ];
    final tools = <Tool>[
      for (final tool in widget.registry.all)
        if (peerCaps.values.any((c) => c.toolIds.contains(tool.id)))
          LoadBalancedTool(
            inner: tool,
            localDeviceId: identity.deviceId,
            candidates: candidates,
            tracker: tracker,
            executeRemote: (deviceId, input) async {
              final reply = await clients[deviceId]!.invoke(tool.id, input);
              return ToolResult(ok: reply.ok, output: reply.output);
            },
          )
        else
          tool,
    ];
    return (
      registry: ToolRegistry(tools),
      clients: clients.values.toList(),
      note: _balanceNoteFor(clients.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final project = widget.project;
    if (project == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CairnSpacing.xxl),
          child: Text(s.cOpenProjectFirst),
        ),
      );
    }
    if (project.agents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CairnSpacing.xxl),
          child: Text(s.cNoAgentYet),
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
              Text(s.cTitle, style: theme.textTheme.headlineMedium),
              const SizedBox(width: CairnSpacing.md),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: agent.id,
                  decoration: InputDecoration(labelText: s.cAgent),
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
          if (project.pipeline.isNotEmpty) ...[
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: Text(s.runAgentMode)),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.account_tree_outlined),
                    label: Text(s.runChain)),
              ],
              selected: {_chainMode},
              onSelectionChanged: (v) => setState(() => _chainMode = v.first),
            ),
            const SizedBox(height: CairnSpacing.md),
          ],
          if (!_chainMode) ...[
          Text(
            s.cModelLine(agent.model.providerId, agent.model.modelId),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: CairnSpacing.sm),
          TextField(
            controller: _instruction,
            minLines: 2,
            maxLines: 4,
            enabled: !_running,
            decoration: InputDecoration(
              labelText: s.cInstruction,
              hintText: s.cInstructionHint,
            ),
          ),
          const SizedBox(height: CairnSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.cBalanceTitle),
            subtitle: Text(
              _balanceNote ??
                  s.cBalanceSubtitle,
            ),
            value: _balance,
            onChanged:
                _running ? null : (v) => setState(() => _balance = v),
          ),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: const Icon(Icons.play_arrow),
                label: Text(s.cRun),
              ),
              const SizedBox(width: CairnSpacing.sm),
              if (_running)
                OutlinedButton.icon(
                  onPressed: () => _cancelToken?.cancel(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(s.cCancelRun),
                ),
              if (_configError != null) ...[
                const SizedBox(width: CairnSpacing.md),
                Expanded(
                  child: Text(_configError!,
                      style: const TextStyle(color: CairnColors.error)),
                ),
                if (_providerError)
                  TextButton(
                    onPressed: widget.onOpenSettings,
                    child: Text(s.cGoSettings),
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
                    ? s.cCompleted(_outcome!.summary ?? '')
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
                          ? s.cRunning
                          : s.cEventsHint,
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
          if (_chainMode) ..._chainWidgets(theme, s),
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
