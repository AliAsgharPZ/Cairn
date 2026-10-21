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
  String importError(Object e) =>
      fa ? 'خطا در وارد کردن پروژه: $e' : 'Import failed: $e';
  String outputKind(String kind) =>
      kind == 'model' ? (fa ? 'مدل' : 'model') : kind;
  String projectOutputs(String names) =>
      fa ? 'خروجی‌ها: $names' : 'Outputs: $names';
  String get trainIntro => fa
      ? 'اینجا خودت یه مدل کوچیک می‌سازی و آموزش می‌دی — از روی مثال‌هایی که خودت می‌دی یاد می‌گیره.'
      : 'Here you build and train a small model of your own — it learns from examples you give it.';
  String get trainGuideTitle =>
      fa ? 'این صفحه چیه؟ راهنمای خیلی ساده' : 'What is this page? The simple guide';
  String get trainGuideBody => fa
      ? 'مدل یعنی یه مغز کوچیکِ مصنوعی که از روی مثال‌ها یاد می‌گیره کلمهٔ بعدی رو حدس بزنه — مثل بچه‌ای که با شنیدن جمله‌ها حرف‌زدن یاد می‌گیره.\n\n'
          'قدم‌ها:\n'
          '۱) اسم و توانایی مدل رو انتخاب کن (مثلاً فارسی و گفت‌وگو).\n'
          '۲) مثال بده: هر خط یه جمله. هرچی مثال بهتر و بیشتر، مغز بهتر یاد می‌گیره.\n'
          '۳) «شروع آموزش» رو بزن و صبر کن: مغز مثال‌ها رو بارها می‌خونه. عدد «زیان» اشتباهاشه — باید کم و کمتر بشه.\n'
          '۴) وقتی آموزش تموم شد، مدل خودش می‌ره توی قفسهٔ مدل‌ها (بخش ۵) و می‌مونه.\n'
          '۵) آخرش تو بخش ۶ باهاش بازی کن: چند کلمه بنویس تا ادامه‌ش رو حدس بزنه.\n\n'
          'صادقانه: این یه مغز کوچیکه برای یادگرفتن و تجربه‌کردن — ChatGPT نیست و جمله‌های خیلی درست نمی‌سازه.'
      : 'A model is a small artificial brain that learns from examples to guess the next word — like a child learning to talk by hearing sentences.\n\n'
          'Steps:\n'
          '1) Pick a name and what it should be good at (e.g. Persian, chatting).\n'
          '2) Give examples: one sentence per line. Better and more examples = a better brain.\n'
          '3) Press "Start training" and wait: the brain re-reads the examples many times. The "loss" number is its mistakes — it should keep shrinking.\n'
          '4) When training finishes, the model lands on the model shelf (section 5) and stays there.\n'
          '5) Finally, play with it in section 6: type a few words and let it guess the rest.\n\n'
          'Honestly: this is a tiny brain for learning and experimenting — it is not ChatGPT and will not write great sentences.';
  String get trainSampleButton =>
      fa ? 'یه مثال آماده بذار' : 'Fill a ready sample';
  String get trainArchHelp => fa
      ? 'پنهان = اندازهٔ مغز (بزرگ‌تر یعنی باهوش‌تر ولی کندتر) — بافت = چند کلمهٔ قبلی رو یادش می‌مونه — دوره = چند بار کل مثال‌ها رو از اول تا آخر می‌خونه. برای شروع همون پیش‌فرض‌ها (۳۲، ۳، ۳۰) خوبه، دست نزن.'
      : 'Hidden = brain size (bigger means smarter but slower) — Context = how many previous words it remembers — Epochs = how many times it re-reads all the examples. The defaults (32, 3, 30) are a good start — leave them.';
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
