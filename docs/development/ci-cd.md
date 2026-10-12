# Native CI and delivery

Mivu stays private. GitHub Actions builds Swift 6 with a stable Xcode 26 on the
standard `macos-26` Apple Silicon runner. It selects an available iPhone simulator
with iOS 26 or newer and records the actual tool versions, source commit, UTC
execution time and exit status. The committed JOSESwift 3.0.0 revision is enforced.
Local Apple builds/tests use XcodeBuildMCP; hosted jobs use Xcode's installed
command-line tools directly, without another build wrapper dependency.

## Cost gate: allowance verified

Before running hosted jobs, verify the owner's current included Actions minutes,
remaining shared artifact/Packages storage, and spending stop settings in
[GitHub billing settings](https://github.com/settings/billing/usage). Record that
evidence without personal account details. Only then set repository Actions
variable `MIVU_ACTIONS_ALLOWANCE_VERIFIED` to `true`. Clear it when allowance is
no longer established. No job is scheduled while it is absent/false; a skipped
workflow is **NOT_RUN_BLOCKED**, never native validation evidence.

On 2026-10-12 at 05:51 UTC, the owner's authenticated GitHub billing dashboard
verified GitHub Free: 9 / 2,000 included Actions minutes used, 0 / 0.5 GB artifact
storage used, and $0 billable usage. The existing account Actions budget is $0
with **Stop usage: Yes**. Repository variable
`MIVU_ACTIONS_ALLOWANCE_VERIFIED=true` was set and verified after that evidence.
The repository remains private with default branch `main`. No billing, budget,
payment or visibility settings changed. Earlier read-only billing API calls
returned HTTP 404; dashboard evidence resolved that access limitation. This
allowance evidence is separate from the workflow results recorded below.

GitHub's [billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
provides included minutes/storage for private repositories; excess can be billed.
Larger runners are always paid, so these workflows use neither `large` nor
`xlarge`. Artifact retention is one day, and no package cache is uploaded.
Concurrent account usage and storage can exhaust an earlier allowance: the
variable records verification, it does not enforce a spending limit. Recheck
before additional hosted runs; maintain the owner's existing hard stop policy.
Do not enable payment methods or raise budgets.

An existing dedicated self-hosted Mac would avoid hosted runner minute charges,
according to GitHub's billing documentation, but registration and persistent
runner security require an owner decision. No runner is installed automatically,
no external build service is used, and making the repository public is excluded.

## Pull requests and main

`Native CI` runs on `pull_request`, pushes to `main`, or manual dispatch, subject
to the cost gate. There are no Apple/provider secrets in CI and no privileged
`pull_request_target` or downstream execution of fork code. Checkout credentials
are not persisted, and the token has `contents: read` only. New commits cancel
obsolete CI runs. Each job has a bounded timeout.

The pipeline checks its test-result verifier, runs the complete `Mivu` scheme
with normal simulator signing so Keychain tests retain their entitlements, then
builds the Release simulator application with normal ad-hoc simulator signing.
This preserves Keychain entitlements without an owner distribution certificate. The verifier reads actual
`xcresulttool` summary and named test-case JSON: at least one passing named case
is required, zero-test wrappers and failures fail the job. Pass/fail/skip counts
and named cases are in `test-report.txt`; XCTest's wrapper count alone is not used.
`native-<source SHA>` preserves `Mivu.xcresult`, tool/provenance/count files and
`Mivu-simulator.app.zip` even when a test step fails. The app runs in a simulator;
it is not an iPhone installation artifact. A failure before result generation
cannot produce passing evidence.

Equivalent hosted commands, from the repository root:

```sh
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
bash scripts/ci/native.sh test
```

Each invocation needs a fresh `build/ci` directory; scripts deliberately do not
overwrite a previous result bundle. For repeated local experiments set
`MIVU_CI_OUTPUT` to a fresh temporary directory. Do not run signing on your normal
workstation through these CI scripts.

## Versioned unsigned delivery

Push an existing version tag, or dispatch `Native release` with `tag`, leaving
`signed_delivery` and `upload_testflight` false. Accepted tags are `v1.0.0` and
`v1.0.0-rehearsal.1` style versions. The tag must resolve to a commit already
merged into `origin/main`. The job checks out that immutable SHA, reruns the
native tests, builds the simulator app and archives the device app with signing
disabled. Publishing runs separately with `contents: write`; it executes no
repository code and downloads the current run's immutable artifact with digest
verification. Release concurrency never cancels an active release.

A private draft GitHub release receives the simulator ZIP, unsigned archive ZIP,
provenance and test report. Existing releases/assets are not overwritten by a
rerun: inspect the earlier run, then use a new version if a new delivery is needed.
The draft remains private to repository collaborators and can be reviewed before
publication. **`Mivu-unsigned.xcarchive.zip` is not installable on a physical
phone.** It proves the device target can archive without purchasing membership.

```sh
bash scripts/ci/native.sh test
bash scripts/ci/native.sh unsigned
```

## Signed IPA and internal TestFlight

Run the release workflow **from `main`**, choose the already merged tag, and set
`signed_delivery=true`. `upload_testflight=true` also requests signing. The signed
job checks out the same SHA that passed release tests. Tag pushes never request
Apple delivery automatically. Store owner signing credentials as **repository
Actions secrets** under Settings → Secrets and variables → Actions. The signed
job has no deployment-environment dependency: private environments and their
secrets require a paid plan, as documented in GitHub's
[environment availability](https://docs.github.com/en/rest/deployments/environments).
Mivu remains private on GitHub Free, without an upgrade. The workflow's explicit
manual/main guard and tested-commit checkout control this lane. Repository
secrets are available to trusted repository workflows, so review workflow changes
before merging and restrict repository write access appropriately. No secrets
are supplied to PR CI. See GitHub's
[repository secret instructions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).
If a future plan supports the desired environment isolation/protection, it may
be added separately; it is not a signing prerequisite for this workflow.

Required repository Actions secrets:

| Secret | Owner-provided value |
| --- | --- |
| `APPLE_DISTRIBUTION_P12_BASE64` | Base64 Apple Distribution certificate and private key exported as P12 |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | P12 password |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64 unexpired App Store distribution profile for `com.yakov103.mivu` |
| `APPLE_TEAM_ID` | Matching Apple Developer team identifier |
| `ASC_KEY_ID` | App Store Connect API key identifier; upload only |
| `ASC_ISSUER_ID` | App Store Connect API issuer identifier; upload only |
| `ASC_PRIVATE_KEY_BASE64` | Base64 `.p8` private key; upload only |

The owner must already have valid Apple membership, bundle identifier, matching
capabilities/profile, App Store Connect app record and appropriate API role.
Apple agreements remain an owner/legal gate. The workflow does not enroll,
purchase membership, accept agreements, register a physical device or invite
testers. Missing required secrets produce a clear **failed** signed lane before
any Apple operation; unsigned delivery does not claim signing success.

Signing uses a temporary keychain, strict credential decoding and team/bundle/
expiry/profile validation. The keychain, profile, credential files and private
logs are cleaned up. Only the exported IPA and credential-free provenance are
uploaded. The build number is `<workflow run number>.<attempt>` to avoid reusing
an uploaded build number. An App Store Connect IPA requires Apple distribution;
it is not an ad-hoc direct-install IPA.

Optional upload uses the App Store Connect API key and Xcode's export/upload
command with `testFlightInternalTestingOnly=true`. Successful upload acknowledges
transfer, **not** Apple's processing, tester availability or a device install.
Verify the resulting build in App Store Connect separately before claiming
TestFlight delivery. Nothing is submitted to App Review or external testers.

Primary references checked 2026-10-12:

- [Runner software and Xcode versions](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Immutable checkout action releases](https://github.com/actions/checkout/releases)
- [Upload action releases](https://github.com/actions/upload-artifact/releases)
- [Download action releases](https://github.com/actions/download-artifact/releases)
- [GitHub certificate installation](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [Apple command-line archive/export](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
- [Apple API-key Xcode flags](https://developer.apple.com/videos/play/wwdc2021/10204/)
- [Apple distribution methods](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Internal TestFlight processing and tester groups](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)

## Verification status — 2026-10-12

The English-only change merged in [PR #3](https://github.com/yakov103/mivu/pull/3)
as `9f02a1568701f62a2afd482bf02fc5ed9d9f30bb`. These are observed workflow and
test results, not predictions from workflow files:

See the [MVP acceptance matrix](../verification/2026-10-12-native-mvp-acceptance.md)
for current product and device gates. The final source SHA and release rehearsal
remain pending the native worker's final UI report.

| Evidence | Source and result |
|---|---|
| [PR #3 Native CI](https://github.com/yakov103/mivu/actions/runs/38230868591) | 199 passed, 0 failed, 1 skipped. |
| [Main Native CI](https://github.com/yakov103/mivu/actions/runs/38232085280) | Source `9f02a1568701f62a2afd482bf02fc5ed9d9f30bb`; macOS 26.6.2 arm64; 2026-10-12 09:52:13 UTC; exit 0; 199 passed, 0 failed, 1 skipped. Downloaded simulator app ZIP integrity and strict code-signature checks passed; the artifact is simulator-only. |
| Final local aggregate native suite | 200 passed, 0 failed, 1 skipped; exit 0 in 109.4 seconds. XcodeBuildMCP result bundle `test_sim_2026-10-12T10-16-03-467Z_pid12767_0a4b06c1.xcresult`; log `test_sim_2026-10-12T10-16-03-467Z_pid12767_62699a23.log`. At run time HEAD was `251aafce42b3d3b8f9258f45c6dd8c784f33f01f` with uncommitted changes to `DiaryStyle.swift` and `DiaryUITests.swift`; final review hashes and merge commit are pending. |
| English-focused suite | 10/10 passed. |
| Accessibility-5/photo-focused UI run | Local working-tree run: 2 passed, 0 failed, 0 skipped in 23.3 seconds; result bundle `test_sim_2026-10-12T10-12-30-197Z_pid12219_955f17db.xcresult`. The Log meal control was hittable. Root visually inspected the dark accessibility-5 screenshot: English LTR, wrapping labels, no permanent horizontal clipping, and below-fold content scrollable in the native list. Full VoiceOver remains unverified. |
| [Initial release rehearsal](https://github.com/yakov103/mivu/actions/runs/38226669674) | `v1.0.0-rehearsal.1` completed successfully; private draft has five digest-validated assets. The unsigned device archive is not phone-installable. |

The final release rehearsal will run after the remaining native UI/Files changes
are merged to `main`, against that immutable implementation commit. A following
evidence-only documentation update will record the same release run without
changing its source. End-to-end
acceptance of creating/writing a user-selected Files folder and restoring from
that backup is **PENDING** while it is being exercised; archive unit tests do not
prove the file-provider journey. Physical-camera, haptics, and hardware
VoiceOver/accessibility checks are **NOT_RUN_BLOCKED**. The signed IPA/TestFlight
lane is **NOT_RUN_BLOCKED** because required Apple signing credentials are
unavailable.
Live ChatGPT recognition and Siri remain intentionally deferred. No physical
device, cloud-sync, or pilot outcome is implied by the passing simulator CI.
