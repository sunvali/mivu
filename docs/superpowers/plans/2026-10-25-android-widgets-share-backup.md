# Android Widgets, Quick Capture, Share and Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Android to iOS parity for milestone 8:
- the calories home-screen widget, small and medium, with Pip;
- quick capture: launcher shortcuts and a Quick Settings tile;
- "Share to Mivu", which saves a message to Coach from outside the app;
- Coach reply notifications for those outside-app messages;
- archive export and restore on Backup & export, with streamed photo bytes.

**Architecture:** This is milestone 8. The storage, archive and Coach
engine already exist:
- `DiaryArchive` reads and writes the `mivu-diary` v4 envelope;
- `DiaryDatabase.importArchive` applies `replacement` with the
  `isVerifiedSuccessor` check;
- `captureCoachSubmission` and `reconcileCoachCapture` save a Coach turn
  durably;
- `CoachJobService` finishes turns after the app leaves the screen;
- `repository.changes` emits after every committed write.

This milestone adds thin platform entry points on top of them:
- **Routing.** One `QuickAction` intent shape is shared by shortcuts, the
  tile, the widget and notifications. `MainActivity` hands it to the shell
  through `MivuApplication.quickRequest`.
- **Widget.** The widget is a classic `AppWidgetProvider` with responsive
  `RemoteViews`. It draws a small `WidgetSnapshot`, as iOS does, which the app
  stores in preferences after each change.
- **Share.** A translucent `ShareToCoachActivity` is the Android counterpart
  of Siri "Tell Coach". It saves the message as a Coach turn, schedules the
  background drain and follows the turn, so its reply can be posted as a
  notification.
- **Archive.** The archive photo bytes are streamed through a spool folder,
  so peak memory is about one photo. The Backup & export screen then adds
  export and restore through the Storage Access Framework.

**Tech Stack:** Kotlin and Jetpack Compose (Material 3 `ModalBottomSheet`,
`AlertDialog`), plus platform APIs:
- `AppWidgetProvider` and `RemoteViews(Map<SizeF, RemoteViews>)` (API 31);
- `AlarmManager.setWindow`;
- `ShortcutManager` static `shortcuts.xml`;
- `TileService`;
- `Intent.ACTION_SEND` and `ACTION_SEND_MULTIPLE`;
- `ActivityResultContracts.CreateDocument` and `OpenDocument`;
- `NotificationCompat` and `NotificationManagerCompat` (already in
  `core-ktx`);
- `JobScheduler`, through the existing `CoachJobService`.

No new dependency.

**Spec:** [`docs/superpowers/specs/2026-10-23-android-app-design.md`](../specs/2026-10-23-android-app-design.md)
(feature map rows: "Archive export and import", "Quick capture",
"Widgets"; "Archive compatibility"; "Backup and restore"). Behaviour comes
from these iOS specs:
- [widgets](../specs/2026-10-20-widget-design.md);
- [Pip entry points](../specs/2026-10-21-pip-entry-points-design.md);
- [Siri to Coach](../specs/2026-10-23-siri-coach-design.md);
- [food logger](../specs/2026-10-11-food-logger-design.md) (archive).

The mockup is
[android-widgets-mockup.png](../../verification/android-design/android-widgets-mockup.png).

The scope comes from:
- [`docs/parity.md`](../../parity.md): the rows `widgets`, `quick-capture`,
  `siri-coach`, `analyzed-notification` (the Coach-reply part) and
  `archive`;
- [`android-carried-items.md`](android-carried-items.md):
  - "Milestone 8 (outside-app capture)";
  - Settings: "Backup & export: the archive export/import UI joins the report
    screen";
  - Play readiness: "Stream photo decoding for large archives, and add the
    export/import UI to Backup & export";
- the M4c ruling in `.superpowers/sdd/2026-10-24-android-coach-history/progress.md`:
  reply notifications wait for an outside-app turn source.

**iOS sources** (the source of truth; copy is verbatim, with "iPhone"
replaced by "phone"):
- `ios/MivuWidgets/CaloriesWidget.swift`: layout, copy, spoken labels, and
  the rollover timeline entry.
- `ios/Shared/WidgetSnapshot.swift`: `nextRollover`, `afterRollover` and
  `ringFraction`.
- `ios/Mivu/WidgetSnapshotWriter.swift`: the snapshot comes from the active
  day, with the rollover from the day's start.
- `ios/MivuWidgets/Assets.xcassets/PipWave.imageset/pip.png`: the waving Pip
  cut by `design-system/mivu/characters/pip/widget/cut-widget-art.swift`.
- `ios/MivuWidgets/LogFoodControl.swift`, `ios/Shared/MivuIntents.swift`
  (`LogFoodIntent` "Snap It", `OpenCoachIntent` "Open Coach") and
  `ios/Mivu/QuickLog.swift`:
  - `QuickLogRequest`;
  - `MivuShortcuts`;
  - the notification tap that opens Coach.
- `ios/Config/Info.plist` `UIApplicationShortcutItems` (the "Snap It" quick
  action).
- `ios/Mivu/Coach/TellCoachIntent.swift`: `TellCoachOutcome` dialogs and
  the `TellCoach.run` order (save first, retry with the same ID, then start
  work).
- `ios/Mivu/Coach/CoachViewModel.swift` 379–397 (`captureExternal`).
- `ios/Mivu/Coach/CoachReplyNotification.swift`: `text(for:)`, `post`,
  `postSaved` and `follow`.
- `ios/Mivu/Diary/DiaryBackupSettings.swift`: export and restore buttons,
  pickers, the confirmation dialog and every error line.
- `ios/Mivu/Diary/DiaryViewModel.swift` 552–563 (`importArchive`: replace the
  selected profile, refuse another local profile, import a new one as its own
  diary and switch to it).
- `ios/Mivu/Diary/DiaryExportCoordinator.swift`: `DiaryExportStage`,
  `checkCapacity` (five copies plus 64 KiB) and the temp-folder release.

## Scope decisions

