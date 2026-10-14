# Coach edit parity: local acceptance

Baseline native inputs: `72822ba8b73a8eee63bd3ef79048edfd94da5dee` on
`feature/coach-edit-parity`, based on main `8cf1e85e0920726638b987468260f35410d4fa53`.
Later documentation-only commits do not change the tested native inputs.
Production app source for that baseline is unchanged from
`39066bf8dd5443bac0c2f7d66e11586def97a834`; `72822ba` corrects the UI harness only.

Local result: **417 unit passes and passing coverage of all 15 simulator
workflows** on the previously recorded inputs. The UI evidence is 13 full-target
passes plus two corrected workflow reruns, not a fresh single all-target green
run. Physical acceptance has started on installed source `be694ad`. The summary
preservation fix is committed as `bae16bc8258c0a17cf11f166e147726e73b9e9e2`;
its exact native source files have focused simulator coverage and were installed
on the physical iPhone. The later live read returned stored progress and workout
facts, as recorded below.
Scroll-follow is committed as
`d1dde4297bbb1811158e345b3fbde3674e911c94` and has focused UI coverage; it has
been installed and relaunched on the phone. Automatic thinking/reply following
was observed; history-position preservation is still pending. The latest native
push check passed 418 tests,
0 failures and 1 skip. The full 15-workflow UI gate has not been rerun on these
latest patches. The earlier 417-unit and 15-workflow coverage does not establish
verification of these latest patches. Keep the PR draft and unmerged.

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

A combined dated-goal, preference, weight and workout request was submitted on
the same QA profile. Its complete Coach reply was later inspected. It reported
the saved 2,000 kcal goal with 200 g carbohydrate, 100 g protein and 70 g fat;
exercise credit was disabled. It also reported quick vegetarian meals, timezone
`Asia/Jerusalem`, a recorded weight of 70 kg, and 30 minutes of cardio. The native
Workout record shows cardio for 30 minutes with an estimated 120 kcal burn and
unspecified time. Native Today had previously shown 1,752 kcal remaining after
the original 248 kcal meal. The native goals/settings editor and morning-weight
flag remain unverified.

- History: the 2026-10-14 tracking day displayed 70 kg.
- Progress daily report: estimated workout burn was 120 kcal, separate from
  food intake. Food remaining stayed 1,752 kcal, consistent with disabled
  exercise credit.

Two more live requests completed against the existing meal. First: “For the
tomato in my existing meal, clear protein and set carbs to 2 g. Keep everything
else unchanged.” The native tomato row showed 22 kcal, 2 g carbohydrate, blank
protein, 0.2 g fat, and quantity one tomato. The eggs remained two and the bread
one; the meal showed 248 kcal, 15.1 g carbohydrate, unknown protein and 11.8 g
fat. Second: “Add one medium apple to the same existing meal. Keep the eggs,
bread and tomato unchanged.” The reply completed and the native meal showed 343
kcal, 40.1 g carbohydrate, unknown protein and 12.1 g fat. Its four rows were
eggs quantity two, bread quantity one, tomato quantity one and apple quantity
one. The food list ended at “Update meal,” with no duplicate rows. These checks
pass the nutrient-clear/change and append-food checklist items.

Mouse-wheel scrolling worked on the native Meal screen. Earlier attempts did not
move the Settings or Coach automation viewport; those particular screens remain
uninspected and this does not indicate whether owner scrolling works. Do not
resend the combined write request: its records are already committed.

## Focused verification of latest local patch

The two-file patch in `CoachEngine.swift` and `CoachEngineTests.swift`, committed
as `bae16bc8258c0a17cf11f166e147726e73b9e9e2`, fixes a summary bug: adding a
read-only Settings operation to a turn no longer discards existing progress or
workout facts from the combined reply. The focused regression first failed, then
passed after the fix. Five selected regression functions, including the new
regression, also passed. The same native source files were tested immediately
before commit at parent
`8a09645b81a7a74b9d7e4749643e5479b0922b08`.

Evidence was recorded 2026-10-14 10:10 UTC in
`/private/tmp/mivu-combined-read-evidence.json` on local macOS using the existing
Mivu simulator and derived data. The focused RED command exited 1 with 0 passed,
1 failed and 0 skipped. GREEN exited 0 with 1 passed, 0 failed and 0 skipped.
Five selected regression functions, including the new regression, passed with
exit 0, 5 passed, 0 failed and 0 skipped. Independent Ponytail review approved
the source delta. That review did not cover patched physical-device acceptance.
The complete native unit suite later passed on descendant source `d1dde42`; see
the latest source verification below. The full UI workflow gate has not been
rerun on these patches.

