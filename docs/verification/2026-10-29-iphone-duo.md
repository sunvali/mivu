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
