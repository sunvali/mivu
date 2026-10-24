# Mivu contributor rules

Read the product design and approved plan linked in README before editing.
Use Ponytail: minimal complete, human-readable Swift; platform APIs first.
The linked taste-skill supplies applicable visual principles; follow Apple HIG
for this native app. No web frontend is required.

- Preserve unrelated changes; use feature branches and pull requests.
- Do not mention codex or ai in commit messages or pull requests.
- Use rtk for verbose shell output when available.
- Use Headroom when available to compress or retrieve large context.
- Write the smallest meaningful failing test before behavioral implementation.
- Use XcodeBuildMCP for Apple builds, tests, and simulator operations.
- Report blocked checks honestly; never accept legal terms for the owner.
- Use only synthetic inputs in connection diagnostics and tests.
- Protect credentials in Keychain; never bundle secrets or log token responses.
- Do not substitute paid API access, enable billing, or publish publicly without
  the owner's explicit authorization.
- Keep analysis separate from meal calculations so a later server worker can
  consume the same small operation.
- Preserve durable local capture: save acknowledgement and backup-folder write
  acknowledgement are separate. Never claim remote sync from a file-provider
  write; retain pending errors and never restore stale data over deletions.
- The MVP UI and acceptance are English-only; disable the Hebrew language
  selector. Preserve existing profile/archive data and stored language values;
  do not require Hebrew RTL functionality for MVP acceptance. Keep Dynamic Type,
  VoiceOver, reduced motion, and minimum 44-point touch targets.
- For behavior changes, include focused evidence from source plus named tests;
  report the source revision, environment, result counts, and any blocked gates.
  A workflow definition is not evidence of a hosted run.
- Follow the PR/CI/release contract in [CI and delivery](docs/development/ci-cd.md):
  merge through a reviewed PR, verify required checks and artifacts, and keep
  release claims tied to the exact merged revision and observed run.
- Before merge, run Ponytail Review, fix blocking findings, and verify CI.
  Follow the owner's existing authorization for merging; do not add approval gates.
- Use Conventional Commit PR/squash titles. All hosted jobs use `ubuntu-slim`
  with two-minute limits for script and title checks only. No hosted macOS,
  self-hosted runner, native build/test, packaging or signing jobs are allowed.
- Keep test work proportional to the change. For a test-only edit, run only that
  test or its suite. For implementation changes, run the new/changed test plus
  the smallest suites covering its direct callers; prefer unit tests for UI
  presentation, validation and state. Use suite selectors when Swift Testing
  method selectors run zero tests; never count zero tests as passing.
- For screens/navigation, add `python3 scripts/ci/smoke.py --simulator-id
  <reserved-UUID>` (120-second cap). Add a specific longer UI test only when the
  changed behavior needs it. Do not run every UI journey or all unit tests on
  every edit, PR, review or handoff. Do not repeat unchanged passing checks or
  broaden a passing focused run without a concrete new risk/failure.
- `MivuQuick` is the default smoke-only Xcode plan. Keep the complete `Mivu`
  unit/UI plan for release candidates, broad regressions or an explicit request.
  This policy supersedes older plans/skills that demand a full run each time.
  Use XcodeBuildMCP, record tested source SHA and named results, and distinguish
  local native evidence from Linux CI. A timeout or blocked run is not a pass.
- Other agents may be using simulators. Check active native jobs first; reserve
  a separate simulator and pass its UUID explicitly. Use a checkout-specific
  DerivedData directory; set `MIVU_TEST_SIMULATOR_ID` for push-hook checks.
  Never change shared defaults, erase, stop or reuse
  another agent's simulator or terminate their build/test processes.
- Version/changelog PRs and tags remain automated. Package and sign the exact
  version tag locally with Xcode/Organizer; record local evidence separately.
  Keep Actions usage/auto-packaging gates false and never count blocked or
  skipped native work as passing evidence.
- Local Git hooks are opt-in via `python3 scripts/ci/git_hooks.py install`.
  Preserve custom hooks. Commits check staged syntax/whitespace only; pushes run
  quick script checks and curated units when native inputs changed or the baseline
  is unknown. Native pushes require the checked-out commit and clean native inputs.
- Reuse local native success only for identical inputs, recipe and environment;
  never cache failed, zero-test or malformed evidence. Hook units do not replace
  focused UI smoke/affected-journey verification or Ponytail Review before merge.

## Companion animation work

For Pip artwork, the rig, motion, gestures, pose transitions, lifecycle, character
selection, or animation verification, read the repository skill
[mivu-animation](.agents/skills/mivu-animation/SKILL.md) first. It maps editable
sources to generated assets and native owners, and links the verification recipe.
Pip is a native Core Animation rig (no Lottie, no painted atlas): the art source is
`design-system/mivu/characters/pip/rig/pip.svg`, built by `rig/build.py` into
`pip-rig.json`. To add or change a gesture, follow
[adding a gesture](.agents/skills/mivu-animation/references/adding-a-gesture.md).
Older Lottie and Rive plans are historical context. Keep animation changes tied to
the approved references and explicit user intent.

## Coach chat history

Follow the approved [Coach chat history plan](docs/superpowers/plans/2026-10-18-coach-chat-history.md),
[behavior contract](docs/development/coach-chat-behavior.md), and
[verification record](docs/verification/2026-10-18-coach-chat-history.md).
Ordinary Coach paths use bounded owner queries; do not rebuild a complete
`DiarySnapshot`. Each request captures its source and ownership at request time.
Keep one persistent 100-exchange window accounting for resident, reserved and
retired page work. Retain reservations for retired requests until their
underlying work actually exits, including after invalidation. Treat accepted
capture identity/context and committed receipts as immutable; reconcile uncertain
capture with the same payload, and never reapply a committed correction. Focused
Coach tests live in `ios/MivuTests` and `ios/MivuUITests`; run them with
XcodeBuildMCP and record the exact source SHA and result bundle.

Keep the floating **Jump to latest** as the native glass `UIButton` owned by
`CoachTimelineTable`, so drags on the control reach the table's native pan
gesture. Preserve the table's default accessibility-element prefix and append
the button through its
[`UIAccessibilityContainer`](https://developer.apple.com/documentation/uikit/uiaccessibilitycontainer)
methods. Use the owner's compact down-arrow treatment: a 48-point circular
control with the spoken “Jump to latest” label. Keep focus away from the
underlying exchange and a 44-point minimum target, and verify an actual button
drag and tap, row/focus routing, icon fit, and viewport restoration within 2 points.

## Knowledge graph

When a local `graphify-out/graph.json` exists (built with graphify; not tracked),
answer codebase questions with `graphify query "<question>"` first. Use
`graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"`
for one concept. Read `graphify-out/GRAPH_REPORT.md` only for broad architecture
review or when those miss context. After code changes, run `graphify update .`
(AST-only, no API cost) to keep the graph current.
