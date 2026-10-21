import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// The app's own settings: UI language and theme. These are the first
/// entries of the real Settings page — persisted in `app_settings.json`
/// in the app data dir (atomic tmp+rename write, like the other
/// stores). Defaults: Persian, follow the system theme.
class AppSettings {
  const AppSettings({this.languageCode = 'fa', this.themeMode = 'system'});

  /// 'fa' | 'en'
  final String languageCode;

  /// 'system' | 'light' | 'dark'
  final String themeMode;

  ThemeMode get themeModeValue => switch (themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  AppSettings copyWith({String? languageCode, String? themeMode}) =>
      AppSettings(
        languageCode: languageCode ?? this.languageCode,
        themeMode: themeMode ?? this.themeMode,
      );

  Map<String, Object?> toJson() => {
    'languageCode': languageCode,
    'themeMode': themeMode,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    languageCode: json['languageCode'] as String? ?? 'fa',
    themeMode: json['themeMode'] as String? ?? 'system',
  );
}

class AppSettingsStore {
  AppSettingsStore(this.baseDir);

  final Directory baseDir;

  File get _file => File('${baseDir.path}/app_settings.json');

  Future<AppSettings> load() async {
    try {
      if (!await _file.exists()) return const AppSettings();
      final json = (jsonDecode(await _file.readAsString()) as Map)
          .cast<String, Object?>();
      return AppSettings.fromJson(json);
    } catch (_) {
      // A corrupt settings file must never block startup.
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await baseDir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_file.path);
  }
}