The ordinary physical-iPhone build from `bae16bc` installed and launched with
exit 0, `SUCCEEDED`, in 10.493 seconds, with zero diagnostics. Invocation reused
the private local device/signing arguments and empty launch arguments; result:
`/private/tmp/mivu-device-combined-reply-result.json`. The existing conversation
and completed 343 kcal append reply were still visible after launch. The exact
read-only prompt, “Show saved goals, preferences, weight and workouts. Read
only.”, was submitted again. Its input saved successfully, but Mirroring paused
because the iPhone was in use before the completed response could be inspected.
The response was later inspected after reconnection: it included the stored
343 kcal food intake, 1,657 kcal remaining, one workout, estimated burn of
120 kcal, average weight 70 kg from one measured date, and cardio for 30 minutes.
Unavailable longer-term weight changes were reported as insufficient data;
protein remained unknown after the explicit nutrient clear. The displayed part
of this reply did not establish that all four requested categories were returned.
The deterministic combined-tool regression establishes summary preservation;
live tool selection was not captured.

## Scroll-follow correction

The owner reported that arriving messages and thinking did not stay visible
automatically. Commit `d1dde4297bbb1811158e345b3fbde3674e911c94` follows new
activity while the reader is at the bottom, preserves history position during
interaction, and provides a “New message” button to return. The two original
product failures were a clipped thinking indicator and a missing new-message
button. A source review also found a follow-state edge case: a resting finger
should pause following without being treated as intentional history browsing.
The test
for a stationary finger passed on old code, so it is not evidence that this
edge case reproduced before the fix.

The ordinary `d1dde42` physical build installed and launched successfully in
6.631 seconds with zero diagnostics, using the existing private device/signing
arguments and no fixture launch flags. Result:
`/private/tmp/mivu-device-scroll-follow-result.json`. A controlled Mivu-only stop
and relaunch both returned exit 0; private results are
`/private/tmp/mivu-scroll-relaunch-stop.json` and
`/private/tmp/mivu-scroll-relaunch-launch.json`. The saved conversation and
progress response remained visible.

Two real requests automatically brought the thinking row fully above the
composer, then followed their completed reply and review link. The historical
request "Prepare a review-first meal of 100 g plain yogurt for 2026-10-13. Do not
accept or count it yet." produced an Awaiting review meal dated 2026-10-13 with
100 g yogurt and no saved food items. "Change the proposed yogurt quantity to
50 g. Keep it awaiting review; do not accept it." changed the native proposal to
50 g while preserving Awaiting review and no saved items. Explicit acceptance
and duplicate-count verification remain pending.

Automated mouse-wheel input did not move the Coach viewport into history. The
owner was asked to scroll manually in Mirroring before a live arrival check.
The physical “New message” affordance and history-position preservation remain
unverified; the four focused simulator cases below cover this behavior locally.

The final focused simulator UI run on `d1dde4297bbb1811158e345b3fbde3674e911c94`
passed **4 cases, 0 failures and 0 skips** in 127.7 seconds with no warnings. It
covered dark mode at the largest text size, latest actions while browsing
history, a resting finger during thinking, and an incoming weekly-history
response followed by returning to the latest activity. This targeted result does
not establish a passing full 15-workflow UI gate. Two earlier selected cases
passed in 135.7 seconds on an intermediate source: one covered the incoming
weekly summary, and the other covered meal correction, historical review and
conversation relaunch. That result included a known frame warning and is separate
from the final four-case run. Independent Ponytail review approved the source
change.

## Latest source verification

