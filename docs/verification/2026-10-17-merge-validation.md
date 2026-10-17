# Full native validation before the color and Pip merges

Tested source: `7eb7035bc31f196d35a3b6958e278d3a5c087c81`. Native tree: `66bf689369d1ab27204cbea689f453621e5eb2ea`.
The following documentation-only evidence commit does not change native inputs.
Independent Ponytail reviews found no blocking regression in PR16 (`897d1a2`)
or PR17 (`7eb7035`). The owner explicitly authorized both merges and a release draft.

## Complete scheme result

| Check | Passed | Failed | Skipped |
|---|---:|---:|---:|
| Native units and renderer | 540 | 0 | 1 |
| Complete native UI suite | 37 | 0 | 0 |
| Combined scheme | 577 | 0 | 1 |
| Repository script tests | 31 | 0 | 0 |

The expected skip is `nativeAuthenticationBrowserReachesLoopback`, which needs
interactive account authorization. No test selector or skip selector was used.
All Coach, Companion, Diary and Progress UI cases passed, including the long
history, large-text, goals/workout persistence and idle-loop journeys.

Environment: iPhone 17 Pro, iOS26.5, macOS 27.0.1,
arm64; Xcode 27.0 at `/Applications/Xcode.app`.
Run began at `2026-10-17T17:47:35.833Z` and took 2133.993 seconds.

Actual command, from the tested checkout:

```sh
rtk proxy xcodebuildmcp simulator test --json '{"projectPath":"/private/tmp/mivu-local-hooks/ios/Mivu.xcodeproj","scheme":"Mivu","simulatorId":"42CE2315-9339-4EF1-A5B4-064444D0FA44","configuration":"Debug","derivedDataPath":"/private/tmp/mivu-pip-derived","preferXcodebuild":true,"extraArgs":["-parallel-testing-enabled","NO","-disableAutomaticPackageResolution","-onlyUsePackageVersionsFromResolvedFile"]}' --output json
```

Exit status was zero; structured `didError` was false, status `SUCCEEDED`,
578 tests were discovered and no test failure was recorded.
Result bundle: `/Users/yaakovkhodorkovski/Library/Developer/XcodeBuildMCP/workspaces/mivu-local-hooks-b9c7ae5548f8/result-bundles/test_sim_2026-10-17T17-47-35-833Z_pid73808_b5f5a248.xcresult`.
The tool result and compact provenance are retained in the primary workspace at
`output/pip-lottie-verification/2026-10-17-merge/`.

## Remaining diagnostic and delivery limits

Nine UI methods logged `Invalid frame dimension (negative or non-finite)` without
failing. The source of this previously observed diagnostic remains unproven;
[issue #18](https://github.com/yakov103/mivu/issues/18) tracks reproducing and fixing
its actual calculation. The passing result is not a claim of warning-free logs.

The earlier iOS 27.0 complete UI run with 34 passes/three failures remains
historical evidence. This new full pass establishes the current iOS 26.5 result;
it does not explain that earlier environment-specific failure.

The Release at implementation `65bd63b` was installed and launched on the owner’s
iPhone; later commits changed documentation only. Physical frame pacing, energy,
thermals, broader provider/camera behavior and manual accessibility acceptance
remain unmeasured. No signed release binary or TestFlight upload is implied.

Runtime JSON SHA-256: `5a39809af6996b9a4c8eb6dc6a21776c90bf192de3071b35eeb75ac4dd54b06d`.
The requested release is a draft; the automated stable version PR remains
separate from binary delivery and publishing.
