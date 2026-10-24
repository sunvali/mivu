# Android Coach History, Replies and Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the Android Coach to match iOS. This adds the chat history
screen, seeking to a source message, long-press and swipe Reply/Copy, photo
Retake, reply notifications, and tests that check every reply summary line
against iOS.

**Architecture:** This is milestone 4c. It builds on the 4b Coach screens
(`CoachViewModel`, `CoachScreen`, `CoachTimeline`, `CoachHistoryWindow`,
`CoachComposer`) and the 4a store (`diary/CoachTimeline.kt`).

History needs conversation segments, which Android does not store yet. A derived
`coach_segment` table, like `coach_undo`, is written by `putCoachTurn` and
rebuilt by `replace`. It is never archived. History pages and the new
`AroundTurn`/`AtDay` timeline requests read it with `LIMIT` queries.

Seeking reuses the 4b replacement path: retire, reserve, then `reset` the
window with one 20-exchange page. Notifications use `NotificationCompat` in one
"Coach" channel. They are posted only while the app is in the background.

**Tech Stack:** Kotlin, Jetpack Compose (Material 3 `TopAppBar`,
`DatePickerDialog`, `DropdownMenu`, `combinedClickable`, `anchoredDraggable`),
navigation-compose, `androidx.core` `NotificationCompat` /
`NotificationManagerCompat` (already a dependency through core-ktx), the
platform SQLite store, JUnit and Compose UI instrumented tests. No new
dependency.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md)
(the Coach history, reply and notification rows), the
[Coach behaviour contract](../../development/coach-chat-behavior.md), the
binding AGENTS.md "Coach chat history" rules, and the mockup
[android-coach-history-mockup.png](../../verification/android-design/android-coach-history-mockup.png).
Carried items come from [`android-carried-items.md`](android-carried-items.md)
(Milestone 4c) and the 4b ledger
`.superpowers/sdd/2026-10-24-android-coach-screens/progress.md`.

