# Coach response recovery verification — 2026-10-13

## Observed problem

A signed development build on a physical iPhone running iOS 27.0.1 completed ChatGPT sign-in and showed plan permission. In the isolated synthetic QA diary, a saved text meal remained pending. An HTTP 200 stream contained a completed function item in `response.output_item.done`, followed by an empty terminal output array. The parser discarded the completed item. After recovering that item, local tool validation rejected a generated date-only `eaten_at` value.

## Changes

- Retain bounded, indexed completed items; accept them only after a successful terminal completion. Reject duplicate indices/IDs, gaps, conflicts, unfinished responses and invalid function arguments. Preserve full items for stateless function-output continuation.
- Declare strict function schemas with explicit nullable optional fields. Treat null as absent only where the field is optional.
- Accept valid calendar-date and ISO 8601 syntax, including fractional seconds, for compatibility timestamps. These values remain unconfirmed and cannot change the requested tracking date or establish an exact eating/weigh-in/workout time.
- Keep finite, content-free failure categories for debugging. No provider text, arguments, prompt text, credentials, account details or device identifiers appear in diagnostics.
- Remove all temporary QA launch routes and engine instrumentation before final regression verification. Keep local signing settings out of the commit.

## Evidence

Tested source: `feature/core-tracking`, parent `d7b4241`, with frozen tracked iOS patch SHA-256 `f7676aaf515481683148f6bc5c471a6ca9f8199ac9b4ed292536cdfc100f1aa5`. The local source manifest was checked after GREEN with zero drift. Local signing differs from the repository project solely for the owner development build.

Environment: macOS 27.0.1, iPhone 18 Pro simulator / iOS 27.0, normal simulator signing. Commands use XcodeBuildMCP.

| Run | Scope | Named pass / fail / skip | Result |
| --- | --- | --- | --- |
| Completed-item RED | ResponsesClientTests | 35 / 3 / 0 | Reproduced discarded done items and missing conflict rejection |
| Completed-item GREEN | Seven parser, connection, job, flow, engine and authorization suites | 144 / 0 / 0 | Passed; independently reviewed |
| Timestamp/schema RED | CoachEngineTests | 32 / 3 / 0 | Reproduced schema, optional-null and date-only/fractional contract gaps |
| Ordinary-source GREEN | Same seven covering suites | 149 / 0 / 0 | Passed; independently reviewed |

Covering command:

```sh
rtk xcodebuildmcp simulator test --project-path /private/tmp/mivu-coach-progress-tools/ios/Mivu.xcodeproj --scheme Mivu --simulator-id <selected-simulator> --derived-data-path /private/tmp/mivu-progress-tools-dd --extra-args '-only-testing:MivuTests/ResponsesClientTests' '-only-testing:MivuTests/CoachConnectionTests' '-only-testing:MivuTests/ProbeJobTests' '-only-testing:MivuTests/CoachFlowTests' '-only-testing:MivuTests/ConnectionTests' '-only-testing:MivuTests/CoachEngineTests' '-only-testing:MivuTests/OAuthAttemptTests' '-resultBundlePath' '/private/tmp/mivu-tool-time-contract-green.xcresult' --output json
```

Exact simulator selection, per-file hashes and local result bundles remain in the private verification artifacts. Actual xcresult named summaries were read; counts are named tests rather than wrapper or parameter-run totals.

## Remaining acceptance

- [x] Physical signed development build and owner-performed sign-in/plan permission observed.
- [x] Synthetic saved input survived retries and updates without another capture.
- [x] Parser and optional timestamp regressions passed on ordinary source.
- [x] Independent scoped reviews approved both changes.
- [x] At 15:51 Asia/Jerusalem, the original saved synthetic prompt completed in ordinary Mivu on the physical iPhone with the real ChatGPT subscription connection. The app displayed the saved eggs/bread meal, a completed receipt-backed reply, 226 kcal, carbs 13.1 g, protein 16.6 g, fat 11.6 g, and 1,774 kcal remaining from the saved 2,000 kcal goal. No new capture was sent for this retry. Earlier automatic launch was denied while locked; the owner reopened the installed ordinary app and Mirroring confirmed the result.
- [ ] Live corrections, retrospective food, conversational weight/workout, remaining budget, sparse weekly progress and relaunch.
- [ ] Final-source hosted CI and PR integration. Previous PR7 run failed two test-interaction cases; their reviewed local fixes are in `d7b4241`.

Simulator tests and review do not establish successful live inference. Manual tracking/Coach edit parity is a separate next slice, requested after the full live response succeeds.


## Hosted CI stall and bounded handoff verification

The first recovery run, [38400937339](https://github.com/yakov103/mivu/actions/runs/38400937339), tested `d6feabc1315a093a91bcb0b8f5e745249dfabe9c` and was canceled after approximately thirty minutes. Its partial result bundle did not finalize; it is not passing evidence. Preserved diagnostics show `CoachFlowTests.sendCommitsTextAndPhotoBeforeInferenceAndRelaunch()` started without a completion. The previously completed suites reported 116 parameter/test runs, one skip and zero failures; there is no complete named-test total for that run.

The test's start wait could suspend indefinitely if the worker never reached the injected inference function. The replacement uses a ten-second monotonic deadline, cancellation-aware waiting and worker-exit detection. Failure cleanup releases the fixture once and joins the worker; a closed fixture cannot create a new suspension from a late response. All existing persistence, original-photo, relaunch and profile-fencing assertions remain.

Local verification on iPhone Air / iOS 26.5 (the hosted runtime):

- A first focused attempt was blocked by runner preflight (`Busy`) and executed no native cases. The simulator was then found shut down and explicitly booted.
- The fresh focused Flow suite passed:14 named tests,0 failures,0 skips.
- The full native unit target passed:386 named tests,0 failures,1 skip. The final small closed-fixture guard was added afterward and requires the subsequent final-source check.
- Native high-entropy image preparation passed separately:one named test,0 failures,0 skips. A requested function-level PNG filter did not execute; selected/discovered names were not counted as passing tests.

The isolated Flow test did not reproduce an early worker failure, so no production cause is claimed. The bounded test prevents this failure mode from silently consuming the whole CI job. A fresh hosted gate remains required. Phone testing stopped when the owner disconnected the device; image-based meal acceptance remains unverified.


## Final reviewed local source

Ponytail Review found and then verified a correction for tied-time historical weights: the chart previously chose the last entry while the numeric report chose the highest revision. Both consumers now use the existing report selection rule through one shared helper: newest measurement, then highest revision, then the first entry for an exact tie. Valid legacy and travel-day fixtures reproduced both mismatches (RED:3 passed,2 failed,0 skipped). The regressions inspect the actual chart projection and confirm stored date/timezone mapping, unit conversion and report agreement.

Final local native unit target, iPhone Air / iOS26.5, passed:388 named tests,0 failures,1 skipped. The actual xcresult summary was read, and all tracked iOS files matched the frozen source manifest after the run. This run includes the closed-fixture cleanup guard and shared chart/report selection. The final independent Ponytail review verdict is Ship, with its one finding closed. Full hosted scheme and Release simulator validation remain the merge gate.


Warning cleanup retains both expected-throw assertions, makes the existing strong task capture explicit, and pins hosted simulator destination architecture to the runner architecture. Final local native verification remains388 passed/0 failed/1 skipped, with no compiler warnings reported and zero frozen-source drift. `bash -n scripts/ci/native.sh` passed and the CI result-verifier tests passed4/0/0. Independent review approved this three-file cleanup. Hosted completion is recorded separately; warnings in an unfinished log are not a failing test result.
