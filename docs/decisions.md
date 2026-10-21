# Cairn — Locked Technical Decisions (Analysis v3, approved 2026-10-21)

These decisions were proposed in analysis v3 and approved by the product owner
with 7 implementation conditions. Any fundamental change requires the owner's
explicit approval first.

- **D1 — Stack.** Flutter (Dart) for UI + shared core; targeted native modules
  (Kotlin on Android; C++ runner additions on Windows); a separate Windows
  **Tool Host** process (isolated, JSON-RPC over Named Pipe) for shell/process/
  browser automation. Windows binary is produced by GitHub Actions
  (`windows-latest`) or `tools/build_windows.ps1` — it cannot be compiled in
  the Linux build environment. Avalonia was rejected (weaker Android/RTL story).
- **D2 — Connectivity.** Direct LAN (mDNS + mutually-authenticated TLS 1.3)
  in-home; **Tailscale** overlay as the supported out-of-home path in v1;
  optional self-hosted relay ships as source in M8, never a public endpoint.
- **D3 — Models.** No bundled keys. Adapters: OpenAI-compatible, Anthropic-style,
  Ollama (Windows local). Language pipeline stages run over one configured
  model by default; per-stage override is a setting.
- **D4 — Minimum Android.** API 26 (Android 8). Targets are only Android and
  Windows; no other product targets are built.
- **D5 — Typefaces.** Persian: **Arad** (OFL 1.1) everywhere Persian appears.
  Latin companion: **Inter** (OFL). Oracle Sans is proprietary and not
  redistributable; this substitution is declared, not silent.
- **D6 — Agent editor (v1).** Structured form editor + live test console.
  Node/graph editor is post-v1.
- **D7 — Sync conflicts (per data class).** Journal/history: append-only union.
  Settings: per-key last-writer-wins with hybrid logical clock. Agent/project
  files: three-way merge against common base, else conflict copy surfaced to
  the user. Deletions: tombstones + 30-day trash; bulk deletes need local
  confirmation on the receiving device.
- **D8 — Overflow.** Per-step, capability-scored dispatch (task requirement
  profile vs. live device capability snapshot: installed models/tools, free
  resources, load, battery/thermal, link) — no fixed RAM threshold. Default is
  local execution; overflow carries context, files (hash-verified), settings
  and the same permission policy, and the destination re-validates everything.
  **Superseded in part by the owner's correction (2026-10-21, v1.1):**
  dispatch is multi-directional load balancing, not phone→PC overflow —
  any device may serve any other and steps split evenly across capable
  devices (capability score per unit of assigned load); link priority is
  local network first (this device + LAN peers), then speed, and the
  internet (e.g. Tailscale routes) LAST. Hard requirements still gate
  eligibility, and the destination still re-validates everything.

## Owner's implementation conditions (2026-10-21)

1. Build milestone by milestone; run real tests at the end of each milestone
   and report the results.
2. Never present unimplemented or untested capabilities as complete.
3. First deliver a genuinely runnable v1 core (studio, agent-project
   create/save, agent execution, test console); then add two-way sync and
   overflow.
4. Oracle and Arad are integrated from the start.
5. Verify file delivery in practice; final ZIP attached in the Cairn chat.
   APK and Windows build/test status reported separately and honestly.
6. No core capability may be replaced by mock UI, fake data, or simulated tests.
7. Ask before any decision that fundamentally changes the approved architecture.
