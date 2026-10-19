# Pip Layered Rig Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the painted-atlas Lottie Pip with a hand-drawn layered vector Pip driven by a native Core Animation rig, so every app event and touch gets a cute, interruptible, empathetic gesture.

**Architecture:** One layered SVG (art source) → `rig/build.py` → bundled `pip-rig.json` → `PipRigView` (a `CALayer` tree of `CAShapeLayer`s). Poses are data; gestures are timed pose lists applied with `CASpringAnimation` from the presentation value, so anything interrupts anything. `CompanionPresentation` (pure) still decides *what* plays; `CompanionRuntime` keeps its public API but drives the rig instead of Lottie. Idle life comes from one pure scheduler that only runs while `MotionPolicy` says `.animated`.

**Tech Stack:** Swift 6 / SwiftUI / UIKit / Core Animation, Swift Testing, XCUITest; Python 3 (stdlib + `cairosvg` for PNG export, installed into `.venv` at repo root); XcodeBuildMCP for native build/test/simulator.

**Spec:** `docs/superpowers/specs/2026-10-19-pip-layered-rig-design.md`

## Global Constraints

- Identity: orange fox, cream muzzle/chest/tail tip, brown eyes and paws, teal scarf, big pointed ears; must read as the same Pip as `design-system/mivu/characters/pip/reference.png`.
- Artboard 512×512, ground line y 472, content inside x 40–472 / y 32–472. Must read at 40 / 64 / 88 / 200 pt.
- Motion caps loosened: squash ≤ 10%, hops allowed, gentle breathing at rest; feet always land back on y 472.
- `pip-rig.json` target < 512 KiB, hard cap 1,048,576 bytes (loader rejects larger).
- `MotionPolicy` gate unchanged: Reduce Motion, Low Power, serious/critical thermal, hidden/covered/background → static pose, zero animations, zero timers.
- `CompanionPresentation` rules unchanged: submit feedback before first await; saved only after durable capture; profile isolation; dedupe by profile/operation(/attempt); 10 s `MivuMotion.feedbackLifetime`; newest fresh success only.
- Priority: policy > recovery > typing > fresh success (incl. affection/habit moments) > processing > tap/pat > greeting > idle beats > rest.
- Never celebrate or comment on food amounts; no confetti, points or streak counters.
- Pip stays `accessibilityHidden(true)`; native text carries all status. Tap/pat are decorative extras.
- Animation never delays a write, button, navigation, scroll or keyboard.
- Repo rules (AGENTS.md): failing test first; XcodeBuildMCP for native builds/tests; Conventional Commit messages; no mention of codex/ai in commits/PRs; record source SHA, environment and counts as evidence.

## Review Focus

1. **Interrupt mid-gesture** (submit while the tap giggle plays, typing during a hop): the new gesture starts from where Pip visibly is — no snap. Test: `PipRigViewTests.interruptStartsFromPresentationValue` (Task 4).
2. **Policy flips mid-animation** (Reduce Motion toggled, app backgrounded during a hop): all animations removed, rig shows the static pose, idle scheduler cancelled. Test: `CompanionRigRuntimeTests.policyChangeMidGestureLeavesNoAnimationsOrTimers` (Task 7).
3. **Rapid taps / pat spam**: escalates once then the shake-off; never queues a backlog of reactions. Test: `CompanionPresentationTests.rapidTapsEscalateOnceThenShakeOff` (Task 6).
4. **Day rollover and duplicate saves**: first-meal-of-day fires once per profile per local day, not again on relaunch or re-observation. Test: `DiaryCompanionMomentTests.firstMealOfDayFiresOncePerLocalDay` (Task 8).
5. **Accessibility sizes / dark mode**: Pip remains inside its frame at 144 pt accessibility size, dark palette keeps contrast. Test: `PipRigSnapshotTests.allSetsFitArtboardInBothAppearances` (Task 3).

---

## File Structure

