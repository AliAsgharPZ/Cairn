import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('RemoteTool', () {
    const context =
        ToolContext(projectId: 'p', agentId: 'a', taskId: 't');

    test('delegates execution to the peer executor', () async {
      Map<String, Object?>? seen;
      final tool = RemoteTool(
        id: 'train.run',
        description: 'Runs training on the peer',
        sensitive: true,
        executor: (input) async {
          seen = input;
          return const ToolResult(ok: true, output: 'trained on pc');
        },
      );
      expect(tool.sensitive, isTrue);
      final result = await tool.run({'epochs': 3}, context);
      expect(seen, {'epochs': 3});
      expect(result.ok, isTrue);
      expect(result.output, 'trained on pc');
    });

    test('a peer refusal is a normal failed result, not a throw',
        () async {
      final tool = RemoteTool(
        id: 'train.run',
        description: 'x',
        executor: (_) async => const ToolResult(
            ok: false, output: 'sensitive tools refused on this device'),
      );
      final result = await tool.run({}, context);
      expect(result.ok, isFalse);
      expect(result.output, contains('refused'));
    });

    test('registers in a ToolRegistry like any local tool', () {
      final registry = ToolRegistry([
        RemoteTool(
          id: 'ml.eval',
          description: 'Evaluates on the peer',
          executor: (_) async =>
              const ToolResult(ok: true, output: 'ok'),
        ),
      ]);
      expect(registry.lookup('ml.eval'), isNotNull);
      expect(registry.all.single.id, 'ml.eval');
    });
  });
}
