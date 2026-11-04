# Workouts

Date: 2026-11-04. Platform: iPhone first. Status: draft for owner review.

Mockups: `workout-simple-v3.html` (screens S1–S9 below) in
`.superpowers/brainstorm/86696-1793825515/content/` of the `coach-photo-answer`
worktree. The earlier `workout-screens-v2.html` shows the hidden extras
(supersets, plates, settings); its layout density is superseded by v3.

## Why

Mivu already stores a basic workout (kind, minutes, exercises with reps and kg,
optional burn). It sits under Progress › Workouts as a long form, and Today does
not show it. The owner wants workouts on the level of the big apps (Strong, Hevy,
Apple Fitness, MyFitnessPal), but simple enough that anyone can use it without a
guide: human, minimal, smooth, one hand, not AI-looking, same design language.

User research (app reviews, forums, articles) shaped the rules. The top
complaints about sport apps: too many taps per set, untrusted and double-counted
calorie burn, lost in-progress workouts, paywalls on basics, rest timers that go
quiet when the phone locks, streak guilt, clutter and lock-in.

## Goals

- Anyone can log a workout on first try, with Pip or without.
- Gym: values are pre-filled from last time, so most sets are one tap on ✓.
- Cardio and sports: two wheels and Save.
- Every number is set on a wheel with one thumb, or typed.
- A running workout is always one tap away: a banner in the app, a timer on the
  lock screen.
- Never lose a logged set.
- Burn is an honest estimate and changes the food budget only if the user says so.

## Non-goals (this version)

- Apple Health, Garmin, Strava or watch import/export. Every workout records its
  source so these can come later without a migration.
- Pip suggesting the next workout or weights (deferred until after App Store
  review; nothing here may block it).
- Android (own plan later).
- GPS route recording, an Apple Watch app, live heart rate.
- Programs, AI plans, social feed, sharing, streaks, scores.

## Anti-goals

- A set takes more than one tap when nothing changed from last time.
- Jargon on screen: no "RPE", "volume", "1RM", "PR", "W/D/F". Say "How hard?",
  "New best", "Warm-up".
- Paragraphs of explanation, or Pip lecturing.
- Burn silently raising the food budget.
- A workout or set lost when the app is killed, the phone locks or a save fails.
- New colors, card styles or navigation patterns that make it feel bolted on.
- Advanced options on the main screens. They exist, one level down.

## Owner decisions

| Topic | Decision |
|---|---|
| Who it serves | Live gym sessions, after-the-fact gym logs and quick cardio, equally |
| Entry | "Start workout" on Today in a new Workouts section under Meals |
| Running workout | A banner on every screen of the app; lock-screen timer while it runs |
| Numbers | Gym: two up/down wheels (weight, reps). Cardio: a sideways ruler per number. Tap the big value to type |
| Exercises | Built-in searchable list plus unlimited own exercises |
| Machine photo | Take a photo of a gym machine; ChatGPT names the exercise; if the machine has several uses, show them; no choice → best guess |
| Gym extras | Last time, new bests, rest timer, routines, set types, how hard, supersets/circuits, plate calculator. All built; extras are hidden one level down |
| Units | Lifting follows the existing body-weight unit (`@AppStorage("weightUnit")`) |
| Cardio fields | Activity, time, distance with pace (distance sports), how hard, avg heart rate, indoor/outdoor, note |
| Burn estimate | Activity + time + body weight (MET), nudged by how hard; labeled estimate; editable |
| Burn in budget | Settings: Off (default) / 50% / 100% |
| Pip | Log from a sentence, start a routine, answer questions |
| Lock screen | Workout timer always shows while a workout runs, even if day Live Activities are off |
| Import/export | Strong and Hevy CSV import; workouts CSV export |
| Delivery | One PR for the whole feature |
| Price | Everything free |

## Experience

Design language: tokens from `ios/Shared/MivuColors.swift` (`diaryCanvas`,
`diarySurface`, `diaryAccent`; `diaryWorkout` purple for workout accents;
`diaryTintBurn` for burn), white rounded cards, big tabular numbers, SF Symbols
(mockup emoji are placeholders), native controls and haptics. Labels and numbers,
rarely a sentence. Every screen has one obvious next action.

### S1 · Today

- Header card adds "320 burned" in `diaryWorkout` when today has burn. "Left"
  includes burn only per the budget setting.
- New "Workouts" section under Meals: rows (icon, title, one detail line such as
  "5 km · 28 min" or "52 min · 14 sets", burn), then a purple "Start workout" card.
  The section, with just the Start card, shows even when no workout exists.
