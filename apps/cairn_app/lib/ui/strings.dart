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
  // Test console
  String get cApprovePlan => fa ? 'تأیید اجرای پلن' : 'Approve plan execution';
  String get cApproveTool => fa ? 'تأیید فراخوانی ابزار' : 'Approve tool call';
  String cPlanBody(String? d) => fa
      ? 'ایجنت می‌خواهد این هدف را اجرا کند:\n\n${d ?? ''}'
      : 'The agent wants to run this goal:\n\n${d ?? ''}';
  String cToolBody(String? toolId, String? d) => fa
      ? 'ابزار «${toolId ?? ''}» برای این گام لازم است:\n\n${d ?? ''}'
      : 'The tool "${toolId ?? ''}" is needed for this step:\n\n${d ?? ''}';
  String get cReject => fa ? 'رد' : 'Reject';
  String get cApprove => fa ? 'تأیید' : 'Approve';
  String get cWriteInstructionFirst =>
      fa ? 'اول یک دستور بنویس' : 'Write an instruction first';
  String cProviderNotConfigured(String id) => fa
      ? 'ارائه‌دهندهٔ «$id» پیکربندی نشده است. از بخش تنظیمات اضافه‌اش کن.'
      : 'Provider "$id" is not configured. Add it in Settings.';
  String cUnexpectedError(String e) =>
      fa ? 'خطای غیرمنتظره: $e' : 'Unexpected error: $e';
  String cBalanceNote(int n) => fa
      ? 'تقسیم بار روشن است: گام‌های ابزار بین این دستگاه و $n دستگاه جفت‌شده پخش می‌شوند (اول شبکهٔ محلی، اینترنت آخر).'
      : 'Load balancing is on: tool steps are shared between this device and $n paired device(s) — local network first, internet last.';
  String get cOpenProjectFirst => fa
      ? 'اول از بخش «پروژه‌ها» یک پروژه را باز کن.'
      : 'Open a project from the Projects section first.';
  String get cNoAgentYet => fa
      ? 'این پروژه هنوز ایجنتی ندارد؛ از «ویرایشگر ایجنت» یکی بساز.'
      : 'This project has no agent yet — create one in the Agent Editor.';
  String get cTitle => fa ? 'کنسول تست' : 'Test Console';
  String get cAgent => fa ? 'ایجنت' : 'Agent';
  String cModelLine(String p, String m) =>
      fa ? 'مدل: $p / $m' : 'Model: $p / $m';
  String get cInstruction => fa ? 'دستور برای ایجنت' : 'Instruction for the agent';
  String get cInstructionHint => fa
      ? 'مثلاً: ساعت الان رو بگو و بعد ۱۲ × ۸ رو حساب کن'
      : 'e.g. Tell me the time, then compute 12 × 8';
  String get cBalanceTitle =>
      fa ? 'تقسیم بار بین دستگاه‌های جفت‌شده' : 'Load balancing across paired devices';
  String get cBalanceSubtitle => fa
      ? 'گام‌های ابزار بین این دستگاه و دستگاه‌های جفت‌شده‌ات پخش می‌شن — هر دستگاهی می‌تونه به بقیه کمک کنه؛ اول شبکهٔ محلی، اینترنت آخرین گزینه‌ست.'
      : 'Tool steps are shared between this device and your paired devices — any device can help the others; local network first, internet is the last resort.';
  String get cRun => fa ? 'اجرا' : 'Run';
  String get cCancelRun => fa ? 'لغو اجرا' : 'Cancel run';
  String get cGoSettings => fa ? 'رفتن به تنظیمات' : 'Go to Settings';
  String cCompleted(String summary) =>
      fa ? '✅ تکمیل شد — $summary' : '✅ Completed — $summary';
  String get cRunning => fa ? 'در حال اجرا…' : 'Running…';
  String get cEventsHint => fa
      ? 'رویدادهای اجرا (پلن، گام‌ها، تأییدها) اینجا زنده نمایش داده می‌شوند.'
      : 'Run events (plan, steps, approvals) appear here live.';

  // Devices & sync (inside Settings)
  String dInvalidOffer(String m) =>
      fa ? 'پیشنهاد نامعتبر است: $m' : 'Invalid offer: $m';
  String get dPaired => fa ? 'دستگاه جفت شد.' : 'Device paired.';
  String get dEnterHostFirst =>
      fa ? 'اول نشانی (IP) دستگاه را وارد کن.' : 'Enter the device address (IP) first.';
  String get dSyncing => fa ? 'در حال سینک…' : 'Syncing…';
  String dSyncDone(int p, int sk, int c, int del) => fa
      ? 'سینک انجام شد — پروژه: $p، مهارت: $sk، تعارض تازه: $c، حذف‌شده: $del'
      : 'Sync done — projects: $p, skills: $sk, new conflicts: $c, deleted: $del';
  String dSyncFailed(String e) => fa ? 'سینک ناموفق بود: $e' : 'Sync failed: $e';
  String dIncomingSync(int p, int c, int del) => fa
      ? 'سینک ورودی انجام شد — پروژه: $p، تعارض: $c، حذف: $del'
      : 'Incoming sync done — projects: $p, conflicts: $c, deleted: $del';
  String dSyncServerFailed(String e) =>
      fa ? 'سرور سینک شروع نشد: $e' : 'Sync server did not start: $e';
  String get dOverflowServerOn =>
      fa ? 'سرور سرریز روشن شد (پورت ۴۷۸۰۱).' : 'Overflow server is on (port 47801).';
  String dOverflowServerFailed(String e) =>
      fa ? 'سرور سرریز شروع نشد: $e' : 'Overflow server did not start: $e';
  String get dFetchingCaps => fa ? 'در حال گرفتن توانمندی‌ها…' : 'Fetching capabilities…';
  String get dNoCaps =>
      fa ? 'دستگاه مقابل توانمندی منتشر نمی‌کند.' : 'The other device does not publish capabilities.';
  String dBlocked(String unmet) => fa ? 'مسدود: $unmet' : 'Blocked: $unmet';
  String get dRunsHere => fa ? 'روی همین دستگاه اجرا می‌شود' : 'Runs on this device';
  String get dRunsThere =>
      fa ? 'روی دستگاه مقابل اجرا می‌شود (تقسیم بار)' : 'Runs on the other device (load balancing)';
  String get dHas => fa ? 'دارد' : 'yes';
  String get dHasNot => fa ? 'ندارد' : 'no';
  String dCapsLine(String name, int cpu, int ram, String gpu, String heavy, String gpuStep) => fa
      ? 'توانمندی‌های $name: $cpu هسته، $ram MB RAM، GPU: $gpu — مرحلهٔ سنگین RAM: $heavy؛ مرحلهٔ GPU: $gpuStep'
      : 'Capabilities of $name: $cpu cores, $ram MB RAM, GPU: $gpu — heavy RAM step: $heavy; GPU step: $gpuStep';
  String dCapsFailed(String e) =>
      fa ? 'گرفتن توانمندی‌ها ناموفق بود: $e' : 'Fetching capabilities failed: $e';
  String get dThisDevice => fa ? 'این دستگاه' : 'This device';
  String dDeviceId(String id) => fa ? 'شناسه: $id' : 'ID: $id';
  String get dDisplayName => fa ? 'نام نمایشی' : 'Display name';
  String get dSave => fa ? 'ذخیره' : 'Save';
  String get dPairNew => fa ? 'جفت‌سازی دستگاه تازه' : 'Pair a new device';
  String get dPairHelp => fa
      ? 'در یک دستگاه «ساخت پیشنهاد» را بزن و متنش را اینجا بچسبان؛ در دستگاه دیگر هم همین کار را برعکس انجام بده. کد ۶ رقمی باید در هر دو دستگاه یکسان باشد.'
      : 'On one device tap "Create pairing offer" and paste its text here; do the reverse on the other device. The 6-digit code must be identical on both.';
  String get dMakeOffer => fa ? 'ساخت پیشنهاد جفت‌سازی' : 'Create pairing offer';
  String get dCopyOffer => fa ? 'کپی پیشنهاد' : 'Copy offer';
  String get dPasteOffer =>
      fa ? 'پیشنهاد دستگاه دیگر را اینجا بچسبان' : 'Paste the other device\'s offer here';
  String get dInspectOffer => fa ? 'بررسی پیشنهاد' : 'Inspect offer';
  String get dSasLabel => fa
      ? 'کد تأیید (باید با دستگاه دیگر یکسان باشد):'
      : 'Confirmation code (must match the other device):';
  String get dPairConfirm =>
      fa ? 'کدها یکسان‌اند — جفت کن' : 'Codes match — pair';
  String get dPairedDevices => fa ? 'دستگاه‌های جفت‌شده' : 'Paired devices';
  String get dNoPairedYet =>
      fa ? 'هنوز دستگاهی جفت نشده است.' : 'No device is paired yet.';
  String get dHostLabel => fa ? 'نشانی IP / Tailscale' : 'IP / Tailscale address';
  String get dSyncNow => fa ? 'سینک کن' : 'Sync now';
  String get dCapabilities => fa ? 'توانمندی‌ها' : 'Capabilities';
  String get dUnpair => fa ? 'لغو جفت‌شدن' : 'Unpair';
  String get dSyncServerTitle => fa
      ? 'سرور سینک (پذیرش سینک از دستگاه جفت‌شده)'
      : 'Sync server (accept sync from paired devices)';
  String get dSyncServerSub =>
      fa ? 'پورت ۴۷۸۰۰ — فقط دستگاه‌های جفت‌شده' : 'Port 47800 — paired devices only';
  String get dOverflowTitle => fa ? 'سرریز محاسباتی' : 'Compute overflow';
  String get dSpecsHelp => fa
      ? 'مشخصات این دستگاه برای مسیریابی مراحل سنگین. تعداد هستهٔ CPU خودکار خوانده می‌شود؛ RAM و دیسک و GPU را خودت وارد کن (از داخل دارت قابل اندازه‌گیری مطمئن نیستند).'
      : 'This device\'s specs for routing heavy steps. CPU cores are read automatically; enter RAM, disk and GPU yourself (they cannot be measured reliably from Dart).';
  String get dRamLabel => fa ? 'RAM (مگابایت)' : 'RAM (MB)';
  String get dDiskLabel => fa ? 'دیسک آزاد (مگابایت)' : 'Free disk (MB)';
  String get dHasGpu => fa ? 'این دستگاه GPU دارد' : 'This device has a GPU';
  String get dSpecsSaved => fa ? 'مشخصات دستگاه ذخیره شد.' : 'Device specs saved.';
  String get dSaveSpecs => fa ? 'ذخیرهٔ مشخصات' : 'Save specs';
  String get dOverflowServerTitle => fa
      ? 'سرور سرریز (اجرای ابزارهای این دستگاه برای جفت‌شده‌ها)'
      : 'Overflow server (run this device\'s tools for paired devices)';
  String get dOverflowServerSub => fa
      ? 'پورت ۴۷۸۰۱ — مقصد همیشه دوباره اعتبارسنجی می‌کند'
      : 'Port 47801 — the destination always re-validates';
  String get dRemoteSensitiveTitle =>
      fa ? 'اجازهٔ اجرای راه‌دور ابزارهای حساس' : 'Allow remote execution of sensitive tools';
  String get dRemoteSensitiveSub => fa
      ? 'پیش‌فرض خاموش است؛ با تغییرش سرور سرریز را خاموش و روشن کن تا اعمال شود'
      : 'Off by default; after changing it, toggle the overflow server off and on to apply';
  String dTrashLine(int n) => fa
      ? 'سطل زبالهٔ سینک: $n مورد حذف‌شده (۳۰ روز نگه داشته می‌شود).'
      : 'Sync trash: $n deleted item(s) (kept for 30 days).';

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
