# iPhone Duo Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mivu fills the iPhone Duo inner display, stays the normal app when held upright, uses a sidebar and two-column layouts when turned sideways, and offers a half-folded meal-snap camera.

**Architecture:** One root decision, `isWideLayout` (the window is wider than tall and the width size class is regular), is computed in `DiaryRootView` and published in the environment. When the layout isn't wide, the root overrides `horizontalSizeClass` to `.compact`, so the upright inner display renders exactly like a normal iPhone. When it is wide, the system `.sidebarAdaptable` tab view shows a sidebar, and screens split into two columns. Half-folded posture comes from the fold's `.division` reserved region and selects a custom AVFoundation camera inside the existing photo sheet.

**Tech Stack:** SwiftUI and UIKit, iOS 27.1 SDK (Xcode 27.1), Swift Testing (`MivuTests`), XCTest UI tests (`MivuUITests`), AVFoundation for D.

**Spec:** `docs/superpowers/specs/2026-10-29-iphone-duo-design.md`

## Global Constraints

- Build with the iOS 27.1 SDK (Xcode 27.1). `IPHONEOS_DEPLOYMENT_TARGET = 26.0` and `TARGETED_DEVICE_FAMILY = 1` stay unchanged.
- `INFOPLIST_KEY_UISupportedInterfaceOrientations` stays portrait (the outer display honors it; the inner display ignores it).
- Upright = the normal app: no split and no sidebar unless `isWideLayout`.
- Columns split 50/50, so the fold sits in the gutter. Inner columns are plain stacks, never a nested `NavigationSplitView`.
- Upright regular-width content is capped at 700 pt wide.
- At accessibility Dynamic Type sizes, `isWideLayout` is false (single column).
- Dynamic Type, VoiceOver, reduced motion and 44-point targets in every layout. English-only.
- Coach rules from AGENTS.md are untouched: no new Coach query consumer, the 100-exchange window is unchanged, and "Jump to latest" stays owned by `CoachTimelineTable`.
- Layout only: no new data paths, models or Coach behaviour.
- Three PRs from `main` on feature branches (`feat/duo-full-screen`, `feat/duo-wide-layouts`, `feat/duo-tabletop-camera`), with Conventional Commit titles. Each PR runs native checks with XcodeBuildMCP and records the exact SHA in `docs/verification/2026-10-29-iphone-duo.md`.
- Work in a fresh worktree from `main`. The current checkout has unrelated uncommitted edits to `TodayView.swift` and `CoachView.swift` that must not be touched or committed.

## Review Focus

1. Rotating or folding while typing a Coach draft: the draft, the selected tab and the selected Diary day survive (state is held in models and `@State` above the layout switch; check on the Duo simulator).
2. Pip (the companion rig) must never mount twice when Coach and Today sit side by side. The right column passes a hidden `CompanionOutput`.
3. Accessibility text sizes on the sideways screen fall back to one column with no clipped controls (`DuoLayoutTests` plus a UI check at `accessibility3`).
4. A Coach correction that edits an existing meal (rather than adding one) still highlights the row in the live column, not only new meals (Task 5 test).
5. If the camera permission is denied or the device has no camera in the half-folded pose, show the same "Camera is unavailable" path as today, not a black preview (Task 9 test).

---

## PR 1 — `feat/duo-full-screen`

### Task 1: Xcode 27.1 toolchain and Duo simulator baseline

**Files:**
- Create: `docs/verification/2026-10-29-iphone-duo.md`

