# Cairn — Progress (kept honest; updated every milestone)

Status legend: ✅ Implemented & tested · 🟡 Implemented, not fully tested ·
🔵 In progress · ⬜ Not started · 🚧 Blocked (with reason)

Last updated: 2026-10-21

## M0 — Toolchain, repo skeleton, design & font assets ✅

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
- Empty-app debug APK smoke build: 🚧 cannot run in this sandbox (network
  gate blocks Gradle's loopback channel — see Build status); routed to the
  CI `android-apk` job instead.

## M1 — Core contracts ✅

- `packages/cairn_core` implemented: agent blueprint + project format (JSON
  round-trip, validation), task state machine (11 states, legal-transition
  table, corrupt-history rejection), execution budgets (steps/model/tool/
  wall-clock, injectable clock), append-only journal (JSONL, sequence-checked),
  UUID v4 + idempotency keys.
- **22 unit tests run and passed** (2026-10-21, `dart test`); `dart analyze`
  clean. App scaffold generated with `flutter create` (android+windows only),
  minSdk pinned to 26 (decision D4).
## M2 — Oracle theme + studio shells + Arad typography gate ✅

- Token layer (`lib/ui/tokens.dart`) + full `ThemeData` (light + dark
  extension) built from DESIGN.md; Arad registered with explicit weights,
  Inter variable font bundled (OFL) as Latin fallback; wordmark widget is
  the only brand-red surface.
- Studio shell (rail/bar responsive) + Projects screen with real
  file persistence (`ProjectStore`, atomic JSON writes, corruption
  surfaced). Agent editor (full blueprint form), provider settings
  (secure key store + real connection test) and the live test console
  are all wired. App tests: **CI run #8 — 9/9 pass** (the create-project
  flow needed duration-pumped settling inside runAsync; runs #4/#7
  failed it 8/9 before the fix). The local `flutter test` harness is
  sandbox-blocked, so app tests execute in CI only.

## M3 — Model layer + agent editor + language pipeline ✅ (engine) / editor UI in M2 scope

- `packages/cairn_models`: OpenAI-compatible, Anthropic and Ollama adapters
  (real HTTP, keys resolved per call, never stored), FakeModelProvider for
  tests, language pipeline (script detection, translate, normalize).
- **14 tests run and passed** (2026-10-21) against in-process HTTP servers;
  `dart analyze` clean.

## M4 — Runtime (orchestrator/state machine/budgets) + test console ✅

- `packages/cairn_runtime`: Planner (strict JSON plan, validated against
  blueprint + device tool registry) and Orchestrator (normalize → plan →
  approval gate → step execution with budgets/retries/idempotency keys →
  verification; every transition journaled; failure modes all fail loudly).
  Network policy enforced: tools flagged `requiresNetwork` are refused
  when the agent policy disallows network.
- **11 tests run and passed** (2026-10-21, incl. the network-policy test);
  `dart analyze` clean.
- Test-console UI: wired (agent picker, live journal polling, approval
  dialogs as the gate, cancel token, honest unconfigured-provider state).

## M5 — Tools v1 + Windows Tool Host 🔵

- ✅ Platform tools (in-process, `packages/cairn_tools`): fs.list /
  fs.read / fs.write confined to the agent workspace root (lexical
  normalization + canonicalized nearest-ancestor check defeats `..` and
  symlink escapes), shell.run (argv-only, timeout, truncated output),
  http.get (size-capped, network-flagged). **16 tests passed**; wired
  into the app registry. Totals across pure-Dart packages: **63 tests**.
- 🔵 Windows Tool Host: protocol + client + server implemented
  (`packages/cairn_toolhost`): length-prefixed JSON-RPC, `host.ping` /
  `host.capabilities` / `tool.invoke`; remote tools plug into the app's
  ToolRegistry as ordinary Tools, so policy/approvals apply unchanged.
  Executable in `tool_host/`. **6 tests passed**, including a real
  spawned-process stdio end-to-end test.
- 🔵 Named Pipe transport (Windows production): implemented in
  cairn_toolhost (`named_pipe.dart`, Win32 FFI via package:win32 —
  the handle is opened in a helper isolate and reads/writes run in
  dedicated isolates so blocking IO can't deadlock the protocol;
  same-user trust model stated in code). The host serves over it via
  `--pipe <name>`. Every FFI call type-checks against the real win32
  API (`dart analyze` clean). The decisive runtime proof is a
  windows-only round-trip test (`named_pipe_test.dart` — ping,
  capabilities, a real calc.eval over a real pipe) wired into the
  windows-build job; it runs on the next windows-build dispatch.
  Remaining: app-side Windows startup integration (spawn the host
  with --pipe, connect, merge its tools into the registry).