**iOS sources:**
- `ios/Mivu/Coach/CoachHistoryView.swift` (screen and copy);
- `CoachNavigationOwner.swift` and `CoachViewModel.seek` (seek rules);
- `CoachReplyNotification.swift` (notification text);
- `CoachView.swift` (`messageActions`, `openQuote`, `inputBubble`, `draftPhotos`, the history button's paging actions);
- `CoachTimelineView.swift` (`replyPan`: swipe-to-reply);
- `ios/Mivu/Diary/DiaryDatabaseQueries.swift` (`coachSegmentPage`, `coachWindow`, the receipt summary at lines 390–460);
- `DiaryDatabaseMutations.swift` (`appendCapture`, segment assignment).

Copy is verbatim, with "iPhone" replaced by "phone".

## Scope decisions

**Kept:**
- the history screen;
- seek to a source turn;
- reply notifications;
- long-press Reply/Copy;
- swipe-to-reply. It stays because the behaviour contract lists swipe first
  ("swipe a row right … or long-press a message and choose Reply"), so it is a
  primary iOS path;
- photo Retake. iOS has a "Retake" button under each draft photo;
- the summary-line tests.

**Deferred or cut, each with its reason:**
- **`record_source`:** deferred. It only fixes two invisible shortcuts:
  leftover photo copies after `delete_workout`, and the `find_meals` origin
  fallback. The `shortcut:` comments stay. Meal seek uses the same fallback
  (Task 2).
- **Model picker:** deferred to M5. iOS shows "Account model" only in the
  Settings ChatGPT connection section, and only when connected. That is the M5
  connection UI.
- **"Connect ChatGPT for replies" link:** deferred to M5. On iOS it starts
  sign-in (`ChatGPTConnectButton`), and release Android has no sign-in screen.
  A dead link is worse than the current footnote "Messages save on this
  phone."
- **Live Coach turn against ChatGPT (Phase 0):** M5. It needs the sign-in UI.
- **Legacy capture recovery and the `pendingMealID` prepare step:** cut. iOS
  recovers meal submissions captured before Coach existed. Android meal
  captures are drained by `MealAnalysisWorker`, and archive import has no UI
  yet (Play readiness). No Android user can reach that state. Revisit when
  import ships.
- **Markdown beyond emphasis:** cut. iOS parses inline-only markdown, and the
  Coach prompt forbids headings, lists and tables. Bold is already handled.
- **4b parked minors:** only one has a concrete user-visible failure. On a
  device without a camera, the camera icon opens a black screen. Its fix is
  folded into Task 3. These are dropped:
  - `MotionPolicy` read-before-register: a millisecond window, not reachable by
    a person;
  - heart pop scale target: it differs only when a part's own scale is not 1;
  - `CoachEngine` needsRetry on cancellation: it matches iOS `CoachEngine`
    line 205;
  - main-thread KDoc, double-parse, slot-cycle, `resolve` in `remember`, and
    `retireAll` ordering: no visible effect;
  - stale coach VM on profile change: latent, because the VM is keyed by profile;
  - scratch Proof profile: debug-only;
  - `announceForAccessibility` deprecation: it still works;
  - retry-after-Absent rebuild: harmless;
  - optional second camera prompt: iOS has none;
  - re-greet: milestone 7.

## Global Constraints

- **Platform:**
  - minSdk 31, targetSdk 37, platform APIs first, no new dependency;
  - predictive back is on by default at targetSdk 37, and pushed routes get it
    for free.
  - `POST_NOTIFICATIONS` is declared, and requested only on API 33+
    (`Build.VERSION.SDK_INT >= TIRAMISU`). On API 31–32, posting needs no
    runtime permission.
- **Bounded reads** (AGENTS.md):
  - every Coach and history path reads with `LIMIT`;
  - nothing calls `snapshot()`, and `snapshotReads` stays 0;
  - a history page holds at most 30 segments and reads `LIMIT 31`;
  - a seek page holds at most 20 exchanges (9 before the target, as iOS
    `coachWindow`);
  - the 100-exchange window counts resident, reserved and retired page work,
    and a seek retires in-flight reads the way `jumpToLatest` does.
- **Ownership:**
  - each history load and seek captures the coach view model's profile at
    request time;
  - a result that arrives after the screen closed, or after the profile
    changed, is dropped (iOS `generation` and `isCurrent`).
- **Immutability:** accepted capture identity and context and committed
  receipts never change. The derived segment table is only ever written from
  stored turns.
- **Touch targets:** at least 48 dp, for history rows (64 dp minimum),
  "Earlier conversations", "Show all chat history", "Try again", Retake and the
  menu items.
- **Copy** (verbatim from iOS):
  - "Chat history";
  - "Choose date";
  - "Selected date";
  - "Show all chat history";
  - "History unavailable";
  - "Chat history is unavailable. Try again.";
  - "Try again";
  - "Loading chat history";
  - "No saved chat" / "No chat for this date";
  - "Your saved conversations will appear here." / "No saved conversation is
    labeled {date}.";
  - "Earlier conversations";
  - "Conversation date";
  - "Choose the date shown in your conversation. Separate visits remain
    separate choices.";
  - "Cancel" and "Show date";
  - "Load earlier messages" / "Load later messages" and "Retry earlier
    messages" / "Retry later messages";
  - "Reply" and "Copy";
  - "Retake" / "Retake photo {n}" and "Retake photo" (the camera shutter while
    retaking);
  - "This conversation is unavailable for the current diary.";
  - notification title "Coach", with the bodies from `CoachReplyNotification.text`.
- **Data and logs:**
  - synthetic data only;
  - never log prompts, replies, notification bodies or tokens.
- **Speed:**
  - each task runs only its own test classes, one class per
    `connectedDebugAndroidTest` run;
  - the full suite runs once, in Task 5.

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest --tests '*<Class>'
  ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.<pkg>.<Class>
  ```

## Review Focus

1. **A diary with 10,000 turns opens history and seeks to an old message**:
   - one history page reads at most 31 segment rows;
   - the seek page holds at most 20 exchanges;
   - `snapshotReads` stays 0.

   (Task 1: `tenThousandTurnsHistoryAndSeekStayBounded`)
2. **Restore or import replaces the diary while segments exist**: the derived
   table is rebuilt from the restored turns, and no stale segment survives.
   (Task 1: `replaceRebuildsSegments`)
3. **The reader taps a history row while an earlier page is still loading**:
   - the in-flight read is retired and still counted until it exits;
   - the window never exceeds 100;
   - the target row is shown and highlighted.

   (Task 2: `seekWhilePagingStaysWithinWindow`)
4. **A Coach reply finishes while Mivu is open**: no notification is posted.
   A reply that saved a meal (`pendingMealID`) posts nothing either. (Task 4:
   `foregroundPostsNothing`)
5. **Notifications denied, or API 31–32**:
   - sending a message never fails or blocks;
   - the permission is asked once, on the first send, only on API 33+.

   (Task 4: `deniedPermissionStillSends`)

---

### Task 1: Segment index, history queries, seek pages and summary-line parity

**Files:**
- Modify: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryDatabase.kt`:
  - add `CREATE TABLE IF NOT EXISTS coach_segment` and its two indexes beside
    `coach_undo`;
  - `putCoachTurn` calls `tx.indexCoachSegment(turn)` for a new turn;
  - `replace` calls `rebuildCoachSegments()` after `writeRows`;
  - `open` rebuilds when `MAX(coach_turn.ordinal)` is not the segment table's
    `MAX(lastOrdinal)`.
- Create: `android/app/src/main/java/com/yakov103/mivu/diary/CoachSegments.kt`
- Modify: `android/app/src/main/java/com/yakov103/mivu/diary/CoachTimeline.kt`.
  Add `CoachPageRequest.AroundTurn` and `AtDay`.
- Modify: `android/app/src/main/java/com/yakov103/mivu/diary/DiaryCapture.kt`.
  Update the segment `shortcut:` comment: the index now exists, but the raw
  head ID is still compared.
- Test:
  - `android/app/src/androidTest/java/com/yakov103/mivu/diary/CoachSegmentsTest.kt`
  - `android/app/src/androidTest/java/com/yakov103/mivu/coach/CoachSummaryLinesTest.kt`

**Interfaces:**
- Produces:
  - **The table:** `coach_segment(segmentID TEXT PRIMARY KEY, trackingDayID TEXT, displayLocalDate TEXT NOT NULL, displayTimeZoneID TEXT NOT NULL, firstTurnID TEXT NOT NULL, firstCapturedAt TEXT NOT NULL, firstOrdinal INTEGER NOT NULL, lastOrdinal INTEGER NOT NULL, preview TEXT NOT NULL)`.
    Its indexes are `(lastOrdinal, segmentID)` and
    `(displayLocalDate, lastOrdinal, segmentID)`.
  - `data class CoachSegmentSummary(segmentID: UUID, trackingDayID: UUID?, displayLocalDate: String, displayTimeZoneID: String, firstTurnID: UUID, firstCapturedAt: Instant, firstOrdinal: Long, lastOrdinal: Long, preview: String)`
  - `data class CoachDayCursor(lastOrdinal: Long, segmentID: UUID, dateFilter: String?)`
  - `data class CoachDayPage(segments: List<CoachSegmentSummary>, cursor: CoachDayCursor?, hasMore: Boolean)`
  - `fun DiaryDatabase.coachDays(before: CoachDayCursor? = null): CoachDayPage`
  - `fun DiaryDatabase.coachSegments(displayLocalDate: String, before: CoachDayCursor? = null): CoachDayPage`.
    It throws `DiaryError.InvalidData("date filter")` for a date that is not
    `yyyy-MM-dd`, and `DiaryError.InvalidData("cursor")` when the cursor's
    filter differs or its segment no longer has that `lastOrdinal`.
  - `CoachPageRequest.AroundTurn(val turnID: UUID)` and
    `CoachPageRequest.AtDay(val dayID: UUID)`. The first throws
    `DiaryError.NotFound` for an unknown turn. The second also throws it for a
    day with no chat; it finds the first segment with that `trackingDayID`,
    then goes around its `firstTurnID`.
  - `fun DiaryDatabase.coachSourceTurn(mealID: UUID): UUID?`. It carries a
    `shortcut:` comment: the earliest turn naming the meal, with the same query
    as `coachMeal`'s description fallback. Upgrade it with `record_source`.
- **Segment assignment** (iOS `appendCapture`, for each new turn in ordinal
  order):
  - the date and zone are the turn's `activeDayID` day's `localDate` and
    `timeZoneID` when that day exists. Otherwise they are the capture date in
    `captureTimeZoneID`, and the zone is `captureTimeZoneID`.
  - With `captureSegmentID`: extend that row if it exists (`lastOrdinal =`
    the turn's ordinal), else insert it.
  - Without it: extend the newest segment when its `trackingDayID` is null and
    its date and zone match. Otherwise insert
    `UUID.nameUUIDFromBytes("mivu.coach.segment:$turnID")`, which stays
    deterministic across rebuilds.
  - `preview = text.take(160)`.

- [ ] **Step 1: Failing tests.**
  - In `CoachSegmentsTest`, with synthetic turns through `captureCoachSubmission`:
    - `turnsInOneActiveSegmentShareOneRow`;
    - `dateOrZoneChangeStartsNewSegment`;
    - `daysPageIs30NewestFirstWithCursor`: 31 segments give 30, then 1, with
      `hasMore` true and then false;
    - `dateFilterKeepsSeparateVisits`: two segments labelled `2026-10-23` both
      come back, and other dates do not;
    - `staleCursorRejected`;
    - `badDateFilterRejected`;
    - `aroundTurnReturnsNinePrecedingAndAtMost20`;
    - `atDayOpensFirstConversationOfDay`;
    - `atDayWithoutChatIsNotFound`;
    - `replaceRebuildsSegments`;
    - `openRebuildsMissingIndex`: drop the table's rows, reopen, and the rows
      are equal to before;
    - `tenThousandTurnsHistoryAndSeekStayBounded`: `snapshotReads == 0`, and the
      page sizes are at most 30 and 20.
  - In `CoachSummaryLinesTest`, expected strings are copied from iOS
    `DiaryDatabaseQueries.swift` 390–460, with one receipt kind per test:
    - `undoOfLogSaysRemoved` ("Removed {names}.");
    - `undoOfEditSaysUndid` ("Undid the change to {names}.");
    - `scaleShowsBeforeAndAfter` ("Updated {names}: {before} → {after} kcal." plus
      the no-calories note for one and for two items);
    - `moveSaysShortDate` ("Moved to {short date}.");
    - `attachPhotosCounts` ("Added the photo." / "Added 2 photos.");
    - `deletePhotoConfirms` ("Removed the photo." / "Check the meal's photos.");
    - `weightAndWorkout` ("Weight saved: **70 kg**. Workout saved: cardio, 45
      minutes.", as iOS `CoachEngineTests` line 523);
    - `goalsUpdated`;
    - `dayMarkedSkippedAndCounted`;
    - `deletedRecordsSayDeleted` (meal, item, weight and workout).
- [ ] **Step 2: Run** both classes. Expected: `CoachSegmentsTest` FAILS with
  unresolved references. `CoachSummaryLinesTest` either passes or shows the
  real gaps.
- [ ] **Step 3: Implement** `CoachSegments.kt`, the table, the rebuild and the
  two requests. Port the queries from iOS `coachSegmentPage` and
  `coachWindow`. Fix any summary line that differs from iOS in
  `coach/CoachReplyLines.kt`.
- [ ] **Step 4: Run** both classes, then `CoachTimelineTest` and
  `DiaryCaptureTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/diary android/app/src/main/java/com/yakov103/mivu/coach/CoachReplyLines.kt android/app/src/androidTest/java/com/yakov103/mivu/diary/CoachSegmentsTest.kt android/app/src/androidTest/java/com/yakov103/mivu/coach/CoachSummaryLinesTest.kt
git commit -m "feat(android): index Coach conversations for history and seek"
```

### Task 2: Chat history screen and seek

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/ui/coach/CoachHistoryScreen.kt`
  (the screen and `CoachHistoryModel`)
- Modify:
  - `ui/coach/CoachViewModel.kt` (`seek`, `highlighted`);
  - `ui/coach/CoachScreen.kt` (scroll to the highlighted row);
  - `ui/coach/CoachTimeline.kt` (the sent quote inside `InputBubble`, and the
    highlight);
  - `ui/MivuApp.kt` (`Route.CoachHistory`, the history action in the Coach top
    bar, and meal Ask Pip seeking);
  - `ui/coach/CoachReplyQuote.kt` (`CoachSentQuote`).
- Test:
  - `android/app/src/test/java/com/yakov103/mivu/ui/coach/CoachHistoryModelTest.kt`
  - `android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachHistoryScreenTest.kt`

**Interfaces:**
- Consumes: `coachDays`, `coachSegments`, `CoachDayCursor`, `CoachDayPage`,
  `CoachPageRequest.AroundTurn/AtDay` and `coachSourceTurn` from Task 1.
- Produces:
  - `sealed interface CoachSeekTarget { data class Turn(val id: UUID); data class Day(val id: UUID) }`
  - `fun CoachViewModel.seek(target: CoachSeekTarget): Job`. It retires the
    in-flight work and reserves a replacement, as `replace()` does. It reads
    the page and `reset`s the window. On success it sets
    `timeline.highlighted` (`Turn` → the id; `Day` → the first exchange whose
    `activeDayID` is that day). On failure it sets the message "This
    conversation is unavailable for the current diary."
  - `val CoachTimelineState.highlighted: UUID?`. It is cleared by
    `jumpToLatest`, the next send, or a user scroll that moves the highlighted
    row off screen.
  - `class CoachHistoryModel(load: suspend (date: String?, before: CoachDayCursor?) -> CoachDayPage)`
    has:
    - `StateFlow` state (`page`, `dateFilter`, `isLoading`, `errorMessage`);
    - `suspend fun show(date: String? = null)`;
    - `suspend fun earlier()`;
    - `fun invalidate()`.

    It is a one-to-one port of iOS `CoachHistoryModel`: a generation counter
    drops late results, and `earlier()` is ignored while a load runs.
  - `@Composable fun CoachHistoryScreen(model: CoachViewModel, zone: ZoneId, onOpen: (CoachSeekTarget.Turn) -> Unit, onClose: () -> Unit)`
  - `@Composable fun CoachSentQuote(reply: CoachReply, onOpen: (() -> Unit)?)`.
    It is the in-bubble quote: white rule, author title, 2 lines (3 at large
    text), at least 48 dp, black at 14% behind it. The spoken label is "Reply
    to {author}: {excerpt}" with the hint "Shows the original". A `Weight`
    target gets `onOpen = null`, as on iOS.
- **Screen** (mockup frames 1–2):
  - an M3 `TopAppBar` titled "Chat history", with Navigate up and a "Choose
    date" calendar action;
  - rows show the `displayLocalDate` headline, the capture label
    `d MMM yyyy, HH:mm:ss · {zone}` in the row's zone (`Locale.US`), and the
    preview in 2 lines;
  - "Choose date" opens `DatePickerDialog`, with the iOS note under the picker
    and "Cancel" / "Show date";
  - the label is the picked date in the profile zone;
  - closing the screen calls `invalidate()`.
- **Seek entry points:**
  - a history row → `seek(Turn(firstTurnID))`, then pop back to Coach;
  - a sent quote, as iOS `openQuote`: `Message` → `seek(Turn)`, `Day` →
    `seek(Day)`, `Meal`/`Item` → `onOpenMeal`, `Workout` → nothing (Android
    has no workout detail yet; add a `shortcut:` comment);
  - meal detail Ask Pip → `coachSourceTurn(mealID)?.let { Turn(it) } ?: Day(meal.dayID)`,
    after `startReply`.
- **History button:** an `IconButton` in the Coach top bar with the
  content description "Chat history" (`ic_history`). Through
  `semantics { customActions }` it carries the named paging actions from iOS
  `accessibilityPageAction`. They call `loadEarlier` / `loadLater` with the
  current visible set.

- [ ] **Step 1: Failing tests.**
  - In `CoachHistoryModelTest`, with a fake `load`:
    - `lateResultAfterShowDateIsDropped`;
    - `earlierIgnoredWhileLoading`;
    - `failureShowsIosMessage`;
    - `invalidateDropsInFlight`.
  - In `CoachHistoryScreenTest`, with synthetic turns:
    - `listsNewestFirstWithCaptureLabel`;
    - `earlierConversationsLoadsNextPage`;
    - `chooseDateFiltersAndShowAllClears`;
    - `emptyAndFilteredEmptyCopy`;
    - `rowSeeksAndHighlightsFirstMessage`;
    - `sentQuoteSeeksOriginalMessage`;
    - `mealAskPipSeeksSourceTurn`;
    - `seekWhilePagingStaysWithinWindow`;
    - `historyButtonHasPagingActions`;
    - `backReturnsToCoachUnchanged`.
- [ ] **Step 2: Run** both classes. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both classes, then `CoachScreenTest` and
  `CoachHistoryWindowTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/ui android/app/src/main/res/drawable android/app/src/test/java/com/yakov103/mivu/ui/coach/CoachHistoryModelTest.kt android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachHistoryScreenTest.kt
git commit -m "feat(android): add Coach chat history and seek"
```

### Task 3: Reply, Copy, swipe-to-reply and photo Retake

**Files:**
- Modify:
  - `ui/coach/CoachTimeline.kt` (message actions);
  - `ui/coach/CoachViewModel.kt` (`replyTo`, `retakePhoto`);
  - `ui/coach/CoachComposer.kt` (Retake under each draft photo; hide the camera
    without a camera);
  - `ui/coach/CoachCameraScreen.kt` (retake mode);
  - `ui/MivuApp.kt` (`Route.CoachCamera(retaking: String?)`).
- Test:
  - `android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachReplyActionsTest.kt`
  - additions to `CoachComposerTest` and `CoachCameraTest`

**Interfaces:**
- Produces:
  - `fun CoachViewModel.replyTo(turn: CoachTurn, fromPip: Boolean)`. It
    replaces the draft's quote with
    `CoachReply(Message(turn.id, fromPip), excerpt)`. The excerpt is the plain
    reply (`CoachReplyLines.plain`) or the text, `take(280)`. Composer focus
    follows, as iOS `reply(to:)`.
  - `fun CoachViewModel.retakePhoto(path: String, file: File)`. It prepares
    `file` on the photo path and replaces `path` at the same index. On failure
    it keeps the old photo and shows `PHOTO_NOT_TAKEN`. The old file is deleted
    only when no attempt holds it, as `removePhoto` does.
- **Message actions** (iOS `messageActions`):
  - a long press on the person's bubble or on Pip's reply text opens a
    `DropdownMenu` with "Reply" (`ic_reply`) and "Copy" (`ic_copy`);
  - Copy is hidden for empty text;
  - Copy uses `LocalClipboard`, with plain reply text for Pip;
  - each also gets `semantics { customActions = "Reply" }`.
- **Swipe-to-reply** (iOS `replyPan`):
  - a horizontal `anchoredDraggable` to the right on the exchange row;
  - it starts only when the drag is mostly horizontal, so vertical scrolling
    wins;
  - the row follows the finger up to 64 dp, then at 0.15× past it;
  - a reply arrow fades in with progress;
  - crossing 64 dp gives one `HapticFeedbackType.LongPress`;
  - release past the threshold replies, to Pip's answer if there is one, else
    to the person's message;
  - the row springs back, or snaps back when animations are removed.
- **Retake** (iOS `draftPhotos`):
  - a "Retake" `TextButton` (48 dp, spoken "Retake photo {n}") under each draft
    thumbnail opens the camera with `retaking = path`;
  - the shutter's label becomes "Retake photo", and one shot returns to the
    composer.
- **Parked fix:** the camera icon and Retake are hidden when
  `!packageManager.hasSystemFeature(FEATURE_CAMERA_ANY)`. "Choose photos"
  stays.

- [ ] **Step 1: Failing tests.**
  - In `CoachReplyActionsTest`:
    - `longPressReplyQuotesPip`;
    - `longPressReplyQuotesOwnMessage`;
    - `copyPutsPlainTextOnClipboard`;
    - `copyHiddenForPhotoOnlyMessage`;
    - `swipePastThresholdReplies`;
    - `shortSwipeDoesNothing`;
    - `verticalDragStillScrolls`;
    - `replyCustomActionExists`.
  - In `CoachComposerTest`:
    - `retakeReplacesPhotoInPlace`;
    - `failedRetakeKeepsOldPhoto`;
    - `noCameraHidesCameraAndRetake` (fake `hasCamera = false`).
  - In `CoachCameraTest`: `retakeModeLabelsShutterAndReturnsAfterOneShot`.
- [ ] **Step 2: Run** `CoachReplyActionsTest`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `CoachReplyActionsTest`, `CoachComposerTest` and
  `CoachCameraTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/ui android/app/src/main/res/drawable android/app/src/androidTest/java/com/yakov103/mivu/ui/coach
git commit -m "feat(android): reply, copy and retake in Coach"
```

### Task 4: Reply notifications

**Files:**
- Create: `android/app/src/main/java/com/yakov103/mivu/coach/CoachReplyNotification.kt`
- Modify:
  - `AndroidManifest.xml` (`POST_NOTIFICATIONS`, and `launchMode="singleTop"` on
    `MainActivity`);
  - `MivuApplication.kt` (a foreground flag, and posting after each drained
    turn);
  - `MainActivity.kt` (`onStart`/`onStop` set the flag; `onNewIntent` and
    `onCreate` read `coachTurnID` and open Coach);
  - `ui/coach/CoachViewModel.kt` (`needsNotificationPermission` on the first
    send);
  - `ui/coach/CoachScreen.kt` (the permission launcher);
  - `ui/MivuApp.kt` (`openCoach` from the intent).
- Test:
  - `android/app/src/test/java/com/yakov103/mivu/coach/CoachReplyNotificationTest.kt`
  - `android/app/src/androidTest/java/com/yakov103/mivu/coach/CoachReplyNotificationPostTest.kt`

**Interfaces:**
- Consumes: the `CoachWorker` drain result and `CoachTurn`.
- Produces:
  - `object CoachReplyNotification` has:
    - `const val TURN_KEY = "coachTurnID"` and `const val CHANNEL = "coach"`
      (the channel is named "Coach", default importance, and created on first
      post);
    - `fun text(turn: CoachTurn): Pair<String, String>?`, a one-to-one port.
      It returns null when `pendingMealID != null`, or the state is
      `captured`/`analyzing`. For `completed` it returns the plain reply,
      `null` if empty, and cuts at 180 to `prefix(179) + "…"`.
      `needsClarification` gives "The Coach needs a quick answer.". The
      `needsRetry`, `waitingForNetwork` and `waitingForConnection` states give
      "Your message is saved. Open Mivu for the Coach's reply."
    - `fun post(context: Context, turn: CoachTurn)`. It uses the tag
      `"coach-reply-$id"`, so a later reply replaces an earlier note. It uses
      `setGroup("coach")` and `setAutoCancel(true)`, with a `PendingIntent`
      (`FLAG_IMMUTABLE`) to `MainActivity` that carries `TURN_KEY`. It returns
      early when `NotificationManagerCompat.areNotificationsEnabled()` is
      false.
  - `MivuApplication.inForeground: Boolean`, set by `MainActivity`. It is
    `@Volatile`, read when a turn finishes.
- **Posting:** after `coachWorker.drain` processes a turn, post its stored
  result when `!inForeground`. Add a `shortcut:` comment: iOS
  `postSaved`-on-expiry has no Android analogue while drain runs in the process
  scope; upgrade when Coach moves to WorkManager (M5).
- **Permission:**
  - on the first successful send, on API 33+, when the permission is
    undecided, `CoachScreen` launches `RequestPermission(POST_NOTIFICATIONS)`
    once;
  - a `SharedPreferences` flag `asked_notifications` keeps it from asking
    again;
  - denial changes nothing else.
- **Tap:** opens Coach at the latest exchange, as iOS sets `openCoach`. It does
  not seek.

- [ ] **Step 1: Failing tests.**
  - In `CoachReplyNotificationTest` (JVM):
    - `completedUsesPlainReply`;
    - `longReplyCutAt180`;
    - `emptyReplyPostsNothing`;
    - `pendingMealPostsNothing`;
    - `runningPostsNothing`;
    - `clarificationAndRetryCopy`.
  - In `CoachReplyNotificationPostTest`, with the permission granted through
    `UiAutomation`:
    - `backgroundPostsOneNotificationKeyedByTurn`;
    - `foregroundPostsNothing`;
    - `laterReplyReplacesSavedNote`;
    - `tapOpensCoach`;
    - `deniedPermissionStillSends`.
- [ ] **Step 2: Run** both classes. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both classes and `CoachWorkerTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml android/app/src/main/java/com/yakov103/mivu android/app/src/test/java/com/yakov103/mivu/coach/CoachReplyNotificationTest.kt android/app/src/androidTest/java/com/yakov103/mivu/coach/CoachReplyNotificationPostTest.kt
git commit -m "feat(android): notify Coach replies that finish in the background"
```

### Task 5: Milestone 4c evidence and parity

**Files:**
- Create:
  - `docs/verification/2026-10-24-android-coach-history.md`;
  - `docs/verification/android-coach/*.png` (new shots only).
- Modify:
  - `docs/parity.md`;
  - `docs/superpowers/plans/android-carried-items.md`;
  - `android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachFixtureSeed.kt`
    (add segments across dates, and a quoted reply).

- [ ] **Step 1: Run the full suite once** at a clean commit:
  `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks`,
  then `python3 scripts/ci/parity.py` and the `scripts/ci` unit tests.
  - Record the SHA, the emulator, and the counts from the JUnit XML.
  - Never count a skipped or zero-test class.
  - If a class fails, fix it, or record it honestly with its cause.
- [ ] **Step 2: Screenshots** from `CoachFixtureSeed`, in light, dark and font
  scale 2.0:
  - `coach-history`;
  - `coach-history-date`;
  - `coach-seek-highlight`;
  - `coach-reply-menu`;
  - `coach-swipe-reply`;
  - `coach-retake`;
  - `coach-notification` (from the shade, on API 33+).

  Compare them with the mockup.
- [ ] **Step 3: Parity.**
  - `coach-history` becomes `done`.
  - `coach-reply` becomes `done` (seek, long-press, swipe).
  - Notifications get a note about Coach replies. Meal-analysis notifications
    stay M5.
- [ ] **Step 4: Carried items.**
  - Remove from Milestone 4c: summary lines, Retake, legacy recovery and
    markdown, each with its reason from "Scope decisions".
  - Move the model picker, the Connect link and the live Phase 0 turn to
    Milestone 5.
  - Add `record_source` under a new "Later" heading, with its reason.
- [ ] **Step 5: Commit**

```bash
git add docs/verification/2026-10-24-android-coach-history.md docs/verification/android-coach docs/parity.md docs/superpowers/plans/android-carried-items.md android/app/src/androidTest/java/com/yakov103/mivu/ui/coach/CoachFixtureSeed.kt
git commit -m "docs(verification): record Android Coach history and replies"
```