- Bottom bar unchanged (Log with Pip, Add).
- Tap a row: workout detail (edit, delete with Undo, Ask Pip), as meals today.

### S2 · Start workout (sheet)

- "Gym · Sets and reps" as the main purple row.
- Run, Walk, Cycle, Other sport (searchable list of about 40 activities).
  Most-used sports move up; at most four show.
- "Again": routines first, then the last few distinct workouts. Tap starts it
  pre-filled (gym) or opens S6 with last values (cardio).
- Logging something that already happened: a "Today, now" row at the top of the
  sheet changes date and start time. A past gym workout opens S3 without a
  running clock and without the banner, rest timer or Live Activity.

### S3 · Gym (live)

- Top: collapse (⌄, keeps it running, banner shows), elapsed time, Done.
- One card per exercise: name, "Last time 60 kg × 8", then set rows:
  `n  [62.5 kg] × [8]  ✓`. New sets copy the row above, or last time.
- ✓ saves the set at once (haptic, row turns green) and starts the rest timer.
- Change a number: swipe up or down on it (one step per notch, haptic), or tap
  it to open the wheel sheet (S4).
- "+ Set" under the sets, "+ Exercise" at the bottom opens the exercise picker
  (search, recent, muscle filter, camera button for the machine photo).
- Only the current exercise card is expanded; others are one line
  ("3 sets · last 40 kg × 8").
- Hidden one level down (exercise ⋯ menu or long-press): reorder, replace,
  superset with…, rest time, note, remove. Long-press a set: warm-up, drop set,
  to failure, how hard (1–10), delete. Swipe a set left to delete.
- Time-based exercises (plank) show minutes:seconds instead of weight × reps;
  body-weight exercises show reps, with optional added weight.
- A small "New best" pill appears on the exercise when a ticked set beats its
  best.
- Rest bar at the bottom: countdown, Skip, tap for −15/+15.

### S4 · Gym number wheels

- Sheet with two native wheel pickers side by side: weight and reps, current
  value centered, "Set 2" title, ✓ Done (also ticks the set).
- Weight steps follow the unit and plates: 2.5 kg / 5 lb, or 1.25 kg / 2.5 lb if
  the user's plates include them. Range 0–500 kg / 0–1100 lb.
- Tap the centered value to type. A small "Plates" link opens the plate
  calculator for barbell exercises.
- Time-based exercises get minutes and seconds wheels.

### S5 · Machine photo

- In the exercise picker, the camera button takes one photo.
- Mivu sends the photo to ChatGPT (existing connection and OpenAI consent; same
  privacy notice as meal photos) and gets back candidate exercises from Mivu's
  own catalog IDs plus one best guess.
- One clear match: the exercise is added, with a brief "Lat pulldown" toast and
  Undo.
- A multi-use machine (cable station, Smith machine, multi-press): a short list of
  up to four options with the best guess highlighted. Tap one to add it. If the
  user closes the list or starts lifting without choosing, the best guess is added,
  and its name shows a small "Change" link until the first set is ticked.
- Not connected, offline, or nothing recognised: the picker opens with the search
  field focused. No error screens.
- The machine photo is not stored after recognition.
- Apple Intelligence is not used for this (no on-device image input).

### S6 · Cardio and sports

- Title is the activity. Cancel / Save.
- Card per number with a big value and a sideways ruler under it (drag
  left/right, haptic tick per step, tap value to type): Time; Distance for
  distance sports.
- "How hard?" four chips: Easy, Moderate, Hard, Max (stored as effort 3, 5, 7, 9).
- Bottom line: pace or speed (computed) and "~310 kcal" (tap to type your own).
- "More" (collapsed): start time, avg heart rate, indoor/outdoor, note.
- Defaults: last values for that activity, else 30 min and a typical distance.

### S7 · Running workout banner

- While a live workout runs and its screen is not showing, a purple banner sits
  above the tab bar on every tab and sheet-free screen: green dot, title, current
  exercise and set, elapsed time (or rest countdown while resting), chevron.
  Tap returns to S3.
- It is the system tab-bar accessory (`tabViewBottomAccessory`, iOS 26), so it
  sits with the tab bar like a mini player and never covers content.
- VoiceOver: one element, "Push day running, 24 minutes. Opens workout."

### S8 · Lock screen and Dynamic Island

- While a live workout runs: activity icon, "Rest 1:12" with next set, or the
  elapsed time and current exercise when not resting.
