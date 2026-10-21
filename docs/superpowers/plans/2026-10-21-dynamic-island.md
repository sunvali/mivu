# Dynamic Island Day Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional Live Activity that shows today's calories left and macro bars in the Dynamic Island and on the Lock Screen. Mivu updates it locally whenever the diary changes.

**Architecture:** A shared `DayProgressAttributes` file is compiled into both targets. It holds the `ContentState` and its formatting. The app builds that state from `ProgressAnalytics.daily(readModel:)` and starts, updates or ends the activity from the hook `publishWidgetSnapshot` already uses. The existing `MivuWidgets` extension gains an `ActivityConfiguration`.

**Tech Stack:** Swift 6, SwiftUI, ActivityKit, WidgetKit, iOS 26, Swift Testing / XCTest, XcodeBuildMCP.

**Spec:** `docs/superpowers/specs/2026-10-21-dynamic-island-design.md`

## Global Constraints

- Branch `feat/dynamic-island`, based on `feat/widget`. It merges after the widget PR.
- iOS 26.0, iPhone only. Use the existing `MivuWidgets` target. Add no new target, app group or entitlement.
- `@AppStorage` keys: `liveActivityEnabled` (default `false`) and `liveActivityHideWhenLocked` (default `true`).
- Accessibility identifiers: `liveActivityToggle`, `liveActivityHideWhenLocked`, `onboardingLiveActivity`.
- Copy: "Show in Dynamic Island", "Hide numbers on Lock Screen", "Show what's left in your Dynamic Island", "Live Activities are off for Mivu in iOS Settings.", "Open Settings", "left", "over", "eaten", "+ pending", "Open Mivu for today".
- Kcal and grams are whole numbers with grouping (`1,360`), matching the widget.
- "Over" uses `Color.diarySecondary`, never red. Pip is the existing `PipWave` asset.
- The UI-test opt-in is the launch argument `--live-activity`. Otherwise do nothing when `DiaryLaunch.isUITest` is true.
- The extension reads only `ContentState`, never the diary, the App Group or Keychain.
- Use 44-point minimum targets, Dynamic Type and VoiceOver labels. English only.
- Use Conventional Commit titles with no tool or assistant names. Commit as `Yaakov Khodorkovski <yaakovkhodorkovski@Yaakovs-MacBook-Pro-2.local>` via `git -c user.name=… -c user.email=…`.
- The simulator is shared with other agents. Claim it only for the final verification run, and say so.

## Review Focus

1. **Over target or exactly at target** (2,300 of 2,000, or 2,000 of 2,000): shows "300 over" or "0 left", never a negative "left". Test in Task 1.
2. **No kcal target** (the goal is missing or has no kcal): shows "1,360 eaten", with no bar for missing macro targets. Test in Task 1.
3. **Pending analysis only** (a capture is analyzing and no meal is saved, so `foodTotals.kcal` is nil): shows `0` with "+ pending", never a crash or a blank. Test in Task 1.
4. **Toggle off while running, or the profile is cleared** (`readModel == nil`): all activities end, and none is started. Test in Task 2.
5. **Two activities running** (left over from an earlier launch): one is kept and the rest end. Test in Task 2.

---

### Task 1: Shared state and formatting

**Files:**
- Create: `ios/Shared/DayProgressAttributes.swift` (compiled into both targets. `ios/Shared` is already a synchronized folder in both. Confirm in the pbxproj membership exceptions, the way `WidgetSnapshot.swift` is set up.)
- Create: `ios/Mivu/DayProgressActivity.swift` (app only)
- Test: `ios/MivuTests/DayProgressActivityTests.swift`

