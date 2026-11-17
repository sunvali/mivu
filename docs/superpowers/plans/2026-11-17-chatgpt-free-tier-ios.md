# ChatGPT plan not eligible (iOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A signed-in ChatGPT account whose plan can't be used in other apps gets a plain explanation, stays signed in, falls back to Apple's on-device model when available, and is re-checked so an upgrade is noticed.

**Architecture:** `ResponsesClient` classifies 403 `subscription_sharing_user_not_eligible` as a new `Failure.notEligible`. `ChatGPTConnection` gains a persisted `.planNotEligible` account state, a tiny eligibility check after sign-in and on app-open, and a once-only alert flag. Views branch on that state for copy; no new screens.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`ios/MivuTests`), XCUITest (`ios/MivuUITests`), XcodeBuildMCP.

**Spec:** `docs/superpowers/specs/2026-11-17-chatgpt-free-tier-design.md`

## Global Constraints

- Branch `feat/chatgpt-not-eligible-ios` from `docs/free-tier-chatgpt` (it carries the spec and both plans, based on latest `main`); one PR with iOS files, these docs and the App Store note. Android is a separate PR.
- Failing test first for every behavior change; synthetic inputs only; never log token responses.
- English copy only (MVP). Add new strings to `ios/Mivu/Localizable.xcstrings` the way existing ones are added; no Hebrew required.
- Keep 401, 429 and 503 handling unchanged. A 403 without the not-eligible code keeps today's `.forbidden` path.
- 44-point minimum targets, Dynamic Type, VoiceOver labels on every new control.
- Exact copy:
  - `notEligibleTitle` = "Your ChatGPT plan can't be used in Mivu"
  - `notEligibleBody` = "You're signed in, but your ChatGPT plan can't be used in other apps. You can keep logging meals by hand."
  - `notEligibleShort` = "Your ChatGPT plan can't be used in other apps."
  - `onDeviceNote` = "Using on-device AI. Your ChatGPT plan can't be used in other apps."
  - Meal line: "Your ChatGPT plan can't be used in other apps. Add nutrition by hand."
  - Buttons: "Got it", "Learn more", "Check again".
- Learn more URL: `https://help.openai.com/en/articles/20001542-using-your-chatgpt-plan-in-other-apps-and-sites`.
- Eligibility check prompt (synthetic): `"Synthetic eligibility check. Reply with OK."`, no image, no tools.
- Re-check throttle: 900 seconds between automatic checks; "Check again" bypasses it.

## Review Focus

1. A paid account signing in: exactly one extra tiny `/v1/responses` request, then normal behavior. (Task 3 test `paidSignInSendsOneEligibilityCheckAndStaysConnected`.)
2. A plain 403 with an empty or non-JSON body must still pause as permission-missing, not become not-eligible. (Task 1 test `plainForbiddenStaysForbidden`; existing `providerIneligibilityStaysPausedAcrossForegroundAndExplicitRestore` must stay green.)
3. Offline or 503 during the eligibility check must not lock anything. (Task 3 test `transientEligibilityFailureLocksNothing`.)
4. Rapid foregrounding must not spam OpenAI. (Task 4 test `foregroundRecheckIsThrottled`.)
5. Sign-out must clear the not-eligible and alert-seen flags so a different account starts clean. (Task 3 test `disconnectClearsNotEligibleFlags`.)

---

### Task 1: Classify the not-eligible 403

**Files:**
- Modify: `ios/Mivu/Analysis/ResponsesClient.swift` (`Failure` enum ~87, `check` ~206-245, stream error switch ~327, diagnostic classification ~45)
- Test: `ios/MivuTests/ResponsesClientTests.swift`

**Interfaces:**
- Produces: `ResponsesClient.Failure.notEligible`; diagnostic classification string `"notEligible"`.

