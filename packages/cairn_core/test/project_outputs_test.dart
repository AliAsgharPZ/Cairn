import 'package:cairn_core/cairn_core.dart';
import 'package:test/test.dart';

void main() {
  test('project outputs round-trip through JSON', () {
    final project = AgentProject(name: 'p');
    project.addOutput(ProjectOutput(
        kind: 'model', name: 'مدل سلام', refId: 'model-123'));
    final back = AgentProject.fromJson(project.toJson());
    expect(back.outputs, hasLength(1));
    expect(back.outputs.single.kind, 'model');
    expect(back.outputs.single.name, 'مدل سلام');
    expect(back.outputs.single.refId, 'model-123');
    expect(back.validate(), isEmpty);
  });

  test('older projects without outputs still parse', () {
    final json = AgentProject(name: 'legacy').toJson()..remove('outputs');
    final back = AgentProject.fromJson(json);
    expect(back.outputs, isEmpty);
  });

  test('re-registering the same model replaces, never duplicates', () {
    final project = AgentProject(name: 'p');
    project.addOutput(
        ProjectOutput(kind: 'model', name: 'v1', refId: 'model-1'));
    project.addOutput(
        ProjectOutput(kind: 'model', name: 'v2', refId: 'model-1'));
    project.addOutput(
        ProjectOutput(kind: 'model', name: 'other', refId: 'model-2'));
    expect(project.outputs, hasLength(2));
    expect(
        project.outputs.firstWhere((o) => o.refId == 'model-1').name, 'v2');
  });
}
