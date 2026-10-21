import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:flutter/material.dart';

import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'project_store.dart';
import 'provider_factory.dart';
import 'provider_settings.dart';
import 'skill_store.dart';

/// The agent editor (approved v1 form editor): edits one [AgentBlueprint]
/// inside the selected project — identity, system prompt, model, language
/// pipeline, memory, approval policy and declared tools — and persists it
/// through [ProjectStore]. Validation errors from the blueprint itself are
/// shown, never swallowed.
class AgentEditorScreen extends StatefulWidget {
  const AgentEditorScreen({
    super.key,
    required this.store,
    required this.project,
    required this.registry,
    required this.providerConfigs,
    this.onProjectChanged,
    required this.skillStore,
    required this.skills,
    this.onSkillsChanged,
  });

  final ProjectStore store;
  final AgentProject? project;
  final ToolRegistry registry;
  final List<ProviderConfig> providerConfigs;
  final VoidCallback? onProjectChanged;

  /// Installed skills: attachable to the agent, manageable via the dialog.
  final SkillStore skillStore;
  final List<Skill> skills;
  final VoidCallback? onSkillsChanged;

  @override
  State<AgentEditorScreen> createState() => _AgentEditorScreenState();
}

class _AgentEditorScreenState extends State<AgentEditorScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _systemPrompt = TextEditingController();
  final _modelId = TextEditingController();
  final _maxTokens = TextEditingController();

  String? _editingId;
  String _providerId = 'ollama';
  double? _temperature;

  // Flow-1 role models: a separate model per role, or "same as main"
  // (which is stored as null in the blueprint).
  bool _translatorSeparate = false;
  String _translatorProviderId = 'ollama';
  final _translatorModelId = TextEditingController();
  bool _verifierSeparate = false;
  String _verifierProviderId = 'ollama';
  final _verifierModelId = TextEditingController();
  ApprovalLevel _approval = ApprovalLevel.sensitiveOnly;
  String _primaryLanguage = 'auto';
  bool _translate = true;
  bool _memoryEnabled = true;
  bool _allowNetwork = true;
  final Set<String> _toolIds = {};
  final Set<String> _skillIds = {};

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _systemPrompt.dispose();
    _modelId.dispose();
    _maxTokens.dispose();
    _translatorModelId.dispose();
    _verifierModelId.dispose();
    super.dispose();
  }

  void _newAgent() {
    setState(() {
      _editingId = null;
      _name.clear();
      _description.clear();
      _systemPrompt.clear();
      _modelId.clear();
      _maxTokens.clear();
      _providerId = widget.providerConfigs.isNotEmpty
          ? widget.providerConfigs.first.providerId
          : 'ollama';
      _translatorSeparate = false;
      _verifierSeparate = false;
      _translatorProviderId = _providerId;
      _verifierProviderId = _providerId;
      _translatorModelId.clear();
      _verifierModelId.clear();
      _temperature = null;
      _approval = ApprovalLevel.sensitiveOnly;
      _primaryLanguage = 'auto';
      _translate = true;
      _memoryEnabled = true;
      _allowNetwork = true;
      _toolIds.clear();
      _skillIds.clear();
    });
  }

  void _loadAgent(AgentBlueprint a) {
    setState(() {
      _editingId = a.id;
      _name.text = a.name;
      _description.text = a.description;
      _systemPrompt.text = a.systemPrompt;
      _modelId.text = a.model.modelId;
      _maxTokens.text = a.model.maxOutputTokens?.toString() ?? '';
      _providerId = a.model.providerId;
      _translatorSeparate = a.translatorModel != null;
      _translatorProviderId = a.translatorModel?.providerId ?? _providerId;
      _translatorModelId.text = a.translatorModel?.modelId ?? '';
      _verifierSeparate = a.verifierModel != null;
      _verifierProviderId = a.verifierModel?.providerId ?? _providerId;
      _verifierModelId.text = a.verifierModel?.modelId ?? '';
      _temperature = a.model.temperature;
      _approval = a.policy.approvalLevel;
      _primaryLanguage = a.language.primaryLanguage;
      _translate = a.language.translateWhenNeeded;
      _memoryEnabled = a.memory.enabled;
      _allowNetwork = a.policy.allowNetwork;
      _toolIds
        ..clear()
        ..addAll(a.tools.map((t) => t.toolId));
      _skillIds
        ..clear()
        ..addAll(a.skillIds);
    });
  }

  /// Skills manager: list installed skills (with delete) and create new
  /// ones (name, description, instructions, tool selection). Everything
  /// persists through [SkillStore]; the shell reloads on change.
  Future<void> _manageSkills() async {
    final s = S.of(context);
    final name = TextEditingController();
    final description = TextEditingController();
    final instructions = TextEditingController();
    final selectedTools = <String>{};
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.eSkillsManager),
        content: SizedBox(
          width: 480,
          child: StatefulBuilder(
            builder: (context, setDialogState) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.skills.isEmpty)
                    Text(s.eNoSkillsYet)
                  else
                    for (final skill in widget.skills)
                      ListTile(
                        title: Text(skill.name),
                        subtitle: Text(
                          skill.toolIds.isEmpty
                              ? s.eNoTools
                              : skill.toolIds.join(s.listSep),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: s.eDeleteSkill,
                          onPressed: () async {
                            await widget.skillStore.delete(skill.id);
                            setState(() {
                              _skillIds.remove(skill.id);
                            });
                            widget.onSkillsChanged?.call();
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      ),
                  const Divider(),
                  Text(
                    s.eNewSkill,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: s.eSkillName),
                  ),
                  TextField(
                    controller: description,
                    decoration: InputDecoration(labelText: s.eDescription),
                  ),
                  TextField(
                    controller: instructions,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: s.eSkillInstructions,
                    ),
                  ),
                  const SizedBox(height: CairnSpacing.sm),
                  Text(s.eSkillToolsLabel),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final tool in widget.registry.all)
                        FilterChip(
                          label: Text(tool.id),
                          selected: selectedTools.contains(tool.id),
                          onSelected: (v) => setDialogState(() {
                            if (v) {
                              selectedTools.add(tool.id);
                            } else {
                              selectedTools.remove(tool.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.eClose),
          ),
          FilledButton(
            onPressed: () async {
              final skill = Skill(
                name: name.text.trim(),
                description: description.text.trim(),
                instructions: instructions.text,
                toolIds: selectedTools.toList(),
              );
              try {
                await widget.skillStore.save(skill);
                widget.onSkillsChanged?.call();
                if (context.mounted) Navigator.pop(context);
              } on FormatException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: Text(s.eCreateSkill),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    instructions.dispose();
  }

  AgentBlueprint _buildBlueprint() {
    final maxTokens = int.tryParse(_maxTokens.text.trim());
    return AgentBlueprint(
      id: _editingId,
      name: _name.text.trim(),
      description: _description.text.trim(),
      systemPrompt: _systemPrompt.text,
      model: ModelConfig(
        providerId: _providerId,
        modelId: _modelId.text.trim(),
        temperature: _temperature,
        maxOutputTokens: maxTokens,
      ),
      translatorModel: _translatorSeparate
          ? ModelConfig(
              providerId: _translatorProviderId,
              modelId: _translatorModelId.text.trim(),
            )
          : null,
      verifierModel: _verifierSeparate
          ? ModelConfig(
              providerId: _verifierProviderId,
              modelId: _verifierModelId.text.trim(),
            )
          : null,
      language: LanguageConfig(
        primaryLanguage: _primaryLanguage,
        translateWhenNeeded: _translate,
      ),
      tools: [for (final id in _toolIds) ToolBinding(toolId: id)],
      skillIds: _skillIds.toList(),
      memory: MemoryConfig(enabled: _memoryEnabled),
      policy: PolicyConfig(
        approvalLevel: _approval,
        allowNetwork: _allowNetwork,
      ),
    );
  }

  Future<void> _save() async {
    final s = S.of(context);
    final project = widget.project;
    if (project == null) return;
    final blueprint = _buildBlueprint();
    final issues = blueprint.validate();
    if (issues.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.eAgentIncomplete),
          content: Text(issues.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.eOk),
            ),
          ],
        ),
      );
      return;
    }
    project.upsertAgent(blueprint);
    try {
      await widget.store.save(project);
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    setState(() => _editingId = blueprint.id);
    widget.onProjectChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.eSaved)));
    }
  }

  Future<void> _delete() async {
    final s = S.of(context);
    final project = widget.project;
    if (project == null || _editingId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.eDeleteAgentTitle),
        content: Text(s.eDeleteAgentBody(_name.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.eCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.eDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    project.removeAgent(_editingId!);
    await widget.store.save(project);
    widget.onProjectChanged?.call();
    _newAgent();
  }

  /// One Flow-1 role's model picker: either "same as the main model"
  /// (stored as null) or a separate provider + model — any configured
  /// provider counts, external or local (Ollama, trained models).
  Widget _rolePicker({
    required String title,
    required String explanation,
    required bool separate,
    required ValueChanged<bool> onSeparate,
    required String providerId,
    required ValueChanged<String> onProvider,
    required TextEditingController model,
    required List<String> providerIds,
    String? hint,
  }) {
    final theme = Theme.of(context);
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: CairnSpacing.xs),
        Text(explanation, style: theme.textTheme.bodySmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.eSeparateModelTitle),
          subtitle: Text(s.eSeparateModelSub),
          value: separate,
          onChanged: onSeparate,
        ),
        if (separate) ...[
          DropdownButtonFormField<String>(
            initialValue: providerId,
            decoration: InputDecoration(
              labelText: s.eProvider,
            ),
            items: [
              for (final id in providerIds)
                DropdownMenuItem(
                  value: id,
                  child: Text(knownProviders[id] ?? id),
                ),
            ],
            onChanged: (v) {
              if (v != null) onProvider(v);
            },
          ),
          const SizedBox(height: CairnSpacing.sm),
          TextField(
            controller: model,
            decoration: InputDecoration(
              labelText: s.eModelId,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: CairnSpacing.xs),
            Text(hint, style: theme.textTheme.bodySmall),
          ],
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
          child: Text(s.eOpenProjectEdit),
        ),
      );
    }
    final theme = Theme.of(context);
    final providerIds = <String>{
      ...knownProviders.keys,
      for (final c in widget.providerConfigs) c.providerId,
    }.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CairnSpacing.md,
            CairnSpacing.md,
            CairnSpacing.md,
            0,
          ),
          child: Wrap(
            spacing: CairnSpacing.xs,
            runSpacing: CairnSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                s.eProjectLine(project.name),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(width: CairnSpacing.sm),
              for (final agent in project.agents)
                ChoiceChip(
                  label: Text(agent.name),
                  selected: _editingId == agent.id,
                  onSelected: (_) => _loadAgent(agent),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(s.eNewAgent),
                onPressed: _newAgent,
              ),
            ],
          ),
        ),
        const Divider(height: CairnSpacing.xxl),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(CairnSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  decoration: InputDecoration(labelText: s.eAgentName),
                ),
                const SizedBox(height: CairnSpacing.sm),
                TextField(
                  controller: _description,
                  decoration: InputDecoration(labelText: s.eDescription),
                ),
                const SizedBox(height: CairnSpacing.sm),
                TextField(
                  controller: _systemPrompt,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: s.eSystemPrompt,
                  ),
                ),
                const SizedBox(height: CairnSpacing.lg),
                Text(s.eRolesTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: CairnSpacing.xs),
                Text(
                  s.eRolesIntro,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: CairnSpacing.sm),
                Text(s.eBrainTitle, style: theme.textTheme.titleSmall),
                Text(
                  s.eBrainDesc,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: CairnSpacing.xs),
                DropdownButtonFormField<String>(
                  initialValue: _providerId,
                  decoration: InputDecoration(
                    labelText: s.eProvider,
                  ),
                  items: [
                    for (final id in providerIds)
                      DropdownMenuItem(
                        value: id,
                        child: Text(knownProviders[id] ?? id),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _providerId = v;
                      if (_modelId.text.isEmpty) {
                        final cfg = widget.providerConfigs
                            .where((c) => c.providerId == v)
                            .firstOrNull;
                        if (cfg != null && cfg.defaultModelId.isNotEmpty) {
                          _modelId.text = cfg.defaultModelId;
                        }
                      }
                    });
                  },
                ),
                const SizedBox(height: CairnSpacing.sm),
                TextField(
                  controller: _modelId,
                  decoration: InputDecoration(
                    labelText: s.eModelId,
                  ),
                ),
                const SizedBox(height: CairnSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _maxTokens,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: s.eMaxTokens,
                        ),
                      ),
                    ),
                    const SizedBox(width: CairnSpacing.md),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _temperature == null
                                ? s.eTempDefault
                                : s.eTempValue(_temperature!.toStringAsFixed(1)),
                            style: theme.textTheme.labelLarge,
                          ),
                          Slider(
                            value: _temperature ?? 0.7,
                            min: 0,
                            max: 2,
                            divisions: 20,
                            onChanged: (v) => setState(() => _temperature = v),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _temperature = null),
                      child: Text(s.eDefault),
                    ),
                  ],
                ),
                const SizedBox(height: CairnSpacing.lg),
                _rolePicker(
                  title: s.eTranslatorTitle,
                  explanation:
                      s.eTranslatorDesc,
                  separate: _translatorSeparate,
                  onSeparate: (v) => setState(() => _translatorSeparate = v),
                  providerId: _translatorProviderId,
                  onProvider: (v) => setState(() => _translatorProviderId = v),
                  model: _translatorModelId,
                  providerIds: providerIds,
                  hint:
                      s.eTranslatorHint,
                ),
                const SizedBox(height: CairnSpacing.lg),
                _rolePicker(
                  title: s.eVerifierTitle,
                  explanation:
                      s.eVerifierDesc,
                  separate: _verifierSeparate,
                  onSeparate: (v) => setState(() => _verifierSeparate = v),
                  providerId: _verifierProviderId,
                  onProvider: (v) => setState(() => _verifierProviderId = v),
                  model: _verifierModelId,
                  providerIds: providerIds,
                ),
                const SizedBox(height: CairnSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(CairnSpacing.md),
                  decoration: BoxDecoration(
                    color: CairnColors.canvasTint,
                    borderRadius: BorderRadius.circular(CairnRadii.md),
                  ),
                  child: Text(
                    s.eOrchestratorInfo,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: CairnSpacing.lg),
                Text(s.eLangMemoryTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: CairnSpacing.xs),
                DropdownButtonFormField<String>(
                  initialValue: _primaryLanguage,
                  decoration: InputDecoration(labelText: s.ePrimaryLang),
                  items: [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(s.eLangAuto),
                    ),
                    DropdownMenuItem(value: 'fa', child: Text(s.eLangFa)),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (v) =>
                      setState(() => _primaryLanguage = v ?? 'auto'),
                ),
                SwitchListTile(
                  title: Text(s.eTranslateToggle),
                  value: _translate,
                  onChanged: (v) => setState(() => _translate = v),
                ),
                SwitchListTile(
                  title: Text(s.eMemoryToggle),
                  value: _memoryEnabled,
                  onChanged: (v) => setState(() => _memoryEnabled = v),
                ),
                const SizedBox(height: CairnSpacing.lg),
                Text(s.ePolicyTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: CairnSpacing.xs),
                DropdownButtonFormField<ApprovalLevel>(
                  initialValue: _approval,
                  decoration: InputDecoration(labelText: s.eApprovalLevel),
                  items: [
                    DropdownMenuItem(
                      value: ApprovalLevel.sensitiveOnly,
                      child: Text(s.eApprovalSensitive),
                    ),
                    DropdownMenuItem(
                      value: ApprovalLevel.all,
                      child: Text(s.eApprovalAll),
                    ),
                    DropdownMenuItem(
                      value: ApprovalLevel.none,
                      child: Text(s.eApprovalNone),
                    ),
                  ],
                  onChanged: (v) => setState(
                    () => _approval = v ?? ApprovalLevel.sensitiveOnly,
                  ),
                ),
                SwitchListTile(
                  title: Text(s.eNetworkToggle),
                  value: _allowNetwork,
                  onChanged: (v) => setState(() => _allowNetwork = v),
                ),
                const SizedBox(height: CairnSpacing.lg),
                Text(s.eToolsTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: CairnSpacing.xs),
                for (final tool in widget.registry.all)
                  CheckboxListTile(
                    title: Text(tool.id),
                    subtitle: Text(tool.description),
                    secondary: tool.sensitive
                        ? const Icon(Icons.warning_amber_outlined)
                        : const Icon(Icons.check_circle_outline),
                    value: _toolIds.contains(tool.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _toolIds.add(tool.id);
                      } else {
                        _toolIds.remove(tool.id);
                      }
                    }),
                  ),
                const SizedBox(height: CairnSpacing.lg),
                Row(
                  children: [
                    Text(s.eAttachedSkills, style: theme.textTheme.titleMedium),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _manageSkills,
                      icon: const Icon(Icons.extension_outlined),
                      label: Text(s.eManageSkills),
                    ),
                  ],
                ),
                const SizedBox(height: CairnSpacing.xs),
                if (widget.skills.isEmpty)
                  Text(s.eNoSkillsHint)
                else
                  for (final skill in widget.skills)
                    CheckboxListTile(
                      title: Text(skill.name),
                      subtitle: Text(
                        skill.description.isEmpty
                            ? s.eToolCount(skill.toolIds.length)
                            : skill.description,
                      ),
                      value: _skillIds.contains(skill.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _skillIds.add(skill.id);
                        } else {
                          _skillIds.remove(skill.id);
                        }
                      }),
                    ),
                const SizedBox(height: CairnSpacing.xxl),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(s.eSaveAgent),
                    ),
                    const SizedBox(width: CairnSpacing.sm),
                    if (_editingId != null)
                      OutlinedButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(s.eDeleteAgentBtn),
                      ),
                  ],
                ),
                const SizedBox(height: CairnSpacing.xxl),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
