# Native connection proof verification

Recorded 2026-10-11. Environment: local Apple Silicon Mac, Xcode 27.0, Swift 6,
XcodeBuildMCP; simulator evidence uses iOS 27.0 iPhone 18 Pro. Source baseline
is final source commit `2f98f7c34741ef744b6fcdac9acc0ea9e0f39807`. The 36 iOS
source files in `.superpowers/sdd/2026-10-11-native-connection-proof/final-source-hashes.txt`
match the tested freeze and committed tree; no source changes followed the
native test runs. Evidence below distinguishes the final aggregate from earlier
isolated task runs.

## Final native verification

At 2026-10-11 20:14:56 UTC, the final aggregate command exited 0. It ran 118
test declarations across 9 suites: **117 passed, 0 failed, 1 skipped**. The
skip was the explicitly opt-in native browser test.

```sh
rtk proxy xcodebuildmcp simulator test --project-path ios/Mivu.xcodeproj --scheme Mivu --simulator-id 80F2225B-C146-4E59-875C-35249B40F095 --derived-data-path /private/tmp/mivu-native-dd
```

Raw log:
`/Users/yaakovkhodorkovski/Library/Developer/XcodeBuildMCP/workspaces/mivu-fb0f689f0db9/logs/test_sim_2026-10-11T20-14-56-894Z_pid40112_942cbd08.log`.
Result bundle:
`/Users/yaakovkhodorkovski/Library/Developer/XcodeBuildMCP/workspaces/mivu-fb0f689f0db9/result-bundles/test_sim_2026-10-11T20-14-56-895Z_pid40112_bf9a0b27.xcresult`.

At 2026-10-11 20:15:20 UTC, the separate opt-in native browser smoke exited 0
with **7 passed, 0 failed, 0 skipped**. The real
`ASWebAuthenticationSession` test `nativeAuthenticationBrowserReachesLoopback`
passed in 1.393 seconds. It uses a synthetic local callback and does not sign
in to a provider.

```sh
rtk proxy xcodebuildmcp simulator test --json '{"projectPath":"ios/Mivu.xcodeproj","scheme":"Mivu","simulatorId":"80F2225B-C146-4E59-875C-35249B40F095","derivedDataPath":"/private/tmp/mivu-native-dd","extraArgs":["-only-testing:MivuTests/BrowserCallbackProbeTests"],"testRunnerEnv":{"MIVU_NATIVE_BROWSER_PROBE":"1"}}'
```

Raw log:
`/Users/yaakovkhodorkovski/Library/Developer/XcodeBuildMCP/workspaces/mivu-fb0f689f0db9/logs/test_sim_2026-10-11T20-15-20-904Z_pid40227_0aeeb3dd.log`.
Result bundle:
`/Users/yaakovkhodorkovski/Library/Developer/XcodeBuildMCP/workspaces/mivu-fb0f689f0db9/result-bundles/test_sim_2026-10-11T20-15-20-904Z_pid40227_f7b569b4.xcresult`.

The final native controller suite passed **22/22** in its focused run. Its
regressions cover authorization/ineligibility, account changes, backgrounding,
persistence, deletion, and stale completion. Whole-branch review findings P2
and P3 were fixed and accepted in the scoped follow-up review; the separate
AuthSession logout deletion-retry fix was also accepted.

The final post-commit app build-and-run command exited 0 at 20:16:22 UTC. Its
reported simulator PID `40593` was independently verified as Mivu running:

```sh
rtk proxy xcodebuildmcp simulator build-and-run --json '{"projectPath":"ios/Mivu.xcodeproj","scheme":"Mivu","simulatorId":"80F2225B-C146-4E59-875C-35249B40F095","derivedDataPath":"/private/tmp/mivu-native-dd","launchArgs":["--proof-english","--proof-light"]}'
```

Build log:
`/Users/yaakovkhodorkovski/Library/Developer/XcodeBuildMCP/workspaces/mivu-fb0f689f0db9/logs/build_run_sim_2026-10-11T20-16-22-316Z_pid40465_b80d4a04.log`.