- Owner reference flows: `docs/flowcharts.md` (provided 2026-10-21).
  Flow 1 = runtime acceptance picture (voice input captured there as a
  requirement, not yet scheduled). Flow 2 = the M9 training pathway.

## M6 — Skills, policy/approvals, project versioning & export ✅

- ✅ Project export/import (part 1): `ProjectArchive` in cairn_core —
  portable `.cairn.zip` (manifest + project.cairn.json) with strict
  validation (foreign zip / future format version / missing payload /
  corrupt JSON all refused). Wired into `ProjectStore` (exports folder;
  id collisions import as a copy, never an overwrite). 5 archive tests;
  cairn_core now 27/27. App UI buttons for export/import: next.
- 🔵 Skills (engine done): `Skill` model + `SkillRegistry` in cairn_core
  (JSON, validation; 3 tests — core now 30/30). Runtime integration:
  the planner receives attached skills' instructions and their tools
  count as declared (planner + execution guards both use the effective
  set); an unknown skill id fails the run loudly. Policy/approval gates
  still apply to skill tools unchanged. 3 runtime tests (grant, reject
  without skill, unknown id) — runtime now 14/14. Pure-Dart total: 80.
  Remaining: SkillStore persistence + skills UI in the studio and the
  agent editor's skill picker.
- ✅ Skills in the app: `SkillStore` (JSON files, validated/atomic,
  corruption surfaced; 5 store tests) wired through the shell; the
  agent editor keeps skillIds across saves, has an attach checklist
  and a skills manager dialog (create with name/description/
  instructions/tool chips, delete); the test console hands the
  installed SkillRegistry to the orchestrator.
## M7 — Pairing + two-way sync + conflict resolution ✅

- ✅ Sync core (`cairn_core/sync.dart`, pure Dart, deterministic):
  VersionVector (increment/merge/compare with true concurrency
  detection), Hlc hybrid logical clock (tick/receive are monotone even
  across wall-clock skew), SyncRecord, and `mergeSyncRecords`
  implementing the approved per-kind rules — dominating version wins;
  concurrent project/skill edits keep local + emit a conflict copy with
  the joined version vector; journal = append-only union by event id;
  settings = per-key LWW by HLC; tombstones delete only when dominating
  (a concurrent edit resurrects). **11 sync tests; core now 41/41.**
  Pure-Dart total: **91 tests**.
- 🔵 Device identity + pairing (`packages/cairn_sync`): Ed25519 key
  pairs; device id = public-key fingerprint (stable across seed
  restores; the seed is the only secret and belongs in the platform
  secure store). Pairing offers (QR payload JSON) are validated — an
  offer whose claimed id doesn't derive from its key is refused — and
  both sides compute the same 6-digit SAS from both keys + a session
  nonce for the users to compare. **6 tests passed.**
- 🔵 Record-exchange session (`cairn_sync/session.dart`): framed
  protocol with a mutual-auth handshake (each side signs the peer's
  nonce with its long-term key; verification is against the key stored
  at pairing — unpaired strangers are rejected before any record
  moves), full record exchange, local deterministic merge. **Session
  tests prove both sides converge to identical state (same canonical
  records, same conflict-copy id) and that strangers are refused.**
  Fixed during this work: concurrent-edit resolution is now
  HLC-determined with deterministic conflict ids (previously
  local-wins + random ids, which would never converge).
- 🔵 App-side sync (`studio/sync_service.dart`): SyncCoordinator
  builds records from ProjectStore/SkillStore with persisted
  bookkeeping (unchanged entities keep their version — no phantom
  bumps; edits bump version+HLC; local deletions become tombstones)
  and applies session results back (merged records written to the
  stores, conflict copies as new "… (تعارض)" entities, deletions
  moved to a persisted trash list). Socket transport in cairn_sync
  (SyncServer + syncWithPeer) — **verified over a real loopback
  socket test**; sync package now **9/9**. Coordinator covered by 3
  app tests (run in CI).
- ⬜ Remaining in M7: the Devices screen (identity bootstrap + seed in
  secure storage, pairing by pasted offer + SAS compare, paired
  device list, server start / "sync now"), then M8.

## M8 — Compute overflow + optional self-hosted relay ✅

