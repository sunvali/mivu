# Android carried items

These items came out of reviews and must be picked up by the milestone named
on each one. Each milestone's plan reads this file and removes items once they
are done.

## Milestone 4 (Coach)
- Port iOS `capturedOnly` retry in `CoachWorker`: an oldest turn stuck on a retryable error must not hold back newer messages.
- The debug "Run Coach turn" button writes into the selected diary and can report a false failure while a worker pass runs; use a scratch profile.
- Add camera capture, ported from iOS `PhotoCapture` (camera plus the
  permission flow).
- Wire the Ask Pip entry points (Today, Diary, meal, food) to Coach drafts.
- Compare the Coach reply summary lines with iOS for undo, scale, move, photos, weight, workout, goals and day
  coverage. Only the food "Saved" line is tested.
- Add a model picker; the engine uses the first entry of the model catalog.
- Add `record_source`, then make `delete_workout` strip photo copies from turns whose only progress was that
  workout, and make `find_meals` use the real origin instead of the earliest turn naming the meal.
- Run the live Coach turn against ChatGPT once the owner has signed in on the emulator (Phase 0 evidence).
- Port legacy-capture recovery and the pendingMealID prepare step in the Coach worker.

## Milestone 5 (live analysis)
- Sign-in showed only `NetworkUnavailable` when DNS failed. Show a clearer connection error, and note in the dev docs that the emulator may need `-dns-server 8.8.8.8`.
- `MealAnalysisWorker` must not hold its mutex across network calls. Remove
  duplicate drain requests with a flag instead.
- `StaleRevision` retries can cost up to 3 paid calls. Revisit this.
- Analysis failures are swallowed in `MivuApplication`. Surface them and offer
  Retry.

## Settings and day rollover
- Port the per-device day-cutoff setting. It is currently fixed at 04:00.
- Add the morning check-in, the weight row and the goal editor ("Set a goal" /
  "Edit goals" on Today).

## Play readiness
- Run a release-minify smoke test that decodes an archive fixture.
- Re-check `MaterialExpressiveTheme`. It did not compile with material3 1.4.0.
- Stream photo decoding for large archives, and add the export/import UI.
- Wire the profile button, or hide it.
