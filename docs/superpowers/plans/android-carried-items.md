# Android carried items

These items came out of reviews and must be picked up by the milestone named
on each one. Each milestone's plan reads this file and removes items once they
are done.

## Milestone 4 (Coach)
- Normalize the attachment and context instants in `CoachSubmissionPayload`
  with `.stored` before comparing manifests (`DiaryCapture.kt`,
  `MealCapture.kt`), and add a test that retries within the same second.
  Otherwise Coach retries on a real device get `StaleRevision`.
- Add camera capture, ported from iOS `PhotoCapture` (camera plus the
  permission flow).
- Wire the Ask Pip entry points (Today, Diary, meal, food) to Coach drafts.

## Milestone 5 (live analysis)
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
