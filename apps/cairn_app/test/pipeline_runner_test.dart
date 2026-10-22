import 'dart:io';

import 'package:cairn_app/studio/pipeline_runner.dart';
import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end chain runs with REAL trained smart models (the bundled
/// corpora) and a scripted provider for the LLM slot. Verifies the
/// owner's architecture: detect → translate → interpret → manage →
/// answer → translate back, with honest fallbacks when no smart
/// model exists.
void main() {
  late Directory tmp;
  late SmartModelStore store;

  Future<void> trainAll() async {
    final lang = TextClassifier(labels: const ['fa', 'en']);
    lang.train(langDetectCorpus, epochs: 40);
    await store.save(SmartModel(
      id: 'langdetect:t',
      name: 'تشخیص زبان',
      kind: SmartModelKind.langDetect,
      createdAtIso: '2026-10-22T00:00:00.000Z',
      metrics: const {},
      payloadJson: lang.toJson(),
    ));
    final intent = TextClassifier(
        labels: const ['question', 'task', 'chat', 'translate']);
    intent.train(intentCorpus, epochs: 60);
    await store.save(SmartModel(
      id: 'intent:t',
      name: 'مفسر',
      kind: SmartModelKind.intent,
      createdAtIso: '2026-10-22T00:00:00.000Z',
      metrics: const {},
      payloadJson: intent.toJson(),
    ));
    await store.save(SmartModel(
      id: 'translator:t',
      name: 'مترجم',
      kind: SmartModelKind.translator,
      createdAtIso: '2026-10-22T00:00:00.000Z',
      metrics: const {},
      payloadJson: PhraseTranslator.bundled().toJson(),
    ));
  }

  PipelineRunner runner(List<String> script) => PipelineRunner(
        smartStore: store,
        providerFor: (agent, {override}) => FakeModelProvider(script),
        registry: ToolRegistry(),
        skillRegistry: SkillRegistry(const []),
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cairn_chain_test');
    store = SmartModelStore(tmp);
  });

  tearDown(() => tmp.delete(recursive: true));

  test('persian question flows through the whole chain to the LLM answer',
      () async {
    await trainAll();
    final project = buildChainDefaultProject();
    final result = await runner(['Paris is the capital of France.']).run(
      project: project,
      input: 'پایتخت فرانسه کجاست؟',
      approvalGate: (_) async => true,
    );
    expect(result.detectedLang, 'fa');
    expect(result.intent, 'question');
    expect(result.finalText, contains('Paris'));
    final kinds = result.traces.map((t) => t.kind).toList();
    expect(kinds, containsAllInOrder([
      PipelineKind.detect,
      PipelineKind.translateIn,
      PipelineKind.interpret,
      PipelineKind.manage,
      PipelineKind.answer,
    ]));
  });

  test('english chat skips translation and answers directly', () async {
    await trainAll();
    final project = buildChainDefaultProject();
    final result = await runner(['I am fine, thank you!']).run(
      project: project,
      input: 'Hello, how are you?',
      approvalGate: (_) async => true,
    );
    expect(result.detectedLang, 'en');
    expect(result.intent, 'chat');
    expect(result.finalText, 'I am fine, thank you!');
  });

  test('without any models the chain runs on labeled fallbacks only',
      () async {
    final project = buildChainDefaultProject();
    final bare = PipelineRunner(
      smartStore: store,
      providerFor: (agent, {override}) => null, // nothing configured
      registry: ToolRegistry(),
      skillRegistry: SkillRegistry(const []),
    );
    final result = await bare.run(
      project: project,
      input: 'پایتخت فرانسه کجاست؟',
      approvalGate: (_) async => true,
    );
    expect(result.detectedLang, 'fa'); // script heuristic
    expect(result.intent, 'question'); // ؟ heuristic
    // No translator, no LLM: the chain must NOT fabricate an answer.
    expect(result.finalText, isEmpty);
    // The fallbacks announce themselves honestly in the trace.
    final notes = result.traces.map((t) => t.note ?? '').join(' ');
    expect(notes, contains('وصل نیست'));
  });
}
