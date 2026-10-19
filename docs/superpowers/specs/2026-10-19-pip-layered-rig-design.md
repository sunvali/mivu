# Pip layered rig and reactive animation — design

Status: approved by the owner, 19 October 2026. Supersedes the painted-atlas
Lottie rig described in `design-system/mivu/characters/pip/MOTION.md` and
`lottie-source/README.md` once accepted.

## Intent

Pip should feel alive in the way Duolingo's characters do: every gesture answers
something the user just did, motion is fluid and interruptible, and small
moments (a glance, an ear flick, a reaction to a tap) make him feel like a
creature rather than a sticker. The owner asked for "all the gestures by what is
happening in the app" and is fine with rebuilding Pip completely to get there.

Why the rebuild: today Pip is one flat AI-generated painting cut into ~8 pieces
and nudged a few degrees. There is no art behind moving parts, no mouth or eye
shapes beyond one painted blink, and pose changes are cross-fades between
different paintings. Timing tweaks cannot get past that ceiling.

## Goals

1. A new layered vector Pip, redrawn by us from the existing paintings, with the
   same identity: orange fox, cream muzzle/chest/tail tip, brown eyes and paws,
   teal scarf, big pointed ears, same proportions and silhouette.
2. A native rig that can blend from any pose to any other at any moment, with
   anticipation, overshoot and follow-through (ears, tail, scarf).
3. A gesture for every meaningful app event (table below), driven by the
   existing companion signals plus a few new ones.
4. Idle life between events: blinks, glances, ear flicks, occasional yawn/stretch,
   so Pip is never frozen and never repeats an obvious loop.
5. Same Pip on Today (full body, 200 pt slot) and Coach (seated, 88 pt cropped).

## Non-goals

- Sound effects.
- Confetti, streak mechanics, point rewards or calorie-based praise.
- Additional characters (keep the catalog contract; Pip stays the only one).
- Hebrew/RTL work.

## Anti-goals (failure even if it technically works)

- Pip that no longer looks like Pip next to `reference.png`.
- Animation that delays a save, a button, navigation, scrolling or the keyboard.
- Motion that carries meaning on its own: native text still states saved/error.
- Celebrating or shaming food amounts.
- Work while hidden: no frames, timers or display links when Pip is off screen,
  covered, backgrounded, or stopped by policy.

## Constraints (unchanged from the current app)

- `MotionPolicy` stays the gate: Reduce Motion, Low Power Mode, serious/critical
  thermal state, hidden/covered/background → static pose, no timers.
- `CompanionPresentation` keeps its rules: submit feedback starts before the
  first await; saved only after durable local capture; profile isolation,
  receipt/attempt deduplication, 10 s feedback lifetime, newest fresh success
  only, priority policy > recovery > typing > fresh success > processing >
  greeting > rest.
- Decorative for VoiceOver (`accessibilityHidden`), 44 pt targets elsewhere
  untouched, Dynamic Type layouts unchanged.
- Safe artboard 512×512, ground line y 472, content x 40–472 / y 32–472
  (character sheet p.4). Must read at 40 / 64 / 88 / 200 pt.
- Light and dark appearance: same fur and scarf, authored contrast tweaks only.
- Repo rules: failing test first, XcodeBuildMCP for native builds/tests, feature
  branch + reviewed PR, Ponytail Review before merge.

## Decided

### Art: layered vector Pip, drawn by us

- Source of truth: one layered SVG, `design-system/mivu/characters/pip/rig/pip.svg`,
  traced over `reference.png` and the storyboard. Editable later in Figma or
  Illustrator by a human artist.
- Named groups, each with a pivot: `body`, `chest`, `head`, `ear-l`, `ear-r`,
  `brow-l`, `brow-r`, `eye-l`, `eye-r` (white, iris, pupil, highlight, upper
  lid, lower lid), `muzzle`, `nose`, `mouth`, `arm-l`/`forearm-l`/`paw-l`,
  `arm-r`/`forearm-r`/`paw-r`, `leg-l`, `leg-r`, `tail-1..4`, `scarf-knot`,
  `scarf-end-l`, `scarf-end-r`, `shadow`. Hidden areas (fur under arms, neck
  under head, ear bases) are painted in so any rotation looks right.