- [ ] **Step 1:** Confirm `xcodebuild -version` prints `Xcode 27.1`. If it prints 27.0, stop: the owner must click Update on Xcode in the App Store (it needs their password).
- [ ] **Step 2:** Run `xcodebuild -downloadPlatform iOS`. Expected: the iOS 27.1 Simulator runtime is installed (retry once on failure, as reported upstream). Then `xcrun simctl list devicetypes | grep -i duo` lists an iPhone Duo type; create one: `xcrun simctl create "iPhone Duo" "<that type id>"`.
- [ ] **Step 3:** Record the exact foldable API names from the 27.1 SDK: `grep -rl "reservedRegions\|UIHinge\|ArrangementView\|toolbarVerticalBehavior" "$(xcrun --sdk iphoneos --show-sdk-path)"/System/Library/Frameworks/{UIKit,SwiftUI}.framework`. Write the signatures you find into the verification note under "SDK symbols". Tasks 2 and 8 use these names.
- [ ] **Step 4:** Baseline: run the full `MivuTests` unit suite on the iPhone Duo simulator with XcodeBuildMCP. Expected: the same pass count as on 27.0. Record the SHA, the simulator and the counts.
- [ ] **Step 5:** On the simulator's Device Hub, press Open with the app running. Expected: Mivu fills the screen (no centered window). Save a screenshot under `docs/verification/iphone-duo/`.
- [ ] **Step 6:** Commit `docs(duo): record Xcode 27.1 baseline and SDK symbols`.

### Task 2: Wide-layout decision, upright = normal app, readable width

**Files:**
- Create: `ios/Mivu/Design/DuoLayout.swift`
- Modify: `ios/Mivu/Diary/TodayView.swift` (`DiaryRootView`, around lines 69–80 and `rootTabs` at 318–346)
- Test: `ios/MivuTests/DuoLayoutTests.swift`

**Interfaces:**
- Produces:
  - `enum DuoLayout { static func isWide(size: CGSize, horizontal: UserInterfaceSizeClass?, typeSize: DynamicTypeSize) -> Bool; static let readableWidth: CGFloat = 700 }`
  - `extension EnvironmentValues { @Entry var isWideLayout = false; @Entry var isHalfFolded = false }`
  - `extension View { func duoReadableWidth() -> some View }`: caps width at `DuoLayout.readableWidth` only when the real width class is regular and the layout isn't wide; otherwise it does nothing. It keeps `Color.diaryCanvas` behind the margins.
  - Launch argument `--wide-layout-ui-test` forces `isWideLayout = true` (UI tests only, guarded by `DiaryLaunch.isUITest`).

- [ ] **Step 1: Write the failing test** `DuoLayoutTests` (Swift Testing):

```swift
@Test func uprightInnerDisplayIsNotWide() { #expect(!DuoLayout.isWide(size: CGSize(width: 669, height: 951), horizontal: .regular, typeSize: .large)) }
@Test func sidewaysInnerDisplayIsWide() { #expect(DuoLayout.isWide(size: CGSize(width: 951, height: 669), horizontal: .regular, typeSize: .large)) }
@Test func compactWidthIsNeverWide() { #expect(!DuoLayout.isWide(size: CGSize(width: 951, height: 669), horizontal: .compact, typeSize: .large)) }
@Test func accessibilitySizesStaySingleColumn() { #expect(!DuoLayout.isWide(size: CGSize(width: 951, height: 669), horizontal: .regular, typeSize: .accessibility3)) }
@Test func outerDisplayIsNotWide() { #expect(!DuoLayout.isWide(size: CGSize(width: 466, height: 678), horizontal: .compact, typeSize: .large)) }
```

- [ ] **Step 2:** Run `DuoLayoutTests` with XcodeBuildMCP. Expected: FAIL (`DuoLayout` not found).
- [ ] **Step 3:** Implement `DuoLayout.isWide` (`horizontal == .regular && size.width > size.height && !typeSize.isAccessibilitySize`), the two `@Entry` values and `duoReadableWidth()` in `DuoLayout.swift`.
- [ ] **Step 4:** In `DiaryRootView`, measure the window with `onGeometryChange(for: CGSize.self)` on `rootContent`. Read the real `horizontalSizeClass` and `dynamicTypeSize` there, and set `.environment(\.isWideLayout, wide)`. Also set `.environment(\.horizontalSizeClass, wide ? .regular : .compact)` on `rootTabs`, so upright and outer displays render the phone layout. Apply `.duoReadableWidth()` to each tab's root view inside its `NavigationStack`.
- [ ] **Step 5:** Run `DuoLayoutTests` plus the existing `DiaryUITests` and `CoachNavigationUITests` on a standard iPhone simulator. Expected: all pass, with no change on a normal iPhone.
- [ ] **Step 6:** On the Duo simulator, check Open upright: bottom tab bar, single column, content ≤ 700 pt. Check Open rotated: single column filling the width (wide layouts come in PR 2). Then fold and unfold with a Coach draft typed and a Diary day open: the draft, tab and day survive. Record screenshots and results in the verification note.
- [ ] **Step 7:** Commit `feat(duo): fill the iPhone Duo inner display`, run the Ponytail review, then open PR 1.