- ✅ Routing (`cairn_core/capabilities.dart`): DeviceCapabilities /
  StepRequirements / OverflowRouter — local-first; overflow ONLY when
  the local device fails hard requirements (no fixed RAM threshold);
  eligible peers ranked by capability score; when nobody is eligible
  the step is blocked with the unmet requirements listed, never
  silently downgraded. 6 tests; core now **47/47**.
- ✅ Execution protocol (`cairn_sync/overflow.dart`): mutual-auth
  handshake (paired keys) + invoke/result framing (shared framing
  codec extracted). **Destination-side re-validation**: the executing
  device enforces its own remote allowlist and refuses sensitive
  tools remotely unless its owner enabled them; refusals are normal
  error results. `RemoteTool` adapter in cairn_runtime lets the
  orchestrator call peer tools like local ones (approval gates and
  journal unchanged). Tests: sync pkg **13/13**, runtime **17/17**.
- ✅ App wiring: the overflow protocol serves this device's
  capabilities (CPU cores measured; RAM/disk/GPU owner-declared in the
  Devices screen — never fabricated). The Devices screen has the
  overflow-server toggle (port 47801) executing through the app's real
  ToolRegistry, an owner switch for remote sensitive tools (default
  off), and per-peer «توانمندی‌ها» which fetches the peer's real
  capabilities and shows the router's verdicts for sample heavy steps.
  **M8 complete.** Documented follow-up (not hidden): injecting
  RemoteTools into the test console's registry for live peer routing
  during agent runs. Optional self-hosted relay stays deferred by the
  approved design (LAN + Tailscale cover v1).
## M9 — Fine-tune pathway + security hardening ⬜
## M9 — Model-creation & training pathway + security hardening ⬜

Scope = owner's Flow 2 (`docs/flowcharts.md`): capability definition →
data collection/generation → cleaning → dataset splits → tokenization →
architecture/size choice → base training → checkpoints → evaluation →
instruction fine-tune → model registry → serve as a Cairn provider →
feedback loop. Training jobs execute on the peer with the resources
(Windows via Tool Host) under the overflow architecture. Honest bound:
small/medium models and fine-tuning on PC-class hardware; the UI must
state hardware limits instead of pretending foundation-scale training.

## M10 — Docs, packaging, verified ZIP delivery ⬜

## Build status (reported separately, per delivery rules)

- Android APK: **built in CI** (the sandbox cannot run Gradle — its
  network gate kills cross-process loopback TCP; conclusively verified).
  - Debug APK ✅ CI run #1 (commit 2cd02a9), artifact `cairn-debug-apk`.
    First chat-attachment delivery FAILED on the client side (extension
    stripped; 159 MB also exceeds the file-hosting limit) — superseded
    by the release build below.
  - **Release APK (arm64, split-per-ABI) ✅ CI run #4** (commit 07147ed):
    v0.1.0, 19.5 MB, delivered to the owner via a direct download link
    on 2026-10-21.
  - CI run #4: dart-packages ✅ (63 pure-Dart tests), android-apk ✅,
    android-release-apk ✅, flutter-app ❌ 8/9 tests.
  - **CI run #8 (commit e6aeaa3): FULLY GREEN** — dart-packages ✅,
    flutter-app ✅ 9/9, android-apk ✅, android-release-apk ✅.
- Windows binary: `windows-build` runs #1/#2 ❌ — both failed at the
  `flutter test` step on the (now fixed) single app test.
  **`windows-build` #3 (commit dd5b4a8): ✅ SUCCESS** — tests passed on
  Windows, `flutter build windows --release` compiled, artifact
  `cairn-windows-release` (12.7 MB, sha256 8fb23251…) downloaded,
  contents verified (cairn_app.exe + plugin DLLs + Arad/Inter assets)
  and delivered to the owner via a direct download link on 2026-10-21.
  The Windows build therefore exists and runs the same studio code;
  the Named Pipe Tool Host wiring remains the last M5 item.
- ✅ **M7 complete**: the Devices screen replaced the roadmap panel —
  identity bootstrap (seed in platform secure storage; stable device
  id), display name, pairing by pasted offer + SAS compare + confirm,
  paired-device list with per-device host + «سینک کن» (buildRecords →
  syncWithPeer → applyResult with an honest report), the sync-server
  toggle (port 47800, paired devices only), and the sync trash count.
  Identity/paired/profile stores covered by 3 app tests (CI). QR
  rendering of the offer is a display nicety deferred past v1 — the
  offer text itself is the pairing payload.
