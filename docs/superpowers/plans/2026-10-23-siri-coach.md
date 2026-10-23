# Siri to Coach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "Hey Siri, tell Mivu …" sends spoken text into the Coach, saved before Siri confirms, held in a lock-safe inbox when the phone is locked, with a best-effort reply notification.

**Architecture:** One `AppIntent` runs in the app process and talks to a new process-level `MivuServices.shared` that owns the `DiaryViewModel`, `ChatGPTConnection` and `CoachViewModel` the UI already uses, so there is exactly one Coach worker. Unlocked, the intent captures through the existing `CoachAttachmentDraft` capture/reconcile path and hands processing to the existing `CoachViewModel.continueInBackground` lease. Locked, it writes a JSON entry to a `completeUntilFirstUserAuthentication` inbox that the app drains on launch, foreground and the next unlocked intent run.

**Tech Stack:** Swift 6, SwiftUI, App Intents, UserNotifications, Swift Testing (`@Test`), XcodeBuildMCP. iOS 26.0. No new dependencies. New files are picked up automatically (synchronized folder groups).

**Spec:** [docs/superpowers/specs/2026-10-23-siri-coach-design.md](../specs/2026-10-23-siri-coach-design.md)

## Global Constraints

- A prompt is never lost: durable save (diary capture acknowledged, or inbox file written) happens before Siri's dialog returns.
- Never capture the same message twice; never reapply a committed capture (reconcile with the same submission ID and payload).
- Diary file protection stays `completeUnlessOpen`. Inbox files use `FileProtectionType.completeUntilFirstUserAuthentication`.
- Siri copy, exactly:
  - sent: "Sent to the Coach."
  - locked: "Saved. The Coach will reply after you unlock."
  - not connected: "Saved. Open Mivu to connect the Coach."
  - no profile: "Open Mivu to finish setup first."
  - failure: "I couldn't save that. Please try again."
  - parameter prompt: "What should I tell the Coach?"
- Phrases: "Tell \(.applicationName)", "Tell \(.applicationName) Coach", "Message \(.applicationName) Coach", added to the existing `MivuShortcuts` in `ios/Mivu/QuickLog.swift`. main already owns "Ask \(.applicationName) Coach" (opens Coach) and "Log food with \(.applicationName)" (camera), so "Ask"/"Log with" phrases would collide.
- Base: `origin/main` (f66b8896). It already has `MivuShortcuts`, `MivuAppDelegate` as the notification delegate, `QuickLogRequest.openCoach`, and `MealNotification` (posted by the Coach worker for analyzed meals; permission via `MealNotification.requestPermissionIfNeeded()`). Reuse them.
- "Not connected" means `!connection.canInfer` (ChatGPT or on-device Apple Intelligence available), the same check the worker uses.
- Native checks run with the `xcodebuildmcp` CLI, `-testPlan Mivu`, explicit `-only-testing:` selectors, on a dedicated simulator.
- Fallback notification body: "Your message is saved. Open Mivu for the Coach's reply."
- English only. Synthetic text in every test. Never log message text or token responses.
- Commits: Conventional Commits, owner's git identity, no mention of tools or assistants.
- Work on a feature branch from `main` in its own worktree. The current checkout has unrelated uncommitted icon work that must not be touched.

## Review Focus

1. **Siri used while Mivu is open in the foreground**: capture appears in the timeline, processed by the live worker, no background lease, no notification. Test in Task 4 (`foregroundRunOnlyResumes`).
2. **The user's unsent composer draft**: a Siri capture must not clear or replace `coach.draft`. Test in Task 2 (`externalCaptureLeavesDraftUntouched`).
3. **Signed-out or never-onboarded user on a locked phone**: no profile ID in defaults → "Open Mivu to finish setup first.", nothing written. Test in Task 4 (`lockedWithoutProfileNeedsSetup`).
4. **Inbox entry for a profile that isn't selected**: it waits and is not captured into the wrong diary. Test in Task 2 (`drainSkipsOtherProfileEntries`).
5. **A corrupt or unreadable inbox file**: drain skips it without blocking newer entries and without deleting it. Test in Task 1 (`unreadableEntryIsSkippedNotDeleted`).

---

### Task 0: Branch and docs

**Files:**
- Add: `docs/superpowers/specs/2026-10-23-siri-coach-design.md`, `docs/superpowers/plans/2026-10-23-siri-coach.md` (copied from the current checkout)

