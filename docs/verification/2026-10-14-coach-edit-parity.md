# Coach edit parity: local acceptance

Final native inputs: `72822ba8b73a8eee63bd3ef79048edfd94da5dee` on
`feature/coach-edit-parity`, based on main `8cf1e85e0920726638b987468260f35410d4fa53`.
Later documentation-only commits do not change the tested native inputs.
Production app source is unchanged from
`39066bf8dd5443bac0c2f7d66e11586def97a834`; `72822ba` corrects the UI harness only.

Local result: **417 unit passes and passing coverage of all 15 simulator
workflows**. The UI evidence is 13 full-target passes plus two corrected workflow
reruns, not a fresh single all-target green run. Physical acceptance has started:
live meal logging and correction passed as recorded below. The remaining device
and Files-provider checks are incomplete. Keep the PR draft and unmerged.

## Delivered scope

- [x] Meal and proposed-review item patches preserve omitted fields and other items.
- [x] Append food; move/delete meals; attach/delete photos; accept reviews; retry
  the original paused capture without duplicating food.
- [x] Read and patch dated goals and preferences; explicitly start days and set
  historical coverage. Existing weight and workout tools remain available.
- [x] Commit record changes and operation receipts atomically through the same
  `DiaryStore` used by manual screens. Distinct patches get distinct stable keys;
  identical retries reuse their committed result across relaunch.
- [x] Show native, accessible photo/thinking/reading/saving activity. Reduce Motion
  uses a static indicator. Cancel/profile/session changes clear transient activity.
- [x] Offer native Settings links for account, profiles, secrets and Files actions.
  A handoff does not claim the native action has completed.
- [x] Merge untouched Settings fields when Coach changes saved preferences;
  preserve conflicting drafts and reject concurrent stale replacements.
- [x] Run independent Ponytail source review and close its findings.
- [ ] Complete the owner's real-iPhone, real-ChatGPT acceptance checklist.
- [ ] Merge only after that device acceptance. Automatic merging stays disabled.

See the [tool matrix and device checklist](../development/coach-edit-parity.md)
for exact boundaries. No dependency, hosted native job, billing change or new
backend was added.

## Native unit verification

Completed 2026-10-13 at 22:59 UTC (2026-10-14 locally). Environment: Apple Silicon,
macOS 27.0.1, Xcode 27.0 build 27A266a, XcodeBuildMCP 2.6.2, iPhone 18 Pro simulator
with iOS 27.0. Source and environment remained unchanged during the run.

Exact entry command from the repository root:

```sh
python3 -c 'import sys, subprocess; sys.path.insert(0, "scripts/ci"); import git_hooks; git_hooks.native_check(subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip())'
```

The helper invoked XcodeBuildMCP `simulator test` with `-only-testing:MivuTests`,
serial execution, resolved package versions and Swift 6.0. Its cached record keeps
the complete invocation and environment. Exit **0**: **417 passed, 0 failed,
1 skipped**, 43.439 seconds reported by the native runner. The skipped
`nativeAuthenticationBrowserReachesLoopback` test requires an interactive native
browser and is not account-authorization evidence.

Local artifacts in Git's common directory:

- `mivu-checks/native-f4flv0rd/result.json`
- `mivu-checks/native-f4flv0rd/Mivu.xcresult`
- Success record
  `mivu-checks/e59f2e7ce293c1122b0756daded4532bfda3565b171a35f3e720543a14f8ca0f.json`

The earlier complete run at `a09443d` finished with 413 passes, two failing groups,
and one skip. The failures exposed the request client's old 16-tool validation
bound, which rejected the expanded catalog before network access. The fix keeps
the existing size/schema bounds and per-turn execution budget. A focused RED run
had 47 passes and three failures; the corrected `ResponsesClientTests` and
`CoachConnectionTests` run had **50 passes, no failures or skips**. A new test
passes the actual catalog through the real request serializer; another rejects
33 declarations before network access. The bound of 32 is a local resource limit,
not a claim about the live provider's supported catalog size.

## Other checks

`python3 -m unittest discover -s scripts/ci -p 'test_*.py'` completed with exit 0:
**31 passed**, no failures/skips, in 18.753 seconds. These are delivery-script
tests, not native acceptance. `git diff 8cf1e85..HEAD --check` also exited 0.