**Interfaces:**
- Produces:
  - `struct DayProgressAttributes: ActivityAttributes` with `struct ContentState: Codable, Hashable`. Its fields are `kcalEaten: Double`, `kcalTarget: Double?`, `protein: Double?`, `proteinTarget: Double?`, `carbs: Double?`, `carbsTarget: Double?`, `fat: Double?`, `fatTarget: Double?`, `hasPending: Bool` and `hideWhenLocked: Bool`.
  - `ContentState.figure: String`: the grouped whole number, `abs(target − eaten)` when there is a target, else eaten.
  - `ContentState.word: String`: "left", "over" or "eaten".
  - `ContentState.isOver: Bool`
  - `ContentState.compact: String`: `"640"`, `"300 over"` or `"1,360"`.
  - `ContentState.spoken: String`: for example "640 calories left. Protein 80 of 120 grams. Carbs 150 of 200 grams. Fat 40 of 60 grams." A macro with no target reads "Protein 80 grams". A missing macro is omitted.
  - `ContentState.macroLabel(_ letter: String, _ value: Double?, _ target: Double?) -> String`: `"P 80/120g"`, or `"P 80g"` when there is no target.
  - `ContentState.fraction(_ value: Double?, _ target: Double?) -> Double?`: nil without a target, otherwise clamped to `0...1`.
  - Defined in the app's `DayProgressActivity.swift`: `extension DayProgressAttributes.ContentState { init(report: DailyProgress, hideWhenLocked: Bool) }`

- [ ] **Step 1: Write the failing tests** in `DayProgressActivityTests` (Swift Testing). Build the reports with `ProgressAnalytics.daily(readModel:)` from a synthetic `DiaryReadModel`, using the fixture shape in `WidgetSnapshotTests.snapshotMatchesTodaysReport`.
  - `underTarget`: 1,360 eaten of 2,000 → `figure == "640"`, `word == "left"`, `compact == "640"`, `!isOver`.
  - `exactlyAtTarget`: 2,000 of 2,000 → `"0"` and `"left"`.
  - `overTarget`: 2,300 of 2,000 → `"300"`, `"over"`, `compact == "300 over"`, `isOver`.
  - `noKcalTarget`: the goal is nil → `figure == "1,360"`, `word == "eaten"`, `kcalTarget == nil`.
  - `macroLabelsAndFractions`: protein 80 of 120 → `macroLabel("P", 80, 120) == "P 80/120g"` and `fraction(80, 120)` ≈ 0.667. `fraction(150, 120) == 1`. `fraction(80, nil) == nil`. `macroLabel("P", 80, nil) == "P 80g"`.
  - `pendingWithoutSavedMeal`: the report has `hasPending` and `foodTotals?.kcal == nil` → `kcalEaten == 0`, `hasPending`.
  - `unknownItemsCountAsPending`: `unknownItemCount == 1` → `hasPending`.
  - `spokenLabel`: the full sentence above for 1,360 of 2,000 with all macros.
  - `hideFlagPassesThrough`: `init(report:, hideWhenLocked: false).hideWhenLocked == false`.

- [ ] **Step 2: Run** (XcodeBuildMCP `test_sim`, scheme `Mivu`) `MivuTests/DayProgressActivityTests`. Expected: FAIL, because the type is undefined.

- [ ] **Step 3: Implement** the shared file and the `init(report:hideWhenLocked:)` extension. Take eaten from `report.foodTotals`, using `kcal ?? 0` and nil macros as given. Take targets from `report.goal?.targets`. `hasPending = report.hasPending || (report.foodTotals?.unknownItemCount ?? 0) > 0`. Format with `.number.precision(.fractionLength(0))`, the formatter the widget uses.

- [ ] **Step 4: Run** the same suite. Expected: all 9 pass.

- [ ] **Step 5: Commit** `feat(live-activity): day progress state and labels`

### Task 2: Start, update and end the activity

**Files:**
- Modify: `ios/Mivu/DayProgressActivity.swift`
- Modify: `ios/Mivu/Diary/TodayView.swift`, next to `.onChange(of: model.readModel, initial: true)` (~line 187) and in `.onChange(of: phase)` (~line 205)
- Modify: `ios/Config/Info.plist`: add `NSSupportsLiveActivities` = `true`
- Test: `ios/MivuTests/DayProgressActivityTests.swift`

