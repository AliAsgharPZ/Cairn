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
  String get wsProject => fa ? 'پروژه' : 'Project';
  String get wsChain => fa ? 'زنجیره' : 'Chain';
  String get wsAgents => fa ? 'ایجنت‌ها' : 'Agents';
  String get wsRun => fa ? 'اجرا' : 'Run';
  String get wsModels => fa ? 'مدل‌ها' : 'Models';
  String get chainTitle => fa ? 'زنجیرهٔ پردازش این پروژه' : 'This project’s processing chain';
  String get chainHelp => fa
      ? 'درخواست کاربر از این خط رد می‌شود: هر قدم یک کار دارد و مدل خودش را. مدل هر قدم را می‌توانی عوض کنی — بعداً حتی یک مدل بزرگ مثل Gemma را جای هر کدام بگذاری.'
      : 'A user request flows down this line: each step has one job and its own model. You can replace any step’s model — later even with a big model like Gemma.';
  String get chainAddDefault => fa ? 'افزودن زنجیرهٔ پیش‌فرض' : 'Add the default chain';
  String get chainPickProjectFirst => fa
      ? 'اول از بخش «پروژه‌ها» یک پروژه را باز کن.'
      : 'Open a project from “Projects” first.';
  String stepTitle(String kind) => switch (kind) {
        'detect' => fa ? '۱) تشخیص زبان' : '1) Language detection',
        'translateIn' => fa ? '۲) ترجمه به انگلیسی (اگر لازم بود)' : '2) Translate to English (if needed)',
        'interpret' => fa ? '۳) تفسیر درخواست' : '3) Interpret the request',
        'manage' => fa ? '۴) مدیر — مسیریابی' : '4) Manager — routing',
        'agent' => fa ? '۵) اجرای ایجنت' : '5) Agent work',
        'answer' => fa ? '۶) پاسخ با مدل زبانی' : '6) Answer with the LLM',
        'translateBack' => fa ? '۷) ترجمهٔ پاسخ به زبان کاربر' : '7) Translate the answer back',
        _ => kind,
      };
  String stepHelp(String kind) => switch (kind) {
        'detect' => fa
            ? 'مدل کوچک آموزش‌دیده‌ای که فقط می‌گوید متن فارسی است یا انگلیسی.'
            : 'A small trained model whose only job is saying whether the text is Persian or English.',
        'translateIn' => fa
            ? 'اگر متن فارسی بود، به انگلیسی برش می‌گرداند تا بقیهٔ زنجیره راحت کار کنند.'
            : 'If the text is Persian, turns it into English so the rest of the chain works easily.',
        'interpret' => fa
            ? 'مدل مفسر می‌فهمد کاربر چه می‌خواهد: سؤال، کار، گپ یا ترجمه.'
            : 'The interpreter model understands what the user wants: a question, a task, chat, or a translation.',
        'manage' => fa
            ? 'مغز مسیریاب است، مدل سازنده نیست: از روی حرف مفسر تصمیم می‌گیرد درخواست برود پیش ایجنت یا مدل پاسخ.'
            : 'The routing brain, not a generative model: from the interpreter’s verdict it sends the request to the agent or to the answer model.',
        'agent' => fa
            ? 'ایجنت انتخاب‌شده با ابزارها و مهارت‌هایش کار را انجام می‌دهد (فایل، وب، نرم‌افزارها…).'
            : 'The chosen agent does the work with its tools and skills (files, web, software…).',
        'answer' => fa
            ? 'مدل زبانی بزرگ (LLM) جواب متنی را می‌سازد — همین اسلات بعداً به Gemma وصل می‌شود.'
            : 'The large language model (LLM) writes the text answer — this very slot later connects to Gemma.',
        'translateBack' => fa
            ? 'جواب را به زبان خود کاربر برمی‌گرداند تا به همان زبان ببیندش.'
            : 'Turns the answer back into the user’s own language.',
        _ => '',
      };
  String get bindingDefault => fa ? 'پیش‌فرض (جدیدترین مدل آموزش‌دیده)' : 'Default (newest trained model)';
  String get bindingAgent => fa ? 'ایجنت این قدم' : 'Agent for this step';
  String get createChainProject => fa ? 'ساخت پروژهٔ زنجیره‌ای' : 'Create the chain project';
  String get smartTitle => fa ? 'مدل‌های زنجیره (کوچک و آموزش‌پذیر)' : 'Chain models (small & trainable)';
  String get smartHelp => fa
      ? 'این‌ها مدل‌های کوچیکی‌اند که واقعاً همینجا آموزش می‌بینند و روی دستگاهت ذخیره می‌شوند. کارهای سبک زنجیره را انجام می‌دهند؛ برای کار سنگین (ترجمهٔ واقعی، جواب‌های باهوش) بعداً مدل بزرگ وصل می‌کنی.'
      : 'These are small models that are genuinely trained right here and stored on your device. They do the chain’s light jobs; heavy work (real translation, smart answers) takes a big model you connect later.';
  String get trainLangDetect => fa ? 'آموزش مدل تشخیص زبان' : 'Train the language detector';
  String get trainIntent => fa ? 'آموزش مدل مفسر' : 'Train the interpreter';
  String get buildTranslator => fa ? 'ساخت مترجم فارسی↔انگلیسی' : 'Build the fa↔en translator';
  String smartTrained(String acc) => fa ? 'آموزش تمام شد — دقت روی دادهٔ ندیده: $acc' : 'Training done — held-out accuracy: $acc';
  String smartPairs(int n) => fa ? 'مترجم ساخته شد — $n جفت‌جمله' : 'Translator built — $n sentence pairs';
  String get smartNone => fa ? 'هنوز مدلی آموزش نداده‌ای.' : 'No smart model trained yet.';
  String smartMeta(String kind, String metric) => switch (kind) {
        'langdetect' => fa ? 'تشخیص زبان — دقت $metric' : 'Language detector — accuracy $metric',
        'intent' => fa ? 'مفسر — دقت $metric' : 'Interpreter — accuracy $metric',
        'translator' => fa ? 'مترجم — $metric جفت‌جمله' : 'Translator — $metric pairs',
        _ => kind,
      };
  String roleTitle(String role) => switch (role) {
        'llm' => fa ? 'مدل زبانی (LLM)' : 'Language model (LLM)',
        'agent' => fa ? 'ایجنت نرم‌افزار' : 'Software agent',
        'translator' => fa ? 'مترجم' : 'Translator',
        'manager' => fa ? 'مدیر' : 'Manager',
        'interpreter' => fa ? 'مفسر' : 'Interpreter',
        'image' => fa ? 'تصویرساز' : 'Image maker',
        'video' => fa ? 'ویدیوساز' : 'Video maker',
        'coder' => fa ? 'کدنویس' : 'Coder',
        'audio' => fa ? 'صدا و آهنگ‌ساز' : 'Voice & music maker',
        _ => role,
      };
  String roleHelp(String role) => switch (role) {
        'llm' => fa ? 'متن می‌نویسد و جواب می‌دهد.' : 'Writes text and answers.',
        'agent' => fa
            ? 'با دستور و ابزار، توی یک نرم‌افزار کار انجام می‌دهد.'
            : 'Does work in a piece of software, with instructions and tools.',
        'translator' => fa ? 'فارسی و انگلیسی را به هم ترجمه می‌کند.' : 'Translates Persian ↔ English.',
        'manager' => fa ? 'تصمیم می‌گیرد هر درخواست کجا برود.' : 'Decides where each request goes.',
        'interpreter' => fa ? 'می‌فهمد کاربر چه می‌خواهد.' : 'Understands what the user wants.',
        'image' => fa ? 'از روی متن، عکس می‌سازد.' : 'Makes images from text.',
        'video' => fa ? 'از روی متن، ویدیو می‌سازد.' : 'Makes videos from text.',
        'coder' => fa ? 'کد می‌نویسد و درست می‌کند.' : 'Writes and fixes code.',
        'audio' => fa ? 'صدا، گفتار یا آهنگ می‌سازد.' : 'Makes voice, speech or music.',
        _ => '',
      };
  String get modelToolsLabel => fa ? 'ابزارهایش' : 'Its tools';
  String get myModels => fa ? 'مدل‌های من' : 'My models';
  String get myModelsHelp => fa
      ? 'هر مدل یک نقش دارد. مدل را بساز و به یک منبع وصلش کن: مدل متن‌باز روی Ollama، یا یک API. بعد توی فلوچارت پروژه ازش استفاده کن.'
      : 'Every model has a role. Create one and point it at a source: an open-source model on Ollama, or an API. Then use it in a project flowchart.';
  String get createModel => fa ? 'ساخت مدل' : 'Create a model';
  String get modelNameLabel => fa ? 'اسم مدل' : 'Model name';
  String get modelRoleLabel => fa ? 'نقش مدل' : 'Model role';
  String get modelWhatLabel => fa ? 'این مدل چیکار می‌کنه؟' : 'What does this model do?';
  String get modelSourceLabel => fa ? 'منبع (سرویس)' : 'Source (provider)';
  String get modelIdLabel => fa ? 'اسم مدل در آن سرویس' : 'Model name at that source';
  String get modelSoftwareLabel => fa ? 'نرم‌افزاری که باهاش کار می‌کند' : 'Software it works with';
  String get modelInstructionsLabel => fa ? 'دستورهایش (چطور کار کند)' : 'Its instructions (how it works)';
  String get lessonsTitle => fa ? 'درس‌هایی که بهش یاد داده‌ام' : 'Lessons I taught it';
  String get lessonsHelp => fa
      ? 'اپ نمی‌تواند یواشکی کار تو را در برنامه‌های دیگر تماشا کند. عوضش اینجا به ایجنت یاد می‌دهی چطور کار می‌کنی: یک درس بنویس و اگر خواستی عکس صفحه را هم بچسبان.'
      : 'The app cannot secretly watch you work in other apps. Instead, teach the agent here how you work: write a lesson and attach a screenshot if you like.';
  String get addLesson => fa ? 'افزودن درس' : 'Add a lesson';
  String get lessonTitleLabel => fa ? 'عنوان درس' : 'Lesson title';
  String get lessonDetailsLabel => fa ? 'چطور این کار را انجام می‌دهی؟' : 'How do you do this?';
  String get attachScreenshot => fa ? 'چسباندن عکس صفحه' : 'Attach a screenshot';
  String get exportModels => fa ? 'خروجی مدل‌ها' : 'Export models';
  String get importModels => fa ? 'وارد کردن مدل‌ها' : 'Import models';
  String modelsImported(int n) => fa ? '$n مدل وارد شد.' : '$n models imported.';
  String get flowTitle => fa ? 'فلوچارت این پروژه' : 'This project’s flowchart';
  String get flowHelp => fa
      ? 'درخواست از این قدم‌ها رد می‌شود. هر قدم یک نقش است و مدل خودش را دارد — قدم اضافه کن، حذف کن یا جابه‌جا کن.'
      : 'A request flows through these steps. Each step is a role with its own model — add, remove or reorder steps.';
  String get addStep => fa ? 'افزودن قدم' : 'Add a step';
  String get stepModelAuto => fa ? 'خودکار (اولین مدل این نقش)' : 'Automatic (first model of this role)';
  String get noModelForRole => fa ? 'هنوز مدلی با این نقش نساخته‌ای — از تب «مدل‌ها» بسازش.' : 'No model with this role yet — create it in the Models tab.';
  String get runFlow => fa ? 'اجرای فلوچارت' : 'Run the flowchart';
  String get backupTitle => fa ? 'پشتیبان کامل' : 'Full backup';
  String get backupHelp => fa
      ? 'از همه‌چیز (پروژه‌ها، مدل‌ها، دستگاه‌های جفت‌شده) یک فایل پشتیبان بگیر یا برگردان.'
      : 'Back up everything (projects, models, paired devices) into one file, or restore it.';
  String get backupExport => fa ? 'گرفتن پشتیبان' : 'Back up';
  String get backupImport => fa ? 'برگرداندن پشتیبان' : 'Restore';
  String get backupDone => fa ? 'انجام شد.' : 'Done.';
  String get runChain => fa ? 'اجرای فلوچارت' : 'Run the flowchart';
  String get runAgentMode => fa ? 'اجرای ایجنت' : 'Run agent';
  String get chainInputHint => fa ? 'درخواستت را بنویس (فارسی یا انگلیسی)…' : 'Write your request (Persian or English)…';
  String get chainRunButton => fa ? 'اجرا در زنجیره' : 'Run through the chain';
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
  String get netTitle => fa ? 'وضعیت شبکه' : 'Network';
  String get netConnected =>
      fa ? 'متصل به شبکهٔ محلی' : 'Connected to a local network';
  String get netOffline => fa
      ? 'به هیچ شبکه‌ای وصل نیستی — وای‌فای را روشن کن و به همان شبکهٔ دستگاه دیگر وصل شو.'
      : 'Not connected to any network — turn on Wi-Fi and join the same network as your other device.';
  String get netCellularOnly => fa
      ? 'فقط اینترنت همراه (موبایل‌دیتا) داری — این شبکهٔ محلی نیست و دستگاه‌های دیگرت از این راه پیدا نمی‌شوند. به وای‌فای وصل شو.'
      : 'You only have mobile data — that is not a local network and your other devices cannot be found through it. Join a Wi-Fi network.';
  String netYourAddress(String ip) =>
      fa ? 'نشانی این دستگاه در شبکه: $ip' : 'This device’s network address: $ip';
  String get netServersOn => fa
      ? 'سرویس‌های شبکه روشن‌اند: این دستگاه دیده می‌شود و به دستگاه‌های جفت‌شده پاسخ می‌دهد.'
      : 'Network services are on: this device is discoverable and answers paired devices.';
  String get netVisible =>
      fa ? 'دیده‌شدن در شبکه' : 'Visible on the network';
  String get netVisibleSub => fa
      ? 'روشن باشد تا دستگاه‌های دیگرت تو را خودکار پیدا کنند و سینک خودکار کار کند. خاموشش کنی، هیچ‌کس در شبکه تو را نمی‌بیند.'
      : 'Keep on so your other devices find this one automatically and auto-sync works. Off means invisible on the network.';
  String get nearbyTitle => fa ? 'دستگاه‌های اطراف' : 'Nearby devices';
  String get nearbyNone => fa
      ? 'هنوز دستگاهی پیدا نشده — اپ را روی دستگاه دیگرت هم باز کن و چند ثانیه صبر کن.'
      : 'No device found yet — open the app on your other device too and wait a few seconds.';
  String get pairAction => fa ? 'جفت کردن' : 'Pair';
  String get pairedBadge => fa ? 'جفت‌شده' : 'Paired';
  String get pairingSasTitle => fa ? 'کد امنیتی جفت‌شدن' : 'Pairing security code';
  String pairingSasBody(String name, String sas) => fa
      ? 'دستگاه «$name» می‌خواهد جفت شود. اگر روی صفحهٔ آن دستگاه هم دقیقاً همین کد دیده می‌شود، تأیید کن:'
      : '“$name” wants to pair. If that device shows exactly this code too, confirm:';
  String pairingIncoming(String name) => fa
      ? 'درخواست جفت‌شدن از «$name»'
      : 'Pairing request from “$name”';
  String get accept => fa ? 'تأیید و جفت‌کردن' : 'Accept & pair';
  String get reject => fa ? 'رد کردن' : 'Reject';
  String get pairingRejected =>
      fa ? 'جفت‌شدن رد شد یا لغو شد.' : 'Pairing was rejected or cancelled.';
  String pairingFailed(String e) =>
      fa ? 'جفت‌شدن ناموفق بود: $e' : 'Pairing failed: $e';
  String get manualPairTitle =>
      fa ? 'جفت‌کردن دستی (روش قدیمی، بدون کشف شبکه)' : 'Manual pairing (legacy, no discovery)';
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

  // Agent editor
  String get listSep => fa ? '، ' : ', ';
  String get eSkillsManager => fa ? 'مدیریت مهارت‌ها' : 'Manage skills';
  String get eNoSkillsYet => fa ? 'هنوز مهارتی نصب نشده است.' : 'No skill is installed yet.';
  String get eNoTools => fa ? 'بدون ابزار' : 'No tools';
  String get eDeleteSkill => fa ? 'حذف مهارت' : 'Delete skill';
  String get eNewSkill => fa ? 'مهارت تازه' : 'New skill';
  String get eSkillName => fa ? 'نام مهارت' : 'Skill name';
  String get eDescription => fa ? 'توضیح' : 'Description';
  String get eSkillInstructions =>
      fa ? 'دستورالعمل برای ایجنت' : 'Instructions for the agent';
  String get eSkillToolsLabel => fa ? 'ابزارهای این مهارت:' : 'Tools of this skill:';
  String get eClose => fa ? 'بستن' : 'Close';
  String get eCreateSkill => fa ? 'ساختن مهارت' : 'Create skill';
  String get eAgentIncomplete => fa ? 'ایجنت کامل نیست' : 'The agent is incomplete';
  String get eOk => fa ? 'باشه' : 'OK';
  String get eSaved => fa ? 'ایجنت ذخیره شد' : 'Agent saved';
  String get eDeleteAgentTitle => fa ? 'حذف ایجنت' : 'Delete agent';
  String eDeleteAgentBody(String name) => fa
      ? 'ایجنت «$name» از پروژه حذف شود؟'
      : 'Delete agent "$name" from the project?';
  String get eCancel => fa ? 'لغو' : 'Cancel';
  String get eDelete => fa ? 'حذف' : 'Delete';
  String get eSeparateModelTitle =>
      fa ? 'برای این نقش یه مدل جدا می‌خوام' : 'I want a separate model for this role';
  String get eSeparateModelSub => fa
      ? 'خاموش = همان مغز اصلی این کار را هم می‌کند'
      : 'Off = the main brain handles this too';
  String get eProvider => fa ? 'ارائه‌دهنده (Provider)' : 'Provider';
  String get eModelId => fa ? 'شناسهٔ مدل (Model ID)' : 'Model ID';
  String get eOpenProjectEdit => fa
      ? 'اول از بخش «پروژه‌ها» یک پروژه را باز کن تا ایجنت‌هایش را اینجا ویرایش کنی.'
      : 'Open a project from the Projects section first to edit its agents here.';
  String eProjectLine(String name) => fa ? 'پروژه: $name' : 'Project: $name';
  String get eNewAgent => fa ? 'ایجنت جدید' : 'New agent';
  String get eAgentName => fa ? 'نام ایجنت' : 'Agent name';
  String get eSystemPrompt => fa ? 'پرامپت سیستم (System Prompt)' : 'System Prompt';
  String get eRolesTitle => fa ? 'نقش‌ها و مدل‌ها' : 'Roles & models';
  String get eRolesIntro => fa
      ? 'هر ایجنت مثل یه تیم کوچیکه (دقیقاً مثل فلوچارت): هر نقش می‌تونه مدل خودش رو داشته باشه — خارجی (مثل GPT) یا محلی روی دستگاه خودت (مثل Gemma با Ollama).'
      : 'Every agent is a small team (exactly like the flowchart): each role can have its own model — external (like GPT) or local on your own device (like Gemma via Ollama).';
  String get eBrainTitle => fa ? '🧠 مغز اصلی' : '🧠 Main brain';
  String get eBrainDesc => fa
      ? 'مدلی که فکر می‌کند، برنامه می‌ریزد و جواب نهایی را می‌سازد.'
      : 'The model that thinks, plans and produces the final answer.';
  String get eMaxTokens =>
      fa ? 'سقف توکن خروجی (اختیاری)' : 'Max output tokens (optional)';
  String get eTempDefault => fa ? 'دما: پیش‌فرض مدل' : 'Temperature: model default';
  String eTempValue(String v) => fa ? 'دما: $v' : 'Temperature: $v';
  String get eDefault => fa ? 'پیش‌فرض' : 'Default';
  String get eTranslatorTitle => fa ? '🌐 مترجم و آماده‌ساز' : '🌐 Translator & preparer';
  String get eTranslatorDesc => fa
      ? 'اولِ کار، متن کاربر را می‌خواند، زبانش را تشخیص می‌دهد و اگر لازم بود ترجمه و شفافش می‌کند تا مغز اصلی دقیق بفهمد چی می‌خواد.'
      : 'At the start, it reads the user\'s text, detects its language and, if needed, translates and clarifies it so the main brain understands exactly what is wanted.';
  String get eTranslatorHint => fa
      ? 'نکته: می‌تونی یه مدل سبکِ محلی برای ترجمه بذاری؛ مثلاً Gemma روی Ollama — کافیه تو تنظیمات، Ollama رو به‌عنوان ارائه‌دهنده داشته باشی و اسم مدل رو اینجا بنویسی.'
      : 'Tip: you can use a light local model for translation — e.g. Gemma on Ollama. Just add Ollama as a provider in Settings and write the model name here.';
  String get eVerifierTitle => fa ? '✅ بررسی‌کنندهٔ نتیجه' : '✅ Result verifier';
  String get eVerifierDesc => fa
      ? 'آخرِ کار، نتیجه را با خواستهٔ کاربر مقایسه می‌کند؛ اگر کار ناقص باشد، اجرا رد می‌شود و الکی «تمام شد» نمی‌گوید.'
      : 'At the end, it compares the result with what the user asked; if the work is incomplete, the run is rejected instead of pretending to be done.';
  String get eOrchestratorInfo => fa
      ? '🧭 هماهنگ‌کننده مدل نیست! موتور خودِ Cairn است؛ برنامه‌ریزی قدم‌ها، نوبتِ حرف‌زدن مدل‌ها و صدا زدن ابزارها دست اوست.\n🛠 ابزارها و مهارت‌ها دست‌های ایجنت‌اند — پایینِ همین صفحه انتخابشان می‌کنی.'
      : '🧭 The orchestrator is NOT a model! It is Cairn\'s own engine: planning the steps, giving each model its turn and calling the tools.\n🛠 Tools and skills are the agent\'s hands — you choose them further down this page.';
  String get eLangMemoryTitle => fa ? 'زبان و حافظه' : 'Language & memory';
  String get ePrimaryLang => fa ? 'زبان اصلی' : 'Primary language';
  String get eLangAuto => fa ? 'تشخیص خودکار' : 'Auto-detect';
  String get eLangFa => fa ? 'فارسی' : 'Persian';
  String get eTranslateToggle =>
      fa ? 'ترجمهٔ خودکار هنگام نیاز' : 'Translate automatically when needed';
  String get eMemoryToggle =>
      fa ? 'حافظهٔ مکالمه فعال باشد' : 'Conversation memory enabled';
  String get ePolicyTitle => fa ? 'سیاست اجرا' : 'Execution policy';
  String get eApprovalLevel => fa ? 'سطح تأیید' : 'Approval level';
  String get eApprovalSensitive =>
      fa ? 'فقط ابزارهای حساس بپرسد' : 'Ask only for sensitive tools';
  String get eApprovalAll => fa ? 'همهٔ فراخوانی‌ها بپرسد' : 'Ask for every call';
  String get eApprovalNone => fa ? 'بدون پرسش اجرا کند' : 'Run without asking';
  String get eNetworkToggle =>
      fa ? 'دسترسی شبکه مجاز باشد' : 'Network access allowed';
  String get eToolsTitle => fa ? 'ابزارهای مجاز' : 'Allowed tools';
  String get eAttachedSkills => fa ? 'مهارت‌های متصل' : 'Attached skills';
  String get eManageSkills => fa ? 'مدیریت مهارت‌ها' : 'Manage skills';
  String get eNoSkillsHint => fa
      ? 'هنوز مهارتی نصب نشده است؛ از «مدیریت مهارت‌ها» بساز.'
      : 'No skill is installed yet — create one via "Manage skills".';
  String eToolCount(int n) => fa ? '$n ابزار' : '$n tools';
  String get eSaveAgent => fa ? 'ذخیرهٔ ایجنت' : 'Save agent';
  String get eDeleteAgentBtn => fa ? 'حذف ایجنت' : 'Delete agent';

  // Training screen labels
  String _d(int n) => fa
      ? '$n'.replaceAllMapped(
          RegExp(r'[0-9]'),
          (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
        )
      : '$n';
  String get tNameCapsTitle =>
      fa ? '۱) نام و قابلیت‌های هدف' : '1) Name & target capabilities';
  String get tModelName => fa ? 'نام مدل' : 'Model name';
  String get tTargetTitle =>
      fa ? 'این مدل مال کیه؟ (هدف آموزش)' : 'Whose is this model? (training target)';
  String get tStandalone =>
      fa ? 'مدل مستقل — برای همهٔ ایجنت‌ها' : 'Standalone model — for all agents';
  String tOutputOf(String name) => fa
      ? 'خروجیِ پروژهٔ «$name» — مدل مال این پروژه'
      : 'Output of project "$name" — the model belongs to this project';
  String tBrainOf(String agent, String project) => fa
      ? 'مغزِ ایجنت «$agent» — پروژهٔ «$project»'
      : 'Brain of agent "$agent" — project "$project"';
  String get tDataTitle =>
      fa ? '۲) دادهٔ خام (هر خط یک نمونه)' : '2) Raw data (one sample per line)';
  String get tDataHint =>
      fa ? 'متن‌های آموزشی را اینجا بچسبان…' : 'Paste the training texts here…';
  String get tBuildDataset =>
      fa ? 'ساخت دیتاست و توکن‌ساز' : 'Build dataset & tokenizer';
  String get tArchTitle => fa ? '۳) معماری و آموزش' : '3) Architecture & training';
  String tHidden(int n) => fa ? 'پنهان ${_d(n)}' : 'Hidden $n';
  String tContext(int n) => fa ? 'بافت ${_d(n)}' : 'Context $n';
  String tEpochs(int n) => fa ? '${_d(n)} دوره' : '$n epochs';
  String get tStart => fa ? 'شروع آموزش' : 'Start training';
  String get tEvaluate => fa ? 'ارزیابی (پرپلکسیتی)' : 'Evaluate (perplexity)';
  String get tRegister => fa ? 'ثبت در رجیستری' : 'Register in registry';
  String get tFinetuneTitle => fa
      ? '۴) فاین‌تیون دستوری (هر خط یک JSON)'
      : '4) Instruction fine-tune (one JSON per line)';
  String get tFinetuneBtn => fa
      ? 'فاین‌تیون و ثبت مدل دستوری'
      : 'Fine-tune & register instruction model';
  String get tRegistryTitle => fa ? '۵) رجیستری مدل‌ها' : '5) Model registry';
  String get tNoModels =>
      fa ? 'هنوز مدلی ثبت نشده است.' : 'No model is registered yet.';
  String get tPlaygroundTitle => fa
      ? '۶) تولید نمونه با مدل انتخاب‌شده'
      : '6) Generate with the selected model';
  String get tSeedLabel => fa ? 'متن آغازین' : 'Seed text';
  String get tGenerate => fa ? 'تولید' : 'Generate';

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
