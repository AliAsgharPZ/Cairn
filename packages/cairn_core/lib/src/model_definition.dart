import 'ids.dart';

/// The roles a model can have in Cairn (v1.3). The owner's model of
/// the world, made literal: EVERYTHING is a model with a role —
/// including agents ("ایجنت هم یک نوع مدل هست"). A project's
/// flowchart is a line of roles; each step binds a model definition
/// of that role; any open-source model or AI API can fill any role.
class ModelRole {
  /// A large language model: answers and writes text.
  static const String llm = 'llm';

  /// A software agent: does work in/with a piece of software, using
  /// instructions, tools and lessons the owner taught it.
  static const String agent = 'agent';

  /// Translates between Persian and English.
  static const String translator = 'translator';

  /// Routes requests to the right next step.
  static const String manager = 'manager';

  /// Understands what the user wants (intent).
  static const String interpreter = 'interpreter';

  /// Generates images.
  static const String image = 'image';

  /// Generates video.
  static const String video = 'video';

  /// Writes and fixes code.
  static const String coder = 'coder';

  /// Voice and music: speech/music generation.
  static const String audio = 'audio';

  static const List<String> all = [
    llm,
    agent,
    translator,
    manager,
    interpreter,
    image,
    video,
    coder,
    audio,
  ];
}

/// One lesson the owner taught an agent-role model by demonstration:
/// "this is how I do it" — a title, what they did (in their words),
/// and optionally a screenshot they attached. Lessons are injected
/// into the agent's instructions when it runs: the app cannot watch
/// other apps (Android forbids it without accessibility tricks), so
/// learning happens through these demonstrations the owner gives.
class AgentLesson {
  AgentLesson({
    String? id,
    required this.title,
    required this.details,
    this.imagePath,
    DateTime? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now().toUtc();

  final String id;
  final String title;
  final String details;
  final String? imagePath;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'details': details,
        if (imagePath != null) 'imagePath': imagePath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AgentLesson.fromJson(Map<String, Object?> json) => AgentLesson(
        id: json['id'] as String?,
        title: json['title'] as String? ?? '',
        details: json['details'] as String? ?? '',
        imagePath: json['imagePath'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

/// A user-defined model: a name, a ROLE, and where it lives — any
/// configured provider (OpenAI-compatible APIs, Anthropic, a local
/// Ollama serving open-source models like Gemma, or a locally
/// trained model). The definition is deliberately provider-shaped,
/// not vendor-shaped: swapping the underlying model never touches
/// the flowchart that uses it.
class ModelDefinition {
  ModelDefinition({
    String? id,
    required this.name,
    required this.role,
    this.providerId = 'ollama',
    this.modelId = '',
    this.description = '',
    this.targetSoftware = '',
    this.instructions = '',
    this.toolIds = const [],
    List<AgentLesson>? lessons,
    DateTime? createdAt,
  })  : id = id ?? newId(),
        lessons = lessons ?? [],
        createdAt = createdAt ?? DateTime.now().toUtc();

  final String id;
  String name;

  /// One of [ModelRole].
  String role;

  /// ProviderConfig id: 'ollama', 'openai-compatible', 'anthropic',
  /// 'local-trained', or any custom configured provider id.
  String providerId;

  /// The provider's model name (e.g. 'gemma3', 'gpt-4o-mini', or a
  /// locally trained model's registry name).
  String modelId;

  /// In the owner's words: what this model does.
  String description;

  /// Agent role only: the software it works with (e.g. 'Figma').
  String targetSoftware;

  /// Agent/coder roles: the system instructions.
  String instructions;

  /// Agent role: which built-in tools it may use.
  List<String> toolIds;

  /// Agent role: demonstrations the owner taught it.
  final List<AgentLesson> lessons;

  final DateTime createdAt;

  /// The effective system prompt for running this model: its own
  /// instructions plus everything the owner taught it.
  String get effectiveInstructions {
    if (lessons.isEmpty) return instructions;
    final buffer = StringBuffer(instructions);
    buffer.writeln('\n\nدرس‌هایی که کاربر به تو یاد داده است:');
    for (final lesson in lessons) {
      buffer.writeln('- ${lesson.title}: ${lesson.details}');
    }
    return buffer.toString();
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'providerId': providerId,
        'modelId': modelId,
        'description': description,
        'targetSoftware': targetSoftware,
        'instructions': instructions,
        'toolIds': toolIds,
        'lessons': lessons.map((l) => l.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory ModelDefinition.fromJson(Map<String, Object?> json) =>
      ModelDefinition(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? ModelRole.llm,
        providerId: json['providerId'] as String? ?? 'ollama',
        modelId: json['modelId'] as String? ?? '',
        description: json['description'] as String? ?? '',
        targetSoftware: json['targetSoftware'] as String? ?? '',
        instructions: json['instructions'] as String? ?? '',
        toolIds:
            (json['toolIds'] as List? ?? const []).map((e) => '$e').toList(),
        lessons: (json['lessons'] as List? ?? const [])
            .map((e) =>
                AgentLesson.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
