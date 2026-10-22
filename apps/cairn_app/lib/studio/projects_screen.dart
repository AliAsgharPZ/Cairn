import 'package:cairn_core/cairn_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../ui/motion.dart';
import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'project_store.dart';

/// The studio's projects screen: real list/create/open/delete against
/// [ProjectStore]. No sample data is ever fabricated — an empty store shows
/// the empty state.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.store, this.onOpenProject});

  final ProjectStore store;
  final ValueChanged<AgentProject>? onOpenProject;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<AgentProject>> _projects = widget.store.list();

  void _reload() {
    // Block body on purpose: an arrow closure would return the Future,
    // which setState forbids (it asserts in debug/test builds and the
    // refresh silently never happens — caught by CI run #4).
    setState(() {
      _projects = widget.store.list();
    });
  }

  Future<void> _createProject() async {
    final s = S.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.newProject),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: s.projectName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(s.create),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await widget.store.createProject(name);
      _reload();
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// Exports the project as a `.cairn.zip` into the app's exports folder.
  Future<void> _exportProject(AgentProject project) async {
    final s = S.of(context);
    try {
      final file = await widget.store.exportProject(project);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.exportDone(file.path.split('/').last))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.exportError(e))));
      }
    }
  }

  /// Import dialog: lists the archives in the exports folder and imports
  /// the chosen one (validated; id collisions become a copy).
  Future<void> _importProject() async {
    final s = S.of(context);
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Cairn project', extensions: ['zip']),
        XTypeGroup(label: 'All files'),
      ],
    );
    if (picked == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final imported =
          await widget.store.importArchiveBytes(picked.name, bytes);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.imported(imported.name))));
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.importError(e))));
      }
    }
  }

  Future<void> _deleteProject(AgentProject project) async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.deleteProject),
        content: Text(s.deleteProjectConfirm(project.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.delete(project.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.all(CairnSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap (not Row): the header must never overflow on narrow
          // surfaces — CI's 800px test viewport overflowed by 189px
          // when the import button joined the row (run #28).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: CairnSpacing.sm,
            runSpacing: CairnSpacing.sm,
            children: [
              Text(s.agentProjects, style: theme.textTheme.headlineMedium),
              Wrap(
                spacing: CairnSpacing.sm,
                runSpacing: CairnSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _importProject,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: Text(s.importProject),
                  ),
                  FilledButton.icon(
                    onPressed: _createProject,
                    icon: const Icon(Icons.add),
                    label: Text(s.newProject),
                  ),
                ],
              ),
            ],
          ),
          // The system's one ornament: a 40x4 gold rule under the headline.
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: CairnSpacing.xs),
            color: CairnColors.accentGold,
          ),
          const SizedBox(height: CairnSpacing.xxl),
          Expanded(
            child: FutureBuilder<List<AgentProject>>(
              future: _projects,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      s.loadError(snapshot.error!),
                      style: TextStyle(color: CairnColors.error),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final projects = snapshot.data!;
                if (projects.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(CairnSpacing.section),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(CairnRadii.md),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.noProjectsYet,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: CairnSpacing.xs),
                        Text(
                          s.noProjectsHint,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: projects.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CairnSpacing.sm),
                  itemBuilder: (context, i) {
                    final project = projects[i];
                    return FadeSlideIn(
                      delay: Duration(milliseconds: 45 * (i > 8 ? 8 : i)),
                      child: Card(
                      child: ListTile(
                        title: Text(project.name),
                        subtitle: Text(
                          [
                            s.agentsAndLastChange(
                              project.agents.length,
                              _formatDate(project.updatedAt),
                            ),
                            if (project.outputs.isNotEmpty)
                              s.projectOutputs(
                                project.outputs
                                    .map(
                                      (o) =>
                                          '${s.outputKind(o.kind)} «${o.name}»',
                                    )
                                    .join('، '),
                              ),
                          ].join('\n'),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.ios_share),
                              tooltip: s.exportTooltip,
                              onPressed: () => _exportProject(project),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: s.deleteProjectTooltip,
                              onPressed: () => _deleteProject(project),
                            ),
                          ],
                        ),
                        onTap: () => widget.onOpenProject?.call(project),
                      ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final local = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