- Rest end plays the notification sound via a scheduled local notification,
  so it works when locked or the app was killed. Notification permission is asked
  the first time a rest timer starts, once; declined still works in-app.
- This workout Live Activity runs even if the user never turned on Mivu's day
  Live Activity. It respects the existing "hide when locked" choice by showing
  only "Workout · 1:12" without exercise names.
- While it runs, the day-progress Live Activity is paused; it comes back after
  the workout only if the user had it on.

### S9 · Done

- Pip, "Nice work", title and duration. Pip plays the workout gestures from
  PR 106: `workout-breather` after a hard workout, `stretch-reach` otherwise.
  When any workout is saved (cardio, gym, Pip), Pip on Today or Coach plays a
  matching gesture once: squat for gym and HIIT, yoga tree for yoga and pilates,
  stretch for stretching, jumping jack for everything else.
- Three numbers: sets, kcal, new bests.
- "How did it feel?" four chips (as S6), pre-selected from set efforts if any.
- Save. Under it a text button: "Save as routine" (or "Update <routine>" when
  the exercises changed). No streaks, no score.
- Done with no ticked sets asks "Discard empty workout?".

### Settings › Workouts

In the existing settings area: Add burn to food budget (Off / 50% / 100%), rest
timer default, weight unit (the shared one), bar and plates, import from Strong or
Hevy, export CSV, routines, my exercises.

### Detail, history and Progress

- Workout detail: S3 layout read-only, Edit (everything, including date, start
  time and duration), Delete with Undo, Ask Pip.
- Exercise detail (tap a name): bests and the last 20 sessions as rows.
- Diary day view lists workouts under meals. Progress › Workouts keeps the full
  history list with the new rows.

## Behavior rules

### Durability

- A live workout is a stored workout with `state: active` from the first tap.
  Every ✓, edit, add and delete is its own transaction, written before the UI
  shows it done. Elapsed time is derived from `startedAt`.
- On launch an active workout restores the banner (not a forced full screen).
  One active workout per profile; starting another asks to finish or discard.
- Active workouts are left out of totals, burn and bests until finished, and are
  in backups.
- After 12 hours untouched, the banner reads "Finish Push day?" with Finish and
  Discard. Never auto-deleted.
- A failed save keeps the values on screen with Retry (existing pattern).

### Last time

For exercise E at set position n: the n-th normal set of E in the most recent
finished workout containing E; warm-ups match warm-ups. If that session had fewer
sets, use its last set.

### New bests

Per exercise, from finished workouts and the running one, ignoring warm-ups.
A ticked set is a new best when it is the heaviest weight ever done, or more reps
than ever done at that weight or heavier. Body-weight exercises: most reps. Time
exercises: longest time. An exercise's first session sets bests silently. Bests
are computed, not stored, so edits and deletes stay correct.

### Burn estimate

- Net kcal = (MET − 1) × body kg × hours. Subtracting the resting MET avoids
  double counting energy already in the daily target.
- METs: bundled table from the 2024 Adult Compendium of Physical Activities, three
  levels per activity. Easy → light, Moderate/Hard → moderate, Max → vigorous;
  running and cycling with distance use speed-based codes. Gym: resistance
  training 3.5 (easy/moderate) or 6.0 (hard/max).
- Body weight: latest weigh-in on or before the date, else onboarding weight.
  Neither: no estimate, and the burn line reads "Add weight for kcal".
- User-typed burn wins (`burnSource: userEstimate`). Pip passes a number only when
  the user said one; otherwise Mivu computes it. The model never invents burn.
- Shown as "~310 kcal"; the detail says "Estimate".

### Food budget

- `GoalRecord.exerciseCreditEnabled: Bool` becomes `exerciseCreditPercent`
  (0, 50, 100); old `true` reads as 100, `false` as 0.
- The Settings control changes today's goal record (creating a dated revision
  from today, like other goal edits), so past days keep their numbers. With no
  goal, the choice is stored with the next goal.
- Day burn = sum of known burns; workouts without burn add nothing. The header
  shows burn when the sum is above zero.
- Adjusted left = target − food + burn × percent / 100, in the shared
  `ProgressAnalytics` function used by Today, Progress and Coach.
- A day with workouts and no food is not a "skipped" food day; days created only
  by workouts or imports are left out of food coverage counts.

### Pip

- The workout tool schema in `CoachTools.swift` gains the new fields. Edits keep
  every field Pip did not change (no whole-array replace that drops new fields).
- Names resolve to the catalog by normalized name and aliases; unknown names
  become own exercises ("new exercise" on the receipt).
