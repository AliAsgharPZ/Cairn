import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'model_editor_screen.dart';
import 'model_store.dart';
import 'provider_settings.dart';

/// "My models" (v1.3): the owner's models, each with a ROLE. This
/// section replaces the v1.2 one-tap auto-trained smart models,
/// which the owner explicitly asked to remove. A model here is a
/// definition pointing at any open-source model (Ollama) or AI API;
/// project flowcharts bind to these by role.
class ModelsSection extends StatefulWidget {
  const ModelsSection({
    super.key,
    required this.baseDir,
    required this.settingsStore,
    required this.modelRegistry,
    this.toolIds = const [],
  });

  final Directory baseDir;
  final ProviderSettingsStore settingsStore;
  final ModelRegistryStore modelRegistry;
  final List<String> toolIds;

  @override
  State<ModelsSection> createState() => _ModelsSectionState();
}

class _ModelsSectionState extends State<ModelsSection> {
  List<ModelDefinition> _models = const [];
  String _status = '';

  ModelStore get _store => ModelStore(widget.baseDir);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final models = await _store.list();
    if (mounted) setState(() => _models = models);
  }

  Future<void> _openEditor([ModelDefinition? existing]) async {
    final providers = await widget.settingsStore.load();
    final local = await widget.modelRegistry.list();
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ModelEditorScreen(
          store: _store,
          providers: providers,
          localModelNames: [for (final m in local) m.name],
          toolIds: widget.toolIds,
          existing: existing,
        ),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _export() async {
    final json = await _store.exportJson();
    final location = await getSaveLocation(
      suggestedName: 'cairn-models.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (location == null) return;
    await File(location.path).writeAsString(json);
    if (mounted) setState(() => _status = S.of(context).backupDone);
  }

  Future<void> _import() async {
    final s = S.of(context);
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;
    try {
      final count = await _store.importJson(await file.readAsString());
      await _reload();
      if (mounted) setState(() => _status = s.modelsImported(count));
    } catch (e) {
      if (mounted) setState(() => _status = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.myModels, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.xs),
        Text(s.myModelsHelp, style: theme.textTheme.bodySmall),
        const SizedBox(height: CairnSpacing.sm),
        Wrap(
          spacing: CairnSpacing.sm,
          runSpacing: CairnSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: Text(s.createModel),
            ),
            OutlinedButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.ios_share),
              label: Text(s.exportModels),
            ),
            OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(s.importModels),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: s.exportModels,
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: await _store.exportJson()));
              },
            ),
          ],
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: CairnSpacing.sm),
          Text(_status, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: CairnSpacing.sm),
        if (_models.isEmpty)
          Text(s.smartNone, style: theme.textTheme.bodySmall)
        else
          for (final m in _models)
            Card(
              child: ListTile(
                leading: Chip(label: Text(s.roleTitle(m.role))),
                title: Text(m.name),
                subtitle: Text(
                  [
                    '${m.providerId} · ${m.modelId}',
                    if (m.description.isNotEmpty) m.description,
                    if (m.role == ModelRole.agent && m.lessons.isNotEmpty)
                      '🎓 ${m.lessons.length}',
                  ].join('\n'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openEditor(m),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await _store.delete(m.id);
                        await _reload();
                      },
                    ),
                  ],
                ),
                onTap: () => _openEditor(m),
              ),
            ),
        const Divider(height: CairnSpacing.xxl),
      ],
    );
  }
}
