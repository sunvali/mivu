---
name: mivu-animation
description: Use when changing or diagnosing Mivu companion animation, Pip artwork or Lottie assets, Today/Coach pose transitions, character selection, motion accessibility, or animation verification.
---

# Mivu companion animation

Keep the approved painted Pip alive and readable at phone size, with interruptible
feedback and responsive native controls. Shipping playback uses Lottie with Core
Animation and SwiftUI; Rive-era plans are historical. Paths below are repo-relative.

## Read and locate

- Visual authority: [character sheet](../../../design-system/mivu/characters/pip/character-sheet.pdf),
  `reference.png`, `context.png`, and `storyboard.png` beside it.
- Acting contract: [MOTION.md](../../../design-system/mivu/characters/pip/MOTION.md).
- Authoring: [AUTHORING.md](../../../design-system/mivu/characters/pip/AUTHORING.md)
  and [rig README](../../../design-system/mivu/characters/pip/lottie-source/README.md).
- Commands, test selection and evidence: [verification recipe](references/verification.md).

| Change | Owner |
|---|---|
| Today joints, masks, timing, atlas registration | `design-system/mivu/characters/pip/lottie-source/build.py` |
| Seated Coach crop, masks, joints, acting | `design-system/mivu/characters/pip/lottie-source/coach_pose.py`, called by `build.py` |
| Static poses | `lottie-source/fallbacks.py` in the same authoring directory |
| Generated playback resources | `ios/Mivu/Resources/Characters/pip/` |
| Generated static artwork | `ios/Mivu/Assets.xcassets/Companion/Pip/` |
| Semantic poses, submission/receipt deduplication | `ios/Mivu/Design/CompanionPresentation.swift` |
| Player, marker playback, transitions, loading | `ios/Mivu/Design/CompanionRuntime.swift` |
| Native mount, caption, fallback, keyboard sizing | `ios/Mivu/Design/CompanionView.swift` |
| Matte reconstruction and eligibility | `CompanionArtworkImageProvider.swift`, `MotionPolicy.swift` in that Design directory |
| Surface context and accepted/durable signals | `ios/Mivu/Diary/TodayView.swift`, `DiaryViewModel.swift`; `ios/Mivu/Coach/CoachView.swift`, `CoachViewModel.swift` |
| Future characters and persisted selection | `ios/Mivu/Design/CharacterCatalog.swift`, `CompanionSelection.swift` |

## Make the change at its owner

Edit the authoring recipe and regenerate; do not hand-edit generated JSON. Preserve
original painting, proportions and grounded joints. Coach uses one seated painting
for every state and fallback. Use slow chest/head breathing, asymmetric ears,
delayed scarf/tail motion and neutral gesture endpoints. Inspect beyond the eyes.

Accepted submission starts before the first data await; saved feedback follows
durable local capture. Neither blocks data work. Background persistence locks do
not imply a user gesture: untouched Today must stay resting during empty recovery.

Keep timeline updates outside UIKit view animation. Preserve the current explicit
snapshot bridges and native keyboard animation boundaries. Diagnose semantic state
and real displayed frames before changing playback to fix a flash. The idle blink
is embedded in the continuous loop, without a presenter blink timer.

Honor hidden/covered/background state, Reduce Motion, Low Power Mode and thermal
policy; cancel obsolete feedback and keep matching static art. Native text carries
status independently of motion. Preserve profile isolation and receipt identity.

Pip remains the only launch character. When another character is requested, extend
the catalog/selection contract with unique IDs, supported schema, complete markers
and fallbacks; retain unknown-ID fallback to Pip and one-item chooser suppression.

## Finish with evidence

Follow the verification recipe for the changed owner. Review compact/full-size
native pixels, complete loops and joins in both appearances. Update provenance for
changed assets, and record the tested revision, environment, counts and limits.
Historical reports and recordings do not establish current native or hardware
performance. Documentation-only edits need link/skill validation, not a rebuild.