---

## PR 2 — `feat/duo-wide-layouts` (from `main` after PR 1 merges)

### Task 3: Sidebar when sideways

**Files:**
- Modify: `ios/Mivu/Diary/TodayView.swift` (`rootTabs`)
- Test: `ios/MivuUITests/DuoLayoutUITests.swift` (new)

**Interfaces:**
- Consumes: `isWideLayout`, `--wide-layout-ui-test` (Task 2).

- [ ] **Step 1: Write the failing UI test** `testSidewaysShowsSidebarWithAllFourDestinations`: launch with `["--diary-ui-test", UUID().uuidString, "--proof-english", "--wide-layout-ui-test"]` on any iPhone simulator (the flag makes the root report wide, which also sets the regular size class). Assert the sidebar buttons "Today", "Diary", "Progress" and "Coach" exist, that tapping "Coach" shows the Coach composer, and that the profile control exists.
- [ ] **Step 2:** Run it. Expected: FAIL (no sidebar).
- [ ] **Step 3:** Add `.tabViewStyle(.sidebarAdaptable)` and `.defaultAdaptableTabBarPlacement(.sidebar)` to the `TabView`. The compact override from Task 2 keeps the bottom tab bar whenever the layout isn't wide, so view identity never changes. Coach routing (`selectedTab`, `navigationRequest`, `openToday`) stays as is.
- [ ] **Step 4:** Run it plus `CoachNavigationUITests`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(duo): sidebar navigation when sideways`.

### Task 4: Two-column Today (A)

**Files:**
- Modify: `ios/Mivu/Diary/TodayView.swift` (`TodayView.body`, lines ~498–566)
- Test: `ios/MivuUITests/DuoLayoutUITests.swift`

- [ ] **Step 1: Write the failing UI test** `testSidewaysTodaySplitsSummaryAndMeals`: launch wide with the diary history fixture. Assert `todaySummaryColumn` and `todayMealsColumn` exist and `summary.frame.maxX <= meals.frame.minX`. Add `testUprightTodayStaysOneColumn` (no wide flag): `todayMealsColumn` doesn't exist.
- [ ] **Step 2:** Run both. Expected: the first FAILs.
- [ ] **Step 3:** Split `TodayView.body`'s sections into `@ViewBuilder private var summarySections` (sample banner, saved receipt, morning card, goal and summary cards, Pip note) and `mealSections` (meals, add meal). When `isWideLayout` is true, use `HStack(spacing: 0) { List { summarySections }; List { mealSections } }`, with identifiers `todaySummaryColumn` and `todayMealsColumn` and both lists carrying the existing list modifiers. Otherwise keep the single `List { summarySections; mealSections }`.
- [ ] **Step 4:** Run both plus `DiaryUITests`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(duo): two-column Today when sideways`.

### Task 5: Coach beside a live day (B)

**Files:**
- Modify: `ios/Mivu/Diary/TodayView.swift` (`rootTabs` Coach tab; `TodayView` meal rows)
- Test: `ios/MivuUITests/DuoLayoutUITests.swift`

**Interfaces:**
- Consumes: the existing `DiaryViewModel.captureReceipt: UUID?` and `TodayView`'s `savedMealID`.
- Produces: `TodayView(..., highlightsChanges: Bool = false)`.

