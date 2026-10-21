import 'dart:async';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:flutter/material.dart';

import '../ui/cairn_theme.dart';
import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'agent_editor_screen.dart';
import 'app_settings.dart';
import 'sync_runner.dart';
import 'device_identity.dart';
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
    this.toolHostStatus,
    this.appSettings,
    this.onAppSettingsChanged,
  });

  final ProjectStore store;
  final ToolRegistry registry;
  final ProviderSettingsStore settingsStore;
  final ApiKeyStore keyStore;
  final SkillStore skillStore;
  final SeedStore seedStore;

  /// Windows Tool Host boot status (null elsewhere); rendered as a
  /// slim banner so the execution mode is always visible.
  final String? toolHostStatus;

  /// App-level settings (language/theme) + change callback, forwarded
  /// to the Settings screen's appearance section.
  final AppSettings? appSettings;
  final ValueChanged<AppSettings>? onAppSettingsChanged;

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}

List<_Destination> _destinations(S s) => [
  _Destination(s.projects, Icons.folder_outlined),
  _Destination(s.agentEditor, Icons.smart_toy_outlined),
  _Destination(s.testConsole, Icons.terminal_outlined),
  _Destination(s.training, Icons.school_outlined),
  _Destination(s.settings, Icons.settings_outlined),
];

class _StudioShellState extends State<StudioShell> {
  int _index = 0;
  AgentProject? _selectedProject;
  List<ProviderConfig> _providerConfigs = const [];
  List<Skill> _skills = const [];

  // Auto-sync: once shortly after startup, then every 10 minutes
  // while the studio is open. The header button runs the same flow on
  // demand. Auto-sync stays silent unless something actually changed.
  bool _syncing = false;
  Timer? _autoSyncTimer;

  /// Pages slide between destinations (the shell's main animation);
  /// every page is kept alive, so sliding away never loses work.
  final PageController _pageController = PageController();

  void _goTo(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    _reloadProviders();
    _reloadSkills();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSync());
    _autoSyncTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _autoSync(),
    );
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<List<PeerSyncOutcome>> _syncAll() async {
    final identity = await DeviceIdentityService(widget.seedStore)
        .loadOrCreate();
    return SyncRunner(
      projects: widget.store,
      skills: widget.skillStore,
      baseDir: widget.store.baseDir,
      identity: identity,
    ).syncAll();
  }

  Future<void> _autoSync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final outcomes = await _syncAll();
      final changed = outcomes.where((o) => o.changed).toList();
      if (mounted && changed.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'سینک خودکار انجام شد — '
              '${changed.map((o) => '${o.peerName}: ${o.message}').join('؛ ')}',
            ),
          ),
        );
      }
    } catch (_) {
      // Auto-sync must never interrupt the user with failures.
    }
    _syncing = false;
  }

  Future<void> _manualSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final outcomes = await _syncAll();
      if (!mounted) return;
      final text = outcomes.isEmpty
          ? 'دستگاه جفت‌شده‌ای با نشانی ذخیره‌شده نیست — از تنظیمات، '
                'بخش «دستگاه‌ها و سینک»، نشانی IP دستگاه دیگر را وارد کن.'
          : outcomes.map((o) => '${o.peerName}: ${o.message}').join('؛ ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('سینک ناموفق بود: $e')));
      }
    }
    if (mounted) setState(() => _syncing = false);
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
    setState(() => _selectedProject = project);
    _goTo(1); // editor destination
  }

  /// Screens live in a [PageView] whose pages are kept alive
  /// ([_KeepAlivePage]): sliding between tabs animates, and must never
  /// destroy in-progress work (a trained-but-unregistered model, a
  /// half-filled form). A plain switch used to rebuild the selected
  /// screen from scratch on every tab change, silently discarding the
  /// in-memory trained model — the dead end the owner hit on
  /// 2026-10-21. Swiping is disabled; only the nav controls move pages,
  /// so the selected destination and the visible page never desync.
  Widget _body() {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: (i) => setState(() => _index = i),
      children: [
        _KeepAlivePage(
          child: ProjectsScreen(
            store: widget.store,
            onOpenProject: _openProject,
          ),
        ),
        _KeepAlivePage(
          child: AgentEditorScreen(
            store: widget.store,
            project: _selectedProject,
            registry: widget.registry,
            providerConfigs: _providerConfigs,
            onProjectChanged: () => setState(() {}),
            skillStore: widget.skillStore,
            skills: _skills,
            onSkillsChanged: _reloadSkills,
          ),
        ),
        _KeepAlivePage(
          child: TestConsoleScreen(
            project: _selectedProject,
            registry: widget.registry,
            providerConfigs: _providerConfigs,
            keyStore: widget.keyStore,
            onOpenSettings: () => _goTo(4),
            skillRegistry: SkillRegistry(_skills),
            modelRegistry: _modelRegistry,
          ),
        ),
        _KeepAlivePage(
          child: TrainingScreen(
            baseDir: widget.store.baseDir,
            registry: _modelRegistry,
            settingsStore: widget.settingsStore,
            onProvidersChanged: _reloadProviders,
            projectStore: widget.store,
          ),
        ),
        _KeepAlivePage(
          child: SettingsScreen(
            settingsStore: widget.settingsStore,
            keyStore: widget.keyStore,
            onChanged: _reloadProviders,
            modelRegistry: _modelRegistry,
            appSettings: widget.appSettings,
            onAppSettingsChanged: widget.onAppSettingsChanged,
            projectsStore: widget.store,
            skillStore: widget.skillStore,
            seedStore: widget.seedStore,
            toolRegistry: widget.registry,
          ),
        ),
      ],
    );
  }

  /// The floating capsule navigation bar (compact widths): a rounded
  /// pill with a hairline border (Oracle: depth is tonal, no shadows);
  /// the selected destination expands into a filled pill with its
  /// label, animated by [AnimatedContainer].
  Widget _capsuleNav(BuildContext context, List<_Destination> destinations) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CairnSpacing.md,
          CairnSpacing.xs,
          CairnSpacing.md,
          CairnSpacing.sm,
        ),
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(31),
            border: Border.all(color: scheme.outline),
          ),
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(31),
                    onTap: () => _goTo(i),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          horizontal: i == _index ? 14 : 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: i == _index
                              ? scheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              destinations[i].icon,
                              size: 21,
                              color: i == _index
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                            ),
                            if (i == _index) ...[
                              const SizedBox(width: 6),
                              Text(
                                destinations[i].label,
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The shared registry of locally trained models (M9), rooted at
  /// `<cairnDir>/models`.
  ModelRegistryStore get _modelRegistry =>
      ModelRegistryStore(Directory('${widget.store.baseDir.path}/models'));

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final destinations = _destinations(s);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const CairnWordmark(fontSize: 20),
            const SizedBox(width: CairnSpacing.sm),
            Text(s.studio),
          ],
        ),
        actions: [
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'سینک با دستگاه‌های جفت‌شده',
            onPressed: _syncing ? null : _manualSync,
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.toolHostStatus != null)
            Container(
              width: double.infinity,
              color: CairnColors.canvasTint,
              padding: const EdgeInsets.symmetric(
                horizontal: CairnSpacing.md,
                vertical: CairnSpacing.xs,
              ),
              child: Text(
                widget.toolHostStatus!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 720) {
                  return Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: _goTo,
                        labelType: NavigationRailLabelType.all,
                        destinations: [
                          for (final d in destinations)
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
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 720
          ? _capsuleNav(context, destinations)
          : null,
    );
  }
}

/// Keeps a [PageView] page's state alive after it has been built, so
/// sliding away and back never loses in-progress work.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