**Kept:**
- **Widget.** The calories widget, small (2×2) and medium (4×2), in light and
  dark:
  - intake, the goal bar, and "Snap It" and "Coach" on medium;
  - Pip in the corner;
  - the no-diary and no-target states;
  - zero after the waking-day cutoff, even when the app does not run.
- **Quick capture.**
  - Static launcher shortcuts "Snap It" and "Coach". These are the iOS quick
    action and the Shortcuts app shortcuts.
  - A Quick Settings tile "Snap It". This is the iOS Control Center and
    Action button control.
- **Share to Mivu.** Text and up to 8 photos from any app's share sheet. The
  turn is saved without opening the app, using the iOS Siri result lines.
- **Coach reply notifications.** Only for turns saved from the share sheet
  while Mivu is not on screen, as iOS does for Siri. This settles the carried
  item "Milestone 8 (outside-app capture)".
- **Backup & export.** "Export diary and photos" and "Restore from diary
  archive" through the system file picker, with iOS confirmation copy and
  restore rules. Photo bytes are streamed in both directions. This settles
  the Settings and Play-readiness archive items.

**Decided, each with its reason:**
- **The widget uses `RemoteViews`, not Glance.**
  - The spec names Glance. This plan deviates, for these reasons:
    - The widget is two fixed layouts: text, a `ProgressBar`, an
      `ImageView` and two buttons. Every part is a `RemoteViews`-supported
      view.
    - API 31's `RemoteViews(Map<SizeF, RemoteViews>)` gives small and
      medium in one update, and the minSdk is 31.
    - Glance would add `androidx.glance:glance-appwidget` and its runtime
      for about 120 lines of XML, against Ponytail and the spec's "every
      other dependency is justified".
  - Revisit if a scrolling or configurable widget is designed.
- **The widget reads a stored `WidgetSnapshot`.** It never opens the diary,
  as on iOS.
  - The app writes `widgetSnapshot` (JSON) to `DiaryRepository.preferences`
    after each `repository.changes` emission, each rollover and each change
    to "Day starts at".
  - `onUpdate` (add, reboot, the rollover alarm) re-renders from the stored
    value, so a broadcast never bootstraps the diary.
  - **Rollover.** One inexact alarm, `setWindow(RTC, rolloverAt, 10 min)`,
    sends `ACTION_APPWIDGET_UPDATE` to the provider. It then draws
    `afterRollover()`. This is the iOS timeline entry; no exact-alarm
    permission is needed.
  - The iOS lock-screen families (circular, rectangular) have no phone
    counterpart on Android 12–16 and are left out.
- **Pip is the iOS widget art.**
  `ios/MivuWidgets/Assets.xcassets/PipWave.imageset/pip.png` is copied
  unchanged to `res/drawable-nodpi/pip_wave.png`. The provenance comment
  names `cut-widget-art.swift`. It is the approved painting, not the rig, as
  on iOS.
- **One intent shape routes every entry point.**
  - `QuickAction` (`SnapIt`, `OpenCoach`, `Today`) is an explicit
    `MainActivity` intent with `FLAG_ACTIVITY_NEW_TASK or CLEAR_TOP or SINGLE_TOP`.
  - `MainActivity.onCreate` and `onNewIntent` publish it to
    `MivuApplication.quickRequest`.
  - The shell consumes the request once the diary is `Ready`:
    - Snap It: the Coach tab, then `Route.CoachCamera()`;
    - Coach: the Coach tab with the composer focused;
    - Today: the Today tab.
  - This is iOS `QuickLogRequest`.
  - iOS "Log Meal" opens the same camera (its own `shortcut:` comment), so
    no third shortcut is added.
- **Share is the outside-app turn source, and Assistant is skipped.**
  - Google Assistant App Actions (`shortcuts.xml` `<capability>`) are
    skipped. They can only be tested through a Play Console upload and
    Google's App Actions review, and Gemini, which is replacing Assistant,
    offers no stable third-party custom intent.
  - The share sheet carries the same job as Siri "Tell Coach": put a
    message into Coach without opening the app.
  - Voice stays the in-app Coach mic, which is already ported.
  - `siri-coach` is recorded as Android `partial`, with this reason.
- **The share sheet saves; it does not open the app.**
  - `ShareToCoachActivity` is translucent and `excludeFromRecents`. It shows
    a Material bottom sheet titled "Tell Coach", as in mockup frame 4:
    - the shared text, editable;
    - photo thumbnails;
    - the "Logging to …" line;
    - "Cancel" and "Send to Coach".
  - Photos are prepared with the existing `preparePhoto(resolver, uri, folder)`
    while the sheet is open, because the read grant ends with the activity.
  - Sending runs `TellCoach.run`, then a `Toast` with the outcome line, then
    `finish()`.
  - "Failed" keeps the sheet and the text open, with the line inline.
  - "Open Mivu to finish setup first." shows an "Open Mivu" button
    (`QuickAction.Today`).
  - iOS `savedLocked` and the locked inbox are not ported. The activity runs
    only when the phone is unlocked, and the diary is credential-encrypted
    storage.
- **Notifications follow iOS `follow`.**
  - `MivuApplication.followReply(turnID)` records the turn in memory,
    schedules the existing background drain, waits for the worker to be
    idle, reads the one turn, and posts its text when `MainActivity` is not
    started.
  - Android shows notifications in the foreground, unlike iOS, so the
    foreground check replaces the system's suppression.
  - `CoachJobService.onStopJob` posts `postSaved` for followed turns that
    have not finished.
  - The reply's tag is `coach-reply-<turnID>`, so a later reply replaces the
    saved note.
  - `shortcut:` followed turns are in memory, as on iOS. A process death
    before the reply posts nothing. Persist them only if a device check
    shows lost replies.
- **Notification permission.** On API 33 and above, `POST_NOTIFICATIONS` is
  requested from the share sheet after the first successful save, before it
  closes, as iOS asks after a Siri send. The activity finishes when the
  prompt returns.
  - The channel is "coach" ("Coach replies"), separate from "morning", so
    each can be muted on its own.