- [ ] **Step 1: Write failing tests** in `ResponsesClientTests.swift`, using the file's existing synthetic session helper:
  - `notEligibleForbiddenIsClassified`: reply 403 with body `{"error":{"code":"subscription_sharing_user_not_eligible","message":"x"}}` → `respond` throws `.notEligible`; same for `models`.
  - `plainForbiddenStaysForbidden`: 403 with empty body and with `{"detail":"region"}` → throws `.forbidden`.
  - `notEligibleStreamErrorIsClassified`: 200 SSE `event: error` with `code` `subscription_sharing_user_not_eligible` → throws `.notEligible`.
- [ ] **Step 2: Run** `ResponsesClientTests` via XcodeBuildMCP `test_sim` (scheme `Mivu`, `-only-testing:MivuTests/ResponsesClientTests`). Expected: the three new tests FAIL.
- [ ] **Step 3: Implement.** Add `case notEligible` to `Failure`. In `check`, read the body when `captureDiagnostic || status == 503 || status == 403` (the existing 64 KB cap and read-error fallback apply; for 403 a read error throws `.forbidden`). Classify 403 + `error.code == "subscription_sharing_user_not_eligible"` as `.notEligible`. Add the same code → `.notEligible` in the stream error switch. Add `case .notEligible: "notEligible"` to `ResponseFailureDiagnostic`.
- [ ] **Step 4: Run** `ResponsesClientTests`. Expected: all PASS.
- [ ] **Step 5: Commit** `fix(connection): recognize ChatGPT plans that can't be used in other apps`

### Task 2: Not-eligible state, persistence, provider fallback

**Files:**
- Modify: `ios/Mivu/Connection/ChatGPTConnection.swift`
- Modify: `ios/Mivu/Coach/CoachEngine.swift:261-263`
- Test: `ios/MivuTests/ConnectionTests.swift`, `ios/MivuTests/CoachEngineTests.swift`