- Mouth set: closed smile, small open smile, big open smile, "o", flat/concerned,
  yawn. Eye set: open, half, closed-happy (∩), closed-sleepy, wide.
- Style: flat fills plus a few soft shade shapes per part, matching the
  painting's 2D vector look. Fur detail simplified at ≤ 64 pt (character sheet).
- `rig/build.py` converts the SVG to a compact `pip-rig.json` (parts, parent,
  pivot, z-order, path commands M/L/C/Q/Z, fills) bundled in the app. No
  hand-edited generated files.

### Runtime: native Core Animation rig, no Lottie

- `PipRig` builds a `CALayer` tree of `CAShapeLayer`s from `pip-rig.json`
  (a small path parser for M/L/C/Q/Z). No new dependency; Lottie is removed when
  the new rig ships, along with the atlas PNGs, matte, eyelid patches,
  `lottie-source/` and their tests.
- A **pose** is data: per-joint rotation/offset/scale plus which mouth/eye/brow
  shape is shown. A **gesture** is a short list of timed poses (anticipation →
  action → overshoot → settle).
- Joints move with `CASpringAnimation` starting from the presentation layer's
  current value, so any gesture can interrupt any other without a jump.
  Followers (ears, tail segments, scarf ends) use softer springs and a short
  delay to give follow-through. No per-frame app code for body motion.
- Face shapes swap or morph (`path` animation when point counts match).
- Idle life uses one scheduler (randomised 2–6 s beats: blink, glance, ear flick,
  weight shift; rarer yawn/stretch after ~30 s without input). It runs only while
  `MotionPolicy` says `.animated`, and is cancelled on every other state.
- Static pose (Reduce Motion etc.) = the same rig set to the pose with no
  animation. No separate static paintings needed; the rig is the fallback.
- Coach uses the same rig in a seated pose, cropped like today.

### Gestures by app event

Durations follow the character sheet's "brief reactions" timing where one exists.

| App event | Signal | Gesture |
|---|---|---|
| App opens / Today appears first time this session | existing greeting | Ears pop up, small hop, wave (~700 ms); morning variant adds a stretch, evening variant a softer wave |
| Typing a meal | existing `isTyping` (+ new: draft length tick) | Leans in, ears forward, eyes track along the text as it grows; occasional small nod |
| Camera / photo picker opens | new: Coach `showPhotos` | Peeks toward the camera, eyes wide, then a "snap" blink |
| Submit accepted | existing submission (≤100 ms) | Quick anticipation dip, nod, paw lift |
| Analysing | existing `isProcessing` | Paw to chin, eyes look up and side to side, tail swish; loops quietly |
| Saved locally | existing saved event | Happy ∩ eyes, nod, open paw, little bounce (~450 ms) |
| Correction reviewed | existing reviewed event | Grounded stretch, both paws up, smile (~650 ms) |
| Error / retry needed | existing `needsRecovery` | Ears droop, head tilt, open palm, calm mouth; then still. Never cheerful |
| Tap on Pip | new tap gesture | Rotating set: giggle squash, ear wiggle, look-at-you wink, spin of the tail; light haptic. Rapid taps escalate once, then he shakes it off |
| Left alone ~30 s | idle scheduler | Looks around, yawn, sits; after long idle on Today, curls up (wakes on any event) |
| Return from background | existing attach | Little startle-and-smile instead of the full greeting |

### Testing

- Pure, controlled-time unit tests for pose/gesture selection and idle scheduler
  start/stop under every `MotionPolicy` state.
- Rig asset tests: JSON loads, every named part and face shape exists, pivots in
  bounds, ground at 472, size budget (< 512 KiB target, 1 MiB cap).
- Snapshot of each key pose in light/dark at 40/88/200 pt for visual review
  against `reference.png`.
- Existing `CompanionPresentation`, receipt and mount tests keep passing.
- Native UI journey and recordings per `.agents/skills/mivu-animation/references/verification.md`.

### Delivery order

