# iPhone Duo support — verification

Spec: `docs/superpowers/specs/2026-10-29-iphone-duo-design.md`
Plan: `docs/superpowers/plans/2026-10-29-iphone-duo.md`

## Environment

- Xcode 27.1 (App Store), iPhoneOS27.1.sdk. Base: `origin/main` 5afd7931.
- XcodeBuildMCP is not available in this environment; native checks ran with `xcodebuild`, using `-testPlan Mivu SWIFT_VERSION=6.0`, as `scripts/ci/native.sh` does.
- `scripts/ci/native.sh` still pins a stable `Xcode_26*.app`. This PR doesn't change that hosted-recipe pin; the local runs below are separate evidence.

## SDK symbols (iOS 27.1)

- UIKit: `UIView.reservedRegions(kind: UIView.ReservedRegion.Kind, options: UIView.ReservedRegion.QueryOptions = []) -> [UIView.ReservedRegion]`, with kinds `.occlusion` and `.division`, option `.includeInactive`, and `ReservedRegion.isActive`, `.frame` and `.margins`.
- UIKit: `UIHingeInteraction(updateHandler: (UIHingeInteraction, UIHingeInteraction.Update) -> Void)`, where `Update.hinge: UIHinge?` has `UIHinge.status` (`.unknown`, `.closed`, `.partiallyOpen`, `.fullyOpen`) and `angle: CGFloat`.
- SwiftUI: `ArrangementView(primary:secondary:)` with `.arrangementViewStyle(.split / .overlay)` (`@available(anyAppleOS 27.1, *)`); `toolbarVerticalBehavior(_:)`; `defaultAdaptableTabBarPlacement(_:)` with `.sidebar`.

## Results

### PR 1: full screen (working tree on base 5afd7931; the commit SHA is recorded in the PR)

- `MivuTests/DuoLayoutTests`: RED first (`cannot find 'DuoLayout' in scope`), then 5/5 pass. iPhone 17 Pro, iOS 27.0 runtime, Xcode 27.1.
- `MivuUITests/DiaryUITests` + `CoachNavigationUITests` on the iPhone 17 Pro: 26/27 pass. The one failure, `DiaryUITests.testRedoSetupFromSettingsKeepsKeyboardNextAndDone`, can't find the `redoOnboarding` button, and fails identically on unmodified `5afd7931` (stashed run). It's pre-existing and not caused by this change.
- iPhone Duo simulator (iOS 27.1 runtime 24A94425), poses driven in Device Hub:
  - Closed (466×678 pt): full screen, no letterbox. `iphone-duo/closed-outer.png`
  - Open (951×669 pt, the default pose is wider than tall): full screen, no letterbox. The system moves the tab bar and profile control into its vertical bar on the right. `iphone-duo/open-sideways.png`
  - Open, rotated upright (669×951 pt): the normal phone layout with the bottom tab bar and one column; Today stayed selected through the rotation. `iphone-duo/open-upright.png`
- Not yet checked: fold/unfold while a Coach draft is typed (planned with the PR 2 layouts on the Duo).
- Observation for PR 2: the default open pose is landscape, and the system's vertical bar already acts as a navigation rail there.

### Final pass: source 6faf14c3 on base 5afd7931

Xcode 27.1, iPhoneOS27.1.sdk, local `xcodebuild -testPlan Mivu SWIFT_VERSION=6.0`.

**Normal iPhone: no regression found**

- The app is iPhone-only and portrait-only (`Shared.xcconfig`), so a phone can never be wide: a landscape test on iPhone 17 Pro Max stayed upright.
- Pixel comparison of base and branch, iPhone 17, iOS 27.0, same synthetic fixture. Today, Diary, Progress, Coach, camera, Coach after camera, keyboard, a logged receipt and Today after logging: the layout matches, and the only differing pixels (at most 0.24%) are Pip's blink and glance.
- iPhone 17, iOS 26.5: all of `MivuTests` plus Smoke, RootTabNavigation, Progress, SummaryCards, QuickLog, CoachNavigation, Coach and Diary UI suites: 1341 passed, 16 failed, 1 skipped.
  - 11 `AppleInferenceTests`/`FoodSourceTests`: need iOS 27, not available on this runtime.
  - 4 fail identically on base 5afd7931: `DiaryReportTests.summaryCountsEveryCalendarDayInTheRequestedRange`, `CoachUITests.testFixtureGoalsWeightWorkoutBudgetAndRelaunch`, `CoachNavigationUITests.testLegacyRowAndRepeatedCalendarChoicesKeepExactFirstTurns`, `DiaryUITests.testRedoSetupFromSettingsKeepsKeyboardNextAndDone`.
  - 1, `CompanionSurfaceTests.cameraCoverageRejectsAColdLoadAndConsumedReaction`, failed in the full run and passes alone on both base and branch.
- No normal iPhone runs iOS 27.1 here: that runtime is Duo-only, so `reservedRegions` wasn't exercised on a phone.

**iPhone Duo (iOS 27.1, 24A94425)**

- Book pose: `DuoLayoutTests` + `CoachChatLayoutTests` + `DuoLayoutUITests`: 17 passed, 4 skipped (upright-only), 0 failed.
- Rotated while half-folded, which is real table pose: `DuoLayoutUITests`: 7 passed, 1 skipped (sideways Diary), 0 failed.
- Book to table and back with a Coach draft: the app stayed open, the draft survived, and receipts laid out to the new width without clipping.
- Real table pose: Coach ends at the crease (373.5 pt view height) with the composer on the flat half.

**Not verified on this source**

- Closed pose and open-flat upright: Device Hub only; last checked before these commits.
- Device Hub fold/unfold with a draft: earlier pose changes there closed the app, with no crash report. Rotation doesn't.

**Known limits**

- Coach timeline rows stay 84 pt narrower than the composer in Book pose and sideways; three fixes failed and were reverted.
- Progress's chart card is taller than the standing half in table pose, so its bars need a scroll.
- The crease split has no automated test because a forced posture has no real crease.

**After review, source f739d4f6**

- The independent review found nothing blocking and no path that changes a normal iPhone. Its two cheap findings were fixed: the shutter is disabled during the table timer, which re-checks before firing, and a later change clears the live-day highlight. There's no automated test for the timer race, because the simulator has no camera.
- Duo table pose: `DuoLayoutUITests` 7 passed, 1 skipped. Book pose: `DuoLayoutTests` + `DuoLayoutUITests` passed, with 4 upright-only skips, 0 failed.
- iPhone 17, iOS 27.0: `SmokeUITests`, `RootTabNavigationUITests` and `QuickLogUITests`: 6 passed.
- Deferred, cosmetic and Duo only: entering or leaving table pose drops keyboard focus (the draft stays), and switching Progress or Today layouts resets scroll position.
