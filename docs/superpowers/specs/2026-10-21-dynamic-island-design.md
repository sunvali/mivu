# Dynamic Island day progress — design

## Why

People check how much they have left to eat many times a day. Today that means
opening Mivu. An optional Live Activity puts calories left in the Dynamic Island
and on the Lock Screen, so they can see it at a glance. Live Activities show on
the Lock Screen of every supported iPhone, and the island appears on models that
have one. It is opt-in, because a persistent calorie number is not for everyone.

## Goals

- Show calories left for the active waking day, plus protein, carbs and fat
  against today's targets.
- Keep it current whenever Mivu changes the diary: manual capture, edits,
  deletes, Coach mutations, and day rollover.
- Let people turn it on or off at any time from a Settings switch. It is off by
  default, and Mivu doesn't prompt for it (owner decision, 2026-10-21).

## Non-goals

- Push updates (APNs or a server). Mivu has no server.
- A meal-analysis progress mode, a fasting timer, or a home-screen widget.
- Animating Pip in the island.
- Hebrew/RTL. The MVP is English-only.

## Anti-goals (a failure even if it works)

- Wrong or stale numbers shown as current.
- Red or alarm styling when someone goes over their target. Mivu's coach tone is
  supportive.
- Starting the activity without the person's opt-in.
- The extension reading or bundling diary data, credentials or tokens.

## Owner decisions

| Topic | Decision |
|---|---|
| Content | Today's calories left |
| Opt-in | Settings switch only, off by default. No onboarding prompt (changed 2026-10-21). |
| Pip | A static Pip glyph |
| Updates | Local only, sent from the app |
| Start | Every app open starts it, or refreshes it if one is running |
| Expanded / Lock Screen | Calories left plus protein, carbs and fat bars |
| Over target | "120 over" in a neutral color |
| Tap | Opens the Today tab |
| iOS Live Activities off | The switch is disabled, with a note and a button to iOS Settings |
| Rollover | Resets to the new day's full target |
| Lock Screen privacy | The user chooses with a second switch, "Hide numbers on Lock Screen" |

## Behavior

### Layouts

- **Compact leading:** the Pip glyph. **Compact trailing:** the number left
  (`640`), or `120 over` when over target.
- **Minimal:** the number only.
- **Expanded and Lock Screen:** Pip on the leading side. In the center, a large
  "640 left" or "120 over". Below that, three thin bars for protein, carbs and
  fat, each with a label like `P 80/120g`.
- If a target is missing, show the consumed amount without a bar. If the kcal
  target is missing, show "640 eaten" instead of "left".
- If any of today's meals has unknown nutrition (`unknownItemCount > 0`) or is
  still analyzing, show a small "+ pending" caption. The numbers must not look
  complete when they are not.
- Use system fonts and colors and support Dynamic Type. VoiceOver reads, for
  example, "640 calories left. Protein 80 of 120 grams. Carbs … Fat …".

### Lifecycle

1. **Enabled and the app becomes active:** if no Mivu activity is running, start
   one with the current numbers. If one is running, update it. If more than one
   is running, keep one and end the rest.
2. **The diary read model changes** (every capture, edit, delete and Coach
   mutation reaches `DiaryViewModel.readModel`): update the running activity. Do nothing if the switch is off.
3. **Rollover while the app is open:** the read model changes to the new day,
   which resets the activity to the new day's totals. No special case is needed.
4. **Rollover while the app is closed:** each update sets `staleDate` to the next
   cutoff time (`DayCutoff`). When `context.isStale` is true, the view shows
   "Open Mivu for today" in place of the numbers. The next app open updates it.
5. **iOS ends it after about 8 hours** (it can stay on the Lock Screen up to 4
   hours longer). The next app open starts a new one.
6. **Switch turned off:** end all Mivu activities immediately.
7. **Profile switch:** update to the new profile's active day.
8. **Sample mode and UI tests:** never start a real activity. A UI test turns it
   on only with the launch argument `--live-activity`, following the existing
   `DiaryLaunch` argument pattern.
9. **Background:** if a `refresh` lands while the process is still alive in the
   background (for example, an analysis that finishes under the existing
   background-task lease), `sync` updates the activity as usual. ActivityKit
   allows that. Mivu adds no new background execution. Changes made while the
   process is suspended appear at the next open, and until then `staleDate` and
   "+ pending" keep the numbers honest. *(Builder call.)*

### Opt-in

- **Settings:** add a "Show in Dynamic Island" toggle to `DaySettingsSection`.
  It is stored in `@AppStorage("liveActivityEnabled")`, default `false`, has a
  44-point minimum target, and uses the accessibility identifier
  `liveActivityToggle`. If `ActivityAuthorizationInfo().areActivitiesEnabled`
  is false, disable the toggle and show the footer "Live Activities are off for
  Mivu in iOS Settings." with an "Open Settings" button
  (`UIApplication.openSettingsURLString`).