**Interfaces:**
- Consumes: `ContentState.init(report:hideWhenLocked:)` and `WidgetSnapshot.nextRollover(after:timeZoneID:cutoffHour:)`
- Produces:
  - `enum DayProgressSync: Equatable { case endAll, start, update(endingExtra: Int) }`
  - `static func DayProgressSync.decide(enabled: Bool, authorized: Bool, hasDiary: Bool, running: Int) -> DayProgressSync`
  - `@MainActor func syncDayProgressActivity(_ readModel: DiaryReadModel?)`: reads both `@AppStorage` keys from `UserDefaults.standard` and `ActivityAuthorizationInfo().areActivitiesEnabled`, then applies the decision through `Activity<DayProgressAttributes>`.

- [ ] **Step 1: Write the failing tests**:
  - `disabledEndsAll`: `decide(enabled: false, authorized: true, hasDiary: true, running: 1) == .endAll`
  - `unauthorizedEndsAll`: `authorized: false` → `.endAll`
  - `noDiaryEndsAll`: `hasDiary: false` → `.endAll`
  - `noneRunningStarts`: `running: 0` → `.start`
  - `oneRunningUpdates`: `running: 1` → `.update(endingExtra: 0)`
  - `extrasEnd`: `running: 3` → `.update(endingExtra: 2)`

- [ ] **Step 2: Run** `MivuTests/DayProgressActivityTests`. Expected: the 6 new tests fail.

- [ ] **Step 3: Implement** `decide` and `syncDayProgressActivity`. Return early when `DiaryLaunch.isUITest && !arguments.contains("--live-activity")`. `staleDate` is the next rollover, computed with the zone and `DayCutoff.hour` the way `WidgetSnapshot.init(readModel:now:cutoffHour:)` computes them. Start with `Activity.request(attributes: .init(), content: .init(state:, staleDate:), pushType: nil)`, and log failures without the state. Update with `activity.update(_:)`. End with `.end(nil, dismissalPolicy: .immediate)`. Wrap the async ActivityKit calls in one `Task`.

- [ ] **Step 4: Wire it up** in `TodayView`. Call `syncDayProgressActivity(readModel)` in the existing `onChange(of: model.readModel, initial: true)` closure, and `syncDayProgressActivity(model.readModel)` when `phase` becomes `.active`. Add the Info.plist key.

- [ ] **Step 5: Run** the suite, then `build_sim`. Expected: all tests pass and the build succeeds.

- [ ] **Step 6: Commit** `feat(live-activity): keep the day progress activity in sync`

### Task 3: Island and Lock Screen UI

**Files:**
- Create: `ios/MivuWidgets/DayProgressLiveActivity.swift`
- Modify: `ios/MivuWidgets/MivuWidgets.swift`: add `DayProgressLiveActivity()` to the bundle

**Interfaces:**
- Consumes: everything on `ContentState` from Task 1
- Produces: `struct DayProgressLiveActivity: Widget` using `ActivityConfiguration(for: DayProgressAttributes.self)`

- [ ] **Step 1: Implement** the layouts from the spec:
  - Lock Screen and expanded: `PipWave` on the leading side; `figure` plus `word` in the center (`.title.bold().monospacedDigit()`); three bars with `macroLabel`, using `fraction` for the fill and showing no bar when it is nil; "+ pending" in a caption when `hasPending`.
  - Compact leading: `PipWave` at about 24 pt. Compact trailing: `compact`. Minimal: `figure`.
  - `context.isStale` → "Open Mivu for today" in place of the numbers.
  - The figure and bars use `.privacySensitive(state.hideWhenLocked)`, and Pip is never redacted.
  - Colors: `diaryAccent` for the bars, `diaryText` for the figure, `diarySecondary` when `isOver`. Use `.widgetURL(URL(string: "mivu://today"))` and `.keylineTint(.diaryAccent)`. Use `accessibilityElement(children: .ignore)` with `.accessibilityLabel(state.spoken)` on the number group, and hide Pip from VoiceOver.
  - Add `#Preview(as: .dynamicIsland(.expanded), using: DayProgressAttributes())` and `#Preview(as: .content, …)` with under, over, pending and no-target states.

