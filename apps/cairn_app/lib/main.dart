import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'studio/project_store.dart';
import 'studio/studio_shell.dart';
import 'ui/cairn_theme.dart';

/// The Cairn studio app — the identical full studio on Android and Windows.
class CairnApp extends StatelessWidget {
  const CairnApp({super.key, required this.store});

  final ProjectStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cairn',
      debugShowCheckedModeBanner: false,
      theme: buildCairnTheme(Brightness.light),
      darkTheme: buildCairnTheme(Brightness.dark),
      home: StudioShell(store: store),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final store = ProjectStore(Directory('${docs.path}/cairn'));
  runApp(CairnApp(store: store));
}
