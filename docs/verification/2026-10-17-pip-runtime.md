# Pip runtime verification — 17 October 2026

Status: implementation and simulator acceptance in progress. This document does not establish physical-device performance or release readiness.

## Environment and baseline

Local XcodeBuildMCP, iPhone 17 Pro simulator on iOS 26.5 (`42CE2315-9339-4EF1-A5B4-064444D0FA44`). Baseline native units: 441 passed, 0 failed, 1 expected interactive authentication skip. Focused catalog: 7 passed. Motion policy: 29 passed after a controlled-time regression reproduced and corrected hidden typing/recovery cancellation (commit `bda07bc`). Independent scoped review passed.

Local detailed evidence is retained under `/private/tmp/mivu-pip-verification/`; XcodeBuildMCP JSON includes the result bundle and build log paths. Temporary paths are local evidence locations, not portable artifacts.

## Artwork

Original Pip fox curves and gesture keys are editable under `design-system/mivu/characters/pip/source/`. The 512 × 512 script-free rig uses the named artboard, state machine and typed model in its manifest. Seven pose pairs and a preview pair are vector PDFs, including light/dark variants. Official CLI verification reported zero errors and warnings. An independent artwork review verified the packaged hashes, single-page vector PDFs and source provenance.

Real CLI rendering checked attentive, thinking, saved, reviewed, recovery, greeting, blink, and a reviewed gesture after its settle. These single-action renders alone did **not** establish repeated-event correctness; native sequential testing found an issue they could not reveal.

## Repeated-trigger investigation

With official RiveRuntime 6.28.1 concurrency APIs and the real bundled file, the first saved reaction ran for approximately 0.50 seconds, the second saved reaction settled in approximately 0.01 seconds, reviewed ran for approximately 0.70 seconds, greeting settled in approximately 0.01 seconds, and blink ran for approximately 0.19 seconds. The retained typed trigger stream confirmed exactly one underlying event for each of the five calls. This was rejected as a passing result.

Neither an explicit change comparator, a shared Any State reactive branch, nor a zero-time advance before firing resolved the alternating failure. Experimental artwork changes were reverted. No duplicate-trigger workaround was accepted.

A source review found a plausible stale-settlement race in the concurrent renderer: the service drops the settled callback's request ID, and the controller can accept an old settlement after clearing its dirty flag for a newer advance. Exact callback ordering was not instrumented, so this is a diagnosis supported by source and symptoms, not a proven upstream root cause. See the [official 6.28.1 source](https://github.com/rive-app/rive-ios/tree/6.28.1/Source/Concurrency).

The supported synchronous renderer with retained typed data binding passed all 16 focused asset tests (0 failed, 0 skipped), including real repeated rendering, duration checks and natural stopping. Final evidence: `asset-green-final.json`, 11,170 ms, source `c32ef262643120ed84f48c2f01835a3034e630f1`. This includes a stronger pre-first-frame stale-trigger reattachment check and an already-paused no-op check. Real observed durations were saved 0.492 s, repeated saved 0.469 s, reviewed 0.689 s, greeting 0.727 s, and blink 0.185 s, followed by natural idle. A subsequent view-replacement regression reproduced old teardown disconnecting the new representation; an identity guard fixed it. Final asset suite at `15068e210bfd96df508e3cef0dff1be6224e618c`: 17 passed, 0 failed, 0 skipped, 10,013 ms (`asset-view-teardown-green.json`), independently reviewed. Screen integration is undergoing native UI verification. Schema loading or a trigger counter alone was not accepted as evidence. The attempted 6.28.0 comparison was canceled during package resolution; no tests ran on that version. The package remains pinned to 6.28.1.

## Remaining acceptance

- Complete screen integration verification for Today, Coach and Settings. Durable save/review receipt boundaries passed 57 broad regression tests; the final overlapping review fix passed 20 focused tests at `24f3c06` (zero failures/skips). Independent receipt review passed.
- Run the complete native unit/UI scheme and inspect real light/dark surfaces, typing, navigation, static fallback and reduced motion.
- Record a simulator demonstration and create the private draft pull request.
- After the owner connects an iPhone: verify device rendering, haptics, camera/provider behavior, frame time, power and thermal behavior. No simulator observation substitutes for those checks.
