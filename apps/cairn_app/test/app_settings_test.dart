import 'dart:io';

import 'package:cairn_app/studio/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app settings round-trip through the store', () async {
    final dir = await Directory.systemTemp.createTemp('cairn_settings_');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppSettingsStore(dir);

    // Missing file → defaults (Persian, system theme).
    final initial = await store.load();
    expect(initial.languageCode, 'fa');
    expect(initial.themeMode, 'system');
    expect(initial.themeModeValue, ThemeMode.system);

    await store.save(const AppSettings(languageCode: 'en', themeMode: 'dark'));
    final loaded = await store.load();
    expect(loaded.languageCode, 'en');
    expect(loaded.themeMode, 'dark');
    expect(loaded.themeModeValue, ThemeMode.dark);
  });

  test('corrupt settings file falls back to defaults', () async {
    final dir = await Directory.systemTemp.createTemp('cairn_settings_');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/app_settings.json').writeAsString('not json');
    final loaded = await AppSettingsStore(dir).load();
    expect(loaded.languageCode, 'fa');
    expect(loaded.themeModeValue, ThemeMode.system);
  });
}
