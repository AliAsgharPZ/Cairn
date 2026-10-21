import 'package:cairn_core/cairn_core.dart';
import 'package:flutter/material.dart';

import '../ui/cairn_theme.dart';
import '../ui/tokens.dart';
import 'project_store.dart';
import 'projects_screen.dart';

/// The studio shell: one identical structure on phone and desktop —
/// a navigation bar on compact widths, a navigation rail on wide ones
/// (docs/design.md density adaptation). Destinations land milestone by
/// milestone; a destination that is not built yet says so plainly instead
/// of showing fabricated functionality.
class StudioShell extends StatefulWidget {
  const StudioShell({super.key, required this.store});

  final ProjectStore store;

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _destinations = [
  _Destination('پروژه‌ها', Icons.folder_outlined),
  _Destination('ویرایشگر ایجنت', Icons.smart_toy_outlined),
  _Destination('کنسول تست', Icons.terminal_outlined),
  _Destination('دستگاه‌ها و سینک', Icons.devices_outlined),
  _Destination('تنظیمات', Icons.settings_outlined),
];

class _StudioShellState extends State<StudioShell> {
  int _index = 0;
  AgentProject? _selectedProject;

  void _openProject(AgentProject project) {
    setState(() {
      _selectedProject = project;
      _index = 1; // editor destination
    });
  }

  Widget _body() {
    switch (_index) {
      case 0:
        return ProjectsScreen(
            store: widget.store, onOpenProject: _openProject);
      case 1:
        return _RoadmapPanel(
          title: 'ویرایشگر ایجنت',
          milestone: 'M3',
          detail: _selectedProject == null
              ? 'اول از بخش پروژه‌ها یک پروژه را باز کن.'
              : 'پروژهٔ انتخاب‌شده: ${_selectedProject!.name} — '
                  'ویرایشگر فرمی ایجنت در مرحلهٔ M3 روی همین صفحه می‌نشیند.',
        );
      case 2:
        return const _RoadmapPanel(
          title: 'کنسول تست',
          milestone: 'M4',
          detail: 'اجرای زندهٔ ایجنت و مشاهدهٔ پلن، فراخوانی ابزار و لاگ، '
              'همراه موتور اجرا در مرحلهٔ M4 ساخته می‌شود.',
        );
      case 3:
        return const _RoadmapPanel(
          title: 'دستگاه‌ها و سینک',
          milestone: 'M7',
          detail: 'جفت‌سازی امن و سینک دوطرفه بین اندروید و ویندوز '
              'در مرحلهٔ M7 ساخته می‌شود.',
        );
      default:
        return const _RoadmapPanel(
          title: 'تنظیمات',
          milestone: 'M3',
          detail: 'مدل‌ها، کلیدهای API و سیاست‌های اجرا در مرحلهٔ M3 '
              'به این بخش می‌آیند.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            CairnWordmark(fontSize: 20),
            SizedBox(width: CairnSpacing.sm),
            Text('استودیو'),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _body()),
              ],
            );
          }
          return _body();
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 720
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            )
          : null,
    );
  }
}

/// An honest "not built yet" panel for a destination whose milestone has
/// not landed. It never pretends to be the feature itself.
class _RoadmapPanel extends StatelessWidget {
  const _RoadmapPanel(
      {required this.title, required this.milestone, required this.detail});

  final String title;
  final String milestone;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(CairnSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: CairnSpacing.xs),
                Text('مرحلهٔ ساخت: $milestone',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: CairnSpacing.sm),
                Text(detail, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