- [ ] **Step 1: Write the failing UI test** `testSidewaysCoachShowsLiveDayAndHighlightsChange`: launch wide with `--coach-ui-test --coach-inference-fixture`. Open Coach, send "add a flat white", and assert that `coachLiveDay` exists and that a row with identifier `justChangedMeal` appears within 5 s. Add `testCoachCorrectionHighlightsEditedMeal` using the existing correction fixture (see `CoachCorrectionJourneyTests` / `CoachNavigationUITests` launch arguments): after the correction, `justChangedMeal` labels the edited meal.
- [ ] **Step 2:** Run both. Expected: FAIL.
- [ ] **Step 3:** In the Coach tab, when the layout is wide, use `HStack(spacing: 0) { CoachView(...); TodayView(model: model, companionOutput: CompanionOutput(pose: .resting, playback: .hidden, reactionID: nil, nextDeadline: nil), companionRuntime: companionRuntime, onCompanionContextChanged: { _ in }, highlightsChanges: true).environment(\.isWideLayout, false).accessibilityIdentifier("coachLiveDay") }`. The hidden output keeps Pip mounted only once.
- [ ] **Step 4:** In `TodayView`, when `highlightsChanges` is set and `model.captureReceipt` changes, mark the changed meal with an accent outline and identifier `justChangedMeal` for 3 s. Animate only when reduced motion is off. Find the changed meal from whatever the receipt already resolves to (read how `captureReceipt` is set in `DiaryViewModel` and `CoachViewModel`). If it doesn't identify a meal, outline the summary card instead of adding a data path.
- [ ] **Step 5:** Run both plus `CoachNavigationUITests` and the `CoachTimeline*` unit tests. Expected: PASS.
- [ ] **Step 6:** Commit `feat(duo): Coach beside a live day when sideways`.

### Task 6: Two-column Diary

**Files:**
- Modify: `ios/Mivu/Diary/HistoryView.swift` (`HistoryView.body`, day `NavigationLink` at line 49)
- Test: `ios/MivuUITests/DuoLayoutUITests.swift`