English light and Hebrew RTL dark/accessibility-size screenshots show the
initial screen and were visually inspected. Full scrolling, VoiceOver
interaction, and reduced-motion behavior were not verified. Interactive
Simulator UI tooling remains unavailable in this Xcode environment.

## Implemented and observed

- The app is a native SwiftUI diagnostic screen with a synthetic browser probe.
  It is not a meal diary. English light mode was visually inspected. Hebrew
  strings and RTL direction are present; runtime accessibility and appearance
  inspection remain blocked by unavailable simulator UI tooling.
- The callback suite passed **18 test declarations, 0 failed, 0 skipped** on
  iOS 27.0 iPhone 18 Pro. An opt-in test using the real
  `ASWebAuthenticationSession` and the app's foreground window completed a
  synthetic `127.0.0.1` loopback round trip: **5 passed, 0 failed, 0 skipped**.
  It made no provider request and exchanged no token.
- The Responses client fixture suite passed **17 test declarations, 0 failed,
  0 skipped** in an isolated Swift 6/macOS SwiftPM harness using URLProtocol
  interception. No provider network request was made. The core files were then
  copied into the app; the subsequent native smoke compiled that integration.
- App build-and-run succeeded on the iOS 27.0 iPhone 18 Pro simulator; the
  process was independently observed and the English light-mode screenshot was
  inspected. This is simulator evidence, not physical-device verification.
- The account identity/session isolated package suite passed **33 tests, 0
  failed, 0 skipped** on Swift 6/macOS. Its native iOS-target run passed **34
  test declarations, 0 failed, 0 skipped**, including the iOS Keychain test;
  all app and test sources present in that run compiled. Coverage includes
  protected Keychain records and refresh rotation. This does not prove recovery
  if the provider rotates a refresh token and the app terminates before local
  persistence; reauthorization may then be required.
- The durable synthetic probe-job suite passed **21 tests, 0 failed, 0
  skipped** in its isolated Swift 6/macOS harness. Native app composition and
  protected-file behavior on a physical device were not established there.
- The callback review-fix run passed **11, failed 0, skipped 1**. Its default
  opt-in native-browser smoke was skipped; the earlier separately authorized
  synthetic native-browser run passed 5 tests and remains distinct evidence.
  The scoped fix review approved the changes.
- JOSESwift 3.0.0 is pinned as the app's single external package dependency.

The isolated probe-job command was:

```sh
rtk proxy xcodebuildmcp swift-package test --package-path /private/tmp/mivu-job-work --filter ProbeJobTests
```

The native identity/session command was:

```sh
rtk proxy xcodebuildmcp simulator test --project-path ios/Mivu.xcodeproj --scheme Mivu --simulator-name 'iPhone 18 Pro' --use-latest-os true --derived-data-path /private/tmp/mivu-native-task3-derived --extra-args=-only-testing:MivuTests/IDTokenValidatorTests --extra-args=-only-testing:MivuTests/SessionTests
```

The callback-fix command was:

```sh
rtk proxy xcodebuildmcp simulator test --project-path ios/Mivu.xcodeproj --scheme Mivu --simulator-id 80F2225B-C146-4E59-875C-35249B40F095 --derived-data-path /private/tmp/mivu-native-dd --extra-args '-only-testing:MivuTests/BrowserCallbackProbeTests' '-only-testing:MivuTests/LoopbackCallbackTests' 'CODE_SIGNING_ALLOWED=NO'
```

Exact reported commands:

```sh
rtk proxy xcodebuildmcp simulator test --project-path ios/Mivu.xcodeproj --scheme Mivu --simulator-id 80F2225B-C146-4E59-875C-35249B40F095 --derived-data-path /private/tmp/mivu-native-dd --extra-args '-only-testing:MivuTests/BrowserCallbackProbeTests' '-only-testing:MivuTests/OAuthAttemptTests' '-only-testing:MivuTests/LoopbackCallbackTests' 'CODE_SIGNING_ALLOWED=NO'
```

Exit 0; 18 declarations passed. The separate opt-in native-browser run used the
same simulator and suite with `testRunnerEnv.MIVU_NATIVE_BROWSER_PROBE=1`; exit
0, 5 passed. A method-only selector previously returned exit 0 with zero tests
executed and is excluded from these counts.