- [ ] **Step 1:** Create a worktree on a new branch `feat/siri-coach` from `main`. Copy the spec and plan into it.
- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-10-23-siri-coach-design.md docs/superpowers/plans/2026-10-23-siri-coach.md
git commit -m "docs(siri): design and plan for sending Siri prompts to the Coach"
```

### Task 1: Lock-safe inbox

**Files:**
- Create: `ios/Mivu/Coach/CoachInbox.swift`
- Test: `ios/MivuTests/CoachInboxTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct CoachInbox: Sendable {
      struct Entry: Codable, Equatable, Sendable { let id: UUID; let profileID: UUID; let text: String; let capturedAt: Date }
      init(directory: URL)                 // a folder; created on first add
      static var local: CoachInbox         // DiaryLaunch.directory.deletingLastPathComponent()/CoachInbox
      func add(_ entry: Entry) throws      // atomic write of "<id>.json", protection completeUntilFirstUserAuthentication
      func entries() -> [Entry]            // readable entries, oldest capturedAt first; unreadable files skipped
      func remove(_ id: UUID) throws
  }
  ```

- [ ] **Step 1: Write the failing tests** in `CoachInboxTests` (temp directory per test):
  - `addThenReadReturnsEntry`: `add(e)` → `entries() == [e]`.
  - `entriesAreOldestFirst`: entries with `capturedAt` 200 and 100 → order `[100, 200]`.
  - `removeDeletesOnlyThatEntry`.
  - `unreadableEntryIsSkippedNotDeleted`: write `Data([1])` to `<uuid>.json`, add one valid entry → `entries()` returns only the valid one and the bad file still exists.
  - `fileUsesFirstUnlockProtection`: on the written file, `attributesOfItem[.protectionKey]` is `.completeUntilFirstUserAuthentication` (the simulator stores this attribute; if it returns nil there, assert on the write options instead and note it).
- [ ] **Step 2:** Run with XcodeBuildMCP `test_sim`, only `MivuTests/CoachInboxTests`. Expected: FAIL (type missing).
- [ ] **Step 3:** Implement `CoachInbox` in `CoachInbox.swift`. Use `JSONEncoder` with ISO 8601 dates and `Data.write(options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])`, mirroring `ProbeJob.swift:95`.
- [ ] **Step 4:** Run the same tests. Expected: 5 passed.
- [ ] **Step 5: Commit** `feat(coach): lock-safe inbox for Siri prompts`

### Task 2: External capture and inbox drain on `CoachViewModel`

**Files:**
- Modify: `ios/Mivu/Coach/CoachViewModel.swift` (near `send()`, ~line 285)
- Test: `ios/MivuTests/CoachFlowTests.swift` (reuse its private `fixture()`)

**Interfaces:**
- Consumes: `CoachInbox` (Task 1).
- Produces:
  ```swift
  /// Captures text from outside the composer (Siri) without touching `draft`. Idempotent per submissionID.
  @discardableResult
  func captureExternal(_ text: String, submissionID: UUID, capturedAt: Date) async throws -> CoachExchangeSummary
  /// Captures every inbox entry for the selected profile, oldest first, removing each only after capture is acknowledged.
  func drainInbox(_ inbox: CoachInbox) async
  ```

- [ ] **Step 1: Write the failing tests:**
  - `externalCaptureCreatesTurnAtSpokenTime`: `captureExternal("Synthetic eggs", submissionID: id, capturedAt: t)` → the stored turn `id` has text "Synthetic eggs" and `capturedAt == t` (read through `diary.store.snapshotForExport()` like the existing relaunch test).
  - `externalCaptureLeavesDraftUntouched`: set `coach.draft.text = "Unsent"` first; after capture, `coach.draft.text == "Unsent"` and its `submissionID` is unchanged.
  - `externalCaptureTwiceStoresOneTurn`: the same `id` and text captured twice → exactly one turn with that `id`, and no throw.
  - `drainCapturesAndRemovesEntries`: two entries for the selected profile → two turns, `inbox.entries().isEmpty`.
  - `drainSkipsOtherProfileEntries`: an entry with a random `profileID` → no turn, entry still in inbox.
  - `drainTwiceStoresOneTurn`: add an entry, capture it via `captureExternal` (simulating a crash before removal), then `drainInbox` → one turn, inbox empty.
- [ ] **Step 2:** Run only those tests. Expected: FAIL (methods missing).
- [ ] **Step 3: Implement.** `captureExternal`:
  - Build a fresh `CoachAttachmentDraft(ownership: diary.selection, limiter: diary.photoWorkLimiter, dependencies: deps, text: text, submissionID: submissionID)`, where `deps` is the same dependencies `init` builds, with `prepare` overridden to call `diary.store.coachCapturePreparation(at: capturedAt, …)`. Keep the `dependencies` value as a stored property so it can be reused here.
  - Before sending, call `deps.reconcile(submissionID, manifest, owner)`. `.accepted(result)` returns `result`. `.conflictingPayload` throws `CoachAttachmentDraft.Failure.conflictingPayload`. `.absent` proceeds to `send()`. Build `manifest` from a `CoachSubmissionPayload` made with the prepared context.
  - On success, set `captureNeedsProcessing = true` and call `resume()`.
  - Wrap the work in `beginCaptureProtection()`, like `performSend`.

  `drainInbox`: guard `diary.selection`. For each entry whose `profileID` matches, run `captureExternal`, then `inbox.remove`. On the first thrown error, stop and leave the remaining entries.
- [ ] **Step 4:** Run the tests. Expected: 6 passed.
- [ ] **Step 5: Commit** `feat(coach): capture external prompts and drain the Siri inbox`

### Task 3: Process-level services owner

**Files:**
- Create: `ios/Mivu/MivuServices.swift`
- Modify: `ios/Mivu/Diary/TodayView.swift` (`DiaryRootView.init` ~95-135, `.task` ~170-181, `.onChange(of: phase)` ~197-214, `continueInBackground`/`endBackgroundLease` ~463-475)
- Test: `ios/MivuTests/MivuServicesTests.swift`

**Interfaces:**
- Consumes: `CoachViewModel.drainInbox` (Task 2), `CoachInbox.local` (Task 1).
- Produces:
  ```swift
  @MainActor final class MivuServices {
      static let shared: MivuServices
      let diary: DiaryViewModel; let connection: ChatGPTConnection; let coach: CoachViewModel; let nutritionKeys: NutritionAPIKeyStore
      init(diary: DiaryViewModel, connection: ChatGPTConnection, coach: CoachViewModel, nutritionKeys: NutritionAPIKeyStore)
      /// Idempotent: loads the selected diary, restores the connection, starts coach monitoring, drains the inbox. Later calls await the first.
      func start(createDefaultProfile: Bool) async
      /// Moves the background-lease owner out of the view. onExpire runs in the expiration handler before the lease ends.
      func continueCoachInBackground(onExpire: @escaping @MainActor () -> Void = {})
      func endCoachBackground()
  }
  ```

- [ ] **Step 1: Write the failing test** `startRunsOnceAndDrainsInbox`. Build `MivuServices` over the `CoachFlowTests`-style fixture (lift `fixture()` into a shared test helper if needed) with an inbox entry for the fixture profile. Call `start` twice concurrently. Expect one load (the profile is selected) and the inbox empty with one turn. Use the inbox directory through an injectable `inbox: CoachInbox` init parameter that defaults to `.local`.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `shared` moves the construction currently in `DiaryRootView.init` (diary, session, keys, food source, inference fixture, coach) into `MivuServices` verbatim, including the `#if DEBUG` fixture branches.
  - `DiaryRootView.init()` reads `MivuServices.shared` for `model`, `connection`, `coach` and `nutritionKeys`. The DEBUG `init(testDiary:…)` stays as is.
  - `.task` calls `await MivuServices.shared.start(createDefaultProfile: …same expression…)` in place of the current `model.load` / `connection.restore` / `coach.startMonitoring(); coach.resume()` lines. View-only work (tab restore, rollover, companion) stays in the view. `model.resumeCoach` and `model.retryCoachMeal` are set inside `start`.
  - Add `Task { await coach.drainInbox(.local) }` to the `.active` branch of `onChange(of: phase)`.
  - `continueInBackground` and `endBackgroundLease` in the view call the services methods. The `backgroundLease` state moves into `MivuServices`.
  - No UI-test special case is needed for start or drain: `DiaryLaunch.directory` already gives UI tests their own folder, and `CoachInbox.local` sits next to it.
