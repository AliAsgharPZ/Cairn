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
- 🔵 Named Pipe transport: implemented in cairn_toolhost
  (`named_pipe.dart`, Win32 FFI via package:win32 — the handle is
  opened in a helper isolate and reads/writes run in dedicated
  isolates so blocking IO can't deadlock the protocol; same-user
  trust model stated in code). The host can serve over it via
  `--pipe <name>`. **Honest verdict (2026-10-21): NOT verified and
  NOT shipped.** Its Windows round-trip test hung in CI three times
  (runs 39635044715, 39653424975, 39658461234 — the round trip itself
  passed once, then process shutdown/open raced the test harness),
  so the pipe was removed as the windows-build gate and as the app's
  runtime transport. **The shipped transport is the host child's
  stdio** (the app spawns `cairn_tool_host.exe`; protocol frames go
  over its stdin/stdout, diagnostics to stderr) — proven by
  `toolhost_exe_stdio_test.dart` against a real compiled binary
  (locally on Linux, and in windows-build on Windows). The pipe code
  remains in the repo as an unverified option, labelled as such.
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
- 🔁 **Owner correction (2026-10-21, v1.1) — implemented:** the
  local-first OverflowRouter is replaced by a multi-directional
  **LoadBalancer** (cairn_core): any device may serve any other, steps
  split evenly across capable devices (score per unit of assigned
  load), link tiers = local network first, internet last
  (`classifyHost`: loopback local, private ranges LAN, Tailscale
  100.64/10 + public = internet). Live in the test console:
  `LoadBalancedTool` (cairn_runtime) wraps tools that reachable peers
  also offer; the console connects to paired peers at run start,
  fetches capabilities, balances per call with a shared LoadTracker,
  and closes the sessions at run end — the M8 follow-up above is
  closed. Tests: core load-balancer 7, runtime balanced-tool 2.
## M9 — Model-creation & training pathway + security hardening ✅

- ✅ Training core (`packages/cairn_training`, pure Dart, **13/13
  tests**): dataset builder (cleaning with honest drop counts —
  empty/short/duplicate — and deterministic seeded splits); a
  Unicode word-level tokenizer (Persian/Arabic-safe; <unk> fallback,
  documented as NOT BPE); ModelSpec with a documented transformer
  parameter-estimate formula for export specs; **NeuralLanguageModel
  — a real NNLM trained by hand-written backpropagation/SGD in Dart**
  (tests prove loss and perplexity genuinely fall on a toy corpus,
  checkpoint round-trips reproduce identical greedy generations, and
  instruction fine-tuning is continued training on formatted
  examples); ModelRegistryStore (one JSON per model: metadata +
  metrics + full checkpoint). The model reports its TRUE parameter
  count (its own weight arrays), never the transformer estimate.
- ✅ App integration: the **Training screen** (6th shell destination —
  capabilities chips → raw data → build dataset with the honest
  cleaning report and split counts → tokenizer vocab → architecture
  (hidden/context/epochs) with the model's TRUE parameter label →
  train with first→last loss → evaluate (perplexity) → register →
  instruction fine-tune from JSONL lines with skipped-line counting →
  registry list with delete → playground generation) and the
  **«local-trained» provider**: a registered model loads from the
  registry and serves completions through the standard ModelProvider
  interface, so the console and agents can use it like any provider
  (last user message = prompt; the small LM continues the text —
  named honestly in the settings UI). TrainingScreen is analyze-
  clean; its widget tests run in CI like the rest of the app; the
  provider has a unit test (registered-model completion + honest
  failure for unknown ids). **M9 complete.**
- Security hardening (the other half of M9) is the set of mechanisms
  already verified in M5–M8, restated for the record: API keys only
  in the platform secure store and resolved lazily (never in files
  or logs); fs tools confined to the workspace root with symlink-
  escape defeat; shell tool argv-only; the network policy enforced
  by the orchestrator; sync/overflow channels accept only mutually
  authenticated paired devices; remote execution re-validates
  against the destination's own allowlist with sensitive tools off
  by default; bulk sync deletions require local confirmation and
  land in a 30-day trash.

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

## M10 — Packaging & final delivery 🔵

- Version bumped to **1.0.0+1**. Final local verification sweep
  (2026-10-21): **127/127 pure-Dart tests green** across all seven
  packages (core 47, models 14, runtime 17, tools 16, toolhost 6,
  sync 14, training 13) and `flutter analyze` clean for the app.
- Delivery artifact: `Cairn-Complete-Project.zip` built from a clean
  `git archive` of the delivery commit, integrity-tested, extracted
  to a fresh directory and smoke-checked, and scanned for secrets
  before delivery in the Cairn side chat (link + attachment).
- Fresh binaries come from CI on the delivery commit and from the
  `v1.0.0` tag's windows-build (which also runs the windows-only
  named-pipe round-trip test — the last M5 verification). Statuses
  are reported separately and honestly, as agreed.
- Known remainders, stated plainly: the app's Windows startup
  integration for the Tool Host pipe (spawn `--pipe` + merge host
  tools at launch) and voice input from Flow 1 are the two items
  beyond v1.0.0's verified scope.


