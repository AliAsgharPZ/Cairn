import 'dart:async';
import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:flutter/material.dart';

import '../ui/cairn_theme.dart';
import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'app_settings.dart';
import 'project_workspace_screen.dart';
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
  _Destination(s.wsProject, Icons.account_tree_outlined),
  _Destination(s.wsRun, Icons.play_circle_outlined),
  _Destination(s.wsModels, Icons.school_outlined),
  _Destination(s.settings, Icons.settings_outlined),
];

class _StudioShellState extends State<StudioShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  AgentProject? _selectedProject;
  List<ProviderConfig> _providerConfigs = const [];
  List<Skill> _skills = const [];

  // Auto-sync: once shortly after startup, then every 10 minutes
  // while the studio is open. The header button runs the same flow on
  // demand. Auto-sync stays silent unless something actually changed.
  bool _syncing = false;
  Timer? _autoSyncTimer;

  /// Tab switching (v1.3): the owner disliked the PageView slide, so
  /// pages now cross-fade quickly (170ms) via this controller while an
  /// IndexedStack keeps every page mounted — switching never loses
  /// in-progress work (the v1 trained-model lesson).
  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
    value: 1,
  );
  late final Animation<double> _fadeAnimation =
      Tween<double>(begin: 0.82, end: 1).animate(
    CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
  );

  void _goTo(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _fadeController.forward(from: 0);
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
    _fadeController.dispose();
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

  /// Screens live in an [IndexedStack]: every page stays mounted, so
  /// switching tabs never destroys in-progress work (a trained-but-
  /// unregistered model, a half-filled form — the dead end the owner
  /// hit on 2026-10-21). The PageView slide is gone (owner disliked
  /// it); a short cross-fade rides on [_fadeAnimation] instead, and
  /// the stack element itself never remounts, so page state is safe.
  Widget _body() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) =>
          Opacity(opacity: _fadeAnimation.value, child: child),
      child: IndexedStack(
        index: _index,
        children: [
        _KeepAlivePage(
          child: ProjectsScreen(
            store: widget.store,
            onOpenProject: _openProject,
          ),
        ),
        _KeepAlivePage(
          child: ProjectWorkspaceScreen(
            store: widget.store,
            project: _selectedProject,
            registry: widget.registry,
            providerConfigs: _providerConfigs,
            onProjectChanged: () => setState(() {}),
            skillStore: widget.skillStore,
            skills: _skills,
            onSkillsChanged: _reloadSkills,
            baseDir: widget.store.baseDir,
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
            seedStore: widget.seedStore,
            baseDir: widget.store.baseDir,
          ),
        ),
        _KeepAlivePage(
          child: TrainingScreen(
            baseDir: widget.store.baseDir,
            registry: _modelRegistry,
            settingsStore: widget.settingsStore,
            onProvidersChanged: _reloadProviders,
            projectStore: widget.store,
            toolRegistry: widget.registry,
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
      ),
    );
  }

  /// The floating capsule navigation bar (compact widths).
  ///
  /// v1.2 fix for the Android display bug the owner reported: the
  /// selected destination's label is LONG in Persian («ویرایشگر ایجنت»)
  /// and the old layout put icon+label in a plain Row inside an
  /// Expanded cell — on narrow Android screens the row overflowed its
  /// cell and the pill rendered broken/clipped. Now every cell is
  /// overflow-proof: the label is Flexible with ellipsis AND the cell
  /// content is wrapped in a scale-down FittedBox, the pill is
  /// width-capped and centered, and SafeArea only guards the bottom
  /// (Scaffold already insets the bar's top). Selection animates:
  /// the filled pill grows, the icon pops, the label fades/slides in.
  Widget _capsuleNav(BuildContext context, List<_Destination> destinations) {
    final scheme = Theme.of(context).colorScheme;
    // v1.3 REGRESSION FIX: v1.2 wrapped the pill in a Center inside
    // Scaffold.bottomNavigationBar. The bottom bar is laid out with
    // unbounded height, so Center expanded to the FULL screen height:
    // the body collapsed to zero (blank page) and the pill rendered
    // in the middle of the screen — exactly what the owner reported.
    // A Row sizes to its tallest child instead; never put Center/
    // Align-sized widgets in a bottom bar.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CairnSpacing.md,
          CairnSpacing.xs,
          CairnSpacing.md,
          CairnSpacing.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
              height: 64,
              // v1.4 (owner: the leftmost/rightmost items look ugly
              // when selected): the capsule now has UNIFORM inner
              // padding, so an edge item's selected pill is inset
              // from the capsule's curved end by exactly the same
              // gap as everywhere else — before, the pill had only a
              // 3px margin and visually stuck to the capsule wall.
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: scheme.outline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _goTo(i),
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            height: 50,
                            alignment: Alignment.center,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 2),
                            padding: EdgeInsets.symmetric(
                              horizontal: i == _index ? 12 : 9,
                            ),
                            decoration: BoxDecoration(
                              color: i == _index
                                  ? scheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedScale(
                                    scale: i == _index ? 1.12 : 1.0,
                                    duration:
                                        const Duration(milliseconds: 260),
                                    curve: Curves.easeOutBack,
                                    child: Icon(
                                      destinations[i].icon,
                                      size: 21,
                                      color: i == _index
                                          ? scheme.onPrimary
                                          : scheme.onSurface,
                                    ),
                                  ),
                                  AnimatedSize(
                                    duration:
                                        const Duration(milliseconds: 260),
                                    curve: Curves.easeOutCubic,
                                    child: i == _index
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(width: 6),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                        maxWidth: 92),
                                                child: Text(
                                                  destinations[i].label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: scheme.onPrimary,
                                                    fontSize: 12.5,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : const SizedBox.shrink(),
                                  ),
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
            ),
          ],
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
