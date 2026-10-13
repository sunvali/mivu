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
