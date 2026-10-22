import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

void main() {
  test('chain scaffold ships EMPTY: no pre-written agents or models',
      () {
    // v1.4 (owner's order): nothing the assistant authored or
    // trained ships in the app. The scaffold is structure only.
    final project = buildChainDefaultProject();
    expect(project.validate(), isEmpty);
    expect(project.agents, isEmpty);
    expect(project.pipeline, isNotEmpty);
    expect(
      project.pipeline.map((s) => s.role),
      [
        ModelRole.translator,
        ModelRole.interpreter,
        ModelRole.manager,
        ModelRole.agent,
        ModelRole.llm,
        ModelRole.translator,
      ],
    );
    // The final translator step returns to the input language.
    expect(project.pipeline.last.toLang, 'input');
    // No step is bound to any model — the owner binds their own.
    expect(project.pipeline.every((s) => s.modelDefId.isEmpty), isTrue);
  });

  test('chain scaffold survives an archive round-trip', () async {
    final dir = await Directory.systemTemp.createTemp('cairn_default_');
    addTearDown(() => dir.delete(recursive: true));
    final project = buildChainDefaultProject()
      ..language = 'de'
      ..pipeline.first.toLang = 'en';
    final file = await ProjectArchive.exportProject(project, dir);
    expect(file.path, endsWith('.cairn.zip'));
    final imported = await ProjectArchive.importProject(file);
    expect(imported.id, project.id);
    expect(imported.agents, isEmpty);
    expect(imported.language, 'de');
    expect(imported.pipeline.first.toLang, 'en');
    expect(imported.pipeline.last.toLang, 'input');
    expect(imported.validate(), isEmpty);
  });
}