1. **Head spike (owner checkpoint).** Redraw head, ears, eyes, mouth set; show
   blink, glance, talk, ear flick next to the painting. Owner approves the look
   before the body is drawn.
2. Full body art + `build.py` + `pip-rig.json` + rig asset tests.
3. `PipRig` runtime, springs, gestures, idle scheduler, policy wiring; swap
   `CompanionRuntime`'s Lottie player for the rig.
4. New signals (draft length, photo picker, tap, background return) and the
   remaining gestures.
5. Remove Lottie and painted atlas; update MOTION.md, rig README and the
   mivu-animation skill.
6. Full native verification, recordings, PR.

### Calls made by the designer (owner may override)

- **Drawing method:** auto-trace `reference.png` (vtracer/potrace) only as an
  underlay for shape and proportion; every shipped part is hand-authored Bézier
  in the SVG. The head spike is the look checkpoint; expect one or two revision
  rounds there.
- **Alternate part sets:** the SVG carries swappable sets, not just face
  shapes: `standing` (default), `seated` (Coach, idle sit) and `curled` (long
  idle on Today) variants of legs, body and tail. The JSON schema and asset tests
  cover part sets. Tail "spin" becomes a tail flick within the standing set.
- **Camera:** no animation while the photo cover is up (it stays hidden). On
  return Pip does a curious lean toward the new photo. Opening the camera is
  never delayed.
- **New signals in priority order:** policy > recovery > typing > fresh success >
  processing > tap > greeting > idle beats > rest. During recovery or
  processing a tap gets only an ear twitch, never a playful reaction. Any tap or
  app event resets the idle timer and wakes a curled Pip.
- **Tap is decorative:** tap-only, stays hidden from VoiceOver because it carries
  no information. Its hit area is Pip's own frame, separate from the composer.

## Left to the builder

- Exact spring stiffness/damping per joint, idle beat weights, and tap reaction
  order — tune by eye on device.
- Whether mouth shapes morph or swap, per shape pair.
- How the asset-load failure case shows (rig failing to decode is near
  impossible since it is bundled; a single exported PNG of the resting pose is
  acceptable).

## Owner decisions (19 October 2026)

1. **Motion limits loosened.** The character sheet's caps (6° nod, 8° tilt, ≤3%
   squash, no leap, still rest) no longer apply. Pip may bounce, hop, squash up to
   ~10%, and breathe gently at rest. Feet still land on the ground line and he
   stays inside the 512 artboard.
2. **Cute, affectionate, empathetic.** The owner wants Pip to feel alive and win
   the user's affection; slightly over-the-top love gestures are welcome. The
   builder may add gestures beyond the table when they serve that.
3. **Habit celebrations allowed** (designer's call, owner delegated): celebrate
   logging habits, never food amounts. No confetti, points or streak counters.
4. **Visibility** (designer's call, owner delegated): Coach shows the full seated
   Pip in its existing strip (the seated set fits 76×66 without cropping paws or
   tail), so Coach reactions are fully visible. Today layout is unchanged.

### Affection and habit gestures (added)

| Moment | Signal | Gesture |
|---|---|---|
| First meal saved today | new: first saved event of the local day | Heart eyes, happy wiggle, one small heart pops above his head |
| Every meal of the day logged | new: `DayCompleteness` becomes complete | Both paws up cheer, little hop, blush, two hearts |
| Head pat | new: long-press or slow drag on Pip's head | Leans into the hand, eyes close (∩), blush, tail wags, a heart drifts up; let go → happy shake |
| Return after a day or more away | new: last active date ≥ 1 day ago | Ears droop with puppy eyes for a beat, then bursts into a joyful wave |
| Error / retry | existing `needsRecovery` | Adds a supportive "it's okay" paw over his heart after the tilt; still never cheerful |
| Long idle | idle scheduler | Hugs his tail, rests his chin on it, slow sleepy blinks before curling up |

Hearts and blush are small rig layers (hidden by default), not a particle system.
All new moments follow the same priority order (affection and habit moments rank
with fresh success) and the same policy, lifetime and deduplication rules.
