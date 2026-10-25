# Android carried items

These items came out of reviews and must be picked up by the milestone named
on each one. Each milestone's plan reads this file and removes items once they
are done.

## Connection (from milestone 5)
Milestone 5 closed in [its record](../../verification/2026-10-24-android-connection.md): the model picker, the
"Connect ChatGPT for replies" link and the emulator live Coach turn are done; the DNS note is in AGENTS.md; the three
`MealAnalysisWorker` items closed as not applicable (live analysis is the Coach, the worker is sample-only).
- Physical phone: sign-in, the Custom Tab return and a live Coach turn (text and a drawn-plate photo), leaving the app
  mid-turn, and Disconnect saving a new message as `waitingForConnection`.
- Responses-host network errors still map to "unavailable"; map them to the offline notice as sign-in errors are.

## Milestone 7 (Pip moments)
Milestone 7 closed in [its record](../../verification/2026-10-25-android-pip-moments.md): Today plays saved, first
meal today, welcome back and reviewed, and re-greets after the background. Day complete is not wired, since iOS has
no trigger (moved to Later).

## Milestone 8 (outside-app capture)
Milestone 8 closed in [its record](../../verification/2026-10-25-android-widgets-share-backup.md): Coach reply
notifications are posted for messages shared into Mivu (the Android counterpart of Siri-started turns); widgets, quick
capture, share and the archive export/restore are in.
- Widget and reply notification on a physical phone: delivery, the tap into Coach and the widget's update after a
  capture and after the 04:00 cutoff (emulator results do not prove notifications).

## Settings and day rollover
Milestone 6 closed in [its record](../../verification/2026-10-24-android-progress.md): the per-device day cutoff, the
morning check-in, the weight row and the goal editor are done.
- Morning reminder: deliver and tap on a physical phone.
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
- Run a release-minify smoke test that decodes an archive fixture.
- Release-minify smoke: the widget and the share activity survive R8 (with the archive smoke above).
- Launcher icon: the manifest has no `android:icon`. Add Pip's adaptive launcher icon, and a monochrome Pip small icon
  for the Coach reply and morning notifications.
- Archive export peak is about 100 MB of Java heap at 120 MB of photos (kotlinx encodes each photo as one base64
  string). Write base64 in chunks, as iOS does, if low-memory phones matter.
- Re-check `MaterialExpressiveTheme`. It did not compile with material3 1.4.0.
- Check Pip's frame rate on an idle host or a real phone. On the loaded emulator the GPU took about 4950 ms per frame,
  so smooth playback could not be judged there; this is not a regression.
- `CoachHistoryScreenTest.mealAskPipSeeksSourceTurn` fails (it already failed at `9987338b`; cause not established), and
  `TodayScreenTest.logWithPipSelectsCoach` asserts the selected tab without waiting (flaked once). `MorningCheckInSeed`
  still runs in the full suite despite `notClass`. See the [milestone 7 record](../../verification/2026-10-25-android-pip-moments.md).
- Coach meal chip: the question's meal chip has an empty leading area where the mockup has an icon.
- Coach camera at font scale 2.0: "Choose photos" runs under the shutter.

## Later
- Pip `characterChanged` and character selection.
- Day complete: iOS has no trigger yet.
- `record_source`: only fixes two invisible shortcuts, leftover photo copies after `delete_workout` and the
  `find_meals` origin fallback (meal seek uses the same fallback). The `shortcut:` comments stay until then.
