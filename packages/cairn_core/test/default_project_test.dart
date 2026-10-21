import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

void main() {
  test('flow-1 default project validates and matches the flowchart', () {
    final project = buildFlowOneDefaultProject();
    expect(project.validate(), isEmpty);
    expect(project.agents, hasLength(1));
    final agent = project.agents.single;
    // The flowchart's operation types all have their tools bound.
    final toolIds = agent.tools.map((t) => t.toolId).toSet();
    expect(toolIds, {
      'fs.list',
      'fs.read',
      'fs.write',
      'shell.run',
      'http.get',
      'calc.eval',
      'text.stats',
      'text.transform',
      'clock.now',
      'id.uuid',
    });
    // Language pipeline: detect + translate when needed (flow start).
    expect(agent.language.primaryLanguage, 'auto');
    expect(agent.language.translateWhenNeeded, isTrue);
    // A real model slot (owner re-points it in the editor).
    expect(agent.model.providerId, isNotEmpty);
    expect(agent.model.modelId, isNotEmpty);
  });

  test('flow-1 default project survives an archive round-trip', () async {
    final dir = await Directory.systemTemp.createTemp('cairn_default_');
    addTearDown(() => dir.delete(recursive: true));
    final project = buildFlowOneDefaultProject();
    final file = await ProjectArchive.exportProject(project, dir);
    expect(file.path, endsWith('.cairn.zip'));
    final imported = await ProjectArchive.importProject(file);
    expect(imported.id, project.id);
    expect(imported.name, project.name);
    expect(imported.agents.single.name, 'دستیار فلوچارت');
    expect(imported.agents.single.tools, hasLength(10));
    expect(imported.validate(), isEmpty);
  });
}