## Simulator UI investigation

The first complete UI attempt at `d52590a` was stopped after it exposed two
reproducible Coach failures. The final partial result reported 5 passes and
3 failures: two assertions and one cancellation from stopping the active case.
This interrupted run is **not** a passing full UI result.

- The conversation and its four replies persisted across relaunch. The failing
  assertion checked that the fixture banner at the top of a lazy scroll stack
  existed while that part of the stack was offscreen.
- At the largest Dynamic Type size, a completed reply existed but was not
  reachable without scrolling. The follow logic treated the pre-scroll tracking
  phase as a user scroll-away and could skip its only follow attempt during
  keyboard/layout changes.

Artifacts: `/private/tmp/mivu-coach-parity-ui-final.json` and
`/private/tmp/mivu-coach-parity-ui-final.xcresult`. The fix and final UI gate
are recorded separately on their exact source revision.

The correction excludes `.tracking` from intentional user scrolling and holds a
pending reply until it can be followed while idle. A real drag away still turns
following off. The relaunch assertion reveals the lazy banner before checking
it. Both formerly failing cases passed on the reviewed two-file change:
**2 passed, 0 failed, 0 skipped** at 2026-10-13 22:40 UTC. Artifacts:
`/private/tmp/mivu-coach-scroll-green.json` and
`/private/tmp/mivu-coach-scroll-green.xcresult`. These native inputs were then
committed as `39066bf`. The scroll fix also received independent Ponytail review
with no open source finding.

