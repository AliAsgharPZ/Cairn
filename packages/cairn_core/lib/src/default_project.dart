import 'pipeline.dart';
import 'project.dart';

/// The ready-made CHAIN project scaffold: an empty flowchart with
/// the default role steps and NO agents and NO models.
///
/// v1.4 (owner's order): every pre-written agent that used to ship
/// here — the Figma design agent, the general assistant, the Flow-1
/// reference agent — is REMOVED, together with every dataset/model
/// the assistant authored or trained. Cairn ships empty: the models
/// and agents in it are the owner's own creations or connections.
/// This scaffold is pure structure (the flowchart skeleton); the
/// owner binds their own models to its steps.
AgentProject buildChainDefaultProject() {
  return AgentProject(
    id: 'chain-default-project',
    name: 'پروژهٔ زنجیره‌ای من',
    description: 'اسکلت فلوچارت: قدم‌ها را بچین و برای هر قدم مدل '
        'خودت را وصل کن. هیچ مدل یا ایجنت آماده‌ای داخلش نیست.',
    agents: const [],
    pipeline: defaultPipeline(),
  );
}