**Interfaces:**
- Consumes: `ResponsesClient.Failure.notEligible`.
- Produces on `ChatGPTConnection`:
  - `ProofState.planNotEligible`
  - `var planNotEligible: Bool { accountState == .planNotEligible }`
  - `private(set) var planScopeGranted: Bool` (from the last applied snapshot's `planPermissionGranted`)
  - `var showsNotEligibleNotice: Bool` — `planNotEligible && !appleModelAvailable() && preferences.string(forKey: "notEligibleNoticeSeenRegistrationID") != activeRegistrationID`
  - `func acknowledgeNotEligibleNotice()` — stores `activeRegistrationID` under `notEligibleNoticeSeenRegistrationID`
  - `private func markNotEligible(_ snapshot: SessionSnapshot?)` — stores the registration ID under `notEligibleRegistrationID`, removes `pausedRegistrationID` for it, sets `.planNotEligible`, clears `models`, `selectedModel`, `lastCompletedProbe`, `inferenceState`
  - UserDefaults keys: `notEligibleRegistrationID`, `notEligibleNoticeSeenRegistrationID`

- [ ] **Step 1: Write failing tests** in `ConnectionTests.swift`, reusing `ConnectionFixture(response:)` with a reply of 403 + the not-eligible JSON body:
  - `notEligibleResponseMarksPlanNotEligibleNotPermissionMissing`: restore, `captureSample()`, `waitForProbe()` → `accountState == .planNotEligible`, `notice == nil`, `preferences.string(forKey: "pausedRegistrationID") == nil`, `preferences.string(forKey: "notEligibleRegistrationID") == registrationID`, the saved job still exists in `jobStore`.
  - `notEligibleSurvivesRestore`: a new `ChatGPTConnection` on the same preferences/store → after `restore()` it is `.planNotEligible` with `activeRegistrationID` kept and `canInfer == false`.
  - `notEligibleFallsBackToAppleWhenAvailable`: construct with `appleModelAvailable: { true }`, stored `aiProvider = "chatGPT"`, not-eligible → `provider == .apple`, `canInfer`, and `showsNotEligibleNotice == false`; with `{ false }` → `provider == .chatGPT`, `!canInfer`, `showsNotEligibleNotice`; after `acknowledgeNotEligibleNotice()` → false.
  - In `CoachEngineTests.swift`: `notEligibleTurnWaitsForConnection` — inference throwing `.notEligible` leaves the turn `.waitingForConnection` (follow the existing `.forbidden` test there).
- [ ] **Step 2: Run** `ConnectionTests` and `CoachEngineTests`. Expected: new tests FAIL.
- [ ] **Step 3: Implement.**
  - `apply(_:)`: order is not-eligible (stored ID matches) → `.planNotEligible`; else today's connected/paused rule. Set `planScopeGranted`.
  - `reflectFailure`: `.notEligible` branch before `.forbidden` → `markNotEligible(snapshot)`, `notice = nil`.
  - `provider` getter: treat ChatGPT as not chosen-and-usable when `planNotEligible`, so a stored or implied ChatGPT returns `.apple` when `appleModelAvailable()`, else `.chatGPT`. An explicit stored `.apple` is unchanged.
  - `disconnect()`: when `outcome != nil`, remove both new keys.
  - `CoachEngine`: add `error as? ResponsesClient.Failure == .notEligible` to the `.waitingForConnection` condition.
- [ ] **Step 4: Run** `ConnectionTests` and `CoachEngineTests`. Expected: PASS, including every pre-existing test.
- [ ] **Step 5: Commit** `feat(connection): keep ineligible ChatGPT accounts signed in and fall back on-device`

### Task 3: Eligibility check at sign-in and the second-consent rule

**Files:**
- Modify: `ios/Mivu/Connection/ChatGPTConnection.swift` (`authorize`, new method)
- Modify: `ios/Mivu/Analysis/ResponsesClient.swift` (add `EligibilityCheck` enum next to `SyntheticConnectionProbe`)
- Test: `ios/MivuTests/ConnectionTests.swift` (extend `ConnectionFixture`)

**Interfaces:**
- Consumes: Task 2's `markNotEligible`, keys, `planScopeGranted`.
- Produces:
  - `enum EligibilityCheck { static let prompt = "Synthetic eligibility check. Reply with OK." }`
  - `func checkEligibility(force: Bool = false) async` on `ChatGPTConnection`
  - `@ObservationIgnored private var lastEligibilityCheck: Date?`

- [ ] **Step 1: Extend the fixture.** In `ConnectionFixture`, route a `/v1/responses` request whose body contains `EligibilityCheck.prompt` to a new init parameter `eligibility: (@Sendable (URLRequest) throws -> SessionReply)?` (default `connectionCompletion()`), before the existing saved-job assertions.
- [ ] **Step 2: Write failing tests:**
  - `paidSignInSendsOneEligibilityCheckAndStaysConnected`: use the existing callback-exchange test pattern (`consumedCallbackExchangesOnceAndEnablesValidatedRegistration`) → exactly one eligibility request, `accountState == .connected`, models loaded.
  - `freeSignInIsMarkedNotEligible`: eligibility reply 403 not-eligible → `.planNotEligible`, `showsNotEligibleNotice` (Apple unavailable).
  - `transientEligibilityFailureLocksNothing`: eligibility reply 503 `subscription_sharing_usage_unavailable`, and separately `URLError(.notConnectedToInternet)` → `.connected`, no `notEligibleRegistrationID`.
  - `recheckSuccessRestoresChatGPT`: start not-eligible, eligibility reply 200 → `checkEligibility(force: true)` → `.connected`, key removed, `models` non-empty, `provider == .chatGPT` when `aiProvider` was never stored as `apple`.
  - `secondConsentWithoutScopeIsNotEligible`: fixture with `permission: false`, already `.planPermissionMissing`; complete a consent callback that again returns without `chatgpt.tokens.use.direct` → `.planNotEligible`, and `ChatGPTConnectButton`'s title source is not "Enable ChatGPT plan usage" (assert `accountState != .planPermissionMissing`).
  - `disconnectClearsNotEligibleFlags`: not-eligible + acknowledged → `disconnect()` with confirmed revocation → both keys absent.
  - Update request-count expectations in existing sign-in tests that now see one extra eligibility request (only those that fail for that reason).
- [ ] **Step 3: Run** `ConnectionTests`. Expected: new tests FAIL.
- [ ] **Step 4: Implement `checkEligibility(force:)`.** Guard: `planNotEligible || accountState == .connected`, `planScopeGranted`, `activeRegistrationID != nil`, `!isDisconnecting`; when `!force`, return if `lastEligibilityCheck` is under 900 s old. Set `lastEligibilityCheck = .now`. Get the token, fetch `client.models`, pick `selectedModel` if listed else the first, call `client.respond` with `[.message(role: .user, text: EligibilityCheck.prompt, images: [])]`, no tools. Respect `generation` like `loadModels`. Success: remove `notEligibleRegistrationID`, `apply(await auth.snapshot())`, set `models`/`selectedModel` if empty, `resumePending()`. `.notEligible` (from either call): `markNotEligible`. Any other error: no state change, no notice.
- [ ] **Step 5: Wire `authorize`.** Compute `askedConsent = returning != nil && (accountState == .planPermissionMissing || accountState == .planNotEligible)` before building the attempt and pass it as `requestPlanConsent`. After `establish`: if `snapshot.planPermissionGranted`, remove `notEligibleRegistrationID`; else if `askedConsent`, store it. Then `apply`. After `loadModels()`, `if accountState == .connected { await checkEligibility(force: true) }`.
- [ ] **Step 6: Run** `ConnectionTests`. Expected: PASS.
- [ ] **Step 7: Commit** `feat(connection): check plan eligibility right after sign-in`

### Task 4: Re-check on app open

**Files:**
- Modify: `ios/Mivu/Connection/ChatGPTConnection.swift` (`restore`, `enterForeground`)
- Test: `ios/MivuTests/ConnectionTests.swift`

**Interfaces:**
- Consumes: `checkEligibility(force:)`.

- [ ] **Step 1: Write failing tests:**
  - `restoreRechecksNotEligibleAccount`: stored not-eligible, eligibility reply 200 → after `restore()` the account is `.connected`.
  - `foregroundRecheckIsThrottled`: stored not-eligible, eligibility reply 403 not-eligible → `restore()` then `enterForeground()` twice → exactly one eligibility request.
  - `connectedAccountIsNotRecheckedOnOpen`: connected → `restore()` + `enterForeground()` send no eligibility request.
- [ ] **Step 2: Run** `ConnectionTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `restore()` after `apply(snapshot)`/`updateSavedState()`, and in `enterForeground()` after `apply(snapshot)`: `if planNotEligible { await checkEligibility() }`, keeping each method's `generation` guards.
- [ ] **Step 4: Run** `ConnectionTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(connection): re-check ineligible plans when the app opens`

### Task 5: Copy and surfaces

**Files:**
- Modify: `ios/Mivu/Connection/OpenAIConsent.swift` (`MivuLinks.chatGPTPlanHelp`)
- Modify: `ios/Mivu/Diary/TodayView.swift` (~215, ~425: second alert next to the plan welcome)
- Modify: `ios/Mivu/Diary/SettingsView.swift` (~243-268)
- Modify: `ios/Mivu/Coach/CoachView.swift` (`.connect` bubble ~421, footer ~497, `status(_:)` ~857)
- Modify: `ios/Mivu/Diary/MealDetailView.swift` (~331, ~340)
- Modify: `ios/Mivu/Onboarding/OnboardingView.swift:260`, `ios/Mivu/Localizable.xcstrings`
- Modify: `ios/Mivu/Diary/DiaryViewModel.swift` (`DiaryLaunch.isPlanNotEligibleFixture`), `ios/Mivu/MivuServices.swift`
- Test: `ios/MivuUITests/DiaryUITests.swift`

**Interfaces:**
- Consumes: `planNotEligible`, `planScopeGranted`, `showsNotEligibleNotice`, `acknowledgeNotEligibleNotice()`, `checkEligibility(force:)`, `connect()`.
- Produces: `MivuLinks.chatGPTPlanHelp: URL`; `DiaryLaunch.isPlanNotEligibleFixture: Bool` (`isUITest && arguments.contains("--plan-not-eligible-fixture")`, DEBUG only); `#if DEBUG func applyNotEligibleFixture()` on `ChatGPTConnection` setting `activeRegistrationID = "fixture-registration"` and `.planNotEligible`.

- [ ] **Step 1: Write failing UI test** `testPlanNotEligibleExplainsOnceAndInSettings` in `DiaryUITests.swift`, launching with `--plan-not-eligible-fixture` through the file's existing launch helper: alert "Your ChatGPT plan can't be used in Mivu" appears with "Got it" and "Learn more"; tap "Got it"; relaunch with the same test ID → no alert; open Settings → Coach AI → see "Your ChatGPT plan can't be used in other apps." and a "Check again" button; no "Enable ChatGPT plan usage" anywhere.
- [ ] **Step 2: Run** that UI test via XcodeBuildMCP. Expected: FAIL.
- [ ] **Step 3: Implement the fixture.** `MivuServices.local()` calls `session.applyNotEligibleFixture()` when `DiaryLaunch.isPlanNotEligibleFixture`.
- [ ] **Step 4: Implement the surfaces**, all gated on `connection.planNotEligible`:
  - TodayView: `.alert(notEligibleTitle)` bound to `showsNotEligibleNotice` with the same "no sheet up" conditions as `showsPlanWelcome`; message `notEligibleBody`; "Got it" (cancel) and "Learn more" (`openURL(MivuLinks.chatGPTPlanHelp)`); dismissal calls `acknowledgeNotEligibleNotice()`.
  - Settings Connection section: label "ChatGPT plan unavailable", `notEligibleShort`, "Check again" button (`planScopeGranted ? checkEligibility(force: true) : connect()`), `Link("Learn more", …)`; hide `ChatGPTConnectButton` in this state. Keep Disconnect. Coach AI footer: `.chatGPT` text becomes "Uses your ChatGPT plan. Coach messages and photos you send are shared with OpenAI."; when provider is `.apple` and `planNotEligible`, add `onDeviceNote`.
  - CoachView: `.connect` bubble shows `notEligibleShort` + "Learn more" instead of Connect; `status(.waitingForConnection)` returns `notEligibleShort`; the Apple footer line adds `onDeviceNote` with a "Learn more" link.
  - MealDetailView: waiting-for-connection line becomes the meal line; replace the Connect button with "Learn more".
  - Onboarding promise: "Recommended. Works with your ChatGPT plan and uses its allowance. No extra cost."
  - Add new and changed English keys to `Localizable.xcstrings`; remove now-unused keys only if Xcode marks them stale.
- [ ] **Step 5: Run** the new UI test plus `CoachUITests` and `SmokeUITests`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(ui): explain ChatGPT plans that can't be used in Mivu`

### Task 6: Store notes, verification record, PR

**Files:**
- Modify: `docs/app-store/openai-plan-usage.md:78`, `docs/development/personal-iphone-testing.md:18`
- Create: `docs/verification/2026-11-17-chatgpt-not-eligible-ios.md`

- [ ] **Step 1:** Replace plan lists with: "OpenAI decides which ChatGPT plans can be used in other apps (currently Plus and Pro). Other accounts can sign in; Mivu explains that the plan can't be used and the diary keeps working." Keep surrounding text.
- [ ] **Step 2:** Run all of `MivuTests` and the UI tests touched in Task 5 via XcodeBuildMCP. Record source SHA, simulator, result counts and bundle path in the verification file. Record "live Free-account check: blocked, owner-only" explicitly.
- [ ] **Step 3:** Commit `docs: record ChatGPT not-eligible verification`, push, open the PR titled `feat(connection): handle ChatGPT plans that can't be used in Mivu`, run Ponytail Review, fix blocking findings, verify CI.