Apple defines [tracking](https://developer.apple.com/documentation/swiftui/scrollphase/tracking)
as the phase before scrolling begins; [animating](https://developer.apple.com/documentation/swiftui/scrollphase/animating)
describes a programmatic scroll. The distinction keeps touches and automatic
layout changes from being interpreted as a request to stop following replies.

The complete 15-case UI target at `39066bf` finished with **13 passed, 2 failed,
0 skipped** in 932.954 seconds. This is a failed full-target result. Both failed
Progress workflows used a helper that required the multiline meal field to stay
hit-testable after keyboard focus; native typing succeeded and the saved meal
later produced the expected 95 kcal. One also required a separate hit test on
the workout-burn field before a successful native tap, typing and saved 120 kcal
assertion. Other Coach, diary, profile, English LTR, accessibility and chart
workflows passed.

The test-only correction in `72822ba` removes those transient hit-test assumptions
and checks the exact nonempty edited value instead. Empty goal clears still use
the existing save/relaunch assertions because the accessibility value of an
empty field contains its placeholder. All button, report and chart reachability
checks remain. `git diff 39066bf..72822ba --name-only -- ios/Mivu` is empty: no
production app source changed. Independent Ponytail review found no issue in
this five-line test delta.

Artifacts: `/private/tmp/mivu-coach-parity-ui-39066bf.json` and
`/private/tmp/mivu-coach-parity-ui-39066bf.xcresult`. Two affected complete
workflows are rerun separately on the corrected harness; the other 13 are not
repeated. Report those covering results separately rather than claiming a new
single all-target green run.

The two corrected complete workflows at `72822ba` finished on 2026-10-13 at
23:06 UTC with exit **0**: **2 passed, 0 failed, 0 skipped**, 351.163 seconds:

- `ProgressUITests.testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch`
- `ProgressUITests.testSavedWorkoutSetsAndNoGoalReport`

Invocation (the local simulator identifier is kept in the private result JSON):

```sh
rtk xcodebuildmcp simulator test \
  --project-path /private/tmp/mivu-local-hooks/ios/Mivu.xcodeproj \
  --scheme Mivu --simulator-id "$MIVU_SIMULATOR_ID" \
  --derived-data-path /private/tmp/mivu-coach-parity-dd \
  --extra-args \
  '-only-testing:MivuUITests/ProgressUITests/testSavedGoalsWeightWorkoutAndReportsSurviveRelaunch' \
  '-only-testing:MivuUITests/ProgressUITests/testSavedWorkoutSetsAndNoGoalReport' \
  '-parallel-testing-enabled' 'NO' '-disableAutomaticPackageResolution' \
  '-onlyUsePackageVersionsFromResolvedFile' \
  '-resultBundlePath' '/private/tmp/mivu-progress-input-green.xcresult' \
  --output json > /private/tmp/mivu-progress-input-green.json
```

The full-target command used the same project, simulator, scheme and derived-data
directory, selected `-only-testing:MivuUITests`, and wrote the `ui-39066bf` artifacts
above. No test was skipped in either UI result. All 15 workflows have passing
coverage against identical production app inputs; only the two corrected tests
were repeated. No physical-device or live-provider claim follows from these
fixture-based workflows.

The UI runner also recorded non-failing `Invalid frame dimension (negative or
non-finite)` warnings in existing native forms. The artifacts retain them; this
slice does not establish their cause or claim the forms are warning-free.

## Review

Independent Ponytail review inspected the connected engine, validation, store,
receipt, Settings and test paths for the expected single-profile local-app load.
There are no open source findings in the reviewed delta. Its fixes cover distinct
sequential edits versus retry identity, complete meal refresh after writes,
truthful photo/move confirmations, retaining one durable photo copy, preserving
exact eating timestamps, and forwarding the actual catalog through the request
boundary. Focused regression tests reproduced the original failures before the
fixes and passed afterward.

Review does not authorize merging before the owner's device gate.

## Physical acceptance in progress

On 2026-10-14, the ordinary Debug build from clean source
`be694adf922fbefd287e2e2f3413113d8568203a` was signed locally, installed and
launched on the owner's physical iPhone running iOS 27.0.1. XcodeBuildMCP
`device build-and-run` returned exit 0 and `SUCCEEDED` in 22.789 seconds, with
empty launch arguments and no fixture mode. Device and signing identifiers stay
in private local invocation files. Result:
`/private/tmp/mivu-device-parity-result.json`.

Live interaction used iPhone Mirroring and the existing ChatGPT sign-in. A new
isolated local profile, `Coach acceptance Oct 14`, was selected before submitting
synthetic inputs. No account tokens or personal diary records are included here.

- Text logging: "Log two boiled eggs, two slices of whole-wheat bread, and one
  tomato for today. This is synthetic test data." The completed response reported
  318 kcal and uncertainty. The native saved meal agreed: 2026-10-14, 318 kcal,
  29.9 g carbohydrate, 21.7 g protein and 12.8 g fat.
- Correction: "Actually I only ate one slice of the bread. Update the existing
  meal and keep the eggs and tomato unchanged." The completed response reported
  248 kcal. The same native meal showed bread changed from two slices to one,
  eggs still two and tomato still one. Totals were 248 kcal, 17.9 g carbohydrate,
  17.7 g protein and 11.8 g fat; Today displayed the same values.
- The native thinking indicator was visible during live requests. Mouse-wheel
  scrolling revealed all corrected food items in the native meal screen.

A combined dated-goal, preference, weight and workout request was submitted and
its saved input and thinking indicator were visible. After reopening the installed
app, native screens on the same QA profile established these saved results:

- Today: 2,000 kcal goal; carbohydrate 200 g, protein 100 g and fat 70 g targets;
  1,752 kcal remaining after the recorded 248 kcal meal. Macro remaining values
  were 182.1 g carbohydrate, 82.3 g protein and 58.2 g fat.
- History: the 2026-10-14 tracking day displayed 70 kg.
- Progress daily report: estimated workout burn was 120 kcal, separate from the
  recorded 248 kcal food intake. Food remaining stayed 1,752 kcal, consistent
  with the requested disabled exercise credit.

The full combined reply, native goal-weight editor, preference text, morning
weight flag and workout type/duration have **not yet been inspected**. Automated
mouse-wheel scrolling did not move the Settings or Coach viewport during this
attempt. This is an automation limitation, not evidence that owner scrolling is
broken. Mirroring then disconnected because the iPhone was in use. Do not resend
the combined write request: the native records already show committed changes.

## Remaining acceptance

Eligible-model inspection, the remaining manual-edit workflows, relaunch,
live image inference, interruption/retry and Files-provider actions are still
unverified. No cloud-sync claim follows from a local save or file-provider write.
Simulator inference uses synthetic fixtures; those tests establish local
behavior only. Keep the PR draft and unmerged until device acceptance is complete.