```sh
rtk proxy xcodebuildmcp swift-package test --package-path /private/tmp/mivu-response-work --filter ResponsesClientTests
```

Final reported fixture run exited 0 with 17 declarations passed. It ran in the
temporary harness, not the Xcode app target. The original short official
documentation URLs returned 404; current [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
and [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
pages were checked on 2026-10-11.

An XcodeBuildMCP build-and-run and independent simulator process check both
exited 0. The native-browser test log named the test as started and passed.
Result bundle and log paths are retained in the task reports under
`.superpowers/sdd/2026-10-11-native-connection-proof/`.

## Historical initial blocker

The initial scaffold report recorded an Xcode license blocker before
compilation: **0 tests executed**, with pass/fail counts unavailable. The owner
accepted the license afterward, and actual compilation/test runs proceeded.
The old Hello World/zero-tests description is historical and no longer current.

## Decision and remaining gates

The synthetic native callback works on the tested iOS 27 simulator. The log
also warns that HTTP callback support in `ASWebAuthenticationSession` is
deprecated and may be removed in a future iOS release. The documented flow
uses HTTPS for authorization and an HTTP loopback redirect; that live
authorize-to-redirect sequence has not been proven. The current authorized
sign-in implementation remains in scope, with this platform warning recorded
as a future compatibility risk; no alternate redirect was substituted.

The following are not established by these runs:

- Owner-authorized sign-in and consent, provider eligibility, live identity
  validation, token exchange/refresh, or plan usage authorization. The
  sign-in path is implemented; actual owner consent and provider responses are
  the human step needed for live verification.
- A compatible account model completing image inference, or any live provider
  request.
- Physical iPhone behavior, background/lock/relaunch recovery, or runtime
  VoiceOver, Hebrew RTL, dark mode, large-text, and reduced-motion inspection.
- Meal diary behavior, backup provider selection, backup/restore, or completion
  of the full proof.

## Owner live-verification walkthrough

This walkthrough has not been performed. In Xcode, open
`ios/Mivu.xcodeproj`, select the `Mivu` scheme and an iOS 27 simulator, then
run the app. Tap **Connect ChatGPT** and complete the owner's sign-in and
consent in the system browser. The earlier **Test native browser** smoke only
used a synthetic HTTP loopback callback; it did not sign in. Live authorization
uses HTTPS and is expected to return through the documented HTTP loopback
redirect, but that HTTPS-to-HTTP sequence is still unproven and carries the
recorded future iOS compatibility risk.

After the account model catalog loads, choose one listed model and tap **Save
and test synthetic sample**. Wait for the probe status to show **Completed**.
If recording evidence, include only sanitized status, selected model name, and
latency. Do not capture or log tokens, identity details, callback URLs, or raw
provider responses. This step checks a synthetic prompt/image with the owner's
authorized plan; it does not establish behavior with real meal data.

Phone recovery remains a separate unverified step: repeat on the owner's
physical iPhone, then exercise foreground/background, lock, and relaunch and
record whether pending work completes or safely resumes. Until those checks are
performed, physical-device protection and interruption recovery remain
`NOT_RUN_BLOCKED`.

These gates are `NOT_RUN_BLOCKED` or pending, not passes. Interactive AX
inspection was blocked because the available tool expects a SimulatorKit
framework path absent from Xcode 27; no simulator reset or personal data
erasure was performed. The draft PR is [#1](https://github.com/yakov103/mivu/pull/1);
no required CI runs have been observed. Live consent and image inference,
physical-phone interruption recovery, and full accessibility interaction
remain open gates.

## Cost and backup research

Read-only sources checked 2026-10-11: Apple Developer Program membership is
listed at **USD 99/year** (local currency may apply); CloudKit private database
data counts toward each user's iCloud quota; private database use requires
iCloud capability/container setup. See [membership enrollment](https://developer.apple.com/help/account/membership/program-enrollment/),
[program benefits](https://developer.apple.com/programs/whats-included/),
[CloudKit private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase),
and [Xcode iCloud capability setup](https://help.apple.com/xcode/mac/current/en.lproj/dev52452c426.html).
Owner membership and available quota were not verified. No backup provider was
selected, no resources were created, and no restore was proven.
