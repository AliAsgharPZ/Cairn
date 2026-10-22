import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:flutter/material.dart';

import '../ui/motion.dart';
import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'agent_editor_screen.dart';
import 'language_store.dart';
import 'model_store.dart';
import 'project_store.dart';
import 'provider_settings.dart';
import 'skill_store.dart';

/// The project workspace (v1.3): the project's FLOWCHART and its
/// agents in one place.
///
/// The flowchart is the owner's to shape (their words: «بشه فلوچارت
/// پروژه‌رو مشخص کرد تا مدل‌ها بر اساس اون روشن بشن و کار کنن»):
/// steps are roles, each step binds a model of that role, and steps
/// can be added, removed, reordered and switched on/off. Everything
/// is labeled in plain language — no jargon, no long texts.
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
  bool _showFlow = true;
  List<ModelDefinition> _models = const [];
  List<AppLanguage> _languages = LanguageStore.builtins;

  ModelStore get _modelStore => ModelStore(widget.baseDir);

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void didUpdateWidget(ProjectWorkspaceScreen old) {
    super.didUpdateWidget(old);
    if (old.project?.id != widget.project?.id) _loadModels();
  }

  Future<void> _loadModels() async {
    final models = await _modelStore.list();
    final languages = await LanguageStore(widget.baseDir).list();
    if (mounted) {
      setState(() {
        _models = models;
        _languages = languages;
      });
    }
  }

  Future<void> _save() async {
    final project = widget.project;
    if (project == null) return;
    project.updatedAt = DateTime.now().toUtc();
    await widget.store.save(project);
    widget.onProjectChanged();
    if (mounted) setState(() {});
  }

  Future<void> _addStep() async {
    final s = S.of(context);
    final role = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(s.addStep),
        children: [
          for (final role in ModelRole.all)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, role),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.roleTitle(role),
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(s.roleHelp(role),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (role == null) return;
    widget.project!.pipeline.add(PipelineStep(role: role));
    await _save();
  }

  Widget _stepCard(S s, PipelineStep step, int index) {
    final theme = Theme.of(context);
    final project = widget.project!;
    final options = [
      for (final m in _models)
        if (m.role == step.role) m,
    ];
    return FadeSlideIn(
      delay: Duration(milliseconds: 35 * (index > 6 ? 6 : index)),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(CairnSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${index + 1}) ${s.roleTitle(step.role)}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 19),
                    onPressed: index == 0
                        ? null
                        : () async {
                            project.pipeline.removeAt(index);
                            project.pipeline.insert(index - 1, step);
                            await _save();
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 19),
                    onPressed: index == project.pipeline.length - 1
                        ? null
                        : () async {
                            project.pipeline.removeAt(index);
                            project.pipeline.insert(index + 1, step);
                            await _save();
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 19),
                    onPressed: () async {
                      project.pipeline.removeAt(index);
                      await _save();
                    },
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
              Text(s.roleHelp(step.role), style: theme.textTheme.bodySmall),
              const SizedBox(height: CairnSpacing.sm),
              if (options.isEmpty)
                Text(s.noModelForRole, style: theme.textTheme.bodySmall)
              else
                DropdownButtonFormField<String>(
                  initialValue: step.modelDefId,
                  decoration: InputDecoration(labelText: s.stepModelAuto),
                  items: [
                    DropdownMenuItem(value: '', child: Text(s.stepModelAuto)),
                    for (final m in options)
                      DropdownMenuItem(value: m.id, child: Text(m.name)),
                  ],
                  onChanged: (v) async {
                    step.modelDefId = v ?? '';
                    await _save();
                  },
                ),
              if (step.role == ModelRole.translator) ...[
                const SizedBox(height: CairnSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: step.fromLang,
                        decoration: InputDecoration(labelText: s.fromLang),
                        items: [
                          DropdownMenuItem(
                              value: '', child: Text(s.autoLang)),
                          for (final l in _languages)
                            DropdownMenuItem(
                                value: l.code, child: Text(l.name)),
                        ],
                        onChanged: (v) async {
                          step.fromLang = v ?? '';
                          await _save();
                        },
                      ),
                    ),
                    const SizedBox(width: CairnSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: step.toLang,
                        decoration: InputDecoration(labelText: s.toLang),
                        items: [
                          DropdownMenuItem(
                              value: '', child: Text(s.autoLang)),
                          DropdownMenuItem(
                              value: 'input',
                              child: Text(s.backToInputLang)),
                          for (final l in _languages)
                            DropdownMenuItem(
                                value: l.code, child: Text(l.name)),
                        ],
                        onChanged: (v) async {
                          step.toLang = v ?? '';
                          await _save();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _flowView(S s) {
    final project = widget.project!;
    return ListView(
      padding: const EdgeInsets.all(CairnSpacing.md),
      children: [
        Text(s.flowHelp, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: CairnSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: project.language,
          decoration: InputDecoration(labelText: s.projectLang),
          items: [
            DropdownMenuItem(value: '', child: Text(s.autoLang)),
            for (final l in _languages)
              DropdownMenuItem(value: l.code, child: Text(l.name)),
          ],
          onChanged: (v) async {
            project.language = v ?? '';
            await _save();
          },
        ),
        const SizedBox(height: CairnSpacing.md),
        if (project.pipeline.isEmpty)
          FilledButton.icon(
            icon: const Icon(Icons.add_link),
            label: Text(s.chainAddDefault),
            onPressed: () async {
              project.pipeline.addAll(defaultPipeline());
              await _save();
            },
          )
        else ...[
          for (var i = 0; i < project.pipeline.length; i++) ...[
            _stepCard(s, project.pipeline[i], i),
            if (i < project.pipeline.length - 1)
              const Center(child: Icon(Icons.arrow_downward, size: 18)),
          ],
          const SizedBox(height: CairnSpacing.md),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(s.addStep),
            onPressed: _addStep,
          ),
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
                selected: {_showFlow},
                onSelectionChanged: (v) =>
                    setState(() => _showFlow = v.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: CairnSpacing.sm),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _showFlow
                ? KeyedSubtree(
                    key: const ValueKey('flow'), child: _flowView(s))
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