- If a live workout is running, "another set 60 × 8" or "add rows" changes that
  workout; otherwise a sentence logs a finished workout with a receipt and Undo.
- Read tool for exercise history (bounded) and workouts in progress reads, for
  questions. Answers are one line.
- `start_routine` returns a routine card; the user taps Start.
- Routines, own exercises and workout settings managed by hand are reached from
  Pip through the existing settings handoff.
- The rules forbid suggesting workouts, weights or plans in this version.

### Import (Strong, Hevy)

- Pick a CSV file; format detected from the header row.
  - Strong: Date, Workout Name, Duration, Exercise Name, Set Order, Weight, Reps,
    Distance, Seconds, Notes, Workout Notes, RPE.
  - Hevy: title, start_time, end_time, description, exercise_title,
    superset_id, exercise_notes, set_index, set_type, weight_kg or weight_lbs,
    reps, distance_km or distance_miles, duration_seconds, rpe.
- Parse locale-safely (decimal comma, both date styles). Units from column names,
  else ask once.
- Preview: "84 workouts · 23 exercises (6 new)". One transaction. A broken
  workout is skipped and counted.
- Same source + start time + title already present → skipped, so re-import is safe.
- No burn unless the file has one.
- Tests use synthetic CSVs only.

### Export

One row per set, Hevy-like columns, via the share sheet. The full backup also
carries routines and own exercises.

## Data

Additive; existing workouts keep working.

- `WorkoutSession` adds optional `title`, `activity` (catalog ID; `kind` kept and
  derived for old rows), `state` (`active`/`finished`, absent = finished),
  `durationSeconds` (truth for new rows; `durationMinutes` kept in sync),
  `distanceMeters`, `avgHeartRate`, `effort` (1–10), `indoor`, `note`,
  `routineID`, `source` (`manual`, `coach`, `live`, `import.strong`,
  `import.hevy`; later `health`, `garmin`, `strava`) and `externalID`.
- `WorkoutExercise` adds `exerciseID`, `groupID`, `restSeconds`, `note`.
- `WorkoutSet` adds `type` (normal, warmup, drop, failure), `effort`, `seconds`,
  `distanceMeters`, `done`.
- One new collection, `routine`, same pattern as `goal` (id, ordinal, JSON
  payload, no day parent) with a `routine_tombstone`.
- Own exercises need no table: a `WorkoutExercise` with no `exerciseID` is an
  own exercise, identified by its normalized name, and carries its `measure`.
  "My exercises" lists those names from history; rename and merge rewrite the
  matching workouts and routines in one transaction.
- Bundled `exercises.json` (about 150: stable ID, name, aliases, measure,
  equipment, muscle, `machine` flag) and an activity table (about 40: ID, name,
  SF Symbol, distance or not, indoor/outdoor, METs, matching
  `HKWorkoutActivityType` for a later Health export).
- Device preferences in `AppStorage`: rest default, bar, plates.
- `DiaryArchive` version 5 (all new fields and collections at once). Version 4
  still restores. Older readers, including current Android, reject version 5.

## Testing

Smallest failing test first. Synthetic inputs only.
- Unit: burn formula; budget percent and the old bool; day burn sum; plate fill;
  last time; new bests with edits and deletes; superset round order; Strong and
  Hevy parsing (decimal comma, lb, missing columns, duplicates); archive v5 round
  trip and v4 restore; active workout resume and exclusion from totals; workout-only
  days not counted as skipped.
- Coach: schema for new fields; edits keep untouched fields; sentence into a
  running workout; `start_routine` returns a card only; no suggestions; machine
  photo result parsing with one, several and no candidates, and best guess on
  dismiss.
- UI (focused, XcodeBuildMCP): first-time user logs a run from Today; three gym
  sets ticked, app killed, relaunched, sets and banner remain; banner visible on
  every tab; largest Dynamic Type on S1, S3 and S6; VoiceOver on wheels, ruler and
  banner. Real iPhone: rest sound while locked, Live Activity, wheel haptics.

## Build order inside the one PR

Commits in this order, each with its tests: data and archive v5; catalogs and burn;
budget setting; Today section, start sheet and cardio; live gym, wheels, banner,
rest timer and Live Activity; bests and last time; routines, supersets, set
options, plates; Pip tools and machine photo; import and export.

## Left to the builder

- Exact exercise and activity lists, aliases and symbols, within the sizes above.
- The ruler component (a horizontal `ScrollView` with snapping and sensory
  feedback is the expected route), wheel sizes and animation details.
- Table and index layout for the new collections, following `workout`.
