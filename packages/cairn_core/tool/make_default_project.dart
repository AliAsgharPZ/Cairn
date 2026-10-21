import 'dart:io';

import 'package:cairn_core/cairn_core.dart';

/// Builds the distributable Flow-1 default project archive:
/// `dart run tool/make_default_project.dart <output-dir>`
Future<void> main(List<String> args) async {
  final outDir = Directory(args.isEmpty ? 'build' : args[0]);
  final project = buildFlowOneDefaultProject();
  final issues = project.validate();
  if (issues.isNotEmpty) {
    stderr.writeln('default project does not validate: $issues');
    exitCode = 1;
    return;
  }
  final file = await ProjectArchive.exportProject(
    project,
    outDir,
    fileName: 'Cairn-Flow1-Default-Project.cairn.zip',
  );
  stdout.writeln(file.path);
}
