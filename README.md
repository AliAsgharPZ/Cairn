# Cairn

A graphical development platform (studio) for building AI agents — one identical,
full studio on **Android** and **Windows**, with two-way peer sync between the
devices and compute overflow (a task/step moves to the paired device only when
the local device cannot handle it).

> Status: under active construction, milestone by milestone. See
> [PROGRESS.md](PROGRESS.md) for the honest, test-backed status of every
> milestone and [docs/decisions.md](docs/decisions.md) for the locked
> architecture decisions (analysis v3, approved 2026-10-21).

## Layout

- `apps/cairn_app/` — the Flutter studio app (targets: Android, Windows only)
- `packages/cairn_core/` — agent blueprint, orchestrator, task state machine, journal
- `packages/cairn_models/` — model provider adapters (OpenAI-compatible, Anthropic, Ollama, Fake-for-tests)
- `packages/cairn_sync/` — two-way sync engine, version vectors, pairing protocol
- `packages/cairn_overflow/` — capability-based overflow router
- `packages/cairn_tools/` — tool contracts and platform tool implementations
- `packages/cairn_skills/` — skill registry and manifest schema
- `tool_host/` — isolated Windows tool-host process (shell/process/browser automation)
- `DESIGN.md` — Oracle design system (installed via `npx getdesign@latest add oracle`)
- `docs/` — architecture, decisions, security, sync, overflow, test plans

## Design & fonts

- Oracle design language per `DESIGN.md` (warm neutral ladder, charcoal actions,
  Oracle red reserved for the wordmark). Tokens are mapped to a single Flutter
  theme layer; see `docs/design.md`.
- Persian typeface: **Arad** (SIL OFL 1.1) from
  https://github.com/MohamadDarvishi/Arad — bundled under
  `apps/cairn_app/assets/fonts/arad/` with its license. Latin companion: Inter
  (OFL). See `docs/fonts.md`.
