import 'dart:convert';
import 'dart:io';

/// A language the app can work in (v1.4).
///
/// Cairn makes NO Persian/English assumption: flows, translator
/// steps and projects name languages from this registry. Two
/// languages are built in (Persian, English — the studio's own UI
/// languages); the owner can add ANY custom language and it becomes
/// selectable everywhere a language is chosen. [englishName] is
/// what models are told in prompts ("translate to German"), [name]
/// is the display name, [code] a short id the owner picks (de, ar…).
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.name,
    required this.englishName,
    this.rtl = false,
    this.builtin = false,
  });

  final String code;
  final String name;
  final String englishName;
  final bool rtl;
  final bool builtin;

  Map<String, Object?> toJson() => {
        'code': code,
        'name': name,
        'englishName': englishName,
        'rtl': rtl,
      };

  factory AppLanguage.fromJson(Map<String, Object?> json) => AppLanguage(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        englishName: json['englishName'] as String? ?? '',
        rtl: json['rtl'] as bool? ?? false,
      );
}

/// The language registry, persisted as languages.json in the studio
/// directory (custom languages only; built-ins are merged in code).
class LanguageStore {
  LanguageStore(this.baseDir);

  final Directory baseDir;

  static const builtins = [
    AppLanguage(
      code: 'fa',
      name: 'فارسی',
      englishName: 'Persian',
      rtl: true,
      builtin: true,
    ),
    AppLanguage(
      code: 'en',
      name: 'English',
      englishName: 'English',
      builtin: true,
    ),
  ];

  File get _file => File('${baseDir.path}/languages.json');

  Future<List<AppLanguage>> list() async {
    final custom = <AppLanguage>[];
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is List) {
          for (final e in decoded) {
            final lang =
                AppLanguage.fromJson((e as Map).cast<String, Object?>());
            if (lang.code.isNotEmpty &&
                !builtins.any((b) => b.code == lang.code)) {
              custom.add(lang);
            }
          }
        }
      }
    } catch (_) {
      // A broken registry file must never break the studio.
    }
    return [...builtins, ...custom];
  }

  Future<void> _saveCustom(List<AppLanguage> custom) async {
    await baseDir.create(recursive: true);
    await _file.writeAsString(
      jsonEncode([for (final l in custom) l.toJson()]),
      flush: true,
    );
  }

  /// Adds (or replaces, by code) a custom language.
  Future<void> add(AppLanguage language) async {
    final all = await list();
    final custom = [
      for (final l in all)
        if (!l.builtin && l.code != language.code) l,
      AppLanguage(
        code: language.code,
        name: language.name,
        englishName: language.englishName,
        rtl: language.rtl,
      ),
    ];
    await _saveCustom(custom);
  }

  /// Removes a custom language (built-ins cannot be removed).
  Future<void> remove(String code) async {
    final all = await list();
    await _saveCustom([
      for (final l in all)
        if (!l.builtin && l.code != code) l,
    ]);
  }
}

/// The name a model should be told for [code] ("German"), falling
/// back to the code itself; '' and unknown codes stay readable.
String languageEnglishName(List<AppLanguage> languages, String code) {
  for (final l in languages) {
    if (l.code == code) return l.englishName;
  }
  return code;
}