- [ ] **Step 4:** Run the new test and the existing `CoachFlowTests`. Expected: all pass.
- [ ] **Step 5:** Build and launch on a simulator with XcodeBuildMCP. Confirm the diary loads and a typed Coach message completes. Run only the Coach-related UI test class `CoachUITests` (per the targeted-runs rule), since app wiring changed. Expected: pass.
- [ ] **Step 6: Commit** `refactor(app): process-level services owner for Coach and diary`

### Task 4: Siri action

**Files:**
- Create: `ios/Mivu/Coach/TellCoachIntent.swift` (app target only; not `ios/Shared`, which the widget extension also compiles)
- Modify: `ios/Mivu/QuickLog.swift` (`MivuShortcuts`: add the third `AppShortcut`)
- Test: `ios/MivuTests/TellCoachTests.swift`

**Interfaces:**
- Consumes: `MivuServices` (Task 3), `CoachInbox` (Task 1), `CoachViewModel.captureExternal` (Task 2), `CoachReplyNotification.follow` (Task 5, called through the closure below so this task tests without it).
- Produces:
  ```swift
  enum TellCoachOutcome: Equatable { case sent, savedLocked, savedNeedsConnection, needsSetup, failed
      var dialog: String }                       // the exact Global Constraints copy
  @MainActor enum TellCoach {
      static func run(_ text: String, services: MivuServices, inbox: CoachInbox,
                      defaults: UserDefaults, protectedDataAvailable: Bool, appActive: Bool,
                      now: Date = Date(), onBackgroundCapture: @MainActor (UUID) -> Void) async -> TellCoachOutcome
  }
  struct TellCoachIntent: AppIntent { … @Parameter(title: "Message", requestValueDialog: "What should I tell the Coach?") var message: String }
  ```

