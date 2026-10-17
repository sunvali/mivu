# Animation regeneration and verification

Run commands from the repository root. Use `rtk` for verbose commands when
available (`rtk proxy` can wrap tools it does not specialize). Use Headroom for
large context when available. Keep native jobs serial; do not contend for a
simulator or change global defaults while another job is using them.

## Regenerate only when authoring changes

Use Python 3 with Pillow and NumPy. Prefer an existing suitable interpreter;
if missing, create a local virtual environment rather than changing system Python.

```sh
python3 -c 'import PIL, numpy'
python3 design-system/mivu/characters/pip/lottie-source/build.py
python3 design-system/mivu/characters/pip/lottie-source/fallbacks.py
python3 design-system/mivu/characters/pip/lottie-source/test_motion.py
```

`build.py` imports and calls `coach_pose.authored_peek`; there is no separate
Coach regeneration command. It writes the JSON, registration and painted assets.
It consumes the existing coverage alpha; this is not a blank-project bootstrap.
`fallbacks.py` uses that registration and coverage alpha to write static poses;
the Coach fallback is prepared through the Coach recipe invoked by `build.py`.
**The Python regression suite also calls `build.build()` and rewrites generated
outputs.** Inspect its diff even when running it only as a test.

Check the diff at source and output. Preserve untouched surfaces and artwork;
compare hashes against the checked-out baseline when identity must stay unchanged.
Do not regenerate or replace original references to make a test pass. Inspect
moving-mask connectivity, joint overlap and grounded paw coverage: a tiny detached
paint component can become obvious during a larger gesture.

The loader caps JSON at **1,048,576 bytes**. Preserve marker names expected by
the loader and presenter; derive current durations from `MOTION.md` and source.
Do not treat a metadata match as proof of rendered motion.

`design-system/mivu/characters/pip/asset-manifest.json` is separate provenance;
the builder does not refresh it. After intended changes, update affected SHA-256
and byte entries in `runtimeAsset`, `sourceArtwork`, `fallbacks`, `authoringSources`
and `assets`, plus applicable layer/marker metadata. `assets[].file` is relative
to the Pip directory; other `path` fields are repo-relative. Preserve historical
validation and record fresh evidence separately instead of relabeling old runs.

## Choose checks for the changed owner

Tests live in `ios/MivuTests/` unless specified otherwise.

| Change | Useful checks |
|---|---|
| Generator, masks, gesture strength | Python `test_motion.py`; `CompanionLottieAssetTests`, `CompanionArtworkMatteTests`, `CompanionLottiePreviewTests` |
| Loading, transitions, completion, cancellation | `CompanionAssetTests`, `CompanionSurfaceTests`, `CompanionMountTests`, `CompanionRootIntegrationTests` |
| Accepted input versus durable save/review | `CompanionPresentationTests`, `CompanionReceiptTests`, `CoachReceiptFeedbackTests`, root integration |
| Eligibility or fallback policy | `MotionPolicyTests`, asset and mount tests |
| Character catalog/selection | `CharacterCatalogTests`, `CompanionSelectionTests`, asset failure/switch cases |
| Screens, keyboard, focus, text size | `ios/MivuUITests/CompanionUITests.swift` and affected Coach/Diary journeys |

For regressions, reproduce at the relevant layer before changing behavior.
`CompanionRootIntegrationTests.untouchedTodayKeepsBreathingDuringAnEmptyBackgroundCoachRefresh`
exercises the actual shared persistence lock; the display-frame tests in
`CompanionLottiePreviewTests` exercise idle wrap and greeting completion. These
check different failure sources.

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
  --json '{"scheme":"Mivu","simulatorName":"iPhone 17 Pro","useLatestOS":true,"extraArgs":["-parallel-testing-enabled","NO","-disableAutomaticPackageResolution","-onlyUsePackageVersionsFromResolvedFile","-only-testing:MivuTests/CompanionLottiePreviewTests"]}' \
  --output json
```

Replace the `-only-testing` entry with the relevant suite(s). Swift Testing
method selectors can yield **zero tests** without failing the build; prefer
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
