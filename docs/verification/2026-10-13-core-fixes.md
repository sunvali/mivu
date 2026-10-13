# Core fix verification — 2026-10-13

This is the local verification snapshot at product source `1fc3687682eb4012818504aa8d3022e644cd0b41`, before hosted delivery. Later aggregate and merge evidence belongs to the associated pull request and workflow artifacts.

**Status: scoped fixes verified; full core acceptance remains incomplete.** This record covers the local UI and ChatGPT-plan recovery fixes after the full aggregate stopped at source `61c80599718b4ec2f80b71b116354f6e79c0e029`. It does not claim a passing full-app gate, hosted CI, main merge, live provider use, or physical-iPhone acceptance.

## Source and review

The UI fix is commit `4689df62349d1d27ca7997fea95aa198a84ca33a`; its bounded source review verdict is Ship. The ChatGPT subscription recovery fix is commit `1fc3687682eb4012818504aa8d3022e644cd0b41`; its rereview found no remaining scoped blocker, and its exact tested source was preserved through commit. The auth verification ran from base `61c80599718b4ec2f80b71b116354f6e79c0e029` with the frozen UI/auth changes present. The complete tracked iOS file manifest matched after the run and after commits, with zero source drift (manifest SHA-256 `607bad1ad00362793e93fa697aa0d6d230f482abbea349b7fd3007475b229a99`).

The UI fixes clear an all-unset dated goal without changing earlier dated goals, keep numeric field labels and units visible after entry, reset the selected weight cue after switching profiles, give Coach meal links a usable 44-point target, and prevent automatic reply positioning during manual scrolling. Review and test assertions preserved goal revisions, profile isolation, corrections, meal quantities, AX5 behavior, and workout details.

The auth fixes make plan-use permission explicit, preserve the account grant through temporary usage outages, classify the two supported outage codes in HTTP 200 streams and HTTP 503 responses, bound retries, retain saved input for explicit retry, stop retry after profile changes, and show accurate Usage guidance. They do not introduce API-key billing fallback. The owner’s existing ChatGPT subscription remains the intended inference path.

## Local evidence

Environment for both simulator runs: macOS 27.0.1 arm64, Xcode 27A266a, Mivu Debug, iPhone 18 Pro simulator on iOS 27.0, isolated DerivedData `/private/tmp/mivu-progress-tools-dd`.

The UI covering command was:

```sh
rtk xcodebuildmcp simulator test --project-path /private/tmp/mivu-coach-progress-tools/ios/Mivu.xcodeproj --scheme Mivu --simulator-id 80F2225B-C146-4E59-875C-35249B40F095 --derived-data-path /private/tmp/mivu-progress-tools-dd --extra-args '-only-testing:MivuTests/ProgressEditorStateTests' '-only-testing:MivuUITests/ProgressUITests' '-only-testing:MivuUITests/CoachUITests' '-resultBundlePath' '/private/tmp/mivu-core-native-fix1-green2.xcresult'
```

It started at `2026-10-13T08:11:26Z` and produced 11 passed, 1 failed, 0 skipped in `/private/tmp/mivu-core-native-fix1-green2.xcresult`. The sole failure was `ProgressUITests/testSavedWorkoutSetsAndNoGoalReport`: the newly labeled burn field was below the visible form area when the test tried to edit it. The source review confirmed that its saved labels and values were present; the remaining adjustment reveals the field before editing. It changed only the test helper, not product code or semantic assertions.

The isolated follow-up command was:

```sh
rtk xcodebuildmcp simulator test --project-path /private/tmp/mivu-coach-progress-tools/ios/Mivu.xcodeproj --scheme Mivu --simulator-id 80F2225B-C146-4E59-875C-35249B40F095 --derived-data-path /private/tmp/mivu-progress-tools-dd --extra-args '-only-testing:MivuUITests/ProgressUITests/testSavedWorkoutSetsAndNoGoalReport' '-resultBundlePath' '/private/tmp/mivu-core-native-fix1-workout-final.xcresult'
```

It started at `2026-10-13T08:30:18Z` and passed 1/0/0. This is a separate focused pass, not a combined 12/0/0 result. Covered native scenarios include clearing the final goal and relaunching, preserving historical goals, visible filled-field labels, profile-switch chart selection, actual workout details, separate burn and food budget, and Coach scrolling/touch behavior.

The ChatGPT recovery gate ran from `2026-10-13T08:33:57.935Z` to `08:34:24.402Z`. Exact command:

```sh
rtk proxy xcodebuildmcp simulator test --json '{"projectPath":"/private/tmp/mivu-coach-progress-tools/ios/Mivu.xcodeproj","scheme":"Mivu","simulatorId":"80F2225B-C146-4E59-875C-35249B40F095","derivedDataPath":"/private/tmp/mivu-progress-tools-dd","extraArgs":["-only-testing:MivuTests/ConnectionTests","-only-testing:MivuTests/CoachConnectionTests","-only-testing:MivuTests/CoachEngineTests","-only-testing:MivuTests/ResponsesClientTests","-only-testing:MivuTests/OAuthAttemptTests","-only-testing:MivuTests/ProbeJobTests","-only-testing:MivuTests/CoachFlowTests"]}'
```

The result bundle `test_sim_2026-10-13T08-33-56-489Z_pid43540_0f8d7329.xcresult` reports **130 passed, 0 failed, 0 skipped across seven suites**. The actual named-case verifier confirmed 130 unique tests from `/private/tmp/mivu-subscription-green-summary.json` and the evidence directory:

```sh
rtk proxy python3 scripts/ci/verify_results.py /private/tmp/mivu-subscription-green-evidence
```

These seven suites cover permission/consent, temporary usage recovery, bounded retries, profile-switch cancellation, saved-input retry, and HTTP 503 classification. This is the auth-focused suite, not the full app gate.

## Remaining acceptance

The earlier full aggregate on base `61c80599718b4ec2f80b71b116354f6e79c0e029` stopped at 360 passed, 3 failed (including one owner-canceled test), and 1 skipped. It is historical evidence for the pre-fix source. The scoped fixes above do not turn that run into a pass, and a final full native aggregate on the fixed source is still required. P1 has no hosted PR/CI result and is not merged to main.

Real ChatGPT account consent and eligibility, native iPhone callback/loopback behavior, live text/photo recognition, physical-device accessibility, and actual Files-provider backup/restore remain unverified. Use the owner checklist in [personal iPhone testing](../development/personal-iphone-testing.md) only after a core build is declared ready. Protect the only current backup during restore testing. Keep P2/P3 deferred until core acceptance.
