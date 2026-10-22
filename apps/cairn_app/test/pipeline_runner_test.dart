import 'dart:io';

import 'package:cairn_app/studio/model_store.dart';
import 'package:cairn_app/studio/pipeline_runner.dart';
import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flowchart runs (v1.3) with role-based model definitions and
/// scripted providers. Verifies the owner's architecture as roles:
/// translator → interpreter → manager (routes) → agent OR llm →
/// translator, honest no-model behavior, and that an agent model's
/// lessons reach its instructions.
void main() {
  late Directory tmp;
  late ModelStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cairn_flow_test');
    store = ModelStore(tmp);
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<void> seedDefs({bool withAgent = false}) async {
    await store.save(ModelDefinition(
      id: 'def-translator',
      name: 'مترجم من',
      role: ModelRole.translator,
      providerId: 'fake',
      modelId: 't',
    ));
    await store.save(ModelDefinition(
      id: 'def-interpreter',
      name: 'مفسر من',
      role: ModelRole.interpreter,
      providerId: 'fake',
      modelId: 'i',
    ));
    await store.save(ModelDefinition(
      id: 'def-llm',
      name: 'مدل زبانی من',
      role: ModelRole.llm,
      providerId: 'fake',
      modelId: 'l',
    ));
    if (withAgent) {
      await store.save(ModelDefinition(
        id: 'def-agent',
        name: 'ایجنت فایل',
        role: ModelRole.agent,
        providerId: 'fake',
        modelId: 'a',
        instructions: 'You handle files.',
        lessons: [
          AgentLesson(title: 'پاک‌کردن', details: 'اول سطل آشغال، بعد حذف'),
        ],
      ));
    }
  }

  PipelineRunner runner({
    required Map<String, List<String>> Function() scripts,
  }) {
    return PipelineRunner(
      models: store,
      providerFor: (def) =>
          FakeModelProvider(scripts()[def.role] ?? const ['ok']),
      providerForAgent: (_) => null,
      mediaFor: (_) => null,
      registry: ToolRegistry(),
      skillRegistry: SkillRegistry(const []),
      outputsDir: Directory('${tmp.path}/outputs'),
    );
  }

  test('persian question: translate → interpret → manager → llm → translate back',
      () async {
    await seedDefs();
    var translatorCalls = 0;
    final r = runner(scripts: () {
      translatorCalls++;
      return {
        ModelRole.translator: [
          translatorCalls == 1
              ? 'Where is the capital of France?'
              : 'پایتخت فرانسه پاریس است.',
        ],
        ModelRole.interpreter: ['question'],
        ModelRole.llm: ['Paris is the capital of France.'],
      };
    });
    final project = buildChainDefaultProject();
    final result = await r.run(
      project: project,
      input: 'پایتخت فرانسه کجاست؟',
      approvalGate: (_) async => true,
    );
    expect(result.detectedLang, 'fa');
    expect(result.intent, 'question');
    expect(result.finalText, 'پایتخت فرانسه پاریس است.');
    final agentTrace =
        result.traces.firstWhere((t) => t.role == ModelRole.agent);
    expect(agentTrace.skipped, isTrue,
        reason: 'manager routed a question away from the agent');
    final roles = result.traces.map((t) => t.role).toList();
    expect(
        roles,
        containsAllInOrder([
          ModelRole.translator,
          ModelRole.interpreter,
          ModelRole.manager,
          ModelRole.llm,
        ]));
  });

  test('persian task reaches the agent model, lessons included', () async {
    await seedDefs(withAgent: true);
    const normalize =
        '{"goal": "Delete the file", "language": "en", "inputs": [], "constraints": []}';
    const plan =
        '{"steps": [{"description": "Handle it", "kind": "model"}]}';
    const verify = '{"done": true, "summary": "Goal achieved"}';
    String? seenSystem;
    final r = PipelineRunner(
      models: store,
      providerFor: (def) {
        if (def.role == ModelRole.agent) {
          return _CapturingProvider(
            [normalize, plan, 'working on it', verify],
            onRequest: (req) {
              for (final m in req.messages) {
                if (m.role == ChatRole.system) seenSystem = m.content;
              }
            },
          );
        }
        return FakeModelProvider(const ['task']);
      },
      providerForAgent: (_) => null,
      mediaFor: (_) => null,
      registry: ToolRegistry(),
      skillRegistry: SkillRegistry(const []),
      outputsDir: Directory('${tmp.path}/outputs'),
    );
    final project = buildChainDefaultProject();
    final result = await r.run(
      project: project,
      input: 'این فایل را پاک کن',
      approvalGate: (_) async => true,
    );
    expect(result.intent, 'task');
    final agentTrace =
        result.traces.firstWhere((t) => t.role == ModelRole.agent);
    expect(agentTrace.skipped, isFalse);
    expect(seenSystem, isNotNull);
    expect(seenSystem, contains('پاک‌کردن'),
        reason: 'the lesson the owner taught must reach the agent');
  });

  test('no models at all: honest passthrough, nothing fabricated', () async {
    final r = runner(scripts: () => const {});
    final bare = PipelineRunner(
      models: store,
      providerFor: (_) => null,
      providerForAgent: (_) => null,
      mediaFor: (_) => null,
      registry: ToolRegistry(),
      skillRegistry: SkillRegistry(const []),
      outputsDir: Directory('${tmp.path}/outputs'),
    );
    expect(r, isNotNull);
    final project = buildChainDefaultProject();
    final result = await bare.run(
      project: project,
      input: 'پایتخت فرانسه کجاست؟',
      approvalGate: (_) async => true,
    );
    expect(result.detectedLang, 'fa');
    expect(result.intent, 'question'); // ؟ heuristic
    expect(result.finalText, 'پایتخت فرانسه کجاست؟'); // untouched
    final notes = result.traces.map((t) => t.note ?? '').join(' ');
    expect(notes, contains('وصل نیست'));
  });
}

/// A FakeModelProvider that also reports the requests it saw.
class _CapturingProvider extends FakeModelProvider {
  _CapturingProvider(super.script, {required this.onRequest});

  final void Function(ModelRequest) onRequest;

  @override
  Future<ModelResponse> complete(
      ModelConfig config, ModelRequest request) async {
    onRequest(request);
    return super.complete(config, request);
  }
}
