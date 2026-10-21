import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_tools/cairn_tools.dart';
import 'package:test/test.dart';

void main() {
  group('evaluateExpression', () {
    test('respects precedence and parentheses', () {
      expect(evaluateExpression('2 + 3 * 4'), 14);
      expect(evaluateExpression('(2 + 3) * 4'), 20);
      expect(evaluateExpression('10 % 3'), 1);
    });

    test('power is right-associative; unary minus works', () {
      expect(evaluateExpression('2 ^ 3 ^ 2'), 512); // 2^(3^2)
      expect(evaluateExpression('-3 + 5'), 2);
      expect(evaluateExpression('-(2 + 3)'), -5);
      expect(evaluateExpression('2 ^ -1'), 0.5);
    });

    test('decimals and fractional powers', () {
      expect(evaluateExpression('1.5 * 2'), 3.0);
      expect(evaluateExpression('9 ^ 0.5'), closeTo(3, 1e-9));
    });

    test('division by zero and malformed input fail loudly', () {
      expect(() => evaluateExpression('1 / 0'), throwsFormatException);
      expect(() => evaluateExpression('2 +'), throwsFormatException);
      expect(() => evaluateExpression('hello'), throwsFormatException);
      expect(() => evaluateExpression('(2 + 3'), throwsFormatException);
      expect(() => evaluateExpression(''), throwsFormatException);
      expect(() => evaluateExpression('2 3'), throwsFormatException);
    });
  });

  group('built-in tools', () {
    const ctx = ToolContextForTest();

    test('calc.eval returns formatted results and data', () async {
      final tool = CalcEvalTool();
      final res = await tool.run({'expression': '7 * 6'}, ctx.context);
      expect(res.ok, isTrue);
      expect(res.output, '42');
      expect(res.data?['value'], 42.0);
    });

    test('calc.eval reports bad input as a tool failure, not a crash',
        () async {
      final tool = CalcEvalTool();
      final res = await tool.run({'expression': '1/0'}, ctx.context);
      expect(res.ok, isFalse);
      expect(res.output, contains('Division by zero'));
      final res2 = await tool.run({}, ctx.context);
      expect(res2.ok, isFalse);
    });

    test('text.stats counts a known text', () async {
      final tool = TextStatsTool();
      final res = await tool
          .run({'text': 'Hello world. This is Cairn!'}, ctx.context);
      expect(res.ok, isTrue);
      expect(res.data?['words'], 5);
      expect(res.data?['sentences'], 2);
    });

    test('text.transform applies ops and rejects unknown ops', () async {
      final tool = TextTransformTool();
      expect((await tool.run({'text': 'hi there', 'op': 'upper'}, ctx.context))
          .output, 'HI THERE');
      expect((await tool.run({'text': 'hi there', 'op': 'title'}, ctx.context))
          .output, 'Hi There');
      final bad = await tool.run({'text': 'x', 'op': 'nope'}, ctx.context);
      expect(bad.ok, isFalse);
    });

    test('clock.now and id.uuid produce well-formed output', () async {
      final clock = await ClockNowTool().run({}, ctx.context);
      expect(clock.ok, isTrue);
      expect(clock.data?['utc'], contains('T'));
      final uuid = await IdUuidTool().run({}, ctx.context);
      expect(uuid.output,
          matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('the shared registry holds all five built-ins, none sensitive',
        () {
      final registry = BuiltInTools.registry();
      expect(registry.all.map((t) => t.id),
          ['clock.now', 'calc.eval', 'text.stats', 'text.transform', 'id.uuid']);
      expect(registry.all.every((t) => !t.sensitive), isTrue);
    });
  });
}

/// Tiny helper so tests don't repeat the ToolContext literal.
class ToolContextForTest {
  const ToolContextForTest();
  ToolContext get context => const ToolContext(
      projectId: 'p', agentId: 'a', taskId: 't');
}
