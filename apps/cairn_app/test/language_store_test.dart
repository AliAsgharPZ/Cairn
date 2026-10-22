import 'dart:io';

import 'package:cairn_app/studio/language_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cairn_lang_test');
  });
  tearDown(() => tmp.delete(recursive: true));

  test('built-ins are always there; custom languages persist', () async {
    final store = LanguageStore(tmp);
    var langs = await store.list();
    expect(langs.map((l) => l.code), containsAll(['fa', 'en']));
    expect(langs.every((l) => l.builtin || false) || langs.length == 2,
        isTrue);

    await store.add(const AppLanguage(
      code: 'de',
      name: 'Deutsch',
      englishName: 'German',
    ));
    await store.add(const AppLanguage(
      code: 'ar',
      name: 'العربية',
      englishName: 'Arabic',
      rtl: true,
    ));
    langs = await LanguageStore(tmp).list(); // fresh instance: persisted
    expect(langs.map((l) => l.code), ['fa', 'en', 'de', 'ar']);
    final german = langs.firstWhere((l) => l.code == 'de');
    expect(german.builtin, isFalse);
    expect(languageEnglishName(langs, 'de'), 'German');
    expect(languageEnglishName(langs, 'xx'), 'xx'); // readable fallback

    await store.remove('de');
    langs = await store.list();
    expect(langs.map((l) => l.code), ['fa', 'en', 'ar']);

    // Built-ins cannot be removed.
    await store.remove('fa');
    langs = await store.list();
    expect(langs.map((l) => l.code), contains('fa'));
  });
}
