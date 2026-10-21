import 'blueprint.dart';
import 'project.dart';

/// The ready-made reference project for Flow 1 (agent execution),
/// built for the owner to import into the studio and run as-is:
/// one agent whose instructions follow the flowchart stage by stage
/// (language detection → request preparation/translation → planning
/// with project memory → permission gate → tool choice by operation
/// type → execute → verify → loop or final answer, translated back
/// when needed).
///
/// The model slot points at a local Ollama model by default; the
/// owner re-points it at any configured provider from the agent
/// editor. Tool bindings list every tool the app ships, grouped by
/// the flowchart's operation types.
AgentProject buildFlowOneDefaultProject() {
  final agent = AgentBlueprint(
    id: 'flow1-assistant',
    name: 'دستیار فلوچارت',
    description: 'ایجنت مرجع فلوچارت ۱ (اجرای ایجنت): از تشخیص زبان و '
        'آماده‌سازی درخواست تا برنامه‌ریزی، بررسی مجوز، انتخاب ابزار '
        'بر اساس نوع عملیات، اجرا، بررسی نتیجه و پاسخ نهایی.',
    systemPrompt: 'تو «دستیار فلوچارت» در Cairn هستی و دقیقاً طبق این '
        'روند کار می‌کنی:\n'
        '۱) اول زبان و نوع درخواست کاربر را تشخیص بده.\n'
        '۲) اگر لازم بود، درخواست را ترجمه و شفاف کن تا دقیق و روشن شود.\n'
        '۳) با حافظه و اطلاعات همین پروژه، درخواست را تحلیل کن و یک '
        'برنامهٔ مرحله‌به‌مرحله بساز.\n'
        '۴) قبل از هر اقدام، مجوزها و سیاست امنیتی را بررسی کن؛ اگر '
        'کاری حساس یا غیرمجاز بود، متوقف شو و از کاربر تأیید بخواه.\n'
        '۵) برای هر مرحله ابزار درست را بر اساس نوع عملیات انتخاب کن: '
        'کدنویسی و اجرا ← shell.run و ابزارهای فایل؛ فایل و سیستم ← '
        'fs.list و fs.read و fs.write؛ وب ← http.get؛ محاسبه و متن ← '
        'calc.eval و text.stats و text.transform؛ زمان و شناسه ← '
        'clock.now و id.uuid.\n'
        '۶) هر مرحله را اجرا کن و نتیجه و خطاهایش را بررسی کن؛ اگر کار '
        'کامل نشده بود، به برنامه‌ریزی برگرد و ادامه بده.\n'
        '۷) در پایان پاسخ نهایی را بساز و اگر لازم بود به زبان کاربر '
        'ترجمه کن.\n'
        'همیشه کوتاه، دقیق و صادق باش؛ اگر ابزاری در دسترس نیست یا '
        'کاری را نمی‌توانی انجام دهی، صریح بگو.',
    model: ModelConfig(providerId: 'ollama', modelId: 'llama3.1'),
    language: const LanguageConfig(
      primaryLanguage: 'auto',
      translateWhenNeeded: true,
    ),
    tools: [
      ToolBinding(toolId: 'fs.list'),
      ToolBinding(toolId: 'fs.read'),
      ToolBinding(toolId: 'fs.write'),
      ToolBinding(toolId: 'shell.run'),
      ToolBinding(toolId: 'http.get'),
      ToolBinding(toolId: 'calc.eval'),
      ToolBinding(toolId: 'text.stats'),
      ToolBinding(toolId: 'text.transform'),
      ToolBinding(toolId: 'clock.now'),
      ToolBinding(toolId: 'id.uuid'),
    ],
    policy: const PolicyConfig(
      approvalLevel: ApprovalLevel.sensitiveOnly,
      allowNetwork: true,
    ),
  );
  return AgentProject(
    id: 'flow1-default-project',
    name: 'پروژهٔ پیش‌فرض فلوچارت ۱',
    description: 'پروژهٔ آماده طبق فلوچارت اجرای ایجنت (فلوچارت ۱). '
        'ایمپورتش کن، از ویرایشگر ایجنت مدل دلخواهت را برایش انتخاب '
        'کن (پیش‌فرض: Ollama محلی) و در کنسول تست اجراش کن.',
    agents: [agent],
  );
}
