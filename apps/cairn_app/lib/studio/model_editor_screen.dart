import 'package:cairn_core/cairn_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'model_store.dart';
import 'provider_settings.dart';

/// Create/edit ONE model (v1.3) in plain language: give it a name,
/// pick its ROLE (what kind of model it is), say what it does, and
/// point it at a source — any open-source model served by Ollama or
/// any AI API the owner configured. Agent-role models additionally
/// get their software, instructions, tools, and the lessons the
/// owner teaches them by demonstration.
class ModelEditorScreen extends StatefulWidget {
  const ModelEditorScreen({
    super.key,
    required this.store,
    required this.providers,
    required this.localModelNames,
    required this.toolIds,
    this.existing,
  });

  final ModelStore store;
  final List<ProviderConfig> providers;

  /// Names of locally trained models (the 'local-trained' source).
  final List<String> localModelNames;
  final List<String> toolIds;
  final ModelDefinition? existing;

  @override
  State<ModelEditorScreen> createState() => _ModelEditorScreenState();
}

class _ModelEditorScreenState extends State<ModelEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _modelId;
  late final TextEditingController _software;
  late final TextEditingController _instructions;
  late String _role;
  late String _providerId;
  late final Set<String> _tools;
  late final List<AgentLesson> _lessons;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _modelId = TextEditingController(text: e?.modelId ?? '');
    _software = TextEditingController(text: e?.targetSoftware ?? '');
    _instructions = TextEditingController(text: e?.instructions ?? '');
    _role = e?.role ?? ModelRole.llm;
    _providerId = e?.providerId ?? 'ollama';
    _tools = {...?e?.toolIds};
    _lessons = [...?e?.lessons];
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _modelId.dispose();
    _software.dispose();
    _instructions.dispose();
    super.dispose();
  }

  List<String> get _providerIds {
    final ids = <String>{'ollama', 'local-trained'};
    for (final c in widget.providers) {
      ids.add(c.providerId);
    }
    return ids.toList();
  }

  Future<void> _addLesson() async {
    final s = S.of(context);
    final title = TextEditingController();
    final details = TextEditingController();
    String? imagePath;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(s.addLesson),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(labelText: s.lessonTitleLabel),
                ),
                TextField(
                  controller: details,
                  minLines: 2,
                  maxLines: 4,
                  decoration:
                      InputDecoration(labelText: s.lessonDetailsLabel),
                ),
                const SizedBox(height: CairnSpacing.sm),
                OutlinedButton.icon(
                  icon: const Icon(Icons.image_outlined),
                  label: Text(imagePath == null
                      ? s.attachScreenshot
                      : imagePath!.split('/').last),
                  onPressed: () async {
                    final file = await openFile(
                      acceptedTypeGroups: const [
                        XTypeGroup(
                            label: 'images',
                            extensions: ['png', 'jpg', 'jpeg', 'webp']),
                      ],
                    );
                    if (file != null) {
                      setLocal(() => imagePath = file.path);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cReject),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.dSave),
            ),
          ],
        ),
      ),
    );
    if (saved == true && title.text.trim().isNotEmpty) {
      setState(() {
        _lessons.add(AgentLesson(
          title: title.text.trim(),
          details: details.text.trim(),
          imagePath: imagePath,
        ));
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final def = ModelDefinition(
      id: widget.existing?.id,
      name: name,
      role: _role,
      providerId: _providerId,
      modelId: _modelId.text.trim(),
      description: _description.text.trim(),
      targetSoftware: _software.text.trim(),
      instructions: _instructions.text.trim(),
      toolIds: _tools.toList(),
      lessons: _lessons,
      createdAt: widget.existing?.createdAt,
    );
    await widget.store.save(def);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isAgent = _role == ModelRole.agent;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? s.createModel : _name.text),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(CairnSpacing.lg),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: s.modelNameLabel),
          ),
          const SizedBox(height: CairnSpacing.md),
          Text(s.modelRoleLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: CairnSpacing.sm),
          Wrap(
            spacing: CairnSpacing.sm,
            runSpacing: CairnSpacing.sm,
            children: [
              for (final role in ModelRole.all)
                ChoiceChip(
                  label: Text(s.roleTitle(role)),
                  selected: _role == role,
                  onSelected: (_) => setState(() => _role = role),
                ),
            ],
          ),
          const SizedBox(height: CairnSpacing.xs),
          Text(s.roleHelp(_role), style: theme.textTheme.bodySmall),
          const SizedBox(height: CairnSpacing.md),
          TextField(
            controller: _description,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: s.modelWhatLabel),
          ),
          const SizedBox(height: CairnSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _providerIds.contains(_providerId)
                ? _providerId
                : _providerIds.first,
            decoration: InputDecoration(labelText: s.modelSourceLabel),
            items: [
              for (final id in _providerIds)
                DropdownMenuItem(value: id, child: Text(id)),
            ],
            onChanged: (v) => setState(() => _providerId = v ?? 'ollama'),
          ),
          const SizedBox(height: CairnSpacing.md),
          if (_providerId == 'local-trained' &&
              widget.localModelNames.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: widget.localModelNames.contains(_modelId.text)
                  ? _modelId.text
                  : widget.localModelNames.first,
              decoration: InputDecoration(labelText: s.modelIdLabel),
              items: [
                for (final n in widget.localModelNames)
                  DropdownMenuItem(value: n, child: Text(n)),
              ],
              onChanged: (v) => setState(() => _modelId.text = v ?? ''),
            )
          else
            TextField(
              controller: _modelId,
              decoration: InputDecoration(
                labelText: s.modelIdLabel,
                hintText: _providerId == 'ollama' ? 'gemma3, llama3.1, …' : '',
              ),
            ),
          if (isAgent) ...[
            const SizedBox(height: CairnSpacing.md),
            TextField(
              controller: _software,
              decoration: InputDecoration(labelText: s.modelSoftwareLabel),
            ),
            const SizedBox(height: CairnSpacing.md),
            Text(s.modelToolsLabel, style: theme.textTheme.titleSmall),
            Wrap(
              spacing: CairnSpacing.sm,
              runSpacing: CairnSpacing.sm,
              children: [
                for (final t in widget.toolIds)
                  FilterChip(
                    label: Text(t),
                    selected: _tools.contains(t),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _tools.add(t);
                      } else {
                        _tools.remove(t);
                      }
                    }),
                  ),
              ],
            ),
          ],
          if (isAgent || _role == ModelRole.coder || _role == ModelRole.llm) ...[
            const SizedBox(height: CairnSpacing.md),
            TextField(
              controller: _instructions,
              minLines: 3,
              maxLines: 8,
              decoration:
                  InputDecoration(labelText: s.modelInstructionsLabel),
            ),
          ],
          if (isAgent) ...[
            const Divider(height: CairnSpacing.xxl),
            Text(s.lessonsTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: CairnSpacing.xs),
            Text(s.lessonsHelp, style: theme.textTheme.bodySmall),
            const SizedBox(height: CairnSpacing.sm),
            for (final lesson in _lessons)
              Card(
                child: ListTile(
                  leading: Icon(lesson.imagePath != null
                      ? Icons.image_outlined
                      : Icons.school_outlined),
                  title: Text(lesson.title),
                  subtitle: Text(lesson.details,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        setState(() => _lessons.remove(lesson)),
                  ),
                ),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: Text(s.addLesson),
              onPressed: _addLesson,
            ),
          ],
          const SizedBox(height: CairnSpacing.xl),
          FilledButton(onPressed: _save, child: Text(s.dSave)),
        ],
      ),
    );
  }
}
