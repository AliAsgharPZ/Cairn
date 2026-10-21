import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_tools/cairn_tools.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'studio/device_identity.dart';
import 'studio/project_store.dart';
import 'studio/provider_settings.dart';
import 'studio/skill_store.dart';
import 'studio/studio_shell.dart';
import 'studio/tool_host_boot.dart';
import 'ui/cairn_theme.dart';

/// The Cairn studio app — the identical full studio on Android and Windows.
class CairnApp extends StatelessWidget {
  CairnApp({
    super.key,
    required this.store,
    ToolRegistry? registry,
    ProviderSettingsStore? settingsStore,
    ApiKeyStore? keyStore,
    SkillStore? skillStore,
    SeedStore? seedStore,
    this.toolHostStatus,
  })  : registry = registry ??
            ToolRegistry([
              ...BuiltInTools.all(),
              // Platform tools are confined to the agent workspace inside
              // the app's data directory.
              ...PlatformTools.all(
                  root: Directory('${store.baseDir.path}/workspace')),
            ]),
        settingsStore = settingsStore ?? ProviderSettingsStore(store.baseDir),
        // Tests may omit the key store (in-memory); main() always passes the
        // platform secure store.
        keyStore = keyStore ?? MemoryApiKeyStore(),
        skillStore = skillStore ?? SkillStore(store.baseDir),
        // Tests use the in-memory seed store; main() passes the secure one.
        seedStore = seedStore ?? MemorySeedStore();

  final ProjectStore store;
  final ToolRegistry registry;
  final ProviderSettingsStore settingsStore;
  final ApiKeyStore keyStore;
  final SkillStore skillStore;
  final SeedStore seedStore;

  /// Windows Tool Host boot outcome (null on non-Windows / in tests);
  /// shown as a banner in the shell so the mode is visible.
  final String? toolHostStatus;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cairn',
      debugShowCheckedModeBanner: false,
      theme: buildCairnTheme(Brightness.light),
      darkTheme: buildCairnTheme(Brightness.dark),
      home: StudioShell(
        store: store,
        registry: registry,
        settingsStore: settingsStore,
        keyStore: keyStore,
        skillStore: skillStore,
        seedStore: seedStore,
        toolHostStatus: toolHostStatus,
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final cairnDir = Directory('${docs.path}/cairn');
  // The agent workspace: the confined root of the platform tools.
  final workspace = Directory('${cairnDir.path}/workspace');
  await workspace.create(recursive: true);
  // Windows: platform tools run in the separate Tool Host process
  // (M5). Boot happens before runApp because the registry is built
  // synchronously; any failure falls back to local tools and the
  // status banner says so.
  ToolRegistry? registry;
  String? toolHostStatus;
  if (Platform.isWindows) {
    final boot = await bootWindowsToolHost(workspaceRoot: workspace);
    registry = boot.registry;
    toolHostStatus = boot.status;
  }
  runApp(CairnApp(
    store: ProjectStore(cairnDir),
    registry: registry,
    settingsStore: ProviderSettingsStore(cairnDir),
    keyStore: SecureApiKeyStore(),
    seedStore: SecureSeedStore(),
    toolHostStatus: toolHostStatus,
  ));
}