- [ ] **Step 1: Write the failing tests** for `TellCoach.run`:
  - `lockedWritesInboxEntry`: `protectedDataAvailable: false`, defaults `diarySelectedProfile = p` → `.savedLocked`, one inbox entry with `profileID == p`, `capturedAt == now` and the same text. No diary write.
  - `lockedWithoutProfileNeedsSetup`: no `diarySelectedProfile` (or `diarySignedOut == true`) → `.needsSetup`, inbox empty.
  - `unlockedCapturesTurn`: fixture with a connection whose `canInfer` is false → `.savedNeedsConnection`, one turn with the text.
  - `unlockedDrainsInboxFirst`: a pre-existing inbox entry → after run, inbox empty, two turns, the older one first.
  - `foregroundRunOnlyResumes`: `appActive: true` → `onBackgroundCapture` not called.
  - `backgroundRunHandsOffTurn`: `appActive: false` → `onBackgroundCapture` called once with the new turn ID.
  - `blankTextFails`: `"  "` → `.failed`, nothing saved. (Siri re-asks before this in practice. The test guards the Shortcuts path.)
  - `dialogCopyIsExact`: each case's `dialog` equals the Global Constraints string.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `run`:
    - Blank text → `.failed`.
    - Locked: read the profile from `diarySelectedProfile` (and `diarySignedOut`), `inbox.add`, return `.savedLocked`. A thrown error → `.failed`.
    - Unlocked: `await services.start(createDefaultProfile: false)`. No `diary.selection` → `.needsSetup`. Drain the inbox, then `captureExternal(text, submissionID: UUID(), capturedAt: now)`. If `!appActive`, call `onBackgroundCapture(turnID)`. Return `.sent`, or `.savedNeedsConnection` when `!services.connection.canInfer`. A thrown error → `.failed`.
  - `TellCoachIntent`:
    - `title` "Tell Coach".
    - Use `static let supportedModes: IntentModes = .background` if the iOS 26 SDK has it; otherwise `openAppWhenRun = false`.
    - `authenticationPolicy = .alwaysAllowed`.
    - `perform()` calls `TellCoach.run` with `UIApplication.shared.isProtectedDataAvailable` and `applicationState == .active`, and returns `.result(dialog: IntentDialog(stringLiteral: outcome.dialog))`.
    - Its `onBackgroundCapture` calls `CoachReplyNotification.follow(_:services:)` (Task 5). Until Task 5 lands, pass `{ _ in services.continueCoachInBackground() }`.
  - `MivuShortcuts`: add one `AppShortcut(intent: TellCoachIntent(), phrases: [the three phrases], shortTitle: "Tell Coach", systemImageName: "bubble.left.and.text.bubble.right")`.
- [ ] **Step 4:** Run the tests. Expected: 8 passed. Build the app. Expected: the App Shortcuts metadata processor reports no phrase errors.
- [ ] **Step 5: Commit** `feat(siri): tell the Coach from Siri and Shortcuts`

### Task 5: Reply notifications and tap routing

**Files:**
- Create: `ios/Mivu/Coach/CoachReplyNotification.swift`
- Modify: `ios/Mivu/QuickLog.swift` (`MivuAppDelegate.didReceive`: a Coach reply tap sets `QuickLogRequest.shared.openCoach = true`), `ios/Mivu/Coach/TellCoachIntent.swift` (wire `follow`)
- Test: `ios/MivuTests/CoachReplyNotificationTests.swift`

