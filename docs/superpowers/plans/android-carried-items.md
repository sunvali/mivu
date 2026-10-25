# Android carried items

These items came out of reviews and must be picked up by the milestone named
on each one. Each milestone's plan reads this file and removes items once they
are done.

## Connection (from milestone 5)
Milestone 5 closed in [its record](../../verification/2026-10-24-android-connection.md): the model picker, the
"Connect ChatGPT for replies" link and the emulator live Coach turn are done; the DNS note is in AGENTS.md; the three
`MealAnalysisWorker` items closed as not applicable (live analysis is the Coach, the worker is sample-only).
- Responses-host network errors still map to "unavailable"; map them to the offline notice as sign-in errors are.

## Milestone 7 (Pip moments)
Milestone 7 closed in [its record](../../verification/2026-10-25-android-pip-moments.md): Today plays saved, first
meal today, welcome back and reviewed, and re-greets after the background. Day complete is not wired, since iOS has
no trigger (moved to Later).

## Milestone 8 (outside-app capture)
Milestone 8 closed in [its record](../../verification/2026-10-25-android-widgets-share-backup.md): Coach reply
notifications are posted for messages shared into Mivu (the Android counterpart of Siri-started turns); widgets, quick
capture, share and the archive export/restore are in.

## Settings and day rollover
Milestone 6 closed in [its record](../../verification/2026-10-24-android-progress.md): the per-device day cutoff, the
morning check-in, the weight row and the goal editor are done.
- Disconnect ChatGPT when the last profile is deleted.
- The remaining Settings rows: profiles (forget `companion.lastActive` on profile delete), diary preferences and
  nutrition source. The nutrition-source item adds the
  USDA consent sentence back to the OpenAI consent dialog. Add the receipt links for `profiles`, `nutritionSource` and
  `backup` when those screens exist.
- Day tests depend on the clock: `MealComposerScreenTest`, `CoachScreenTest.dayChoiceLogsToChosenDay`,
  `DiaryScreenTest.futurePillDisabled` and `EditorsTest` fail between 00:00 and the cutoff or on a Sunday. Make them
  clock-independent, then rerun them.
- Goals opened from Settings after midnight start on the calendar date, not the waking day, with empty targets while a
  goal exists. Check against iOS.
- Settings at font scale 2.0: the "Coach AI" title wraps letter by letter beside "Connect ChatGPT".

## Play readiness
Milestone 9 closed in [its record](../../verification/2026-10-25-android-play-readiness.md), with these outcomes:
- Release-minify smoke (archive fixtures, widget, share activity, MainActivity): done, `ReleaseSmokeTest` on the
  minified release build.
- Launcher and notification icon: done, Pip's adaptive icon with a themed layer and `ic_stat_pip` (`AppIconTest`).
- `MaterialExpressiveTheme`: moved to Later.
- Archive export memory: moved to Later.
- Coach meal chip and Coach camera at font scale 2.0: done (`CoachScreenTest`, `CoachCameraTest`).
- Flaky tests: `mealAskPipSeeksSourceTurn`, `alarmPostsTheMorningNotification` and `recreateMidCaptureKeepsDraft` fixed;
  `logWithPipSelectsCoach` and the `MorningCheckInSeed` exclusion were already fixed. What remains:
  `MealEditorsTest.scaleToTargetUpdatesFoods` (not reproduced, no cause found).
- The restore flow takes 4–8 s on the emulator although the archive decode is about 12 ms on release; add a trace
  around the picker, `openInputStream` and the restore transaction before changing it.
- Small widget at font scale 2.0: Pip sits under the end of "Set a target" and "kcal recorded" (text stays on top and
  readable); see `widget-no-target-font2.png` in the record.
- Two permission-denied tests (`ShareToCoachTest.deniedPermissionPostsNothingAndSaves`,
  `MorningCheckInTest.deniedNotificationPermissionExplainsTheOffSwitch`) stop on an assumption whenever the install
  already holds the notification grant, which the full suite always does; give them a run that revokes it first.
- The Play submission draft is [play-submission.md](../../development/play-submission.md); everything in the Console is
  the owner's.

## Physical phone (owner)
Every check that needs a real phone is listed, with its steps, in the "Physical phone" section of the
[milestone 9 record](../../verification/2026-10-25-android-play-readiness.md): Phase 0 items 2–5 (sign-in, inference,
photo analysis, token refresh and Disconnect), Pip's smoothness, TalkBack, live voice, the keyboard on non-Coach screens
and the composer gap, the widget and the notifications (reply and morning reminder), the API 31–32 clipboard toast,
and the restore time from Drive or Downloads.

## Later
- `MaterialExpressiveTheme` and the Expressive `LoadingIndicator`: material3 1.4.0 keeps them internal. Take them with
  the first stable BOM that ships them; the `shortcut:` comment in `CoachTimeline.kt` stays until then.
- Archive export peak is about 100 MB of Java heap at 120 MB of photos. Write base64 in chunks, as iOS does, if a
  physical phone fails the 120 MB export.
- Pip `characterChanged` and character selection.
- Day complete: iOS has no trigger yet.
- `record_source`: only fixes two invisible shortcuts, leftover photo copies after `delete_workout` and the
  `find_meals` origin fallback (meal seek uses the same fallback). The `shortcut:` comments stay until then.
