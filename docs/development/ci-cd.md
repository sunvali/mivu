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

On 2026-10-13, the post-merge run
[38425072684](https://github.com/yakov103/mivu/actions/runs/38425072684) was blocked
before any steps by GitHub's payment/spending-limit check. The earlier allowance
is no longer established. Native scheduling remains blocked until the owner
restores Actions availability and verifies the current included allowance.

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

The Linux `checks` job runs short CI-script tests and shell syntax checks. Edits
limited to Markdown or `docs/` stop there. Unknown or empty changed-file lists
select native verification. Source changes cannot pass by silently skipping an
unverified native allowance: the selection step fails with a blocked message.

Routine native checks build Debug and run the entire `MivuTests` unit target,
with a ten-minute timeout and normal simulator signing for Keychain entitlements.
They do not run UI journeys or package a Release app. Main uses the same quick
checks rather than repeating the full UI suite after every merge. There is no
new package/build cache or larger runner spending.

Before merging screen/navigation changes, dispatch **Native CI** from Actions,
select the PR's current branch, and enable **full_suite**. This runs the complete
unit and UI scheme with a thirty-minute timeout. Verify the successful run's
source SHA against the final PR head; a subsequent commit needs fresh evidence.
This is a contributor merge rule, not an enforced branch-protection setting.

Both modes retain actual `xcresulttool` summary and named-test verification:
zero-test wrappers, failures and expected failures fail the job. The
`native-<source SHA>` artifact preserves the result bundle and tool, provenance
and count files. Unit evidence is not full UI acceptance. Release simulator
packaging belongs to the release workflow; that app is not a phone installation
artifact. The faster hosted duration must be measured after Actions is available.

Equivalent hosted commands, from the repository root:

```sh
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
bash scripts/ci/native.sh unit # routine Debug build and unit tests
bash scripts/ci/native.sh test # manual full unit and UI suite
```

Each invocation needs a fresh `build/ci` directory; scripts deliberately do not
overwrite a previous result bundle. For repeated local experiments set
`MIVU_CI_OUTPUT` to a fresh temporary directory. Do not run signing on your normal
workstation through these CI scripts.

## Versioned unsigned delivery

Google's pinned **release-please** action maintains a version/changelog PR after
Conventional Commits reach `main`. Squash merges use the PR title:
`fix: ...` bumps patch, `feat: ...` bumps minor, and `feat!: ...` or a breaking
change bumps major. The separate **Commit title** check validates those titles
and reruns on title edits without restarting native CI. Preserve a conventional
title when squash-merging; the repository's default squash title is the PR title.

The baseline is `1.0.0`, matching `version.txt`, the release manifest and the
shared Xcode marketing version. Existing rehearsal tags are preserved. Bootstrap
starts after `4f97261eb10d2af2a1301251c8e46748d7cc0dab`; release-please determines
the next version from subsequent commits and updates the shared `.xcconfig`
alongside its version file, manifest and changelog.

Merging a reviewed version PR creates its tag and GitHub release. Explicit
workflow dispatch starts full native verification and unsigned packaging for
that tag. Token-created PRs and tags do not automatically start other workflows,
so version PRs explicitly dispatch quick CI and title validation too. The action
uses the built-in token; no personal access token or Apple credential is added.
Bot PR creation must be allowed in repository Actions settings. The workflow
creates version PRs; it never approves or merges them.

Release notes/tag creation and successful binary packaging are separate outcomes.
Packaging attaches products to an existing release while preserving its notes,
or creates the earlier private draft release when the tag has no release. It
never clobbers assets. A duplicate upload fails rather than replacing published
files. The repository remains private; automatic packaging does not request
signed delivery or TestFlight.

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
bash scripts/ci/native.sh release # full tests and Release simulator packaging
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

These are observed results, not predictions from workflow files. The [MVP
acceptance matrix](../verification/2026-10-12-native-mvp-acceptance.md) separates
the hosted baseline from local working-tree checks and remaining acceptance gates.

| Evidence | Source and result |
|---|---|
| [PR #4](https://github.com/yakov103/mivu/pull/4) | Merged externally while its CI run was still running. |
| [Main Native CI](https://github.com/yakov103/mivu/actions/runs/38236090700) | Source `7a86d046200fa4e86e5110b96aa31fd479a99822`; macOS 26.6.2 arm64; provenance `2026-10-12T10:29:43.930615Z`; exit 0; 200 passed, 0 failed, 1 skipped. This is the clean hosted baseline. |
| [Unsigned release rehearsal](https://github.com/yakov103/mivu/actions/runs/38238559422) | Run succeeded against the same `7a86d046200fa4e86e5110b96aa31fd479a99822` source; 200 passed, 0 failed, 1 skipped. Test provenance `2026-10-12T10:53:36.332089Z` and unsigned archive provenance `2026-10-12T10:54:17.610489Z`; both exit 0. Five downloaded assets matched release metadata size and SHA-256; ZIP integrity checks passed. The simulator app ZIP SHA-256 is `edf74aba2512397602b2e7cdc34a529723f34483c9bb0c2ad096809640ae1fa8`; the unsigned archive ZIP SHA-256 is `376652240209c6337671c1e945bede0a8f91e3bab441e42a505b6bcc1214857c`. |
| [Private draft release](https://github.com/yakov103/mivu/releases/tag/untagged-746cb4d76e3ed82ebe51) | Tag `v1.0.0-rehearsal.2`; the unsigned device archive is not installable on a physical iPhone. |

The tag-triggered rehearsal did not request signed delivery, so the signed job
was skipped. Required Apple signing secrets remain unavailable; signed delivery
is separately blocked. No signed or phone-installable artifact was produced.
Physical camera, haptics, hardware VoiceOver/accessibility, actual Files-provider
roundtrip, and pilot acceptance remain unverified. The current coach expansion is
underway and is not verified by this sample-diary baseline. Simulator CI and
archive tests do not establish those outcomes.
