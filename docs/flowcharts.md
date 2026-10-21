# Cairn reference flows (provided by the project owner, 2026-10-21)

These two flowcharts are the owner's reference for what Cairn must do.
They are the acceptance picture for the runtime (Flow 1) and for the
model-training pathway (Flow 2). Status notes map each part to the
implementation as of v0.1.0; update them as milestones land.

## Flow 1 — Agent execution

```mermaid
flowchart TD
    U["کاربر: متن یا دستور صوتی"] --> L["تشخیص زبان و نوع درخواست"]
    L --> N["مدل آماده‌سازی درخواست<br/>ترجمه و شفاف‌سازی"]
    N --> O["هماهنگ‌کنندهٔ ایجنت<br/>Orchestrator"]
    O --> M["مدل اصلی هوش مصنوعی<br/>تحلیل، استدلال و برنامه‌ریزی"]
    MEM[("حافظه و اطلاعات پروژه")] <--> O
    MEM <--> M
    M --> P["برنامهٔ انجام کار<br/>تقسیم به مراحل"]
    P --> S{"بررسی مجوزها<br/>و سیاست امنیتی"}
    S -->|غیرمجاز| R["توقف یا درخواست تأیید"]
    S -->|مجاز| T["انتخاب ابزار یا مهارت"]
    T --> C{"نوع عملیات"}
    C -->|کدنویسی| CODE["ابزارهای برنامه‌نویسی"]
    C -->|فایل و سیستم| OS["ابزارهای سیستم‌عامل"]
    C -->|نرم‌افزار| APP["مهارت نرم‌افزاری<br/>مثل Office یا Adobe"]
    C -->|وب| WEB["مرورگر و ابزارهای وب"]
    C -->|مدل یا تحلیل| ML["مدل‌ها و ابزارهای تحلیل"]
    CODE --> X["اجرای مرحله و جمع‌آوری نتیجه"]
    OS --> X
    APP --> X
    WEB --> X
    ML --> X
    X --> V["بررسی نتیجه و خطاها"]
    V --> D{"کار کامل شده؟"}
    D -->|خیر| O
    D -->|بله| MEM
    MEM --> F["ساخت پاسخ نهایی"]
    F --> OUT["ترجمه در صورت نیاز<br/>و نمایش به کاربر"]
    R --> OUT
```

Status vs v0.1.0:
- ✅ Language detection + normalization (cairn_models language pipeline, runs
  over the configured model).
- ✅ Orchestrator + planner + step plan (cairn_runtime).
- ✅ Policy/approval gate (sensitive tools, network policy, budgets).
- ✅ Tool execution + result verification + retry loop (orchestrator).
- ✅ Project memory: project files + append-only run journal persist; the
  planner receives project context. Long-term memory beyond the project is
  still basic.
- 🔵 OS/file tools: fs.list/read/write, shell.run, http.get (M5 part 1 done).
  Coding-specific tools (patch/test-run conveniences) build on shell+fs.
- ⬜ Software skills (Office/Adobe-style app skills): skills system, M6.
- ⬜ Full web/browser tool: beyond http.get, M6+.
- ⬜ Voice input: not in v1 scope so far — captured here as an owner
  requirement from this flow; to be scheduled (platform speech input).
- ✅ Final answer passed back through the language pipeline.

## Flow 2 — Model creation & training

```mermaid
flowchart TD
    A["تعریف توانایی‌های مدل<br/>فارسی، انگلیسی، کدنویسی و استدلال"] --> B["جمع‌آوری یا تولید داده"]
    B --> C["پاک‌سازی داده‌ها<br/>حذف تکرار و اصلاح خطا"]
    C --> D["ساخت مجموعه‌های آموزش<br/>اعتبارسنجی و آزمون"]
    D --> E["توکن‌سازی متن<br/>Tokenizer"]
    E --> F["انتخاب معماری مدل<br/>و اندازهٔ پارامترها"]
    F --> G["آموزش مدل پایه"]
    G --> H["ذخیرهٔ Checkpoint"]
    H --> I["ارزیابی کیفیت و خطاها"]
    I --> J{"نتیجه قابل قبول است؟"}
    J -->|خیر| K["اصلاح داده، تنظیمات<br/>یا معماری"]
    K --> G
    J -->|بله| L["آموزش تکمیلی برای<br/>دنبال‌کردن دستورها"]
    L --> M["آزمون مکالمه، زبان<br/>و توانایی‌های موردنظر"]
    M --> N{"کیفیت کافی است؟"}
    N -->|خیر| K
    N -->|بله| O["ثبت نسخه در مخزن مدل‌ها"]
    O --> P["اتصال به موتور اجرای مدل"]
    P --> Q["استفاده در Cairn<br/>به‌عنوان مدل اصلی یا کمکی"]
    Q --> R["جمع‌آوری خطاهای مجاز<br/>و ارزیابی نسخهٔ بعدی"]
    R --> B
```

Status vs v0.1.0:
- ⬜ This whole flow is roadmap **M9** (training pathway) — not yet built.
- Design anchor: training is heavy compute, so jobs run on the peer with
  the resources (the Windows device via the Tool Host) under the
  symmetric-peer + overflow architecture; the phone can author the model
  project, prepare datasets and monitor the job.
- Honest scope: the pathway implements the full loop of this flowchart
  (define capabilities → data → clean → dataset splits → tokenize →
  architecture/size → train → checkpoint → evaluate → instruction
  fine-tune → registry → serve as a Cairn provider → feedback into the
  next dataset) for small/medium models and fine-tuning on PC-class
  hardware. Training a large foundation model from scratch is bounded by
  the user's hardware, and Cairn must say so in the UI rather than pretend.
- The trained model registers as a model provider (local inference via an
  Ollama-compatible endpoint or the Tool Host) and is then usable as the
  main or auxiliary model of any agent — closing the loop with Flow 1.