- [ ] **Step 2: Run** `build_sim`, scheme `Mivu`. Expected: BUILD SUCCEEDED, and the previews render in Xcode for all four states.

- [ ] **Step 3: Commit** `feat(live-activity): Dynamic Island and Lock Screen layouts`

### Task 4: Settings and onboarding opt-in

**Files:**
- Modify: `ios/Mivu/Diary/DaySettingsSection.swift`
- Modify: `ios/Mivu/Onboarding/OnboardingView.swift`: the `results` view (~line 257) and `save()`
- Test: `ios/MivuUITests/DiaryUITests.swift` (or a new `LiveActivityUITests.swift` there)

**Interfaces:**
- Consumes: `syncDayProgressActivity(_:)` from Task 2. Change the section to `DaySettingsSection(readModel: DiaryReadModel?)`, and have `SettingsView` (~line 46) pass `model.readModel`. Each toggle change calls `syncDayProgressActivity(readModel)`.

- [ ] **Step 1: Write the failing UI test** `testDynamicIslandTogglesShowAndPersist`. In Settings, `liveActivityToggle` is off and `liveActivityHideWhenLocked` does not exist. Tap the main toggle, then check that the hide toggle exists and is on. Relaunch with the same test ID and check both toggles keep their values. Don't pass `--live-activity`, so nothing real starts.

- [ ] **Step 2: Run** it. Expected: FAIL, because `liveActivityToggle` is not found.

- [ ] **Step 3: Implement** the Settings rows in the existing "Your day" section:
  - "Show in Dynamic Island", with the `livephoto` symbol (the builder may pick a better SF Symbol).
  - "Hide numbers on Lock Screen", with `eye.slash`, shown only while the main one is on. Both have `minHeight: 44`, and each change calls sync.
  - When `!ActivityAuthorizationInfo().areActivitiesEnabled`, disable the main toggle and add the footer line plus an "Open Settings" button that opens `UIApplication.openSettingsURLString`.

  On the onboarding `results` step, add a toggle `onboardingLiveActivity` below the targets card with Pip's offer copy. It is bound to `liveActivityEnabled` and off by default. `save()` needs no change, because saving the targets changes `readModel`, which syncs.

- [ ] **Step 4: Run** the new UI test plus the existing onboarding and settings UI tests. Expected: all pass.

- [ ] **Step 5: Commit** `feat(live-activity): opt in from onboarding and Settings`

### Task 5: Native verification record

**Files:**
- Create: `docs/verification/2026-10-21-dynamic-island.md` and screenshots in `docs/verification/dynamic-island/`

- [ ] **Step 1:** Claim the shared simulator and say so. Run `test_sim` with the full unit plan and the UI tests touched in Task 4. Record the source SHA, the result counts and the result-bundle path.
- [ ] **Step 2:** On the iPhone 17 Pro simulator, launch with `--live-activity` and a synthetic diary. Screenshot the compact, minimal, expanded and Lock Screen views, with hiding on and off while locked (use `xcrun simctl` to lock), plus over target, pending, stale (set the clock past the cutoff, or use a short test `staleDate`), and the largest Dynamic Type size. Confirm VoiceOver reads `spoken`. Confirm a tap opens Today. Confirm turning the toggle off removes the activity.
- [ ] **Step 3:** Write the record, list any blocked checks honestly, and commit it as `docs: Dynamic Island verification record`.
