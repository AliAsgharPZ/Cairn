import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:flutter/material.dart';

import '../ui/cairn_theme.dart';
import '../ui/tokens.dart';
import 'agent_editor_screen.dart';
import 'device_identity.dart';
import 'devices_screen.dart';
import 'project_store.dart';
import 'projects_screen.dart';
import 'provider_settings.dart';
import 'settings_screen.dart';
import 'skill_store.dart';
import 'test_console_screen.dart';
import 'training_screen.dart';

/// The studio shell: one identical structure on phone and desktop —
/// a navigation bar on compact widths, a navigation rail on wide ones
/// (docs/design.md density adaptation). Destinations land milestone by
/// milestone; a destination that is not built yet says so plainly instead
/// of showing fabricated functionality.
class StudioShell extends StatefulWidget {
  const StudioShell({
    super.key,
    required this.store,
    required this.registry,
    required this.settingsStore,
    required this.keyStore,
    required this.skillStore,
    required this.seedStore,
  });

  final ProjectStore store;
  final ToolRegistry registry;
  final ProviderSettingsStore settingsStore;
  final ApiKeyStore keyStore;
  final SkillStore skillStore;
  final SeedStore seedStore;

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
  _Destination('آموزش مدل', Icons.school_outlined),
  _Destination('تنظیمات', Icons.settings_outlined),
];

class _StudioShellState extends State<StudioShell> {
  int _index = 0;
  AgentProject? _selectedProject;
  List<ProviderConfig> _providerConfigs = const [];
  List<Skill> _skills = const [];

  @override
  void initState() {
    super.initState();
    _reloadProviders();
    _reloadSkills();
  }

  Future<void> _reloadProviders() async {
    final configs = await widget.settingsStore.load();
    if (mounted) {
      setState(() {
        _providerConfigs = configs;
      });
    }
  }

  Future<void> _reloadSkills() async {
    final skills = await widget.skillStore.list();
    if (mounted) {
      setState(() {
        _skills = skills;
      });
    }
  }

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
        return AgentEditorScreen(
          store: widget.store,
          project: _selectedProject,
          registry: widget.registry,
          providerConfigs: _providerConfigs,
          onProjectChanged: () => setState(() {}),
          skillStore: widget.skillStore,
          skills: _skills,
          onSkillsChanged: _reloadSkills,
        );
      case 2:
        return TestConsoleScreen(
          project: _selectedProject,
          registry: widget.registry,
          providerConfigs: _providerConfigs,
          keyStore: widget.keyStore,
          onOpenSettings: () => setState(() => _index = 5),
          skillRegistry: SkillRegistry(_skills),
          modelRegistry: _modelRegistry,
        );
      case 3:
        return DevicesScreen(
          projects: widget.store,
          skills: widget.skillStore,
          baseDir: widget.store.baseDir,
          seedStore: widget.seedStore,
          registry: widget.registry,
        );
      case 4:
        return TrainingScreen(
          baseDir: widget.store.baseDir,
          registry: _modelRegistry,
          settingsStore: widget.settingsStore,
          onProvidersChanged: _reloadProviders,
        );
      default:
        return SettingsScreen(
          settingsStore: widget.settingsStore,
          keyStore: widget.keyStore,
          onChanged: _reloadProviders,
          modelRegistry: _modelRegistry,
        );
    }
  }

  /// The shared registry of locally trained models (M9), rooted at
  /// `<cairnDir>/models`.
  ModelRegistryStore get _modelRegistry =>
      ModelRegistryStore(Directory('${widget.store.baseDir.path}/models'));

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

