import 'dart:io';

import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_tools/cairn_tools.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'studio/project_store.dart';
import 'studio/provider_settings.dart';
import 'studio/studio_shell.dart';
import 'ui/cairn_theme.dart';

/// The Cairn studio app — the identical full studio on Android and Windows.
class CairnApp extends StatelessWidget {
  CairnApp({
    super.key,
    required this.store,
    ToolRegistry? registry,
    ProviderSettingsStore? settingsStore,
    ApiKeyStore? keyStore,
  })  : registry = registry ?? BuiltInTools.registry(),
        settingsStore = settingsStore ?? ProviderSettingsStore(store.baseDir),
        // Tests may omit the key store (in-memory); main() always passes the
        // platform secure store.
        keyStore = keyStore ?? MemoryApiKeyStore();

  final ProjectStore store;
  final ToolRegistry registry;
  final ProviderSettingsStore settingsStore;
  final ApiKeyStore keyStore;

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
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final cairnDir = Directory('${docs.path}/cairn');
  runApp(CairnApp(
    store: ProjectStore(cairnDir),
    settingsStore: ProviderSettingsStore(cairnDir),
    keyStore: SecureApiKeyStore(),
  ));
}
