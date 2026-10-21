import 'package:flutter/widgets.dart';

/// UI strings in Persian (fa) and English (en) for the studio chrome
/// and the main screens. The chosen locale ALSO drives the whole
/// layout direction through flutter_localizations: fa → RTL,
/// en → LTR (the v1.0.0 app had no locale at all, so everything was
/// forced LTR — the owner's «همه‌ش چپ‌چینه» report).
///
/// Screens not yet migrated fall back to their Persian strings, which
/// still render correctly under the fa locale; migration proceeds
/// screen by screen with each screen's other scheduled work.
class S {
  const S(this.languageCode);

  final String languageCode;

  bool get fa => languageCode != 'en';

  static S of(BuildContext context) =>
      S(Localizations.localeOf(context).languageCode);

  // Shell
  String get studio => fa ? 'استودیو' : 'Studio';
  String get projects => fa ? 'پروژه‌ها' : 'Projects';
  String get agentEditor => fa ? 'ویرایشگر ایجنت' : 'Agent Editor';
  String get testConsole => fa ? 'کنسول تست' : 'Test Console';
  String get devicesAndSync => fa ? 'دستگاه‌ها و سینک' : 'Devices & Sync';
  String get training => fa ? 'آموزش مدل' : 'Model Training';
  String get settings => fa ? 'تنظیمات' : 'Settings';

  // Appearance & language (Settings)
  String get appearanceAndLanguage =>
      fa ? 'ظاهر و زبان' : 'Appearance & language';
  String get language => fa ? 'زبان برنامه' : 'App language';
  String get persian => 'فارسی';
  String get english => 'English';
  String get theme => fa ? 'تم' : 'Theme';
  String get themeSystem => fa ? 'خودکار (سیستم)' : 'System';
  String get themeLight => fa ? 'روشن' : 'Light';
  String get themeDark => fa ? 'تیره' : 'Dark';

  // Projects screen
  String get agentProjects => fa ? 'پروژه‌های ایجنت' : 'Agent Projects';
  String get newProject => fa ? 'پروژهٔ جدید' : 'New Project';
  String get importProject => fa ? 'وارد کردن' : 'Import';
  String get projectName => fa ? 'نام پروژه' : 'Project name';
  String get cancel => fa ? 'لغو' : 'Cancel';
  String get create => fa ? 'ساختن' : 'Create';
  String get delete => fa ? 'حذف' : 'Delete';
  String get deleteProject => fa ? 'حذف پروژه' : 'Delete Project';
  String deleteProjectConfirm(String name) =>
      fa ? 'پروژهٔ «$name» حذف شود؟' : 'Delete project “$name”?';
  String get noProjectsYet => fa ? 'هنوز پروژه‌ای نداری' : 'No projects yet';
  String get noProjectsHint => fa
      ? 'با «پروژهٔ جدید» اولین پروژهٔ ایجنتت را بساز.'
      : 'Create your first agent project with “New Project”.';
  String exportDone(String file) => fa
      ? 'خروجی گرفته شد: $file (پوشهٔ exports)'
      : 'Exported: $file (exports folder)';
  String exportError(Object e) =>
      fa ? 'خطا در خروجی گرفتن: $e' : 'Export failed: $e';
  String get importTitle => fa ? 'وارد کردن پروژه' : 'Import Project';
  String get importEmpty => fa
      ? 'آرشیوی در پوشهٔ exports نیست. اول روی یک دستگاه خروجی بگیر و فایل .cairn.zip را اینجا بگذار.'
      : 'No archive in the exports folder. Export one on a device first and put the .cairn.zip file here.';
  String imported(String name) =>
      fa ? 'پروژهٔ «$name» وارد شد' : 'Project “$name” imported';
  String loadError(Object e) =>
      fa ? 'خطا در خواندن پروژه‌ها: $e' : 'Error loading projects: $e';
  String agentsAndLastChange(int count, String date) => fa
      ? '$count ایجنت · آخرین تغییر: $date'
      : '$count agent(s) · Last change: $date';
  String get exportTooltip => fa ? 'خروجی (.cairn.zip)' : 'Export (.cairn.zip)';
  String get deleteProjectTooltip => fa ? 'حذف پروژه' : 'Delete project';
}