On 2026-10-14, the local push check for `d1dde4297bbb1811158e345b3fbde3674e911c94`
completed successfully from `/private/tmp/mivu-local-hooks` on macOS. Exact entry
command: `git push origin feature/coach-edit-parity`. Its local hook passed 31
script checks in 23.432 seconds and the full Mivu native unit suite: **418
passed, 0 failed, 1 skipped** in 54.209 seconds. The hook exited 0. Linux script
checks (22 seconds) and the PR title check (7 seconds) also
passed in [the script check run](https://github.com/yakov103/mivu/actions/runs/38551334922/job/115809744121)
and [the title check run](https://github.com/yakov103/mivu/actions/runs/38551334858/job/115809741510).
The native result is in `mivu-checks/native-eh0qwvu4/result.json` with
`Mivu.xcresult` alongside it in the Git common directory. This is the first full
native unit result for the latest source; the historical 417-test result above
belongs to `72822ba`.

The four focused UI cases were run with XcodeBuildMCP `simulator test` on the
iPhone 18 Pro / iOS 27 simulator, scheme `Mivu`, serial execution. The selected
tests were `testLatestFollowsActionsAndHistoryOffersNewMessage`,
`testThinkingFollowsLatestThenReplyPreservesHistoryAndJumpResumesFollowing`,
`testRestingFingerDuringThinkingDoesNotDisableFollowing`, and
`testLargestDynamicTypeDarkCoachKeepsCaptureReachable`. The command and private
arguments are recorded in `/private/tmp/mivu-scroll-follow-evidence.json`; the
final result bundle is
`test_sim_2026-10-14T10-35-37-531Z_pid87991_3526cded.xcresult`. Its evidence has
no simulator identifier in this document. This focused UI result does not
replace the full 15-workflow UI gate.

## Remaining acceptance

Eligible-model inspection and the remaining manual-edit workflows,
live image inference, interruption/retry and Files-provider actions are still
unverified. No cloud-sync claim follows from a local save or file-provider write.
Simulator inference uses synthetic fixtures; those tests establish local
behavior only. Keep the PR draft and unmerged until device acceptance is complete.

## Offline follow-up after owner-reported failures

The owner reported that the “New message” button appeared while already viewing
the newest message. The live QA conversation also showed “Are another yougurt”
and the corrected “I ate another yougurt” each completing with “No new food was
saved in this turn” and the unchanged 343 kcal daily summary. The exact provider
tool choices and raw final prose were not captured, so the original cause of
its choice cannot be asserted. Source inspection did confirm that the engine
discarded a safe follow-up question when it appeared as final prose.

The owner disconnected the iPhone for this work. No installation, Mirroring,
or physical acceptance is claimed for this follow-up patch.

The new `ask_clarification` tool chooses one of five fixed kinds: portion, food,
day, meal or workout. The app owns the question text, persists the reply in the
existing conversation, and makes no food change. The tool must be called alone
before current-turn writes. The logging instructions distinguish later intake
from a named unaccepted review. The native store and committed receipts remain
the authority for save confirmations.

Independent review rejected an earlier free-text question design: “Saved the
yogurt. What portion did you eat?” and passive save claims could bypass the
old prose guard. The typed-kind design rejects arbitrary question fields and
renders only app-owned questions. On local macOS, the safety regressions first
returned exit 1 with **1 passed, 4 failed, 0 skipped**; the final focused result
returned exit 0 with **5 passed, 0 failed, 0 skipped**. Thirteen selected engine
regressions then passed with **13 passed, 0 failed, 0 skipped** and no diagnostics.
These runs used the uncommitted patch on parent `398ea63`, before its source
commit. The evidence records exact file hashes and commands in
`/private/tmp/mivu-clarification-kind-evidence.json`; argument and result files
are retained beside it. The GREEN artifact is
`/private/tmp/mivu-clarification-kind-green.xcresult`, and the regression artifact
is `/private/tmp/mivu-clarification-kind-regressions.xcresult`.

The regression leaves an earlier 50 g yogurt proposal unaccepted, persists a
portion question, then saves one new 150 g yogurt after an answer. It interrupts
and retries the save and verifies the same receipt and record are reused.
This establishes local orchestration and persistence, not live provider choice.

Scroll migration tests also exposed real failures. An edge-only target left a
long reply below the composer, despite relaunch positioning passing. Registering
lazy scroll targets and following the last row's identity corrected that case.
An intermediate four-case gate then returned **2 passed, 2 failed**: latest/relaunch
and large text passed, but history browsing moved and its arrival button was
missing. Native user-position reporting alone did not replace direct touch-phase
intent checks. These failed runs remain in
`/private/tmp/mivu-scroll-badge-evidence.json`; they are not passing acceptance.
The owner's transient badge trigger itself has not been reproduced.
Restoring direct interacting/decelerating intent checks alongside the native
user-position flag passed both affected history cases: **2 passed, 0 failed,
0 skipped**, exit 0, 84.4 seconds. The result bundle is
`test_sim_2026-10-14T11-56-48-894Z_pid35367_359f8572.xcresult`; exact commands and
source hashes are in the same private evidence record.
The latest-message/no-badge/relaunch case then passed **1 passed, 0 failed,
0 skipped**, exit 0, 32.7 seconds, with result bundle
`test_sim_2026-10-14T11-58-28-896Z_pid35805_cd658c3c.xcresult`. There are three
distinct passing UI cases on the final source, across two invocations, with no
diagnostics. This is not a four-case combined pass or a full UI-target pass.
The final five code/test files were committed as
`78498f2b6d336f0c411fa4a53cb92cc694a06df7`. Their exact hashes
match the focused evidence. Independent cross-review of the engine and UI
found no remaining source issue for a selected local profile with one serialized
worker. Pointer input and real provider behavior remain outside this evidence.

The required local pre-push gate on `78498f2b6d336f0c411fa4a53cb92cc694a06df7`
returned exit **0** on 2026-10-14, local macOS / Xcode 27 / iOS 27 simulator:
**31 script tests passed** in 24.251 seconds and **422 native unit tests passed,
0 failed, 1 interactive-browser test skipped** in 52.466 seconds. Exact entry:

```python
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
base = subprocess.check_output(
    ['git', 'rev-parse', 'origin/feature/coach-edit-parity'], text=True).strip()
ref = 'refs/heads/feature/coach-edit-parity'
subprocess.run(['python3', 'scripts/ci/git_hooks.py', 'pre-push'],
               input=f'{ref} {head} {ref} {base}\n', text=True, check=True)
```

The hook records its exact native invocation and environment in the Git common
directory's `mivu-checks` evidence. The result is
`mivu-checks/native-m2cxynoz/result.json`, with `Mivu.xcresult` alongside it.
Later documentation-only commits reuse this success only when native inputs and
the environment match. No hosted native job was run for this patch.

Primary-source research and the exact chat interaction contract are documented
in [chat behavior](../development/coach-chat-behavior.md). The next physical pass
must test real yogurt intake/clarification, no badge at the bottom, mouse-wheel
history preservation and jumping, and cold relaunch. The broader device checklist
remains open and the PR remains draft.
