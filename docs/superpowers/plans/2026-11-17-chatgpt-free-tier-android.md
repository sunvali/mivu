# ChatGPT plan not eligible (Android) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Same behavior as the iOS plan on Android: a signed-in ChatGPT account whose plan can't be used in other apps is told plainly, stays signed in, falls back to Gemini Nano when available, and is re-checked on app open.

**Architecture:** `ResponsesClient.open()` reads the 403 body and throws a new `Failure.NotEligible` for `subscription_sharing_user_not_eligible`. `ChatGPTConnection` gains `AccountState.planNotEligible`, persisted per registration in `SharedPreferences`, a tiny eligibility check after sign-in and on app open, and a once-only dialog flag on `ConnectionState`. Compose screens branch on the state for copy.

**Tech Stack:** Kotlin, Jetpack Compose, JUnit4 + JVM `HttpServer` fakes (`app/src/test`), Compose UI tests (`app/src/androidTest`).

**Spec:** `docs/superpowers/specs/2026-11-17-chatgpt-free-tier-design.md`

## Global Constraints

- Branch `feat/chatgpt-not-eligible-android` from latest `main` once the iOS PR (which carries the spec and both plans) has merged; otherwise from `docs/free-tier-chatgpt`. Separate PR from iOS. Never read or copy from `ios/`.
- Failing test first; synthetic inputs only; never log token responses.
- Keep 401, 429 and 503 handling unchanged; a 403 without the code stays `Failure.Forbidden`.
- 48 dp minimum targets (the app's existing `heightIn(min = 48.dp)`), TalkBack labels on new controls.
- Copy, Learn more URL, eligibility prompt and the 900-second throttle are exactly as in the iOS plan's Global Constraints (`docs/superpowers/plans/2026-11-17-chatgpt-free-tier-ios.md`), with "on-device AI" for Gemini Nano.
- Run unit tests with `cd android && ./gradlew :app:testDebugUnitTest` (export Android Studio `JAVA_HOME` and `ANDROID_HOME` first); instrumented with `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=<fully.qualified.TestClass>`.
- Update `docs/parity.md` for the new behavior.

## Review Focus

1. Paid sign-in sends exactly one extra eligibility request and stays connected. (Task 3 `paidSignInSendsOneEligibilityCheck`.)
2. A plain 403 with an empty or non-JSON body stays `Forbidden` → permission-missing. (Task 1 `plainForbiddenStaysForbidden`.)
3. Offline or 503 during the check locks nothing. (Task 3 `transientEligibilityFailureLocksNothing`.)
4. Repeated `onStart` doesn't spam OpenAI. (Task 4 `startRecheckIsThrottled`.)
5. Sign-out clears the not-eligible and dialog-seen keys. (Task 3 `disconnectClearsNotEligibleKeys`.)

---

### Task 1: Classify the not-eligible 403

**Files:**
- Modify: `android/app/src/main/java/com/yakov103/mivu/analysis/ResponsesClient.kt` (`Failure` ~38, `open()` ~160, `SseParser.processEvent` ~253)
- Test: `android/app/src/test/java/com/yakov103/mivu/analysis/ResponsesClientTest.kt`

**Interfaces:**
- Produces: `ResponsesClient.Failure.NotEligible` (object).

- [ ] **Step 1: Write failing tests** using the file's `status`/`reply` vars: `notEligibleForbiddenIsClassified` (403 + `{"error":{"code":"subscription_sharing_user_not_eligible"}}` → `NotEligible` for both `run` and `models`), `plainForbiddenStaysForbidden` (403 empty and `{"detail":"region"}` → `Forbidden`), `notEligibleStreamErrorIsClassified` (200 SSE error event with that code → `NotEligible`).
- [ ] **Step 2: Run** `./gradlew :app:testDebugUnitTest --tests '*ResponsesClientTest*'`. Expected: new tests FAIL.
- [ ] **Step 3: Implement.** On 403, read `conn.errorStream` with `readLimited` (cap 64 KB; any read or parse error → `Forbidden`), parse `error.code`, throw `NotEligible` on a match. Add the code to the SSE error `when`.
- [ ] **Step 4: Run** the same tests. Expected: PASS.
- [ ] **Step 5: Commit** `fix(connection): recognize ChatGPT plans that can't be used in other apps`

### Task 2: State, persistence, provider fallback

**Files:**
- Modify: `android/app/src/main/java/com/yakov103/mivu/connection/ChatGPTConnection.kt`
- Modify: `android/app/src/main/java/com/yakov103/mivu/coach/CoachEngine.kt:101-104`
- Test: `android/app/src/test/java/com/yakov103/mivu/connection/ChatGPTConnectionTest.kt`, the existing `CoachEngine` unit test file

**Interfaces:**
- Consumes: `Failure.NotEligible`.
- Produces:
  - `AccountState.planNotEligible`
  - `ConnectionState.notEligibleNoticeSeen: Boolean`, `ConnectionState.planScopeGranted: Boolean`
  - `ConnectionState.showsNotEligibleNotice` = `account == planNotEligible && nano != NanoStatus.available && !notEligibleNoticeSeen`
  - `fun acknowledgeNotEligibleNotice()` on `ChatGPTConnection`
  - `private fun markNotEligible(snapshot: SessionSnapshot?)`
  - prefs keys `NOT_ELIGIBLE = "notEligibleRegistrationID"`, `NOT_ELIGIBLE_SEEN = "notEligibleNoticeSeenRegistrationID"`

- [ ] **Step 1: Extend the fake API server** with an `errorBody` var used for non-200 replies (default `""`).
- [ ] **Step 2: Write failing tests:** `notEligibleMarksStateNotPermission` (respond → 403 not-eligible: `account == planNotEligible`, `notice == null`, `PAUSED` unset, `NOT_ELIGIBLE == registrationID`); `notEligibleSurvivesRestore` (new connection on same prefs/store → `planNotEligible`, `registrationID` kept, `!canInfer` with Nano unavailable); `notEligibleFallsBackToNano` (stored provider `chatGPT`, `nano = available` → `provider == onDevice`, `canInfer`, `!showsNotEligibleNotice`; Nano unavailable → `showsNotEligibleNotice`, false after `acknowledgeNotEligibleNotice()`). In the CoachEngine test: `notEligibleTurnWaitsForConnection`.
- [ ] **Step 3: Run** `./gradlew :app:testDebugUnitTest --tests '*ChatGPTConnectionTest*' --tests '*CoachEngine*'`. Expected: FAIL.
- [ ] **Step 4: Implement.** `apply`: stored `NOT_ELIGIBLE` match → `planNotEligible` first, else today's rule; set `planScopeGranted` and `notEligibleNoticeSeen` (seen key equals registration). `reflectFailure`: `NotEligible` → `markNotEligible(snapshot)`, notice `null`. `provider`: when `account == planNotEligible && nano == available` and the stored or implied provider is `chatGPT`, return `onDevice`; an explicit stored `onDevice` is unchanged. `disconnect`: remove both keys when the outcome is non-null. `CoachEngine`: add `Failure.NotEligible` to the waiting-for-connection list.
- [ ] **Step 5: Run** the same tests plus the full unit suite. Expected: PASS.
- [ ] **Step 6: Commit** `feat(connection): keep ineligible ChatGPT accounts signed in and fall back on-device`

### Task 3: Eligibility check at sign-in and the second-consent rule

**Files:**
- Modify: `ChatGPTConnection.kt` (`authorize`, new method), `ResponsesClient.kt` (`object EligibilityCheck { const val PROMPT = "Synthetic eligibility check. Reply with OK." }`)
- Test: `ChatGPTConnectionTest.kt`

**Interfaces:**
- Produces: `suspend fun checkEligibility(force: Boolean = false)`; `private var lastEligibilityCheck: Long?` (`System.currentTimeMillis()`).

- [ ] **Step 1: Write failing tests:** `paidSignInSendsOneEligibilityCheck` (via `connect(c)` helper → one request whose body has `PROMPT`, `account == connected`); `freeSignInIsMarkedNotEligible`; `transientEligibilityFailureLocksNothing` (503 body `subscription_sharing_usage_unavailable`; and server stopped/unreachable); `recheckSuccessRestoresChatGPT`; `secondConsentWithoutScopeIsNotEligible` (`planPermissionMissing` + consent callback still missing the plan scope → `planNotEligible`, `buttonTitle != "Enable ChatGPT plan usage"`); `disconnectClearsNotEligibleKeys`. Adjust request counts in existing sign-in tests that now see the extra request.
- [ ] **Step 2: Run** `--tests '*ChatGPTConnectionTest*'`. Expected: FAIL.
- [ ] **Step 3: Implement `checkEligibility`.** Guard: account is `connected` or `planNotEligible`, `planScopeGranted`, a registration, not disconnecting; unless `force`, skip when the last check is under 900 s old. Token → `client.models` → `client.run(model, PROMPT, null, null, token)` with the selected model if listed else the first. Success: remove `NOT_ELIGIBLE`, `apply(auth.snapshot())`, load models into state. `NotEligible`: `markNotEligible`. Other exceptions (not `CancellationException`): no change. Use `ifCurrent(revision)` like `loadModels`.
- [ ] **Step 4: Wire `authorize`.** `askedConsent = returning != null && current.account in (planPermissionMissing, planNotEligible)` → `requestPlanConsent`. After `establish`: plan scope granted → remove `NOT_ELIGIBLE`; else if `askedConsent` → store it. After `loadModels`, call `checkEligibility(force = true)` when connected.
- [ ] **Step 5: Run** tests. Expected: PASS.
- [ ] **Step 6: Commit** `feat(connection): check plan eligibility right after sign-in`

### Task 4: Re-check on app open

**Files:**
- Modify: `ChatGPTConnection.kt` (`restore`), `android/app/src/main/java/com/yakov103/mivu/MainActivity.kt` (`onStart` ~56)
- Test: `ChatGPTConnectionTest.kt`

- [ ] **Step 1: Write failing tests:** `restoreRechecksNotEligibleAccount`; `startRecheckIsThrottled` (two `checkEligibility()` calls → one request); `connectedAccountIsNotRecheckedOnOpen`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** In `restore()` after `apply`, `if (account == planNotEligible) checkEligibility()`. In `MainActivity.onStart`, launch `app.chatGPT.checkEligibility()` on the app scope only when the account is `planNotEligible`, next to `refreshNano()`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(connection): re-check ineligible plans when the app opens`

### Task 5: Copy and surfaces

**Files:**
- Modify: `ui/settings/ChatGPTConnectButton.kt` (`MivuLinks.PLAN_HELP`), `ui/today/TodayScreen.kt` (new `PlanNotEligible` dialog next to `PlanWelcome` ~172), `ui/MivuApp.kt` (~564), `ui/settings/SettingsScreen.kt` (row ~118, section ~160-209, `CHATGPT_FOOTER` ~214), `ui/coach/CoachComposer.kt` (~292), `ui/coach/CoachTimeline.kt` (~348), `ui/meal/MealDetailScreen.kt` (~414), `ui/onboarding/OnboardingScreen.kt` (~581)
- Test: `android/app/src/androidTest/java/com/yakov103/mivu/ui/settings/ConnectionScreenTest.kt`, plus a dialog test beside the existing `PlanWelcome` test if one exists

**Interfaces:**
- Consumes: `planNotEligible` state, `showsNotEligibleNotice`, `planScopeGranted`, `acknowledgeNotEligibleNotice()`, `checkEligibility(force = true)`; `ConnectionScreen` gains an `onCheckAgain: () -> Unit` parameter.

- [ ] **Step 1: Write failing Compose tests:** `notEligibleShowsExplanationAndCheckAgain` (state `ConnectionState(AccountState.planNotEligible, "reg-1", consented = true, planScopeGranted = true)` → shows the short copy, "Check again" calls `onCheckAgain`, "Learn more" present, no "Enable ChatGPT plan usage"); `notEligibleDialogShowsOnce` (`PlanNotEligible` renders title, body, "Got it" acknowledges).
- [ ] **Step 2: Run** the two tests on an emulator. Expected: FAIL.
- [ ] **Step 3: Implement**, all gated on `account == planNotEligible`: dialog shown from `MivuApp` when `showsNotEligibleNotice`; Settings row label "ChatGPT plan unavailable", short copy, "Check again" (`planScopeGranted` → `checkEligibility(force = true)`, else `connect`), "Learn more", connect button hidden, Disconnect kept; footer "Uses your ChatGPT plan. Coach messages and photos you send are shared with OpenAI."; on-device note when provider is `onDevice`; Coach bubble and timeline status use the short copy + "Learn more" instead of Connect; meal detail uses the meal line with "Learn more"; onboarding promise "Recommended. Works with your ChatGPT plan and uses its allowance. No extra cost."
- [ ] **Step 4: Run** the new tests plus the existing `ConnectionScreenTest`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ui): explain ChatGPT plans that can't be used in Mivu`

### Task 6: Notes, parity, verification, PR

**Files:**
- Modify: `docs/development/play-openai-plan-usage.md:62`, `docs/parity.md`
- Create: `docs/verification/2026-11-17-chatgpt-not-eligible-android.md`

- [ ] **Step 1:** Store note line → "OpenAI decides which ChatGPT plans can be used in other apps (currently Plus and Pro). Other accounts can sign in; Mivu explains that the plan can't be used and the diary keeps working." Add the not-eligible row to `docs/parity.md`.
- [ ] **Step 2:** Run `./gradlew :app:testDebugUnitTest :app:lintDebug` and the Task 5 instrumented tests. Record SHA, emulator, counts; record "live Free-account check: blocked, owner-only".
- [ ] **Step 3:** Commit `docs: record Android ChatGPT not-eligible verification`, push, open PR `feat(android): handle ChatGPT plans that can't be used in Mivu`, run Ponytail Review, fix blocking findings, verify CI.