| Path | Responsibility |
|---|---|
| `design-system/mivu/characters/pip/rig/pip.svg` | Art source: named, pivoted groups; editable in any vector tool |
| `design-system/mivu/characters/pip/rig/build.py` | SVG → `pip-rig.json`; exports fallback PNGs |
| `design-system/mivu/characters/pip/rig/test_rig.py` | Python checks of the generated rig |
| `design-system/mivu/characters/pip/rig/README.md` | Part naming, pivots, how to edit and rebuild |
| `ios/Mivu/Resources/Characters/pip/pip-rig.json` | Generated runtime rig |
| `ios/Mivu/Design/PipRigAsset.swift` | Decodable rig + validation + SVG path → `CGPath` |
| `ios/Mivu/Design/PipRigView.swift` | Layer tree, `apply(pose:animated:)`, breathing, face shapes |
| `ios/Mivu/Design/PipPose.swift` | `PipPose`, `PipGesture` types and the spring player contract |
| `ios/Mivu/Design/PipGestureLibrary.swift` | The gesture catalogue: one entry per gesture, and the single moment → gesture map (the only file to edit when adding a gesture) |
| `ios/Mivu/Design/PipIdleScheduler.swift` | Pure idle beat selection with injected clock/RNG |
| `ios/Mivu/Design/CompanionPresentation.swift` | + new moments, touch, welcome-back |
| `ios/Mivu/Design/CompanionRuntime.swift` | Same API; drives `PipRigView` instead of Lottie |
| `ios/Mivu/Design/CompanionView.swift` | Mounts rig, tap/pat gestures, haptics |
| `ios/Mivu/Design/CharacterCatalog.swift` | Pip descriptor → schema 2, `pip-rig.json` |

Removed in Task 9: Lottie SPM package, `pip.json`, `pip-artwork*.png`, `pip-*eyelids.png`, `pip-coach.png`, `lottie-source/`, `CompanionLottie*Tests.swift`, `CompanionArtworkMatteTests.swift`, `CompanionArtworkImageProvider.swift`, imagesets other than `PipResting`, `PipCoach`, `PipPreview`.

---

### Task 1: Rig format, build pipeline and Pip's head art

**Files:**
- Create: `design-system/mivu/characters/pip/rig/pip.svg`, `rig/build.py`, `rig/test_rig.py`, `rig/README.md`
- Create (generated): `ios/Mivu/Resources/Characters/pip/pip-rig.json`

**Interfaces:**
- Produces `pip-rig.json`:
  ```json
  {"version": 2, "artboard": 512, "ground": 472,
   "frames": {"today": [x,y,w,h], "coach": [x,y,w,h]},
   "parts": [{"id": "head", "parent": "body", "pivot": [x,y], "z": 40,
              "set": null, "shape": null, "visible": true,
              "fill": "#E8833A", "fillDark": "#E8833A", "path": "M… C… Z"}]}
  ```
  `set` ∈ `standing|seated|curled|null` (null = shared). `shape` names a face alternative (`mouth.smile`, `eye-l.closedHappy`…); only the default shape has `visible: true`. One entry per drawn shape with a unique `id`; shading shapes are child parts (e.g. `head.shade`) grouped via `parent`.
- SVG convention: each `<g id="…" data-pivot="x y" data-set="…" data-shape="…">`; paths use only M/L/C/Q/Z absolute commands (build.py normalises with `svgpathtools` or a small converter — choose stdlib if the authored SVG already uses absolute commands).
- Head part ids (required now): `head, ear-l, ear-r, ear-inner-l, ear-inner-r, muzzle, nose, brow-l, brow-r, eye-l, eye-r, iris-l, iris-r, pupil-l, pupil-r, glint-l, glint-r, lid-upper-l, lid-upper-r, cheek-blush-l, cheek-blush-r`; mouth shapes `mouth.closedSmile, mouth.smallOpen, mouth.bigOpen, mouth.o, mouth.concerned, mouth.yawn`; eye shapes per eye `open, half, closedHappy, closedSleepy, wide, heart`.

- [ ] **Step 1: Set up tooling.** `python3 -m venv .venv && .venv/bin/pip install cairosvg pillow`; add `.venv/` to `.gitignore` if absent.
- [ ] **Step 2: Write failing `test_rig.py`** (stdlib `unittest`) with:
  - `test_head_parts_present`: every required head id and every mouth/eye shape exists in `pip-rig.json`.
  - `test_pivots_inside_artboard`: all pivots within 0…512.
  - `test_one_default_shape_per_slot`: for each slot (`mouth`, `eye-l`, `eye-r`) exactly one shape has `visible: true`.
  - `test_size_budget`: file < 524,288 bytes.
  - `test_paths_use_supported_commands`: every `path` matches `^[MLCQZ0-9.,\s-]+$`.
- [ ] **Step 3: Run** `.venv/bin/python design-system/mivu/characters/pip/rig/test_rig.py` → FAIL (file missing).
- [ ] **Step 4: Draw the head** in `pip.svg` by hand-authoring Béziers over `reference.png` (trace the big waving Pip and the dark seated Pip for the ¾ face). Optionally run `vtracer` on a crop only as an underlay for proportions; do not ship traced paths. Fill the hidden areas (ear bases, neck under head). Palette sampled from `reference.png`.
- [ ] **Step 5: Implement `build.py`**: parse SVG with `xml.etree`, flatten group transforms, emit JSON sorted by `z`, write to `ios/Mivu/Resources/Characters/pip/pip-rig.json`; `--png` flag renders sets to PNG with `cairosvg` (used in Task 3).
- [ ] **Step 6: Run build then tests** → PASS.
- [ ] **Step 7: Commit** `feat(pip): add layered head rig source and build pipeline`.

