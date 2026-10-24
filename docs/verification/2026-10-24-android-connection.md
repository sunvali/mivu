# Android ChatGPT connection and live analysis verification

Recorded 2026-10-24. Plan: [Android connection and live analysis](../superpowers/plans/2026-10-24-android-connection-analysis.md)
(milestone 5), milestone close. By ruling, one full suite closes milestones 5 and 6; its counts are in the
[Progress record](2026-10-24-android-progress.md#per-class-counts) and are summarised here.

- Milestone 5 commits: `cef11c8a`, `0deeba23`, `b44e54bf`, `6eb2328f`, `e4ac7d88`, `c4d4d916`, `62f282a5`.
- Full-suite source SHA: `26b5cd94a5e5e4c161184e19f9044d9a55f28f35` (branch `docs/android-design`, clean tree). It contains every milestone 5 commit.
- Environment: macOS 27.0, Android Studio JBR, Gradle 9.8.2; emulator `Medium_Phone_API_37.0` (emulator-5554, API 37).
- Result: unit 309/309 in 40 classes; instrumented 393 of 401 in 46 classes (7 failures and 1 assumption stop, all
  in the 00:00–04:00 day-cutoff window the run crossed, none in a milestone 5 class); lint 2 errors in milestone 6
  test code, fixed in `e0214396`; `assembleRelease` passed. Details in the Progress record.

## Milestone 5 classes in the full suite

All have 0 failures, 0 errors and 0 skipped.

| Class | Kind | Tests |
|---|---|---|
| `ChatGPTConnectionTest` | JVM | 17 |
| `AuthSessionTest` | JVM | 19 |
| `ConnectionScreenTest` | instrumented | 12 |
| `PlanWelcomeTest` | instrumented | 2 |
| `CoachJobServiceTest` | instrumented | 5 |
| `CoachWorkerTest` | instrumented | 11 |
| `CoachComposerTest` | instrumented | 21 |
| `CoachTimelineTest` | instrumented | 11 |
| `MealDetailScreenTest` | instrumented | 11 |
| `ConnectionProofScreenTest` | instrumented | 2 |
| `CoachReplyActionsTest` | instrumented | 8 |

`CoachScreenTest` (18) had one failure, `dayChoiceLogsToChosenDay`, a day-cutoff window test unrelated to the
connection; its milestone 5 tests (`connectionReceiptOpensConnection`, `unsupportedDestinationShowsNoLink`) passed.

Before the close, the review fixes were rerun at `62f282a5`: `CoachJobServiceTest` 5/5, `CoachWorkerTest` 11/11,
`CoachComposerTest` 21/21, `PlanWelcomeTest` 2/2. The full suite below supersedes those focused runs.

## Coverage by feature

- Connection owner (`chatgpt-connection`): `ChatGPTConnectionTest` (JVM, 17 tests) covers restore with and without
  consent, restoring only the chosen account, connect requiring consent, the offline, denied, cancelled and quota
  notices, Disconnect and its outcome, a disconnect or model change during a reply ending the turn, and the
  plan-permission pause on `unauthorized`. `CoachWorkerTest.bindsOncePerTurnAcrossRetries` covers per-turn binding.
- Consent (`openai-consent`): `ConnectionScreenTest` covers `consentShownBeforeFirstConnect`,
  `agreeRecordsConsentThenConnects`, `notNowChangesNothing`, `consentedConnectSkipsDialog`, the connected model
  picker and Disconnect, Cancel while connecting, the announced notice, the button titles, the profile button opening
  Settings, and 48 dp targets at font scale 2.0. `ConnectionProofScreenTest` checks that the debug proof screen opens
  sign-in only after consent.
- Plan use (`connection-plan-use`): `PlanWelcomeTest` (`shownOnceAfterConnect`, `hiddenWhileSheetOpen`) and
  `CoachComposerTest` (`notConnectedFootnoteOffersConnect`, `connectLinkAsksConsentFirst`,
  `connectedFootnoteShowsManageUsage`).
- Links and retry: `CoachScreenTest.connectionReceiptOpensConnection` and `unsupportedDestinationShowsNoLink`;
  `MealDetailScreenTest.liveRetryAnalysisRerunsSameTurn` and `retryWithoutTurnShowsMealChanged`;
  `CoachTimelineTest.coachTurnForMealFindsPendingTurn` and `coachTurnForMealIgnoresReceiptOnlyTurns`.
- Background continuation: `CoachJobServiceTest` (`stopWithPendingTurnSchedulesExpeditedJob`,
  `stopWithNothingPendingSchedulesNothing`, `jobFinishesPendingTurn`, `jobWaitsForRestoreBeforeRunningTurn`,
  `stoppedJobLeavesTurnPendingAndRelaunchResumes`) and `CoachWorkerTest` (`awaitIdleWaitsForTheRunningWorker`,
  `retryLeavesARunningOrFinishedTurnAlone`).

## Live check (emulator, owner present)

Run on 2026-10-24 at `31ece21b` (its ancestors include every milestone 5 commit), debug build without sample mode, on
`Medium_Phone_API_37.0` started with `-dns-server 8.8.8.8,1.1.1.1`.

- Consent: the owner read the consent dialog and tapped "Agree and Continue" himself.
- Sign-in: completed in the Custom Tab on the owner's account, with the owner's authorization; the agent name was
  `mivu-android-simulator`. No token, reply text or account identifier is recorded here beyond "owner account".
- Connected state: Settings showed ChatGPT connected; the selected model was GPT-6.1-Sol. The model list count was
  not recorded.
- Text meal in Coach: a garbled first message ("twoboil") got a clarifying question ("What food did you eat?"). The
  follow-up saved "Boiled eggs, Toast", 236 kcal, with Undo and Review on the receipt. Screenshot:
  [live-coach-turn.png](android-connection/live-coach-turn.png).
- Grounding: Pip's prose said "about 240 calories" while the card said 236. iOS `CoachReplyCheck.allowedNumbers`
  allows each fact, its value rounded to 1 and rounded to 10, so 236 grounds 240; Android `CoachReplyCheck.kt` is the
  same port (`rounded(it, BigDecimal.TEN)`), and `CoachReplyCheckTest.groundedReplyPasses` already asserts the
  rounded total (455 → 460). Android matches iOS; no change was made.
- Not run, each `blocked`: the plate photo through Coach, leaving the app mid-turn live (covered by
  `CoachJobServiceTest` only), and Disconnect with a new message saving as `waitingForConnection` (covered by
  `ChatGPTConnectionTest` and `CoachWorkerTest` only). The owner was not asked to repeat the sign-in.
- Physical phone: not run. Per AGENTS.md, emulator results never prove sign-in, so `chatgpt-connection` stays
  `partial`.

## Screenshots

`docs/verification/android-connection/live-coach-turn.png` (owner account, synthetic meal text) is the only capture.
The light, dark and font-scale-2.0 set for Settings and the connection states named in the plan was not taken at
this close; Settings appears in the milestone 6 set (`android-progress/settings-your-day-*`). The consent and
connected states are covered by `ConnectionScreenTest` assertions only.

## Scope closed

From the plan's "Scope decisions":

- Model picker: done ("Account model" on the Coach AI screen, `ConnectionScreenTest`).
- "Connect ChatGPT for replies" link: done (`CoachComposerTest`).
- Live Coach turn: done on the emulator (above); physical phone still carried.
- Sign-in DNS: the offline notice is Android-only copy, and AGENTS.md now says to start the emulator with
  `-dns-server 8.8.8.8` when it cannot resolve `auth.openai.com`.
- `MealAnalysisWorker` mutex, paid `StaleRevision` retries and swallowed failures: closed as not applicable. Live meal
  analysis is the Coach, as on iOS; the worker stays sample-only and makes no network call.
- Profile button: wired to Settings (Play readiness item removed).

## Not covered

- No physical phone: sign-in, background continuation under real process death and the Custom Tab return.
- Responses-host network errors still map to "unavailable", not "offline" (carried).
- No hosted CI run is claimed.
