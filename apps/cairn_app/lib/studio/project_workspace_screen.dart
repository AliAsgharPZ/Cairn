import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:flutter/material.dart';

import '../ui/motion.dart';
import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'agent_editor_screen.dart';
import 'project_store.dart';
import 'provider_settings.dart';
import 'skill_store.dart';

/// The project workspace (v1.2 restructure): ONE place per project
/// holding the two things a project is made of —
///
///  * the CHAIN (زنجیره): the connected line of models + agents a
///    request flows through, each step's model replaceable;
///  * the AGENTS (ایجنت‌ها): the existing editor, unchanged inside.
///
/// v1 kept "agent editor" as a detached tab and training in another,
/// which the owner (rightly) called illogical: a project of several
/// models and agents could not be seen — or wired — as one thing.
class ProjectWorkspaceScreen extends StatefulWidget {
  const ProjectWorkspaceScreen({
    super.key,
    required this.store,
    required this.project,
    required this.registry,
    required this.providerConfigs,
    required this.onProjectChanged,
    required this.skillStore,
    required this.skills,
    required this.onSkillsChanged,
    required this.baseDir,
  });

  final ProjectStore store;
  final AgentProject? project;
  final ToolRegistry registry;
  final List<ProviderConfig> providerConfigs;
  final VoidCallback onProjectChanged;
  final SkillStore skillStore;
  final List<Skill> skills;
  final VoidCallback onSkillsChanged;
  final Directory baseDir;

  @override
  State<ProjectWorkspaceScreen> createState() =>
      _ProjectWorkspaceScreenState();
}

class _ProjectWorkspaceScreenState extends State<ProjectWorkspaceScreen> {
  bool _showChain = true;
  List<SmartModel> _smartModels = const [];

  SmartModelStore get _smartStore =>
      SmartModelStore(Directory('${widget.baseDir.path}/models'));

  @override
  void initState() {
    super.initState();
    _loadSmart();
  }

  @override
  void didUpdateWidget(ProjectWorkspaceScreen old) {
    super.didUpdateWidget(old);
    if (old.project?.id != widget.project?.id) _loadSmart();
  }

  Future<void> _loadSmart() async {
    final models = await _smartStore.list();
    if (mounted) setState(() => _smartModels = models);
  }

  Future<void> _save() async {
    final project = widget.project;
    if (project == null) return;
    project.updatedAt = DateTime.now().toUtc();
    await widget.store.save(project);
    widget.onProjectChanged();
    if (mounted) setState(() {});
  }

  String _kindForStep(String stepKind) => switch (stepKind) {
        PipelineKind.detect => SmartModelKind.langDetect,
        PipelineKind.interpret => SmartModelKind.intent,
        PipelineKind.translateIn ||
        PipelineKind.translateBack =>
          SmartModelKind.translator,
        _ => '',
      };

  Widget _stepCard(S s, PipelineStep step, int index) {
    final theme = Theme.of(context);
    final kind = _kindForStep(step.kind);
    final options = [
      for (final m in _smartModels)
        if (m.kind == kind) m,
    ];
    return FadeSlideIn(
      delay: Duration(milliseconds: 40 * (index > 6 ? 6 : index)),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(CairnSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(s.stepTitle(step.kind),
                        style: theme.textTheme.titleSmall),
                  ),
                  Switch(
                    value: step.enabled,
                    onChanged: (v) async {
                      step.enabled = v;
                      await _save();
                    },
                  ),
                ],
              ),
              Text(s.stepHelp(step.kind),
                  style: theme.textTheme.bodySmall),
              if (kind.isNotEmpty) ...[
                const SizedBox(height: CairnSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: step.modelRef,
                  decoration:
                      InputDecoration(labelText: s.bindingDefault),
                  items: [
                    DropdownMenuItem(value: '', child: Text(s.bindingDefault)),
                    for (final m in options)
                      DropdownMenuItem(value: m.id, child: Text(m.name)),
                  ],
                  onChanged: (v) async {
                    step.modelRef = v ?? '';
                    await _save();
                  },
                ),
              ],
              if (step.kind == PipelineKind.agent &&
                  widget.project!.agents.isNotEmpty) ...[
                const SizedBox(height: CairnSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: step.agentId.isEmpty
                      ? widget.project!.agents.first.id
                      : step.agentId,
                  decoration: InputDecoration(labelText: s.bindingAgent),
                  items: [
                    for (final a in widget.project!.agents)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (v) async {
                    step.agentId = v ?? '';
                    await _save();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chainView(S s) {
    final project = widget.project!;
    if (project.pipeline.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CairnSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.chainHelp, textAlign: TextAlign.center),
              const SizedBox(height: CairnSpacing.md),
              FilledButton.icon(
                icon: const Icon(Icons.add_link),
                label: Text(s.chainAddDefault),
                onPressed: () async {
                  project.pipeline.addAll(defaultPipeline(
                    firstAgentId:
                        project.agents.isEmpty ? '' : project.agents.first.id,
                  ));
                  await _save();
                },
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(CairnSpacing.md),
      children: [
        Text(s.chainHelp, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: CairnSpacing.md),
        for (var i = 0; i < project.pipeline.length; i++) ...[
          _stepCard(s, project.pipeline[i], i),
          if (i < project.pipeline.length - 1)
            const Center(child: Icon(Icons.arrow_downward, size: 18)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final project = widget.project;
    if (project == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CairnSpacing.xxl),
          child: Text(s.chainPickProjectFirst, textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              CairnSpacing.md, CairnSpacing.md, CairnSpacing.md, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(project.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis),
              ),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.account_tree_outlined),
                      label: Text(s.wsChain)),
                  ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: Text(s.wsAgents)),
                ],
                selected: {_showChain},
                onSelectionChanged: (v) =>
                    setState(() => _showChain = v.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: CairnSpacing.sm),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _showChain
                ? KeyedSubtree(
                    key: const ValueKey('chain'), child: _chainView(s))
                : KeyedSubtree(
                    key: const ValueKey('agents'),
                    child: AgentEditorScreen(
                      store: widget.store,
                      project: project,
                      registry: widget.registry,
                      providerConfigs: widget.providerConfigs,
                      onProjectChanged: widget.onProjectChanged,
                      skillStore: widget.skillStore,
                      skills: widget.skills,
                      onSkillsChanged: widget.onSkillsChanged,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