### Task 2: Native rig rendering and the head spike (owner checkpoint)

**Files:**
- Create: `ios/Mivu/Design/PipRigAsset.swift`, `ios/Mivu/Design/PipRigView.swift`, `ios/Mivu/Design/PipPose.swift` (face part only for now)
- Create: `ios/MivuTests/PipRigAssetTests.swift`, `ios/MivuTests/PipRigViewTests.swift`
- Create: `ios/Mivu/Design/PipRigPreview.swift` (`#if DEBUG` SwiftUI preview + debug screen with buttons)

**Interfaces:**
- Produces:
  - `struct PipRigAsset: Decodable { let version: Int; let artboard: CGFloat; let ground: CGFloat; let frames: [String: CGRect]; let parts: [Part]; static func load(_ data: Data) throws -> PipRigAsset }` — throws `PipRigAsset.Error.{tooLarge, version, missingPart(String), badPath(String)}`; enforces 1,048,576 cap and `version == 2`.
  - `static func cgPath(_ svg: String) throws -> CGPath` (M/L/C/Q/Z).
  - `final class PipRigView: UIView { init(asset: PipRigAsset, set: PipPose.BodySet); func apply(_ pose: PipPose, animated: Bool); func removeAllMotion(); var isDark: Bool }`
  - `struct PipPose: Equatable { var joints: [String: Joint]; var eyes: EyeShape; var mouth: MouthShape; var brows: Joint?; var gaze: CGPoint; var blush: Bool; var hearts: Int; var set: BodySet; var headTurn: CGFloat }` (headTurn −1…1: |turn| ≤ 0.35 slides face features by each part's `parallax` factor within the current view; beyond that the head swaps to the `left`/`front`/`right` view — −1 left, 0 front, +1 right; `.rest` uses headTurn 1.0 = the default `right` view) with `struct Joint { var rotation: CGFloat = 0; var offset: CGPoint = .zero; var scale: CGSize = .init(width: 1, height: 1) }`, `enum EyeShape { open, half, closedHappy, closedSleepy, wide, heart }`, `enum MouthShape { closedSmile, smallOpen, bigOpen, o, concerned, yawn }`, `enum BodySet { standing, seated, curled }`, `static let rest: PipPose`.

- Rig JSON facts from Task 1 (see `design-system/mivu/characters/pip/rig/README.md`): parts carry `view` (`right|front|left|null`) and optional `parallax` (x factor); `visible` is already the *effective* default visibility (children of hidden shapes/views are false), so showing a shape or view must show its whole subtree; the parent tree is separate from draw order — order siblings by `z`; `head`'s parent `body` does not exist until Task 3 (treat a missing parent as root).

- [ ] **Step 1: Failing tests:**
  - `PipRigAssetTests.bundledRigLoadsAndHasHeadParts` — loads bundle `Characters/pip/pip-rig.json`, `version == 2`, contains `"pupil-l"`.
  - `PipRigAssetTests.rejectsOversizeWrongVersionAndBadPath` — 1,048,577-byte data → `.tooLarge`; version 1 → `.version`; path `"M 0 0 A 1 1"` → `.badPath`.
  - `PipRigAssetTests.cgPathParsesCubicAndQuadratic` — `"M0 0 C 10 0 10 10 0 10 Q 5 5 0 0 Z"` bounding box == `CGRect(0,0,7.5,10)` ±0.5.
  - `PipRigViewTests.restPoseShowsDefaultFaceShapesOnly` — after `apply(.rest, animated: false)`, the `mouth.closedSmile` layer is visible, `mouth.bigOpen` hidden, `eye-l.open` visible.
  - `PipRigViewTests.headTurnSwapsViewsAndSlidesFeatures` — headTurn 1.0 shows only `view: right` parts; −1.0 only `left`; 0 only `front`; 0.8 vs 1.0 moves `nose` x by parallax × offset while the head outline stays put.
  - `PipRigViewTests.gazeMovesPupilsWithinIris` — `gaze = (1, 0)` moves `pupil-l` x by > 0 and keeps pupil frame inside `iris-l` frame.
- [ ] **Step 2: Run** with XcodeBuildMCP test (scheme `Mivu`, only these suites) → FAIL.
- [ ] **Step 3: Implement** asset decode/validation, path parser, layer tree (one `CALayer` per part; `anchorPoint` from pivot; z via `zPosition`; parent hierarchy mirrors JSON), face shape switching, gaze mapping (pupil offset ≤ 35% of iris radius). `apply(animated: false)` wraps changes in `CATransaction.setDisableActions(true)`.
- [ ] **Step 4: Run tests** → PASS.
- [ ] **Step 5: Debug spike screen** `PipRigPreview` (DEBUG-only, reachable from the existing debug/settings path or a `#Preview`): head at 200 pt and 64 pt next to `reference.png` crop; buttons Blink, Glance, Talk (cycles mouth shapes 120 ms), Ear flick (uses simple springs — Task 4 formalises them).
- [ ] **Step 6: Record evidence:** boot simulator via XcodeBuildMCP, screenshot light/dark + a short screen recording to `docs/verification/pip-layered-rig/head-spike/`.
- [ ] **Step 7: Commit** `feat(pip): render layered head rig natively`.
- [ ] **Step 8: STOP — owner checkpoint.** Show the screenshots/recording side by side with the painting. Iterate on `pip.svg` until the owner approves the look. Do not start Task 3 before approval.

### Task 3: Full-body art, body sets and fallback images

**Files:**
- Modify: `rig/pip.svg`, `rig/build.py`, `rig/test_rig.py`
- Modify (generated): `pip-rig.json`; `ios/Mivu/Assets.xcassets/Companion/Pip/PipResting.imageset/*`, `PipCoach.imageset/*`, `PipPreview.imageset/*` (light + dark PNGs from `build.py --png`)
- Create: `ios/MivuTests/PipRigSnapshotTests.swift`

**Interfaces:**
- Adds part ids: `body, chest, chest-fluff, arm-l, forearm-l, paw-l, arm-r, forearm-r, paw-r, leg-l, leg-r, foot-l, foot-r, tail-1, tail-2, tail-3, tail-4, scarf-knot, scarf-end-l, scarf-end-r, shadow, heart-1, heart-2, heart-3`, with `standing`, `seated` and `curled` variants of `body`, `leg-*`, `foot-*`, `tail-*` (ids suffixed `@seated`, `@curled`).
- `frames.coach` crops the seated set so the whole seated Pip fits a 76×66 pt view.

- [ ] **Step 1: Failing Python tests:** `test_body_parts_present` (all ids above + set variants), `test_feet_on_ground` (lowest point of `foot-l`/`foot-r` in every set within ±2 of 472), `test_inside_safe_bounds` (union bounds per set within x 40–472, y 32–472), `test_coach_frame_contains_seated_set`.
- [ ] **Step 2: Failing Swift test** `PipRigSnapshotTests.allSetsFitArtboardInBothAppearances` — for each `BodySet` × light/dark, render `PipRigView` at 200 pt and 40 pt; assert union of visible sublayer frames is inside bounds and the image has non-transparent pixels in the head region (sanity, not pixel-matching).
- [ ] **Step 3: Draw** body, arms with elbows, legs, 4-segment tail, scarf ends, hidden fur, seated and curled sets (refs: storyboard row 4 col 4 sitting, `reference.png` curled), hearts and blush; dark-mode fill tweaks only where contrast needs it.
- [ ] **Step 4: Build, export PNGs, run Python + Swift tests** → PASS.
- [ ] **Step 5: Commit** `feat(pip): add full-body layered rig with seated and curled sets`.

### Task 4: Poses, springs and the gesture library

**Files:**
- Modify: `ios/Mivu/Design/PipPose.swift`, `ios/Mivu/Design/PipRigView.swift`
- Create: `ios/MivuTests/PipGestureTests.swift`; extend `PipRigViewTests.swift`

**Interfaces:**
- Produces:
  - `struct PipGesture { let name: String; let keys: [(at: TimeInterval, pose: PipPose)]; var duration: TimeInterval { keys.last!.at } }`
  - `enum PipMoment: Hashable { case greeting(hour: Int), welcomeBack, attentive, submitted, thinking, saved, reviewed, recovery, firstMealToday, dayComplete, curious, tapped(level: Int), patted, earTwitch }`
  - `static func PipGesture.for(_ moment: PipMoment) -> PipGesture` and `static func PipGesture.loopFor(_ moment: PipMoment) -> PipGesture?` (loops: attentive, thinking).
  - `PipRigView.play(_ gesture: PipGesture, completion: @escaping (Bool) -> Void)` — schedules each key as `CASpringAnimation` (per joint; followers `ear-*`, `tail-2…4`, `scarf-end-*` get stiffness × 0.6 and +40 ms delay), `fromValue` = presentation layer's current value; completion `false` if interrupted.
- Timings (spec): greeting ≈ 700 ms (prep 100 / lift 160 / wave 180 / settle 260); saved ≈ 450 ms (70/120/90/170); reviewed ≈ 650 ms (90/170/120/270); submitted ≤ 800 ms with first visible change ≤ 100 ms; thinking loop 1.4 s; recovery 200 ms tilt + paw-over-heart then still.
- Gesture content per the spec tables (greeting variants: hour 5–11 adds stretch, 19–4 softer wave; tapped levels 0–3 rotate giggle squash / ear wiggle / wink / tail flick, level 4 = shake-off; patted = lean in, closedHappy eyes, blush, tail wag, 1 heart; firstMealToday = heart eyes, wiggle, 1 heart; dayComplete = both paws up, hop, blush, 2 hearts; welcomeBack = droop + puppy (`wide`) eyes 400 ms then joyful wave; curious = lean toward camera side, `wide` eyes; earTwitch = single ear flick).

- Living eyes (owner asked that the eyes really move; Task 2 only slides the pupil inside the iris, which is barely visible):
  - Gaze moves the whole iris group (iris + pupil + glint) inside the eye white, clipped by the eye-white shape as a mask; the glint counter-shifts ~30% so the light source feels fixed. Pupil-in-iris reach stays as a small extra.
  - Blink is animated, not a shape swap: the upper lid sweeps down over ~70 ms, holds ~40 ms, opens over ~90 ms, with a tiny 3% eye squash; occasional double blink.
  - Eyes lead the head: on a gaze or head-turn change the eyes reach the target ~80 ms before the head finishes turning (Disney "eyes lead").
  - Saccades: gaze changes snap fast (~60 ms, slight overshoot) instead of drifting.
  - `PipRigView.blink()` and `PipRigView.look(at: CGPoint, animated: Bool)` are public so idle (Task 5) and typing (Task 7) can drive them.

- Extensibility (owner: adding gestures/moves later must be easy):
  - All gestures live in `PipGestureLibrary.swift` as `static let all: [PipGesture]`, each built with a small readable builder, e.g. `PipGesture("saved") { $0.at(0.07, \.nod(-6)); $0.at(0.19, \.pawUp(.right)); $0.settle(at: 0.45) }` — named joint helpers (`nod`, `tilt`, `earPerk`, `pawUp`, `hop`, `squash`, `tailWag`, `eyes`, `mouth`, `hearts`, `blush`, `look`) instead of raw joint dictionaries.
  - One `static func gesture(for moment: PipMoment) -> PipGesture` switch is the only mapping from app moments; variants (e.g. tap levels, greeting by hour) are picked there.
  - Validation tests iterate `PipGestureLibrary.all`, so any new gesture is automatically checked (ends at rest, ≤ 2 s unless a loop, squash/feet caps, unique name, recovery-safe faces) with no new test code.
  - `PipRigPreview` lists `PipGestureLibrary.all` automatically (one button per gesture), so a new gesture is immediately reviewable on the simulator.

- [ ] **Step 1: Failing tests:**
  - `PipGestureTests.everyLibraryGestureEndsAtRestWithinTwoSeconds` — iterates `PipGestureLibrary.all` (loops excluded): last key == `.rest` (same set), duration ≤ 2.0 s; names unique.
  - `PipGestureTests.everyMomentMapsToALibraryGesture` — for every `PipMoment` case, `gesture(for:)` returns a gesture contained in `all`.
  - `PipGestureTests.spokenTimingsMatchSpec` — greeting 0.70 ±0.01, saved 0.45 ±0.01, reviewed 0.65 ±0.01; submitted first key ≤ 0.1 and duration ≤ 0.8.
  - `PipGestureTests.squashAndFeetStayInCaps` — every key: joint scales within 0.9…1.1; `foot-*` offsets y ≤ 0 (never below ground) and final y == 0.
  - `PipGestureTests.recoveryIsNeverCheerful` — recovery keys never use `bigOpen`, `closedHappy`, hearts or blush.
  - `PipRigViewTests.gazeMovesIrisAcrossEyeWhite` — for both eyes, `look(at: (1,0), animated: false)` moves the iris group centre by ≥ 25% of the eye-white width and the iris layer has the eye-white mask; (−1,0) moves the other way.
  - `PipRigViewTests.blinkAnimatesUpperLid` — `blink()` adds a position/path animation on `lid-upper-l` and `lid-upper-r` with total duration 0.2 ±0.02 s and ends open.
  - `PipRigViewTests.interruptStartsFromPresentationValue` — play `saved`, after 0.2 s play `tapped(level: 0)`; first added animation's `fromValue` equals the head layer's presentation rotation at interrupt time (±0.001).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** library + `play`. **Step 4: Run** → PASS.
- [ ] **Step 5: Make `PipRigPreview` list `PipGestureLibrary.all` as buttons; screen-record all gestures to `docs/verification/pip-layered-rig/gestures/`.**
- [ ] **Step 6: Commit** `feat(pip): add spring-driven gesture library`.

### Task 5: Idle life and breathing

**Files:**
- Create: `ios/Mivu/Design/PipIdleScheduler.swift`, `ios/MivuTests/PipIdleSchedulerTests.swift`
- Modify: `PipRigView.swift` (breathing)

**Interfaces:**
- `struct PipIdleScheduler { enum Beat { blink, glance(CGPoint), earFlick, weightShift, yawn, stretch, hugTail, curlUp } ; init(random: some RandomNumberGenerator); mutating func next(after lastInput: Date, now: Date, surface: CompanionSurface) -> (beat: Beat, at: Date) }` — common beats every 2–6 s; `yawn`/`stretch` only after ≥ 30 s without input; `hugTail` then `curlUp` only on `.today` after ≥ 90 s; Coach never curls.
- `PipRigView.setBreathing(_ on: Bool)` — chest/head scale-y 1.00↔1.02, 4.5 s, autoreverse, repeat; one `CABasicAnimation` keyed `"breath"`.
- Idle beats map to small `PipGesture`s (`PipGesture.forIdle(_:)`).

- [ ] **Step 1: Failing tests** (seeded generator, fixed dates):
  - `PipIdleSchedulerTests.commonBeatsSpacedTwoToSixSeconds` — 200 draws, all `at - now` in 2…6.
  - `noYawnBeforeThirtySecondsOfQuiet`, `curlOnlyOnTodayAfterNinetySeconds`, `coachNeverCurls`.
  - `PipRigViewTests.removeAllMotionClearsBreathAndGestures` — after `setBreathing(true)` + `play`, `removeAllMotion()` leaves zero animation keys on every sublayer.
- [ ] **Step 2–4:** run (FAIL) → implement → run (PASS).
- [ ] **Step 5: Commit** `feat(pip): add idle beats and breathing`.

### Task 6: Presentation — new moments, touch and welcome back

**Files:**
- Modify: `ios/Mivu/Design/CompanionPresentation.swift`, `ios/Mivu/Design/MivuMotion.swift`
- Modify: `ios/MivuTests/CompanionPresentationTests.swift`

**Interfaces:**
- `CompanionPose` gains: `firstMealToday = 8, dayComplete = 9, curious = 10, tapped = 11, patted = 12, welcomeBack = 13`.
- `CompanionEvent.Kind` gains `firstMealToday, dayComplete, photoAdded` (deduped/expired exactly like `saved`; rank as fresh success; `photoAdded` → `.curious`).
- `CompanionOutput` gains `tapLevel: Int` (0 unless `.tapped`) and `typingProgress: Double` (0…1, passed through from context).
- `CompanionContext` gains `draftLength: Int` (typingProgress = min(1, draftLength / 60)).
- `func touch(_ kind: CompanionTouch, now: Date) -> Bool` with `enum CompanionTouch { tap, pat }` — returns `false` (caller does an ear twitch only) when recovery, typing or processing is active, or playback isn't `.animated`; taps within 1.5 s of the previous raise `tapLevel` 0→3, the 5th becomes level 4 (shake-off) and resets.
- `attach(profileID:existingEvents:existingSubmissions:now:lastActiveAt: Date? = nil)` — if `lastActiveAt` is ≥ 1 calendar day before `now`, the available greeting resolves to `.welcomeBack` instead of `.greeting`.
- `MivuMotion`: `firstMealToday = 1.0, dayComplete = 1.4, curious = 0.8, tapped = 0.6, patted = 1.2, welcomeBack = 1.6`; greeting 0.7, saved 0.45, reviewed 0.65 (spec timings).

- [ ] **Step 1: Failing tests:**
  - `tapDuringRecoveryOrProcessingOnlyTwitches` — `touch(.tap)` returns false; resolved pose stays `.recovery` / `.thinking`.
  - `rapidTapsEscalateOnceThenShakeOff` — 5 taps 0.3 s apart → tapLevels 0,1,2,3,4; 6th tap → 0; no reaction queue (one active reaction).
  - `freshSuccessOutranksTap` — tap then saved event → `.saved`.
  - `habitMomentsDedupeAndExpireLikeSaved` — same `firstMealToday` key twice → one reaction; event older than 10 s → ignored.
  - `welcomeBackAfterADayAway` — `lastActiveAt = now - 26h` → first resolve `.welcomeBack`; `now - 2h` → `.greeting`.
  - `typingProgressClampsAtSixtyCharacters`.
  - Existing presentation tests still pass.
- [ ] **Step 2–4:** run (FAIL) → implement → run (PASS).
- [ ] **Step 5: Commit** `feat(companion): add affection, habit and touch moments`.

### Task 7: Runtime swap to the rig, touch and Coach framing

**Files:**
- Modify: `ios/Mivu/Design/CompanionRuntime.swift`, `CompanionView.swift`, `CharacterCatalog.swift`
- Modify: `ios/Mivu/Coach/CoachView.swift:283-288` (frame), `ios/Mivu/Diary/TodayView.swift:569-575`
- Create: `ios/MivuTests/CompanionRigRuntimeTests.swift`; rewrite Lottie-specific cases in `CompanionAssetTests.swift`, `CompanionMountTests.swift`, `CompanionSurfaceTests.swift`, `CompanionRootIntegrationTests.swift`; update `CharacterCatalogTests.swift`

**Interfaces:**
- `CompanionRuntime` keeps: `isReady, loadFailed, isPaused, character, displayedPose, triggerCount, select(_:), attach(eligible:), apply(_:darkMode:surface:), reconcileMount(_:), stop(), fallbackAssetName(for:)`. `player` becomes `rig: PipRigView?`. `apply` maps `CompanionPose` (+ `tapLevel`, greeting hour from an injected `clock: () -> Date`) to `PipMoment`, plays it via `PipRigView.play`, returns to rest + breathing + idle scheduler on completion. Idle scheduler runs on a cancellable `Task` that exists only while eligible and `.animated`. New: `func earTwitch()`.
- `CharacterDescriptor` for Pip: `schemaVersion: 2`, `animationResourcePath: "Characters/pip/pip-rig.json"`; catalog precondition updated accordingly.
- `fallbackAssetName(for:)` → `"PipCoach"` on Coach, else `"PipResting"` (used only when the rig fails to load).
- `CompanionView` gains `var onTouch: (CompanionTouch) -> Void = { _ in }`; `.onTapGesture` → `.tap` + `UIImpactFeedbackGenerator(style: .light)`; `.onLongPressGesture(minimumDuration: 0.35)` → `.pat` + `.soft` haptic. Gestures attach only when playback is `.animated`. Stays `accessibilityHidden(true)`.
- Coach: `CompanionView(... size: 76, surface: .coach)` in a 76×66 frame using `frames.coach`, no clipping of paws/tail.

- [ ] **Step 1: Failing tests:**
  - `CompanionRigRuntimeTests.policyChangeMidGestureLeavesNoAnimationsOrTimers` — play `.dayComplete`, then `apply` with `.staticPose` → no animation keys on any rig layer, idle task cancelled, rig shows rest pose.
  - `hiddenRuntimeSchedulesNoIdleBeats` — after `stop()`, advancing an injected clock 60 s produces zero idle plays.
  - `oneShotReturnsToRestThenBreathes` — after `.saved` completes, `displayedPose == .resting` and `"breath"` animation present.
  - `greetingVariantFollowsHour` — clock at 08:00 → morning gesture name; 21:00 → evening.
  - `catalogResolvesPipRigSchemaTwo`.
  - Port each still-meaningful case from `CompanionAssetTests` (corrupt asset → fallback, rapid load cancellation, switch drops late load, repeated reaction advances `triggerCount`, appearance change doesn't retrigger).
- [ ] **Step 2–4:** run (FAIL) → implement → run (PASS) with XcodeBuildMCP, Companion* suites.
- [ ] **Step 5: Commit** `feat(companion): drive Pip with the native rig`.

### Task 8: App signals for the new moments

**Files:**
- Modify: `ios/Mivu/Diary/DiaryViewModel.swift` (near `:249` saved event), `ios/Mivu/Coach/CoachViewModel.swift` (near `:265-276`), `ios/Mivu/Coach/CoachView.swift` (`reportCompanionContext`, `onTouch`), `ios/Mivu/Diary/TodayView.swift` (attach/receive/refresh, `onTouch`)
- Create: `ios/MivuTests/DiaryCompanionMomentTests.swift`
- Modify: `ios/MivuUITests/CompanionUITests.swift`

**Interfaces:**
- `DiaryViewModel.companionHabitEvent: CompanionEvent?` — after a durable save: `.firstMealToday` when it is the first saved meal on that profile's active local day (operationID = the save's submissionID); `.dayComplete` when `activeDay.completeness` transitions to `.complete` (operationID = day ID). Emitted after the save commits; never blocks it.
- `CoachViewModel.companionPhotoEvent: CompanionEvent?` — `.photoAdded` when an attachment is accepted into the draft (operationID = `attachmentDraft.submissionID`).
- Coach context adds `draftLength: coach.draft.text.count`.
- Last active date: `UserDefaults` key `"companion.lastActive." + profileID.uuidString`, read on `attach`, written when the scene goes to background.
- Both views pass `onTouch: { touch in if !companion.touch(touch, now: Date()) { companionRuntime.earTwitch() }; refreshCompanion() }`.

- [ ] **Step 1: Failing tests:**
  - `DiaryCompanionMomentTests.firstMealOfDayFiresOncePerLocalDay` — two saves same day → one `.firstMealToday`; re-observing the same event doesn't re-emit; save on the next local day → fires again.
  - `dayCompleteFiresOnTransitionOnly` — partial→complete fires; complete→complete doesn't.
  - `photoAddedEmitsOncePerAttachment`.
  - `lastActiveRoundTripsPerProfile` — profile A's date never affects profile B.
  - UI: `CompanionUITests.tapOnPipDoesNotStealComposerFocus` — tap Pip in Coach, composer focus state unchanged; Pip has no accessibility element.
- [ ] **Step 2–4:** run (FAIL) → implement → run (PASS).
- [ ] **Step 5: Commit** `feat(companion): react to first meal, full day, photos and taps`.

### Task 9: Remove Lottie and the painted atlas; update docs

**Files:**
- Delete: listed under File Structure "Removed in Task 9"
- Modify: `ios/Mivu.xcodeproj/project.pbxproj` (remove `lottie-spm` package reference, product dependency and build file — lines ~11, 91, 178, 239, 584-600)
- Modify: `design-system/mivu/characters/pip/MOTION.md`, `AUTHORING.md`, `asset-manifest.json`, `.agents/skills/mivu-animation/SKILL.md`, `.agents/skills/mivu-animation/references/verification.md`

- [ ] **Step 1:** `grep -rn "Lottie\|lottie\|pip.json\|pip-artwork" ios .agents design-system` → list every reference.
- [ ] **Step 2:** Delete files and package; fix remaining references.
- [ ] **Step 3a: Agent and contributor files.** Update every agentic file to the new rig: `AGENTS.md` ("Companion animation work" section: native rig, no Lottie; Pip art source `rig/pip.svg`), `.agents/skills/mivu-animation/SKILL.md` (owner table, rules), `.agents/skills/mivu-animation/references/verification.md` (commands, suites), and add `.agents/skills/mivu-animation/references/adding-a-gesture.md`: a step-by-step recipe — (1) add the entry in `PipGestureLibrary.swift` with the builder, (2) if it is a new app event, add a `PipMoment` case + `CompanionPose`/event + priority slot in `CompanionPresentation`, (3) map it in `gesture(for:)`, (4) run the library tests (automatic), (5) review it in `PipRigPreview` (`-PipRigPreview`), (6) record evidence. Include a note on adding a new part/shape to `pip.svg` (ids, pivots, `build.py`, tests). Link the recipe from SKILL.md and AGENTS.md. Grep `.agents`, `AGENTS.md`, `CLAUDE.md`, `docs/development` for `Lottie|pip.json|lottie-source` and fix every live reference (leave historical docs).
- [ ] **Step 3:** Rewrite MOTION.md to the new contract (rig, moments table, timings, loosened caps, policy); skill owner table → `rig/pip.svg`, `rig/build.py`, `PipRigView`, `PipPose`, `PipIdleScheduler`; verification recipe → `.venv/bin/python rig/build.py --png && .venv/bin/python rig/test_rig.py` and the new Swift suites; manifest hashes for new files.
- [ ] **Step 4:** XcodeBuildMCP clean build + full `MivuTests` → PASS, zero Lottie symbols; repeat Step 1 grep → only historical docs.
- [ ] **Step 5: Commit** `refactor(pip): remove Lottie atlas pipeline`.

### Task 10: Native acceptance and PR

- [ ] **Step 1:** XcodeBuildMCP full `MivuTests` + `MivuUITests` on an iPhone simulator; record SHA, simulator/OS, pass/fail/skip counts in `docs/verification/2026-10-19-pip-layered-rig.md`.
- [ ] **Step 2:** Screen recordings light/dark of: launch greeting, Today save + first-meal hearts, Coach typing gaze → submit → thinking → saved, error recovery, tap escalation, head pat, idle to curl-up, Reduce Motion static.
- [ ] **Step 3:** Instruments (Core Animation / Animation Hitches) on device if connected: hitch time < 5 ms/s, idle CPU near zero when hidden; otherwise record as blocked.
- [ ] **Step 4:** Ponytail Review on the branch; fix blocking findings.
- [ ] **Step 5:** Push `feature/pip-layered-rig`, open PR titled `feat(pip): layered reactive Pip rig`, verify CI script/title checks.
