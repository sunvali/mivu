# Siri to Coach: design

Status: draft for owner approval, 2026-10-23.

## Intent

The owner wants to reach the Coach by voice without touching the phone:
while cooking, driving (CarPlay), with AirPods, or with the phone locked.
Spoken words go to the Coach exactly as if typed, so one voice entry covers
the uses the owner named: logging a meal ("two eggs and toast"), asking a
question ("how much protein is left today?"), and correcting a log ("that
was a large coffee, not a small one").

This replaces the three separate actions proposed in the
[food-logger design](2026-10-11-food-logger-design.md#native-siri-integration-proposed-scope-and-research)
(log meal, log weight, start day). The Coach already handles meals, weight,
workouts, questions and corrections, so one action that feeds it gets all of
them with no new interpretation logic, and voice stays at parity with typing
([Coach edit parity](../../development/coach-chat-behavior.md)).

## Owner decisions

- Uses: meal logging, quick questions, corrections, hands-free with the phone
  locked.
- After speaking: **save, confirm, notify.** Siri confirms right away. The
  Coach's reply arrives later as a notification. Siri does not wait to read
  the reply aloud.
- Phone locked and Mivu not already running: **hold it, finish on unlock.**
  Siri saves the words to a small inbox that works while the phone is locked
  and confirms. The Coach processes them after the next unlock.
- Never lose a prompt. The reply notification is best effort; the saved
  prompt is not.
- Notifications: **ask on first Siri use.** If declined, replies stay in Coach
  history and Siri still confirms.
- "Do it the best" was delegated for the overall experience; the calls below
  marked *(builder's call, settled)* were made on that authority.

## Goals

1. "Hey Siri, tell Mivu" → Siri asks "What should I tell the Coach?" → the
   user speaks → Siri confirms within a couple of seconds.
2. The words are durably saved before Siri confirms. Nothing is lost to a
   dropped network, a killed process or a locked phone.
3. The Coach processes the message through the existing `CoachEngine` turn
   path, unchanged.
4. When processing finishes, a local notification shows the reply. Tapping it
   opens the Coach.
5. The same action is available in the Shortcuts app with a text input, so
   the owner's own automations can pass text without the voice prompt.

## Non-goals

- Siri reading the Coach's reply aloud.
- An Apple Watch app (watch Siri cannot run iPhone App Intents without one).
  AirPods and CarPlay work because they run Siri on the phone.
- Photos by voice, Hebrew, or any new Coach tools.
- Claiming an App Intent schema domain. Apple has no food or nutrition domain,
  and a nutrition record must never pose as an unrelated schema.
- Answering questions while locked. "How much protein is left?" asked on a
  locked phone is answered after unlock.

## Anti-goals (failure even if it "works")

- A spoken message that disappears: confirmed by Siri but never reaching
  Coach history.
- The same message logged twice (for example the inbox drained twice, or a
  capture reapplied after an uncertain save).
- Weakening diary file protection to make locked capture work. The diary
  stays `completeUnlessOpen` ([DiaryStore.swift:732](../../../ios/Mivu/Diary/DiaryStore.swift)).
- Two processors running the same Coach turn at once.
- Siri claiming food was logged. It says the message was *sent to the Coach*.
  Logging happens only with a committed receipt, as today.

## Constraints from the codebase

- Deployment target is iOS 26.0. App Intents (`AppIntent`,
  `AppShortcutsProvider`) are available with no extension target. Run the
  intent in the app process so it shares `DiaryStore` and `CoachEngine`.
- ChatGPT credentials use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  ([CredentialStore.swift:30](../../../ios/Mivu/Connection/CredentialStore.swift)),
  so they are readable on a locked phone after the first unlock since restart.
- The diary database is `completeUnlessOpen`. A cold process on a locked phone
  cannot open it, which is why the locked inbox exists.
- `FileProtectionType.completeUntilFirstUserAuthentication` is already used
  for probe job files ([ProbeJob.swift:95](../../../ios/Mivu/Analysis/ProbeJob.swift)).
  The inbox uses the same class.
- Capture today: `CoachAttachmentDraft.send` →
  `DiaryStore.captureCoachSubmission`, with
  `reconcileCoachCapture(submissionID:expectedManifest:…)` for uncertain
  saves. Accepted capture identity and context are immutable (AGENTS.md
  Coach chat history rules).
- Processing today: `CoachViewModel.resume()` runs a worker that calls
  `CoachEngine.run(turnID:expectedProfileID:)`. The worker stops on
  `enterBackground()` and restarts on `enterForeground()`, and
  `recoverLegacyCaptures` picks up captured turns that were never processed.
  `CoachViewModel` is owned by `TodayView` (UI), not by a process-level owner.
- Notification permission already exists for the morning reminder
  ([DaySettingsSection.swift:45](../../../ios/Mivu/Diary/DaySettingsSection.swift)).
- AGENTS.md: keep analysis separate from meal calculations; synthetic inputs
  in tests; English-only; never log token responses.

## How it works

### 1. The Siri action

- One `AppIntent`, "Tell Coach", with a single required `String` parameter
  `message` whose `requestValueDialog` is "What should I tell the Coach?".
- The existing `MivuShortcuts` provider gains the phrases "Tell \(.applicationName)",
  "Tell \(.applicationName) Coach" and "Message \(.applicationName) Coach", all
  starting the same intent. "Ask \(.applicationName) Coach" and "Log food with
  \(.applicationName)" already belong to the existing Open Coach and Log Food
  actions, so "Ask" and "Log with" phrases are avoided. *(builder's call, settled)*
- `openAppWhenRun` is false. The intent never opens the app.
- `authenticationPolicy` is `.alwaysAllowed`, so the intent runs on a locked
  phone. That is what the owner's "hold it, finish on unlock" choice needs.
- An empty or whitespace-only message is rejected with Siri re-asking. Very
  long text uses the same limit the Coach composer enforces.

### 2. Save first (two paths)

When protected data is available (phone unlocked, or diary already open):
capture straight into Coach history through the same store call the composer
uses, with a fresh submission ID. On an uncertain save, reconcile with the
same payload before answering; never re-capture with a new ID.

When protected data is not available: write one small JSON file per message
to an inbox folder in the app container, protected
`completeUntilFirstUserAuthentication`, then answer. Each entry holds a UUID
(later used as the Coach submission ID), the selected profile ID, the text,
and the capture clock at the moment of speaking. (The capture time zone comes
from the profile, as for every composer capture, so it is not stored.) The selected
profile ID must be readable while locked (for example from the app's
defaults, not the diary). The UUID makes the drain idempotent.

The capture time is the moment of speaking, not the moment of the drain, so
"I just had breakfast" said at 08:00 and drained at 09:30 lands on the right
waking day. If the waking-day rule can't decide (an existing
`ambiguousDay` case), the turn asks in the Coach as it does today.

### 3. Siri's reply

| Situation | Siri says *(builder's call, settled wording)* |
| --- | --- |
| Saved, unlocked | "Sent to the Coach." |
| Saved to inbox, locked | "Saved. The Coach will reply after you unlock." |
| Saved, ChatGPT not connected | "Saved. Open Mivu to connect the Coach." |
| No profile yet (onboarding unfinished) | "Open Mivu to finish setup first." Nothing is saved, since there is no owner. |
| Save failed | "I couldn't save that. Please try again." |

### 4. Draining the inbox

Drain on every path where the diary becomes available: app launch, scene
foreground, and the start of any unlocked intent run. For each entry, oldest
first: capture with the entry's UUID as submission ID and its saved clock as
capture context, reconcile if uncertain, and delete the file only after the
capture is acknowledged. A crash between capture and delete is safe because
reconciliation with the same UUID and payload finds the existing capture.

`CoachSubmissionPayload` already takes a caller-supplied submission ID and
`CoachCaptureContext`. The drain sets `capturedAt` and the time zone from the
entry. The remaining context fields (active day, previous-day confirmation,
conversation segment) are read at drain time, as for any capture.

An entry is captured only into the profile it was spoken for. If a different
profile is selected at drain time, the entry waits until its profile is
selected again. *(builder's call, settled)*

### 5. Processing and the notification

- After a successful capture, the intent returns its dialog right away and
  keeps working under a background task assertion (the
  `CoachCaptureProtection` pattern) to run that turn through `CoachEngine`.
- When the turn completes, post a local notification. Its body is the Coach's
  final reply, trimmed to a notification-sized excerpt. If the turn ends
  needing clarification or retry, the body says the Coach needs a quick
  answer. iOS hides previews on the lock screen per the user's own system
  setting. *(builder's call, settled)*
- If the background time runs out, the turn stays captured and is never
  lost. In the expiration handler, post one short notification: "Your message
  is saved. Open Mivu for the Coach's reply." The existing foreground worker
  finishes the turn on the next open.
- Owner rule: **a prompt is never lost; the reply notification is best
  effort.** Durable save before Siri confirms is the hard requirement.
  `BGContinuedProcessingTask` is not used in this scope.
- Tapping a notification opens Mivu on the Coach tab, scrolled to latest.
  Deep-linking to the exact exchange is not required. The app has no
  notification-tap routing today (the morning reminder just opens the app),
  so this adds a small `UNUserNotificationCenterDelegate` that selects the
  Coach tab.

### 6. Notification permission

On the first intent run with the phone unlocked, request `.alert` and
`.sound` authorization. If the first run is locked (no prompt possible), ask
on the next app open. Remember that the question was asked, so it is never
asked twice. If declined, everything else still works.

## Left to the builder

- **One processor per turn.** Settle how the intent's background run and a
  live `CoachViewModel` worker avoid running the same turn together. One
  simple rule: if a foreground `CoachViewModel` exists, the intent only
  captures and calls its `resume()`; otherwise the intent runs the engine.
  Confirm against `CoachEngine.run`'s state handling. A minimal move of the
  worker into a process-level owner is allowed in this scope if that is the
  smallest correct route. *(builder's call, settled)*
- How the intent reaches the shared `DiaryStore` and connection when the UI
  is not built (cold Siri launch). Today both are created in UI code
  (`DiaryViewModel.local()`, `TodayView`). Prefer the smallest process-level
  owner that does not duplicate store instances against the same database.
- File and type names, and where the inbox folder lives.
- Whether `BGContinuedProcessingTask` (iOS 26) is worth adopting later to
  finish more turns before notifying. Not required for this scope.

## Verification

- Unit tests (`ios/MivuTests`, synthetic text only):
  - Inbox write produces a protected file with the saved clock.
  - Drain captures each entry once; draining twice and crash-between-capture-
    and-delete both produce exactly one Coach turn.
  - Intent perform: unlocked → captured turn; locked → inbox entry; no
    profile → nothing saved; empty text → rejected.
  - Notification content for completed and needs-clarification turns.
- Native checks locally with XcodeBuildMCP, recording the exact source SHA.
- **Physical iPhone checklist** (the simulator cannot show locked-device Siri):
  unlocked voice log; locked voice log then unlock; CarPlay or AirPods
  invocation; airplane mode then reconnect; notification tap; Shortcuts app
  with a text input. Record results honestly. Do not advertise hands-free
  completion until this passes.

## Open facts to confirm while building

- The execution time iOS 26 grants an App Intent and the background task that
  follows it.
- Whether the intent can read `isProtectedDataAvailable` reliably on a cold
  launch, or must attempt to open the diary and fall back.
