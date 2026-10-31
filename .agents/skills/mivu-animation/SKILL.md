---
name: mivu-animation
description: Use when changing or diagnosing Mivu companion animation, the Pip rig artwork, gestures and moments, Today/Coach pose transitions, character selection, motion accessibility, or animation verification.
---

# Mivu companion animation

Keep the layered vector Pip alive and readable at phone size, with interruptible
feedback and responsive native controls. Pip is a native Core Animation rig
(`CAShapeLayer` tree driven by springs) in SwiftUI; there is no Lottie and no
painted atlas. Lottie and Rive plans are historical. Paths below are repo-relative.

## Read and locate

- Visual authority: [character sheet](../../../design-system/mivu/characters/pip/character-sheet.pdf)
  and `reference.png` beside it. The motion caps in the sheet are loosened; the
  current contract is [MOTION.md](../../../design-system/mivu/characters/pip/MOTION.md).
- Authoring: [AUTHORING.md](../../../design-system/mivu/characters/pip/AUTHORING.md)
  and the [rig README](../../../design-system/mivu/characters/pip/rig/README.md).
- Adding a gesture, moment, part or face shape: [recipe](references/adding-a-gesture.md).
- Commands, test selection and evidence: [verification recipe](references/verification.md).

| Change | Owner |
|---|---|
| Parts, shapes, pivots, colours | `design-system/mivu/characters/pip/rig/pip.svg`, converted by `rig/build.py` |
| Generated rig and static fallbacks | `ios/Mivu/Resources/Characters/pip/pip-rig.json`; `ios/Mivu/Assets.xcassets/Companion/Pip/` (written by `build.py --png`); never hand-edit |
| Rig checks | `rig/test_rig.py` |
| Rig decoding and layer tree | `ios/Mivu/Design/PipRigAsset.swift`, `PipRigView.swift` |
| Pose data and joint helpers | `PipPose.swift`, `PipGesture.swift` |
| Gestures and moment mapping | `PipGestureLibrary.swift` |
| Idle beats | `PipIdleScheduler.swift` |
| Debug review screen | `PipRigPreview.swift` (launch with `-PipRigPreview`) |
| Timings | `MivuMotion.swift` |
| Semantic poses, priority, submission/receipt deduplication | `CompanionPresentation.swift` |
| Playback, moment mapping, idle, gaze, taps | `CompanionRuntime.swift` |
| Native mount, caption, fallback, keyboard sizing | `CompanionView.swift` |
| Eligibility | `MotionPolicy.swift` |
| Surface context and accepted/durable signals | `ios/Mivu/Diary/TodayView.swift`, `DiaryViewModel.swift`; `ios/Mivu/Coach/CoachView.swift`, `CoachViewModel.swift` |
| Future characters and persisted selection | `CharacterCatalog.swift`, `CompanionSelection.swift` |
| Android rig asset (reads the iOS `pip-rig.json` and `fixtures/pip/gestures.json` in place) | `android/app/src/main/java/com/yakov103/mivu/pip/PipRigAsset.kt`, `PipAssets` in `PipCompanion.kt` |
| Android scene and drawing | `pip/PipRigScene.kt`, `PipRig.kt` |
| Android motion (springs, gestures, idle) | `pip/PipMotion.kt`, `PipPose.kt`, `PipGestures.kt`, `PipIdleScheduler.kt`, `MivuMotion.kt` |
| Android runtime and presentation | `pip/CompanionRuntime.kt`, `CompanionPresentation.kt`, `PipCompanion.kt` |
| Android policy | `pip/MotionPolicy.kt` |
| Android preview (debug only) | `android/app/src/debug/java/com/yakov103/mivu/PipRigPreviewActivity.kt` |

## Make the change at its owner

Edit the SVG and run `build.py`; do not hand-edit generated JSON. Keep Pip the
same orange fox as `reference.png`: ground line y 472, content inside x 40-472 /
y 32-472, readable at 40, 64, 88 and 200 pt. Gestures are data in
`PipGestureLibrary`; the validation tests and preview pick a new entry up
automatically. Feet always land back on y 472.

Priority: policy > recovery > typing > fresh success (including affection and habit
moments) > processing > tap/pat > greeting > idle beats > rest. Never celebrate or
comment on food amounts; no confetti, points or streak counters.

Accepted submission starts before the first data await; saved feedback follows
durable local capture. Neither blocks data work. Background persistence locks do
not imply a user gesture: untouched Today must stay resting during empty recovery.

Honor hidden/covered/background state, Reduce Motion, Low Power Mode and serious or
critical thermal state: show the static pose, with zero animations and zero timers
(the idle scheduler stops too). Cancel obsolete feedback. Pip stays
`accessibilityHidden(true)`; native text carries status, and tap/pat are decorative.
Preserve profile isolation and receipt identity.

Pip remains the only launch character. When another character is requested, extend
the catalog/selection contract with unique IDs, supported schema and fallbacks;
retain unknown-ID fallback to Pip and one-item chooser suppression.

## Finish with evidence

Follow the verification recipe for the changed owner. Review compact and full-size
native pixels in both appearances (`-PipRigPreview`, snapshots). Update provenance
in `asset-manifest.json` for changed assets, and record the tested revision,
environment, counts and limits. Historical reports and recordings do not establish
current native or hardware performance. Documentation-only edits need link/skill
validation, not a rebuild.