## v1.1.4 — WINDOWS FULLY GREEN (2026-10-21 night)
- windows-build #10 (tag v1.1.4, commit e973658): **SUCCESS** — ToolHost stdio proof
  ✅ (22s), flutter test **23/23** ✅ (the colon filename fix + doubled widget-test
  settle budget), Windows release build ✅, Tool Host exe compiled & bundled ✅.
- Artifact cairn-windows-release.zip: 17,155,546 bytes, **sha256 92c2fee2…**
  (verified locally against GitHub's digest; contains cairn_app.exe +
  cairn_tool_host.exe + Arad/Inter). This is the v1.1-series Windows binary with
  RTL/bilingual UI, capsule nav, auto-sync, load balancing and the roles system.
- Android: signing still blocked on the GitHub secret VALUES (CI's fast verify
  step fails in 1s as designed). Re-creating the secrets needs GitHub's sudo
  email code from the owner; the first update attempt died waiting for it.


## v1.1.5 — SIGNED RELEASE DELIVERED; v1.1 BATCH COMPLETE (2026-10-22)
- Signing saga closed: the three GitHub secrets were re-created with exact
  values (KEYSTORE_BASE64 sent in 4 file-exact chunks, field-verified at
  exactly 3464 chars; GitHub sudo email code supplied via the owner's Gmail).
- CI #53 (ac2deeb) FULLY GREEN: dart-packages ✅, flutter-app ✅, android-apk ✅,
  android-release-apk ✅ — verify step printed "SIGNING VERIFY OK" + cert
  SHA256 58:9A:C4:DA:...; windows-build #11 ✅.
- Release APK v1.1.5 (arm64): 20,708,397 bytes, sha256 812ecdfd... — signature
  verified DIRECTLY with apksigner: signer cert SHA-256 digest
  589ac4da54e134b6... == the dedicated cairn keystore cert. Delivered via
  Muse storage (link expires 2026-10-24 09:05 Tehran).
- Windows v1.1.5 zip: 17,155,547 bytes, sha256 de9db289... (digest-verified),
  delivered via Muse storage (same expiry).
- The v1.1 feedback batch is now fully shipped: RTL/bilingual, light+dark,
  real Settings with Devices inside, auto-sync + header button, capsule nav,
  fixed import + Flow-1 default project, name "cairn" + custom icon, real
  release signing, Flow-1 roles with per-role models, simplified training,
  multi-directional load balancing, projects producing models.
- Standing notes: the first signed APK does not install over the debug-signed
  v1.0.0 (export → uninstall → install once); future updates install over it.
  Honest remainders: training screen dynamic status sentences are Persian-only;
  Flow-1 voice input still unscheduled (post-v1); named-pipe Tool Host
  transport remains an unverified experimental option (stdio is shipped).

## v1.2.0 (in delivery) — networking that works, unified projects, the chain

Owner feedback on v1.1.5 (2026-10-22): networking "doesn't work at all"
(no connection status, no visible IP, manual copy-paste pairing, servers
off by default), a capsule-navbar display bug on Android, a confusing
structure (why is the agent a separate section? a project of models +
agents cannot be wired together), and the model chain as the top
priority: language detector → translator (fa/en) → interpreter →
manager → English LLM → software agents — with the first models trained
for real.

- M11 networking (cairn_sync): interface enumeration (connection status
  + own LAN IP), UDP broadcast discovery (port 47802), LAN pairing with
  mutual SAS on port 47803 (no more paste/typed IPs as the main flow).
  Devices screen rebuilt: network status card, nearby-devices list with
  one-tap pairing, incoming-pairing card, servers + discovery +
  pairing listener auto-start behind a visibility switch, paired
  endpoints auto-updated from discovery. Tests: pairing handshake
  (match/reject/abort) + discovery logic green locally; the live-UDP
  test self-skips only in UDP-dropping sandboxes and runs on CI.
- Capsule nav: overflow-proof cells (FittedBox + ellipsis + width cap),
  SafeArea(top:false), soft shadow, animated selection (pill growth,
  icon pop, label size animation); staggered fade/slide list entrances.
- M12 unified structure: AgentProject.pipeline (PipelineStep kinds
  detect/translateIn/interpret/manage/agent/answer/translateBack, each
  with a replaceable modelRef). Tabs are now Projects / Project /
  Run / Models / Settings; the Project tab is a workspace with the
  chain view (per-step model/agent pickers) and the agent editor.
  Console gained a chain-run mode with a per-step trace.
- Smart models (cairn_training): TextClassifier (softmax regression,
  char n-grams + words, real SGD) trained on bundled corpora — language
  detector (168 examples, held-out ≥90% asserted) and interpreter
  (84 examples, 4 intents, ≥70% asserted); PhraseTranslator from 96
  parallel pairs + lexicon with an honest coverage metric. One-tap
  training in the Models tab (isolate), saved via SmartModelStore and
  bindable per pipeline step. Manager = routing layer over the
  interpreter (labeled as such); LLM slot = the agent's provider model
  (Gemma-ready via Ollama); Figma agent ships in the chain default
  project with an honest design-spec prompt (no fake Figma API).