- **Streaming lives in this milestone, with the import UI.**
  - The parity row becomes `done` only when both land.
  - Shipping a picker that runs out of memory above about 60 MB of photos
    would be a regression.
  - **Import.** Decoding spools each photo's bytes to
    `cacheDir/archive-<uuid>/<n>` as it parses. The snapshot holds a 32-byte
    SHA-256 placeholder per photo.
    - `replacement` compares placeholders: `original` is read with
      `photoDigests = true`.
    - `writeRows` streams each photo from its spool file.
    - Peak memory is about one photo: at most 10,000,000 bytes, plus its
      base64 text.
  - **Export.** The same placeholder is used in reverse. `exportArchive`
    reads the snapshot with digests, and the encoder pulls each photo's
    bytes from the database one at a time.
- **The export file is prepared first, then saved, as on iOS.**
  - It is written to `cacheDir/exports/<uuid>/archive.json`. Over the
    350 MB cap, the encoder throws mid-write and no picker opens.
  - Then `CreateDocument("application/json")` with "Mivu-private-diary.json".
  - Then the file is copied into the chosen URI with `openOutputStream(uri, "wt")`.
  - The temp folder is deleted when the copy ends or fails, and on the next
    screen open.
  - Free space is checked before writing: the database size plus WAL, times
    five, plus 64 KiB (iOS `checkCapacity`).
- **Restore reads with `OpenDocument(["application/json", "application/octet-stream"])`.**
  Many providers label `.json` as `octet-stream`. A wrong file fails decoding
  with the iOS "Could not read" line.
- **Restoring another profile's archive follows iOS `importArchive`:**
  - The same profile as the selection is replaced, through `replacement`.
  - A profile that exists locally but is not selected is refused with "This
    archive belongs to another local profile. Select that profile before
    restoring."
  - An unknown profile becomes its own diary, through
    `DiaryRepository.importProfile`, and the app switches to it with
    `choose`.

**Deferred or cut:**
- **Folder backup** ("Choose private backup folder", "Retry backup"): the
  `folder-backup` row stays pending. Whether Drive supports the folder
  picker is unverified, and it needs a real phone.
- **Lock-screen widget families and Live Updates:** `live-activity` stays
  `n/a`.
- **Direct-share targets** (sharing shortcuts to a person): Coach is a single
  destination.
- **Meal-analysis notifications:** the `analyzed-notification` meal part
  stays with live analysis.
- **The Assistant and Gemini voice path:** see above.

## Global Constraints

- **Paths:** `A/` = `android/app/src/main/java/com/yakov103/mivu/`, `T/` =
  `android/app/src/test/java/com/yakov103/mivu/`, `I/` =
  `android/app/src/androidTest/java/com/yakov103/mivu/`, `R/` =
  `android/app/src/main/res/`.
- **Platform:**
  - minSdk 31, targetSdk 37;
  - platform and AndroidX APIs already in the catalog; no new dependency;
  - no new permission except what exists: `POST_NOTIFICATIONS` and
    `RECEIVE_BOOT_COMPLETED` are already declared.
- **Data:**
  - no schema change;
  - the archive stays `mivu-diary` v4, byte-compatible both ways, so the
    fixtures in `fixtures/archive/` must still pass;
  - `widgetSnapshot` lives in `DiaryRepository.preferences` ("mivu", excluded
    from backup);
  - spool and export folders live under `cacheDir` and are deleted in
    `finally`.
- **Restore safety (AGENTS.md "durable local capture"):**
  - restore goes only through `replacement`: same owner, never an older
    revision, `isVerifiedSuccessor` or equal, and never a record whose ID is
    in the original's deleted lists;
  - deletions are unioned;
  - the read and the write are one transaction;
  - a failure leaves the diary untouched;
  - "saved to a file" is never called a backup or a sync.
- **Ownership:** every export, restore and share capture captures `profileID`
  at request time. A result for a profile no longer selected is dropped, and
  its temp files are deleted.
- **Coach capture:**
  - the share capture's identity and context are fixed when it is saved;
  - an uncertain failure reconciles with the same `submissionID` and payload
    and never saves twice;
  - text is at most 20,000 characters and photos at most 8, as
    `CoachSubmissionPayload` checks.
- **Security:** never log tokens, message text or photo URIs. Shared URIs are
  read only while the sheet is open.
- **Synthetic data only:**
  - meals such as "two boiled eggs and a slice of toast", a 2,100 kcal goal,
    1,360 kcal eaten;
  - archives from `fixtures/archive/` or built in the test from
    `TodayFixture` and `DiaryFixture`;
  - photos are generated byte arrays;
  - no live ChatGPT call: Coach tests use `coachInferenceForTest`.
- **Accessibility:**
  - 48 dp minimum targets: the widget buttons, the sheet buttons and the
    Backup rows;
  - the widget figure reads iOS's spoken label ("1,360 of 2,100 calories
    eaten" or "1,360 calories eaten");
  - Pip is hidden from TalkBack;
  - the widget text uses `sp` with the figure at `dp`, capped like iOS
    `xLarge`;
  - the sheet and the screen stack at font scale 2.0;
  - the progress row and outcome lines are live regions.