- [ ] **Step 1: Write the failing UI test** `testSidewaysDiaryShowsDayBesideList`: launch wide with `--diary-history-fixture`, open Diary, tap the first day row, and assert `DayHistoryView` content (`historyMeal`) is visible while the day list is still visible (no push).
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Add `@State private var selectedDay: UUID?` to `HistoryView`. When the layout is wide, show `HStack(spacing: 0) { <existing List>; DayHistoryView(model: model, dayID: selectedDay) }`, with taps setting `selectedDay` instead of pushing. It defaults to the newest day, and shows `ContentUnavailableView("Choose a day", systemImage: "calendar")` when there are no days. Compact keeps the existing `NavigationLink`.
- [ ] **Step 4:** Run it plus `DiaryUITests`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(duo): two-column Diary when sideways`.

### Task 7: Two-column Progress

**Files:**
- Modify: `ios/Mivu/Progress/ProgressView.swift` (`DiaryProgressView.body`, from line 175)
- Test: `ios/MivuUITests/DuoLayoutUITests.swift`

- [ ] **Step 1: Write the failing UI test** `testSidewaysProgressUsesTwoColumns`: launch wide with the history fixture, open Progress, and assert `progressPrimaryColumn` and `progressSecondaryColumn` sit side by side.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** As in Task 4, split the existing sections into a primary group (report controls, goal and trend charts) and a secondary group (weight, workouts, plateau). Wide uses two `List`s in an `HStack`; compact uses one `List`. There's no new selection model.
- [ ] **Step 4:** Run it plus existing Progress UI and unit tests. Expected: PASS.
- [ ] **Step 5:** On the Duo simulator, rotate through Today, Diary, Progress and Coach, fold and unfold with a draft typed, and repeat at `accessibility3`. Record screenshots, the SHA and counts in the verification note. Run the Ponytail review, then open PR 2.

---

## PR 3 — `feat/duo-tabletop-camera` (from `main` after PR 2 merges)

### Task 8: Half-folded posture signal

**Files:**
- Modify: `ios/Mivu/Design/DuoLayout.swift`, `ios/Mivu/Diary/TodayView.swift` (`DiaryRootView`)

**Interfaces:**
- Consumes: the SDK symbol names recorded in Task 1.
- Produces: `isHalfFolded` set from the root, true while the fold's `.division` reserved region is active.

- [ ] **Step 1:** If Task 1 found no public reserved-region or hinge API, stop. Record "D blocked: no public posture API in iOS 27.1 SDK" in the verification note and tell the owner.
- [ ] **Step 2:** In `DiaryRootView`, read the active `.division` region with the recorded API, and set `.environment(\.isHalfFolded, divisionActive)`. When `--tabletop-ui-test` is present (UI tests only), force it to true.
- [ ] **Step 3:** On the Duo simulator, press Book in Device Hub with a debug print. Expected: true in Book, false in Open and Closed. Remove the print and commit `feat(duo): detect half-folded posture`.

### Task 9: Half-folded meal snap camera (D)

**Files:**
- Create: `ios/Mivu/Diary/TabletopCamera.swift`
- Modify: `ios/Mivu/Diary/PhotoCapture.swift:168` (the camera sheet)
- Test: `ios/MivuTests/TabletopCameraTests.swift`, `ios/MivuUITests/DuoLayoutUITests.swift`

**Interfaces:**
- Consumes: `isHalfFolded`; `CameraCapture.preparePhoto(_:preparation:normalize:)`; `PhotoPreparation`.
- Produces: `struct TabletopCameraView: View { let preparation: PhotoPreparation; let onPhoto: (Data) -> Void; let onFailure: () -> Void }`, plus `enum TabletopCamera { static func availability(authorization: AVAuthorizationStatus, hasCamera: Bool) -> Availability }` with `enum Availability { case ready, needsPermission, denied, unavailable }`.

- [ ] **Step 1: Write the failing tests** in `TabletopCameraTests`:

```swift
@Test func authorizedWithCameraIsReady() { #expect(TabletopCamera.availability(authorization: .authorized, hasCamera: true) == .ready) }
@Test func notDeterminedAsksForPermission() { #expect(TabletopCamera.availability(authorization: .notDetermined, hasCamera: true) == .needsPermission) }
@Test func deniedOrRestrictedIsDenied() { #expect(TabletopCamera.availability(authorization: .denied, hasCamera: true) == .denied); #expect(TabletopCamera.availability(authorization: .restricted, hasCamera: true) == .denied) }
@Test func noCameraIsUnavailable() { #expect(TabletopCamera.availability(authorization: .authorized, hasCamera: false) == .unavailable) }
```

Add the UI test `testHalfFoldedPhotoSheetShowsTabletopLayout`: launch with `--tabletop-ui-test --coach-ui-test`, open the photo input's camera, and assert that `tabletopShutter` (a button labeled "Take photo", at least 44 pt) and `tabletopPrompt` exist. On the simulator (no camera), `tabletopUnavailable` shows the existing "Camera is unavailable here. Choose Photos instead." copy.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement `TabletopCamera.availability` and `TabletopCameraView`. The top half is the `AVCaptureVideoPreviewLayer` in a `UIViewRepresentable`, aspect-fill. The bottom half holds the shutter (`tabletopShutter`), Pip's prompt "Snap when ready." (`tabletopPrompt`) and a Cancel button. The capture output's `CGImage` and orientation go through `CameraCapture.preparePhoto`, so normalization and the limiter are shared. Handle permission, denial and no-camera through `availability`, with denial reusing PhotoInput's "Open Settings" alert copy. Stop the session on disappear.
- [ ] **Step 4:** In `PhotoInput`'s camera sheet: `if isHalfFolded { TabletopCameraView(preparation: preparation, onPhoto: …, onFailure: …) } else { CameraCapture(...) }`, with the same callbacks as today.
- [ ] **Step 5:** Run both test files plus `CoachCameraTests` and `CoachPhotoTests`. Expected: PASS.
- [ ] **Step 6:** On a real iPhone Duo if the owner has one (otherwise the simulator's Book pose, noting that it has no camera feed), half-fold, snap a synthetic plate photo and confirm it attaches. Record results and the SHA in the verification note, run the Ponytail review, then open PR 3.