- **Lock Screen privacy:** a second toggle, "Hide numbers on Lock Screen", sits
  under the main one and shows only while the main one is on. It is stored in
  `@AppStorage("liveActivityHideWhenLocked")`, default `true` *(builder call:
  the privacy-preserving default)*, with the identifier
  `liveActivityHideWhenLocked`. When it is on, the number and macro views use
  `.privacySensitive()`, so iOS redacts them on a locked device and Pip stays
  visible. The value reaches the extension through `ContentState`, because the
  extension has no shared defaults. Changing it syncs right away.

### Tap

`widgetURL` opens `mivu://today`, which the widget branch already handles by
selecting the Today tab.

## Architecture

This work builds on the unmerged `feat/widget` branch and merges after it. It
reuses that branch's extension, art and update hook, so there is no second
target.

- **Extension:** add `DayProgressLiveActivity` (an `ActivityConfiguration`) to
  the existing `MivuWidgets` bundle in `ios/MivuWidgets/MivuWidgets.swift`.
  The Live Activity reads only its `ContentState`. It never reads the App Group
  snapshot or the diary.
- **Shared file:** `ios/Shared/DayProgressAttributes.swift`, compiled into both
  targets like `WidgetSnapshot.swift`. It is a `DayProgressAttributes:
  ActivityAttributes` with no static attributes. Its `ContentState` holds
  `kcalEaten, kcalTarget, protein, proteinTarget, carbs, carbsTarget, fat,
  fatTarget` (all `Double?`), `hasPending: Bool` and `hideWhenLocked: Bool`.
  The formatting rules ("left" or "over", "eaten" when the target is missing)
  live here too, so the extension and the tests use the same code.
- **App side:** `ios/Mivu/DayProgressActivity.swift`, next to
  `WidgetSnapshotWriter.swift`:
  - `ContentState.init(readModel:hideWhenLocked:)` is pure. It builds the state
    from `ProgressAnalytics.daily(readModel:)`: `foodTotals` for what's eaten,
    `goal?.targets` for the targets, and `completeness == .partial` or any
    `unknownItemCount > 0` for `hasPending`. It adds no new totals code, which
    keeps it apart from the meal calculations.
  - `@MainActor func syncDayProgressActivity(_ readModel: DiaryReadModel?)` reads
    the two `@AppStorage` keys and the current authorization. It ends every
    activity when disabled, and otherwise starts one or updates it.
    `staleDate` is `WidgetSnapshot.nextRollover(...)`, computed the way
    `WidgetSnapshot.init(readModel:now:cutoffHour:)` does it. It returns early
    under `DiaryLaunch.isUITest` unless `--live-activity` is passed.
  - It is called from the same place as `publishWidgetSnapshot`:
    `.onChange(of: model.readModel, initial: true)` in `TodayView`. It is also
    called when the scene becomes active, and from both toggles. *(Builder call: this reuses the widget's proven hook
    instead of the model-level call this doc proposed earlier.)*
- **Tap:** reuse `.widgetURL(URL(string: "mivu://today"))`. `TodayView`
  already handles it.
- **Pip:** reuse the `PipWave` asset that is already in `MivuWidgets`, at
  island sizes. No new art is needed.
- **Colors:** use `ios/Shared/MivuColors.swift` (`diaryAccent`, `diaryText`,
  `diarySecondary`). "Over" uses `diarySecondary`, never red.
- **Info.plist:** add `NSSupportsLiveActivities = YES` to the app's
  `ios/Config/Info.plist`. Don't set frequent updates.
- **Privacy manifest:** the extension already exists on `feat/widget`. Confirm
  its manifest still covers it, because ActivityKit needs no required-reason
  API.

## Testing

- Unit tests in `ios/MivuTests` for `ContentState.init(readModel:hideWhenLocked:)`: under, exactly at, and over
  target, a missing kcal target, missing macro targets, pending and unknown
  items, an empty day, and a new day after rollover. Add tests for the label
  formatting.
- Unit test that `sync` with `enabled == false` requests an end and never a
  start. Inject a thin protocol over ActivityKit only if the existing test
  patterns need it. Otherwise test the decision as a pure function.
- Manual check in the simulator, on an iPhone 17 Pro with an island: compact,
  minimal, expanded, Lock Screen (both with and without hiding while locked),
  stale, over target, Dynamic Type at the largest size, VoiceOver, the tap opening Today, and the toggle turning it on
  and off. Record the results in `docs/verification/` with the source SHA.

## Left to the builder

- Exact typography, spacing and bar styling, following the HIG Live Activity
  guidance and the Precision Glass tokens where they apply.
- Whether `DayProgressActivity` is an enum with static functions or a small
  class.
