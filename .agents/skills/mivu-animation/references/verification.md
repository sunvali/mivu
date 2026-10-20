# Animation regeneration and verification

Run commands from the repository root. Use `rtk` for verbose commands when
available (`rtk proxy` can wrap tools it does not specialize). Use Headroom for
large context when available. Keep native jobs serial; do not contend for a
simulator or change global defaults while another job is using them.

## Regenerate only when authoring changes

`pip.svg` is the source; `pip-rig.json` is generated and must not be hand-edited.
`build.py` needs only the standard library; `--png` needs `cairosvg` and Pillow in
the repo-root `.venv` (`python3 -m venv .venv && .venv/bin/pip install cairosvg pillow`).

```sh
.venv/bin/python design-system/mivu/characters/pip/rig/build.py --png OUT
.venv/bin/python design-system/mivu/characters/pip/rig/test_rig.py
```

`--png` also rewrites the static fallback images in
`ios/Mivu/Assets.xcassets/Companion/Pip/`: inspect that diff. Check the SVG and
JSON diff at source and output, keep `pip-rig.json` under 512 KiB (the loader
rejects more than **1,048,576 bytes**), and do not replace `reference.png` to make
a test pass. Compare Pip beside `reference.png` at 40, 64, 88 and 200 pt.

`design-system/mivu/characters/pip/asset-manifest.json` is separate provenance;
the builder does not refresh it. After intended changes, update the SHA-256 and
byte entries for `runtimeAsset`, `authoringSources` and `fallbacks`. Preserve
historical validation and record fresh evidence separately.

## Choose checks for the changed owner

Tests live in `ios/MivuTests/` unless specified otherwise.

| Change | Useful checks |
|---|---|
| `pip.svg` / `build.py` | `rig/test_rig.py`; `PipRigAssetTests`, `PipRigViewTests`, `PipRigSnapshotTests` |
| Gestures, moment mapping | `PipGestureTests` (covers every library entry), `PipRigSnapshotTests` |
| Idle beats | `PipIdleSchedulerTests` |
| Runtime playback, interruption, gaze, policy | `CompanionRigRuntimeTests`, `CompanionMountTests`, `CompanionSurfaceTests` |
| Accepted input versus durable save/review, priority | `CompanionPresentationTests`, `CompanionReceiptTests`, `DiaryCompanionMomentTests`, `CoachReceiptFeedbackTests`, `CompanionRootIntegrationTests` |
| Eligibility or fallback policy | `MotionPolicyTests`, asset and mount tests |
| Character catalog/selection | `CharacterCatalogTests`, `CompanionSelectionTests`, `CompanionAssetTests` |
| Screens, keyboard, focus, text size | `ios/MivuUITests/CompanionUITests.swift` and affected Coach/Diary journeys |

For visual review launch the app with the `-PipRigPreview` argument (it shows
`PipRigPreview`: every gesture, gaze, turn and idle beat at shipping sizes in both
appearances). For regressions, reproduce at the relevant layer before changing
behavior. `CompanionRootIntegrationTests.untouchedTodayKeepsBreathingDuringAnEmptyBackgroundCoachRefresh`
exercises the actual shared persistence lock.

Use **XcodeBuildMCP**, not direct native build/simulator commands. Discover the
installed CLI and actual available destinations before running:

```sh
xcodebuildmcp --help
xcodebuildmcp simulator-management list
xcodebuildmcp simulator test --help
```

Example focused renderer run, after confirming that simulator name is available
(adapt it to the selected destination; explicit arguments avoid stale defaults):

```sh
xcodebuildmcp simulator test \
  --project-path "$PWD/ios/Mivu.xcodeproj" \
  --json '{"scheme":"Mivu","simulatorName":"iPhone 18 Pro","useLatestOS":true,"extraArgs":["-parallel-testing-enabled","NO","-disableAutomaticPackageResolution","-onlyUsePackageVersionsFromResolvedFile","-only-testing:MivuTests/PipGestureTests"]}' \
  --output json
```

Replace the `-only-testing` entry with the relevant suite(s). A single-test
`-only-testing` filter (and Swift Testing method selectors) can silently run
**zero tests** without failing the build; prefer
suite selectors and confirm discovered cases and nonzero result counts. XCTest
methods use the `test` prefix shown in source. Parse both tool error status and
the result summary: a successful shell exit alone is insufficient evidence.

Follow the root instructions and `docs/development/ci-cd.md` for required full
native/UI verification after screen/navigation changes. Local push-hook units
and Linux checks do not replace UI acceptance. Do not rerun all native tests for
documentation-only changes.

## Inspect actual motion

Inspect native Core Animation rendering at **88 pt and 148 pt**, light and dark.
Sample gesture onset, peak, settle and joins; verify chest/head and paw acting
below the eyes, intact face/scarf paint and grounded supporting paw. Watch at
original speed: screenshots alone cannot establish smooth pacing.

Leave Today untouched for at least three complete eight-second loops per
appearance, including blink and wrap. Exercise Coach typing, accepted submit,
durable save, review, recovery, interrupted feedback, rapid tabs and reattachment.
Check largest text, composer reachability and retained keyboard focus. Verify
policy/static fallbacks and expired/cancelled reactions do not replay after load,
foregrounding or character changes.

Keep fixture/profile flags confined to isolated simulator data. Physical-device
builds use existing data and no fixture arguments. Build, install and launch are
separate observations; if locked, retry launch after unlock instead of rebuilding.
Device deployment or PR updates still require authorization from the active task.

## Record the result

Put new evidence under `docs/verification/` with source revision, destination/OS,
named tests, passed/failed/skipped counts, result-bundle location, asset hash,
screens/recording references and unresolved gates. Keep large local recordings
outside Git and link their usable local location in the user handoff.

The [idle/Coach report](../../../../docs/verification/2026-10-17-pip-idle-and-coach.md)
shows an example with native screenshots and explicit revision boundaries. It is
historical evidence, not a reusable assertion that later changes pass. Preserve
earlier failed full-UI runs until a new complete run establishes a new result.
Do not infer physical frame pacing, energy or thermal behavior from simulator
capture FPS or a successful launch; measure those on hardware when in scope.