**Interfaces:**
- Consumes: `MivuServices.continueCoachInBackground(onExpire:)` (Task 3), `DiaryStore.coachResult(turnID:expectedProfileID:) -> CoachTurnResult`, `MealNotification.requestPermissionIfNeeded()`.
- Produces:
  ```swift
  enum CoachReplyNotification {
      nonisolated static let turnKey = "coachTurnID"
      nonisolated static func identifier(for turnID: UUID) -> String          // "coach-reply-<uuid>"
      nonisolated static func turnID(from userInfo: [AnyHashable: Any]) -> UUID?
      /// nil while captured/analyzing, and for turns that saved a meal (the worker's MealNotification covers those).
      nonisolated static func text(for turn: CoachTurnResult) -> (title: String, body: String)?
      nonisolated static func post(_ turn: CoachTurnResult)
      nonisolated static func postSaved(turnID: UUID)                         // the fallback body, same identifier
      /// Keeps the turn processing in the background; posts its reply on drain, the fallback on expiry.
      @MainActor static func follow(_ turnID: UUID, services: MivuServices)
  }
  ```

- [ ] **Step 1: Write the failing tests** for `text(for:)` and the identifiers:
  - `completedTurnShowsReplyExcerpt`: `.completed` with `assistantText` "Synthetic reply" → title "Coach", body "Synthetic reply". A 500-character reply is trimmed to at most 180 characters ending in "…".
  - `clarificationTurnAsksForAnswer`: `.needsClarification` → body "The Coach needs a quick answer."
  - `retryStatesSaySaved`: `.needsRetry`, `.waitingForNetwork` and `.waitingForConnection` → body "Your message is saved. Open Mivu for the Coach's reply."
  - `inFlightTurnHasNoContent`: `.captured` and `.analyzing` → nil.
  - `mealTurnDefersToMealNotification`: `.completed` with a `pendingMealID` → nil.
  - `turnIDRoundTrips`: `turnID(from: [turnKey: id.uuidString]) == id`; `identifier(for: id) == "coach-reply-" + id.uuidString`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `follow`: call `services.continueCoachInBackground(onExpire: { postSaved(turnID:) })`. Then in a Task, `await services.coach.waitForBackgroundCompletion()`, read `coachResult`, and `post` it.
  - iOS does not show these while Mivu is open, matching `MealNotification`, so there is no foreground check.
  - The same identifier means the reply replaces the fallback.
  - `MivuAppDelegate.didReceive`: `if CoachReplyNotification.turnID(from:) != nil { QuickLogRequest.shared.openCoach = true }`. The root already opens Coach for that flag.
  - Permission: the intent's unlocked path calls `await MealNotification.requestPermissionIfNeeded()`. It asks only while `.notDetermined`, so it asks once. `MivuServices.start` calls it too when the drain captured at least one inbox entry (the first Siri use was locked).
- [ ] **Step 4:** Run the tests and `TellCoachTests`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(siri): notify with the Coach's reply and open the Coach on tap`

### Task 6: Verification record

**Files:**
- Create: `docs/verification/2026-10-23-siri-coach.md`

- [ ] **Step 1:** Run every test class touched by Tasks 1-5 plus `CoachFlowTests` and `CoachUITests` with XcodeBuildMCP. Record the source SHA, simulator, result bundle path and pass/fail counts.
- [ ] **Step 2:** In the Simulator, run the Shortcuts app action "Tell Coach" with text "Synthetic toast". Expected: "Sent to the Coach." and a new Coach turn.
- [ ] **Step 3:** Write the physical-iPhone checklist into the record, each item marked *not run* until the owner runs it:
  1. Unlocked voice log
  2. Locked voice log, then unlock and open
  3. AirPods or CarPlay invocation
  4. Airplane mode, then reconnect
  5. Notification tap opens the Coach
  6. Notifications declined
  7. Measured seconds between Siri confirming and the reply notification

  Do not mark any of these as passing from simulator evidence.
- [ ] **Step 4: Commit** `docs(siri): verification record for Siri to Coach`

---

## Self-review notes

- Spec coverage: action and phrases (T4), save first, both paths (T1, T2, T4), Siri copy (T4), drain on launch/foreground/unlocked run (T3, T4), profile-bound entries (T2), processing via the existing worker (T3, T5), notification, fallback and tap (T5, reusing main's delegate and `openCoach`), ask once and locked first use (T5, via `MealNotification.requestPermissionIfNeeded`), verification and device checklist (T6).
- Deviation from the spec, recorded there: the inbox stores `capturedAt` only. The time zone comes from the profile, as for every capture.
- One processor per turn: settled by routing all processing through the single `MivuServices.shared.coach` worker. The intent never runs `CoachEngine` itself.
