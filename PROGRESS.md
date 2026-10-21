# Cairn — Progress (kept honest; updated every milestone)

Status legend: ✅ Implemented & tested · 🟡 Implemented, not fully tested ·
🔵 In progress · ⬜ Not started · 🚧 Blocked (with reason)

Last updated: 2026-10-21

## M0 — Toolchain, repo skeleton, design & font assets 🔵

- Toolchain (installed on the build VM, all under `$HOME`):
  - JDK: Temurin OpenJDK 17.0.20.1 ✅ verified (`java -version`)
  - Flutter: **3.47.7 stable / Dart 3.13.5** ✅ verified (`flutter --version`)
  - Android SDK: cmdline-tools + platform-tools (adb 1.0.41) + platform
    android-35 + build-tools 35.0.0 ✅ installed. NOTE: Google's Java-based
    `sdkmanager` cannot traverse this environment's authenticated egress
    proxy (JDK tunneling bug), so the SDK packages were installed by
    downloading the official archives from dl.google.com with curl and
    unpacking them into the standard SDK layout; licenses recorded.
    Gradle proxy settings were written to `~/.gradle/gradle.properties`.
  - `flutter doctor` verdict: pending (after the APK smoke build)
- Repo skeleton created (apps/, packages/, tool_host/, relay/, docs/, tools/, tests/). 🔵
- Oracle: `npx getdesign@latest add oracle` executed in repo root →
  `DESIGN.md` (42,525 bytes) installed ✅. Tokens read and confirmed:
  primary charcoal `#312d2a`, brand red `#c74634` (wordmark only), warm canvas
  ladder `#ffffff/#fbf9f8/#f5f4f2/#f1efed`, link `#006b8f`, focus `#227e9e`,
  error `#d63b25`. Token mapping to Flutter theme lands in M2.
- Arad font: cloned from the verified repo (MohamadDarvishi/Arad, OFL 1.1) and
  bundled (variable font + core statics + Farsi-digits variable + OFL.txt +
  AUTHORS.txt) under `apps/cairn_app/assets/fonts/arad/` ✅.
  SHA-256 of `AradVF.ttf`: `cd45c0bbe78ec6bd45b6f90d294feed37e08b1038c75a30d7388a51bc22bd42e`.
- CI workflows: written (`.github/workflows/ci.yml`, `windows-build.yml`) ✅;
  git repo initialised, first commit `c319b81` ✅.
- Empty-app debug APK smoke build: ⬜ (this milestone, after doctor is green)

## M1 — Core contracts ✅

- `packages/cairn_core` implemented: agent blueprint + project format (JSON
  round-trip, validation), task state machine (11 states, legal-transition
  table, corrupt-history rejection), execution budgets (steps/model/tool/
  wall-clock, injectable clock), append-only journal (JSONL, sequence-checked),
  UUID v4 + idempotency keys.
- **22 unit tests run and passed** (2026-10-21, `dart test`); `dart analyze`
  clean. App scaffold generated with `flutter create` (android+windows only),
  minSdk pinned to 26 (decision D4).
## M2 — Oracle theme + studio shells + Arad typography gate ⬜
## M3 — Model layer + agent editor + language pipeline ⬜
## M4 — Runtime (orchestrator/state machine/budgets) + test console ⬜
## M5 — Tools v1 + Windows Tool Host ⬜
## M6 — Skills, policy/approvals, project versioning & export ⬜
## M7 — Pairing + two-way sync + conflict resolution ⬜
## M8 — Compute overflow + optional self-hosted relay ⬜
## M9 — Fine-tune pathway + security hardening ⬜
## M10 — Docs, packaging, verified ZIP delivery ⬜

## Build status (reported separately, per delivery rules)

- Android APK: **blocked by the build sandbox, not by the code.** The whole
  toolchain works (JDK/Flutter/Android SDK/Gradle 9.3.1 all verified, wrapper
  cache seeded, daemon starts and listens), but the sandbox blocks
  cross-process local TCP, which the Gradle client↔daemon channel requires
  ("Could not dispatch a message to the daemon — Broken pipe"; a raw Java
  socket test receives the sandbox's in-band notice that "Other TCP
  connections is turned off"). Unblocks when the user enables other TCP
  connections for the assistant in the Muse app settings.
- Windows binary: cannot be compiled in this Linux environment (by design of
  the approved architecture it is produced by the GitHub Actions
  `windows-latest` workflow / `tools/build_windows.ps1`); not built yet.
