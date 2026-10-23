# Cairn — AI Agent & Model Studio for Android, Windows, Linux, macOS and iOS

**Cairn is a graphical studio for building your own AI agents and models.**
Design a flowchart, connect any model to each step — any open-source model
(Ollama, Gemma, …) or any AI API (OpenAI-compatible, Anthropic) — and run it.
No ready-made agents, no bundled datasets: Cairn ships empty, everything in it
is yours.

Runs as **one identical, full studio on Android, Windows, Linux, macOS and
iOS** — the same codebase on every platform. Your devices are symmetric
peers: they sync two-way and share compute (a step moves to a paired device
only as overflow, when the local device can't handle it — home LAN first,
internet last).

<p>
  <a href="https://github.com/AliAsgharPZ/Cairn/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/AliAsgharPZ/Cairn?label=latest%20release"></a>
  <a href="https://github.com/AliAsgharPZ/Cairn/actions/workflows/ci.yml"><img alt="CI status" src="https://github.com/AliAsgharPZ/Cairn/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/AliAsgharPZ/Cairn/actions/workflows/windows-build.yml"><img alt="Windows Build status" src="https://github.com/AliAsgharPZ/Cairn/actions/workflows/windows-build.yml/badge.svg"></a>
  <img alt="Platforms: Android, Windows, Linux, macOS, iOS" src="https://img.shields.io/badge/platforms-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20iOS-312d2a">
</p>

## ⬇️ Download

| Platform | File | Get it |
|---|---|---|
| **Android (universal)** | `cairn-v<version>-universal-release.apk` — one signed APK for **all CPUs** (arm64-v8a + armeabi-v7a + x86_64); installs over previous versions | [Latest release](https://github.com/AliAsgharPZ/Cairn/releases/latest) |
| **Windows x64 (installer)** | `cairn-setup-v<version>.exe` | [Latest release](https://github.com/AliAsgharPZ/Cairn/releases/latest) |
| **Windows x64 (portable)** | `cairn-windows-release-v<version>.zip` | [Latest release](https://github.com/AliAsgharPZ/Cairn/releases/latest) |
| **Windows ARM64 (installer)** | `cairn-setup-v<version>-arm64.exe` — native ARM64 build | [Latest release](https://github.com/AliAsgharPZ/Cairn/releases/latest) |
| **Windows ARM64 (portable)** | `cairn-windows-arm64-release-v<version>.zip` | [Latest release](https://github.com/AliAsgharPZ/Cairn/releases/latest) |
| **Linux x64** | `cairn-v<version>-linux-x64.tar.gz` — extract, run `./cairn` (needs GTK 3) | [Latest release](https://github.com/AliAsgharPZ/Cairn/releases/latest) |
| **Linux ARM64** | `cairn-v<version>-linux-arm64.tar.gz` — native ARM64 bundle | [Latest release](https://github.com/AliAsgharPZ/Cairn/releases/latest) |
| **macOS (universal)** | `cairn-v<version>-macos.dmg` / `.zip` — one binary for Apple silicon + Intel; not notarized; first launch: right-click → Open | [Latest release](https://github.com/AliAsgharPZ/Cairn/releases/latest) |
| **iOS (unsigned)** | `cairn-v<version>-ios-unsigned.ipa` — sideload with your own Apple ID (AltStore/SideStore) or sign it yourself | [Latest release](https://github.com/AliAsgharPZ/Cairn/releases/latest) |

🌐 **Website:** https://cairn-abg.pages.dev — downloads and project overview.
All official builds live on the [Releases](https://github.com/AliAsgharPZ/Cairn/releases)
page (permanent links). File naming is one convention everywhere: lowercase,
versioned.

## What you can build

Every model in Cairn has a **role** — what it is and what it does:

- **LLM** — a language model
- **Software agent** — an agent that works in software, taught by *your* lessons (text + screenshots of how you do the task)
- **Translator** — between any two languages you define
- **Manager / router** — picks which model or agent acts next
- **Interpreter** — turns a request into a task or a question
- **Image generator**, **Video generator**, **Code writer**, **Voice & music composer**

Models activate and work **according to your flowchart**: you add, remove,
reorder and bind steps in a visual editor, and the runner executes exactly
that pipeline, showing a short, plain trace of who did what.

## Any language — including yours

There is no built-in Persian/English assumption. Cairn ships with a language
registry: **add any custom language** (name, code, RTL) in Settings and use it
as a project language or as a translator step's source/target.

## Key features

- **Bring your own models & APIs** — local open-source models via Ollama or
  any OpenAI-compatible / Anthropic API, per role.
- **Visual flowchart pipeline editor** — steps are role + model bindings.
- **Test console** — run a project and read a short step-by-step trace.
- **Agent lessons** — teach software agents by demonstration notes.
- **Peer sync & overflow** — two-way sync with version vectors; overflow
  dispatch scored by device capability; LAN → Tailscale → relay order.
- **Import / export at three levels** — a project (`.cairn.zip`), your models
  (JSON), or a full studio backup (API keys never leave the device in exports).

## Status

Under active construction, milestone by milestone, with real tests reported
at every step. See [PROGRESS.md](PROGRESS.md) for the honest, test-backed
status and [docs/decisions.md](docs/decisions.md) for the locked architecture
decisions (analysis v3, approved 2026-10-21). Honest limits are documented
there too — nothing is presented as done before it is tested.

## Repository layout

- `apps/cairn_app/` — the Flutter studio app (Android + Windows)
- `packages/cairn_core/` — projects, flowchart pipelines, model definitions
- `packages/cairn_models/` — provider adapters (OpenAI-compatible, Anthropic, Ollama)
- `packages/cairn_runtime/` — the pipeline runner / orchestrator
- `packages/cairn_sync/` — two-way sync engine, version vectors, pairing
- `packages/cairn_tools/` — tool contracts and platform tool implementations
- `packages/cairn_toolhost/` — the Windows Tool Host process (stdio transport)
- `packages/cairn_training/` — a generic training toolkit for *your* data (datasets, tokenizer, small neural LM, model registry)
- `site/` — the download website (deployed to Cloudflare Pages)
- `DESIGN.md` — the Oracle design system (`npx getdesign@latest add oracle`)
- `docs/` — architecture, decisions, flowcharts, fonts, design mapping

## Design & fonts

- Oracle design language per `DESIGN.md`: warm neutral ladder, charcoal
  actions, the red reserved for the wordmark, a gold rule as the only flourish,
  and no shadows. Mapped to a single Flutter theme layer — see `docs/design.md`.
- Persian typeface: **Arad** (SIL OFL 1.1) from
  https://github.com/MohamadDarvishi/Arad — bundled under
  `apps/cairn_app/assets/fonts/arad/` with its license. Latin companion: Inter
  (OFL). See `docs/fonts.md`.

---

**Keywords:** AI agent studio · build your own AI agent · visual agent
flowchart · LLM orchestration · Ollama GUI · Gemma · OpenAI-compatible ·
Anthropic · model roles · peer-to-peer sync · load-balanced overflow ·
Android · Windows · Linux · macOS · iOS · Flutter · Dart · Persian (فارسی) · ساخت ایجنت هوش مصنوعی