- **Copy** (verbatim from iOS):
  - **widget:**
    - "Today", "of <n> kcal", "kcal recorded", "Set a target";
    - "Set up Mivu", "Pip will track your day here.";
    - "Snap It", "Coach";
    - the picker name "Calories" and the description "Today's calories,
      with Snap It and Coach one tap away.";
  - **shortcuts and tile:**
    - "Snap It" (long label "Photograph a meal and log it in Mivu.");
    - "Coach" (long label "Opens Mivu Coach, ready for a question.");
  - **share sheet:**
    - title "Tell Coach";
    - the outcome lines "Sent to the Coach.", "Saved. Open Mivu to connect
      the Coach.", "Open Mivu to finish setup first." and "I couldn't save
      that. Please try again.";
    - the photo-limit line from `CoachViewModel` ("… not added: a meal holds
      up to 8 photos.");
  - **notification:**
    - title "Coach";
    - the reply as plain text, cut at 180 characters ("…" at 179);
    - "The Coach needs a quick answer.";
    - "Your message is saved. Open Mivu for the Coach's reply.";
  - **Backup & export:**
    - group "Diary archive";
    - "Export diary and photos", "Export saved";
    - "Restore from diary archive", "Reading archive";
    - "Restore <name>?", "Restore diary", "Cancel";
    - the two dialog messages in `DiaryBackupSettings.swift`;
    - the errors:
      - "Could not prepare an export. Your local diary is preserved.";
      - "Export was not saved. Your local diary is preserved.";
      - "Could not read this diary archive. Your local diary is preserved.";
      - "This archive belongs to another local profile. Select that profile
        before restoring.".
- **Speed:**
  - each task runs only its own test classes, one class per
    `connectedDebugAndroidTest` run;
  - the full suite runs once, in Task 6;
  - reviews are batched after Task 2 and after Task 4, and the final review
    comes after Task 6.

  ```sh
  cd android
  ./gradlew :app:testDebugUnitTest --tests '*<Class>'
  ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.<pkg>.<Class>
  ```

## Review Focus

1. **Restoring an older copy, or one that brings back a deleted meal, over
   the live diary.** The restore is refused with "Could not read this diary
   archive…" (`StaleArchive`), and the diary is byte-for-byte unchanged.
   Restoring a verified successor replaces it, keeps the union of deletions,
   and Today shows the restored meals.
   (Task 6: `staleArchiveLeavesTheDiaryUntouched`,
   `deletedMealIsNotResurrected`, `successorReplacesTheDiary`)
2. **A 120 MB-of-photos archive restored over an existing diary on the
   emulator's 192 MB heap.** It imports without `OutOfMemoryError`, and the
   photo bytes match by hash. The spool folder is gone afterwards, including
   after a failure halfway.
   (Task 5: `importHundredTwentyMegabytesOverADiary` (`measureMemory`),
   `failedImportRemovesTheSpool`)
3. **Share to Mivu when the first save throws after committing**, or when the
   app process was cold. Exactly one turn exists, the outcome is "Sent to
   the Coach.", and a second tap of "Send to Coach" in the same sheet adds no
   turn. (Task 3: `uncertainFailureSavesOnce`, `coldStartShareSavesTheTurn`)
4. **The reply finishes while Mivu is open, or the share came from Mivu's own
   screen.** No notification is posted, and the Coach tab shows the reply.
   When it finishes in the background, exactly one notification is posted,
   and tapping it opens Coach.
   (Task 4: `noNotificationWhileMivuIsOnScreen`,
   `backgroundReplyPostsOnceAndOpensCoach`)
5. **The phone passes the 04:00 cutoff with the app closed.** The widget
   reads 0 with the same target. When the app next starts, the new day's
   snapshot replaces it. A diary in another time zone rolls at its own 04:00.
   (Task 2: `rolloverEntryShowsZeroAfterCutoff`,
   `nextRolloverUsesTheDaysZone`)

---

### Task 1: Quick capture routing, launcher shortcuts and the Snap It tile

**Files:**
- Create:
  - `A/quick/QuickCapture.kt` (`QuickAction`, `quickIntent`);
  - `A/quick/SnapItTileService.kt`;
  - `R/xml/shortcuts.xml`.
- Modify:
  - `AndroidManifest.xml` (`MainActivity` `launchMode="singleTop"` and the
    `android.app.shortcuts` meta-data; the tile `service` with
    `BIND_QUICK_SETTINGS_TILE`, label "Snap It", icon `ic_photo_camera`);
  - `A/MivuApplication.kt` (`quickRequest`);
  - `A/MainActivity.kt` (`onCreate` and `onNewIntent`);
  - `A/ui/MivuApp.kt` (`Shell` consumes the request).
- Test: `I/quick/QuickCaptureTest.kt`.

**Interfaces:**
- Consumes:
  - `Route.CoachCamera(retaking: String? = null)`;
  - the shell's `selectTab` and `focusCoach`;
  - `Bootstrap.Ready`.
- Produces:
  - `enum class QuickAction(val action: String) { SnapIt("com.yakov103.mivu.action.SNAP_IT"), OpenCoach("com.yakov103.mivu.action.OPEN_COACH"), Today("com.yakov103.mivu.action.TODAY"); companion object { fun from(intent: Intent?): QuickAction? } }`;
  - `fun quickIntent(context: Context, action: QuickAction): Intent`, an
    explicit `MainActivity` intent with
    `FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_CLEAR_TOP or FLAG_ACTIVITY_SINGLE_TOP`;
  - `val MivuApplication.quickRequest: MutableStateFlow<QuickAction?>`, which
    the shell sets back to null after navigating;
  - `fun MivuApplication.receive(intent: Intent?)`, which maps
    `QuickAction.from(intent)`, plus the notification extra
    `CoachReplyNotification.TURN` (Task 4) to `OpenCoach`.

- [ ] **Step 1: Failing tests** in `QuickCaptureTest`, with camera permission
  granted through `UiAutomation.grantRuntimePermission` as the existing camera
  tests do:
  - `snapItOpensTheCoachCamera`: launch `quickIntent(SnapIt)`; the camera
    screen's tag is displayed.
  - `coachFocusesTheComposer`: the Coach tab is selected, and the composer
    field is focused.
  - `snapItWhileOpenReusesTheActivity`: a second intent goes through
    `onNewIntent`, so there is still one activity and the back stack holds
    Coach.
  - `requestWaitsForTheDiary`: the intent arrives before `Bootstrap.Ready`;
    the camera opens once the diary is ready.
  - `manifestShortcutsAreSnapItAndCoach`: through
    `ShortcutManager.getManifestShortcuts()`, the IDs are `snap_it` and
    `coach`, with short labels "Snap It" and "Coach" and intents with the two
    actions.
  - `snapItTileIsDeclared`: `queryIntentServices(TileService.ACTION_QS_TILE)`
    finds `SnapItTileService` labelled "Snap It".
- [ ] **Step 2: Run** them. Expected: FAIL (unresolved `QuickAction`; no
  shortcuts).
- [ ] **Step 3: Implement.**
  - `SnapItTileService.onClick` calls
    `startActivityAndCollapse(PendingIntent.getActivity(…, quickIntent(SnapIt), FLAG_IMMUTABLE))`
    on API 34 and above, and the `Intent` overload below it.
  - `onStartListening` sets `Tile.STATE_INACTIVE` and the subtitle "Mivu".
  - Shortcut icons are the existing `ic_photo_camera` and `ic_coach` vectors.
- [ ] **Step 4: Run** `QuickCaptureTest`, then `AppShellTest`. Expected:
  PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main android/app/src/androidTest/java/com/yakov103/mivu/quick
git commit -m "feat(android): open Snap It and Coach from launcher shortcuts and a tile"
```

### Task 2: Calories widget

**Files:**
- Create:
  - `A/widget/WidgetSnapshot.kt` (the model, `nextRollover`,
    `afterRollover`, `ringFraction`, `DiaryDatabase.widgetSnapshot`);
  - `A/widget/CaloriesWidget.kt` (the provider, `views`, `publish`);
  - `R/layout/widget_calories_small.xml` and `widget_calories_medium.xml`;
  - `R/xml/widget_calories.xml`;
  - `R/drawable-nodpi/pip_wave.png`, copied unchanged from
    `ios/MivuWidgets/Assets.xcassets/PipWave.imageset/pip.png`;
  - `R/values/widget_colors.xml` and `R/values-night/widget_colors.xml`.
- Modify:
  - `AndroidManifest.xml` (the provider `receiver`, with
    `APPWIDGET_UPDATE` and the meta-data);
  - `A/MivuApplication.kt` (publish on changes, after `rollOverDay`, and
    after a cutoff change);
  - `A/ui/settings/DaySettings.kt` (the cutoff change republishes).
- Test:
  - `T/widget/WidgetSnapshotTest.kt`;
  - `I/widget/CaloriesWidgetTest.kt`.

**Interfaces:**
- Consumes:
  - `QuickAction` and `quickIntent` (Task 1);
  - `repository.changes`;
  - `dayDetail(dayID)`;
  - `goalOn(date, goals)`;
  - `dayNutritionTotals`;
  - `DayCutoff.hour`.
- Produces:
  - `@Serializable data class WidgetSnapshot(val day: String, val eaten: Double, val target: Double?, val hasDiary: Boolean, val rolloverAt: Long, val writtenAt: Long)`,
    with epoch milliseconds, plus:
    - `companion fun nextRollover(afterMillis: Long, timeZoneID: String, cutoffHour: Int): Long`;
    - `fun afterRollover(): WidgetSnapshot`;
    - `val ringFraction: Double` (0 without a positive target, capped at 1).
  - `fun DiaryDatabase.widgetSnapshot(now: Instant, cutoffHour: Int = DayCutoff.hour): WidgetSnapshot`.
    It is one bounded read: the head, the active day's meals and the kcal
    goal for that day, as `TodayViewModel.load` reads them. `rolloverAt` is
    the next cutoff after the active day's `startAt`, in the day's zone (iOS
    rule).
  - `object CaloriesWidget`, with:
    - `fun views(context: Context, snapshot: WidgetSnapshot?, nowMillis: Long): RemoteViews`,
      the `SizeF` map for small (110×110 dp) and medium (250×110 dp);
    - `fun publish(context: Context, snapshot: WidgetSnapshot)`, which
      stores it, updates every widget ID, and books the rollover alarm.
  - `class CaloriesWidgetProvider : AppWidgetProvider`.
- **Layout** (mockup frame 1; iOS sizes):
  - small: the figure at 32 dp bold, "of N kcal", and a 64 dp bar;
  - medium: the "Today" eyebrow, the figure at 38 dp, and a 200 dp bar;
  - medium buttons: filled "Snap It" and tonal "Coach", each 48 dp high;
  - Pip at 76 dp (small) and 120 dp (medium), bottom-end, with 10 dp of
    padding;
  - corner radius `@android:dimen/system_app_widget_background_radius`;
  - taps:
    - the whole widget opens `quickIntent(Today)`;
    - the buttons open `quickIntent(SnapIt)` and `quickIntent(OpenCoach)`;
    - each tap uses its own request code and `FLAG_IMMUTABLE`.

- [ ] **Step 1: Failing tests.**
  - `WidgetSnapshotTest`:
    - `nextRolloverUsesTheDaysZone`: a day started 2026-10-24T22:00 in
      `America/New_York`, cutoff 4 → 2026-10-25T04:00-04:00, whatever the
      JVM zone;
    - `nextRolloverCrossesDst`;
    - `afterRolloverZeroesEatenAndKeepsTarget`;
    - `ringFractionCapsAtOne` (2300 of 2000 → 1.0);
    - `noTargetHasNoFraction`.
  - `CaloriesWidgetTest`, applying each `RemoteViews` into a sized
    `FrameLayout`:
    - `smallShowsIntakeAndGoal`: "1,360" and "of 2,100 kcal"; the figure's
      description is "1,360 of 2,100 calories eaten"; Pip is not important
      for accessibility;
    - `mediumHasSnapItAndCoach`: both buttons are at least 48 dp high, with
      labels "Snap It" and "Coach";
    - `noDiaryShowsSetUp` ("Set up Mivu", "Pip will track your day here.");
    - `noTargetShowsSetATarget` ("kcal recorded", "Set a target");
    - `rolloverEntryShowsZeroAfterCutoff`: with `nowMillis` past
      `rolloverAt`, the widget shows "0";
    - `snapshotFromDatabaseUsesTodaysGoal`: the synthetic Today fixture
      gives 1,360 and 2,100;
    - `snapshotFollowsADiaryWrite`: capturing a meal updates the stored
      `widgetSnapshot` within 2 s.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `MivuApplication.onCreate` collects `repository.changes` with
    `conflate()` on IO. It reads the snapshot for the `Ready` profile and
    calls `publish`; a read error keeps the last snapshot.
  - The alarm is
    `setWindow(RTC, rolloverAt, 10 min, PendingIntent.getBroadcast(… ACTION_APPWIDGET_UPDATE with all IDs …))`.
  - `widget_calories.xml`:
    - `targetCellWidth`/`targetCellHeight` 2/2;
    - `resizeMode` horizontal|vertical;
    - `maxResizeWidth` 4 cells;
    - `previewLayout` small;
    - `description` the iOS line;
    - `widgetCategory` home_screen.
- [ ] **Step 4: Run** both classes, then `DiaryDaysTest` and
  `MorningCheckInTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main android/app/src/test/java/com/yakov103/mivu/widget android/app/src/androidTest/java/com/yakov103/mivu/widget
git commit -m "feat(android): add the calories widget with Pip"
```

**Batch review 1** (Tasks 1–2) runs here.

### Task 3: Share to Mivu saves a Coach turn

**Files:**
- Create:
  - `A/coach/TellCoach.kt` (`TellCoachOutcome`, `TellCoach.run`);
  - `A/share/ShareToCoachActivity.kt` (the sheet and the intent parsing).
- Modify:
  - `AndroidManifest.xml` (the activity, exported, `Theme.Mivu.Translucent`,
    `excludeFromRecents`, `taskAffinity=""`, and the `SEND` and
    `SEND_MULTIPLE` filters for `text/plain` and `image/*`);
  - `R/values/themes.xml` (`Theme.Mivu.Translucent`);
  - `A/MivuApplication.kt` (`followReply` stub, filled in by Task 4).
- Test:
  - `I/coach/TellCoachTest.kt`;
  - `I/share/ShareToCoachTest.kt`.

**Interfaces:**
- Consumes:
  - `captureCoachSubmission(payload, expectedRevision)`;
  - `reconcileCoachCapture(payload)`;
  - `CoachSubmissionPayload`;
  - `CoachCaptureContext`, built from the head as `CoachViewModel` builds it
    (now truncated to seconds);
  - `preparePhoto(resolver, uri, folder)`;
  - `MivuApplication.readyProfile()`, `restored`, `chatGPT.state` and
    `scheduleBackgroundDrain()`;
  - `quickIntent(Today)`.
- Produces:
  - `enum class TellCoachOutcome(val line: String) { Sent("Sent to the Coach."), SavedNeedsConnection("Saved. Open Mivu to connect the Coach."), NeedsSetup("Open Mivu to finish setup first."), Failed("I couldn't save that. Please try again.") }`;
  - `object TellCoach { suspend fun run(app: MivuApplication, text: String, photos: List<File>, submissionID: UUID, now: Instant = Instant.now()): TellCoachOutcome }`.
    - Blank text without photos → `Failed`.
    - No `Ready` diary → `NeedsSetup`.
    - Save, with one rebuild of the context on `StaleRevision`. Any other
      failure reconciles: `Accepted` counts as saved.
    - Then `app.followReply(submissionID)`.
    - After `restored.join()`, `Sent` if `canInfer`, else
      `SavedNeedsConnection`.
    - The photos' IDs are their file names, created at `now`, as
      `CoachAttempt.payload` does.
  - `data class SharedContent(val text: String, val photos: List<Uri>)` and
    `fun SharedContent.Companion.from(intent: Intent): SharedContent?`:
    - `EXTRA_TEXT` (plus `EXTRA_SUBJECT` on its own line when present);
    - `EXTRA_STREAM`, a single `Uri` or a list;
    - photos beyond 8 are dropped with the iOS line;
    - text is cut to 20,000 characters.
- **Sheet** (mockup frame 4):
  - the `ModalBottomSheet` opens on create;
  - the photos are prepared into `cacheDir/share/<submissionID>/` on IO,
    with a spinner per thumbnail;
  - "Send to Coach" is disabled while photos prepare or a send runs;
  - the submission ID is kept in `savedInstanceState`, so rotation never
    makes a second message;
  - dismissing or cancelling deletes the folder;
  - after `Sent` or `SavedNeedsConnection`, the folder is deleted, the
    `Toast` shows, and the activity finishes (Task 4 adds the permission
    prompt in between).

- [ ] **Step 1: Failing tests.**
  - `TellCoachTest`, on a synthetic diary:
    - `savesOneCapturedTurnWithTheText`;
    - `uncertainFailureSavesOnce`: a `TellCoach.afterCaptureForTest` hook (`@VisibleForTesting`, like `CoachViewModel`'s) throws after commit;
      the outcome is `Sent`, and there is one turn;
    - `staleContextIsRebuiltOnce`: the day rolls over between read and
      write;
    - `blankMessageFails`;
    - `noDiaryNeedsSetup`;
    - `disconnectedSavesAndSaysConnect`;
    - `photosAreSavedWithTheTurn` (2 generated JPEGs).
  - `ShareToCoachTest`:
    - `textShareShowsTheSheetWithTheText`;
    - `sendSavesAndFinishes`: the activity finishes, and the turn exists;
    - `nineImagesKeepEightAndSaySo`;
    - `rotationKeepsTheSameSubmission`: send after recreation gives one turn;
    - `cancelSavesNothingAndDeletesPhotos`;
    - `coldStartShareSavesTheTurn`: the process is started by the share
      intent alone;
    - `buttonsAre48dpAtFontScale2`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both classes, then `CoachScreenTest` and
  `DiaryCaptureTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main android/app/src/androidTest/java/com/yakov103/mivu/coach/TellCoachTest.kt android/app/src/androidTest/java/com/yakov103/mivu/share
git commit -m "feat(android): send shared text and photos to Coach"
```

### Task 4: Coach reply notifications for shared messages

**Files:**
- Create: `A/coach/CoachReplyNotification.kt`.
- Modify:
  - `A/MivuApplication.kt` (`screenVisible`, `followReply`, the followed
    set);
  - `A/MainActivity.kt` (`onStart`/`onStop` set `screenVisible`);
  - `A/coach/CoachJobService.kt` (`onStopJob` posts saved notes);
  - `A/share/ShareToCoachActivity.kt` (the permission prompt after the
    first save).
- Test:
  - `T/coach/CoachReplyNotificationTest.kt`;
  - `I/coach/CoachReplyFollowTest.kt`.

**Interfaces:**
- Consumes:
  - `TellCoach.run` (Task 3);
  - `quickIntent(OpenCoach)` and `MivuApplication.receive` (Task 1);
  - `drainCoach(retryWaiting)`;
  - `DiaryDatabase.coachTurn(id)`;
  - `coachReplyText(markdown).text` for plain text.
- Produces:
  - `object CoachReplyNotification`, with:
    - `const val TURN = "coachTurnID"`;
    - `fun text(turn: CoachTurn): Pair<String, String>?`, which ports iOS
      `text(for:)`:
      - null while `captured` or `analyzing`, and null when
        `pendingMealID != null`;
      - `completed`: the plain reply, cut at 180 characters;
      - `needsClarification`: "The Coach needs a quick answer.";
      - `needsRetry`, `waitingForNetwork`, `waitingForConnection`: the
        saved line;
    - `fun post(context: Context, turn: CoachTurn)`;
    - `fun postSaved(context: Context, turnID: UUID)`;
    - the tag is `"coach-reply-$turnID"` with id 0; the channel is "coach"
      ("Coach replies", default importance); the content intent is
      `quickIntent(OpenCoach)` plus `TURN`; it auto-cancels; it does nothing
      without permission on API 33 and above.
  - `@Volatile var MivuApplication.screenVisible: Boolean`.
  - `fun MivuApplication.followReply(turnID: UUID)`. It adds the turn to the
    followed set, calls `scheduleBackgroundDrain()`, then runs
    `drainCoach().join()`. It reads the turn and calls `post` only when
    `!screenVisible`, then removes the turn from the set.
  - `fun MivuApplication.expireFollowed()`. It posts `postSaved` for each
    followed turn whose state is still pending, then clears the set.
    `CoachJobService.onStopJob` calls it.

- [ ] **Step 1: Failing tests.**
  - `CoachReplyNotificationTest` (JVM):
    - `capturedAndAnalyzingPostNothing`;
    - `mealTurnsLeaveItToTheMealNotification`;
    - `completedReplyIsPlainAndCutAt180` (179 characters plus "…");
    - `emptyReplyPostsNothing`;
    - `clarificationAsksForAnswer`;
    - `waitingStatesSaySaved`.
  - `CoachReplyFollowTest`, with scripted `coachInferenceForTest` and
    `POST_NOTIFICATIONS` granted:
    - `backgroundReplyPostsOnceAndOpensCoach`: share, then the activity
      stops; one notification with tag `coach-reply-<id>` and the reply
      text; sending its content intent selects the Coach tab;
    - `noNotificationWhileMivuIsOnScreen`;
    - `stoppedJobPostsTheSavedNote`, then the reply replaces it;
    - `deniedPermissionPostsNothingAndSaves`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** The share sheet requests `POST_NOTIFICATIONS`
  through `RequestPermission` only when it was never asked. A stored
  preference `coachNotificationsAsked` means a denial is not asked again. The
  activity finishes in the callback.
- [ ] **Step 4: Run** both classes, then `ShareToCoachTest`,
  `CoachJobServiceTest` and `MorningReminderTest`. Expected:
  PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main android/app/src/test/java/com/yakov103/mivu/coach/CoachReplyNotificationTest.kt android/app/src/androidTest/java/com/yakov103/mivu/coach/CoachReplyFollowTest.kt
git commit -m "feat(android): notify Coach replies to shared messages"
```

**Batch review 2** (Tasks 3–4) runs here.

### Task 5: Stream archive photo bytes

**Files:**
- Modify:
  - `A/diary/DiaryArchive.kt` (the spooling decode and the pulling encode);
  - `A/diary/SwiftJson.kt` (the spool and source `SwiftData` variants);
  - `A/diary/DiaryRestore.kt` (`importArchive` and `exportArchive`);
  - `A/diary/DiaryDatabase.kt` (the `readSnapshot(photoDigests)` and
    `writeRows` photo source);
  - `A/diary/DiaryValidation.kt` (the photo size check and the manifest
    fingerprints through the spool).
- Test:
  - `T/diary/DiaryRestoreTest.kt`;
  - `I/diary/ArchiveRoundTripTest.kt`.

**Interfaces:**
- Consumes:
  - `replacement(incoming, original)`, unchanged;
  - `validateArchiveManifests`;
  - `fingerprint(bytes)`.
- Produces:
  - `class PhotoSpool(val dir: File) : Closeable`, with:
    - `fun put(bytes: ByteArray): ByteArray`, which writes the file and
      returns a 32-byte SHA-256 placeholder;
    - `fun bytes(placeholder: ByteArray): ByteArray`;
    - `fun fingerprint(placeholder: ByteArray): String`;
    - `close()`, which deletes `dir`.
  - `fun DiaryArchive.decode(input: InputStream, spool: PhotoSpool, expectedProfileID: UUID? = null): DiarySnapshot`.
    It is identical to `decode` except that photo `data` holds placeholders.
    The 1..10,000,000-byte check runs on the real length while spooling.
  - `fun DiaryDatabase.importArchive(input: InputStream, cacheDir: File)`.
    It spools into `cacheDir/archive-<uuid>`, then runs `replace`: the
    original is read with `photoDigests = true`; `replacement` is unchanged;
    `writeRows` takes photo bytes from `spool.bytes`. The spool closes in
    `finally`.
  - `fun DiaryDatabase.exportArchive(out: OutputStream)`. Its signature is
    unchanged. It reads the snapshot with digests, and the encoder resolves
    each placeholder from the database one photo at a time.
  - The old in-memory overloads stay only for tests and the fixtures.

- [ ] **Step 1: Failing tests.**
  - `DiaryRestoreTest`:
    - `spooledReplacementEqualsInMemoryReplacement`: the same archive both
      ways writes an identical snapshot;
    - `spoolRejectsOversizedPhoto` (10,000,001 bytes → `InvalidData`);
    - `manifestFingerprintsUseRealBytes`.
  - `ArchiveRoundTripTest`:
    - `iosFixtureStillImports` and `androidExportStillMatchesFixture`, which
      are the existing fixture tests, run against the streamed paths;
    - `importHundredTwentyMegabytesOverADiary` (`measureMemory=true`, 12 ×
      10 MB generated photos, restored over a diary with 30 MB): no OOM, the
      hashes match, and the peak heap is recorded;
    - `exportHundredTwentyMegabytes` (the same, for export);
    - `failedImportRemovesTheSpool`: the stream is truncated halfway; the
      diary is unchanged and no `archive-*` folder is left.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** In `Envelope` decoding, the photo `data` field
  uses a serializer bound to the current spool, passed through a
  `SerializersModule` contextual entry on a decode-local `Json`. This keeps
  `MealPhoto` and its schema unchanged.
- [ ] **Step 4: Run** both classes, then `DiaryDatabaseTest` and
  `CoachWritesTest`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/yakov103/mivu/diary android/app/src/test/java/com/yakov103/mivu/diary/DiaryRestoreTest.kt android/app/src/androidTest/java/com/yakov103/mivu/diary/ArchiveRoundTripTest.kt
git commit -m "perf(android): stream archive photo bytes through a spool"
```

### Task 6: Backup & export archive UI, full suite, evidence and parity

**Files:**
- Modify:
  - `A/ui/settings/BackupExportScreen.kt` (the "Diary archive" group above
    "Share a report");
  - `A/diary/DiaryRepository.kt` (`importProfile`);
  - `A/ui/MivuApp.kt` (switch to an imported profile);
  - `docs/parity.md`;
  - `docs/superpowers/plans/android-carried-items.md`.
- Create:
  - `docs/verification/2026-10-25-android-widgets-share-backup.md`;
  - `docs/verification/android-widgets/*.png`.
- Test: `I/ui/settings/BackupExportScreenTest.kt`.

**Interfaces:**
- Consumes:
  - `exportArchive(out)` and `importArchive(input, cacheDir)` (Task 5);
  - `DiaryArchive.decode(input, spool)`;
  - `repository.choose(id)`.
- Produces:
  - `fun DiaryRepository.importProfile(input: InputStream, cacheDir: File): UUID`.
    It creates `profiles/<ID>/` from the archive's profile, restores into
    the empty diary, and deletes the folder on any failure.
  - `fun archiveFileName(): String = "Mivu-private-diary.json"`.
- **Screen** (mockup frame 5; iOS `DiaryBackupSettings` order):
  - **Export.** "Export diary and photos":
    - the archive is prepared on IO, with the capacity check, and the row
      shows "Preparing…" with a progress indicator;
    - then `CreateDocument`;
    - then the copy;
    - "Export saved" (check icon), or one of the iOS error lines;
    - a profile change during preparation drops the file.
  - **Restore.** "Restore from diary archive":
    - `OpenDocument` runs, then decoding into a spool on IO, with "Reading
      archive";
    - the owner check (iOS `importArchive` rules);
    - then an `AlertDialog`: title "Restore <name>?", the iOS message for
      replace or separate, a destructive "Restore diary" and "Cancel";
    - then the restore;
    - Today and Diary reload through `repository.changes`;
    - the spool is deleted on cancel.
  - A footnote states that archives move between iPhone and Android, and
    never claims a backup or sync.

- [ ] **Step 1: Failing tests** in `BackupExportScreenTest`, with
  Espresso-Intents stubbing the `CreateDocument` and `OpenDocument` results
  using files in the test's cache:
  - `exportWritesAnArchiveThatDecodes`: the chosen file decodes to the
    synthetic snapshot; "Export saved" is shown; no `exports/` folder is left;
  - `cancelledExportSavesNothing`;
  - `restoreAsksThenReplaces` (the iOS message with "(N meals)");
  - `successorReplacesTheDiary`;
  - `staleArchiveLeavesTheDiaryUntouched`;
  - `deletedMealIsNotResurrected`;
  - `otherLocalProfileIsRefused`;
  - `newProfileImportsAndSwitches`;
  - `garbageFileSaysCouldNotRead`;
  - `rowsAre48dpAtFontScale2`.
- [ ] **Step 2: Run** it. Expected: FAIL. Then **implement** and run it
  again. Expected: PASS.
- [ ] **Step 3: Run the full suite once** at a clean commit:
  `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleRelease --rerun-tasks`,
  then `python3 scripts/ci/parity.py` and the `scripts/ci` unit tests.
  - Record the SHA, the emulator, and the counts from the JUnit XML.
  - Never count a skipped or zero-test class.
  - Record a failing class honestly, with its cause.
- [ ] **Step 4: Screenshots.**
  - Take them in light, dark and font scale 2.0, and compare them with the
    mockup.
  - The list:
    - `widget-small` and `widget-medium`, on the emulator home screen;
    - `widget-no-target`;
    - `launcher-shortcuts`;
    - `qs-tile`;
    - `share-chooser` and `share-sheet`;
    - `reply-notification`;
    - `backup-export` and `restore-dialog`.
  - Real-phone delivery of notifications and widget updates is recorded as
    `blocked`. Per the spec, emulator results do not prove notifications.
- [ ] **Step 5: Parity.** Mark a row Android `done` only where every named
  test passed:
  - `widgets`;
  - `quick-capture`;
  - `archive`, but only if the 120 MB tests passed.
  - Other rows:
    - `siri-coach`: Android `partial`. Share saves to Coach from outside
      the app; voice through Assistant or Gemini is skipped, with the reason
      above.
    - `analyzed-notification`: the note says Coach replies are done for
      shared messages; meal analysis remains.
    - `settings`: the note adds the archive.
    - `folder-backup`: unchanged.
- [ ] **Step 6: Carried items.**
  - Remove these, each with its outcome:
    - "Milestone 8 (outside-app capture)";
    - the Settings "Backup & export" item;
    - the Play-readiness "Stream photo decoding…" item.
  - Add these:
    - "Widget and reply notification on a physical phone";
    - "Release-minify smoke: widget and share activity survive R8"
      (cross-reference the existing release smoke item).
- [ ] **Step 7: Commit**

```bash
git add android/app/src/main android/app/src/androidTest/java/com/yakov103/mivu/ui/settings/BackupExportScreenTest.kt docs/verification/2026-10-25-android-widgets-share-backup.md docs/verification/android-widgets docs/parity.md docs/superpowers/plans/android-carried-items.md
git commit -m "feat(android): export and restore diary archives and record milestone 8"
```

**Final review** of the whole milestone runs here.
