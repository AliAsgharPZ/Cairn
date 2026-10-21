import 'package:cairn_core/cairn_core.dart';
import 'package:flutter/material.dart';

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
    setState(() => _projects = widget.store.list());
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پروژهٔ جدید'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'نام پروژه'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('ساختن'),
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

  Future<void> _deleteProject(AgentProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف پروژه'),
        content: Text('پروژهٔ «${project.name}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
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
    return Padding(
      padding: const EdgeInsets.all(CairnSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('پروژه‌های ایجنت', style: theme.textTheme.headlineMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: _createProject,
                icon: const Icon(Icons.add),
                label: const Text('پروژهٔ جدید'),
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
                    child: Text('خطا در خواندن پروژه‌ها: ${snapshot.error}',
                        style: TextStyle(color: CairnColors.error)),
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
                        Text('هنوز پروژه‌ای نداری',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: CairnSpacing.xs),
                        Text(
                          'با «پروژهٔ جدید» اولین پروژهٔ ایجنتت را بساز.',
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
                    return Card(
                      child: ListTile(
                        title: Text(project.name),
                        subtitle: Text(
                          '${project.agents.length} ایجنت · '
                          'آخرین تغییر: ${_formatDate(project.updatedAt)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'حذف پروژه',
                          onPressed: () => _deleteProject(project),
                        ),
                        onTap: () => widget.onOpenProject?.call(project),
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
