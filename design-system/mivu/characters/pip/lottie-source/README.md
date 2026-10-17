# Pip illustration rig

The original `../storyboard.png` is the painted artwork authority (SHA-256
`5bef0e0459bf52c26fde44170c4b9419d0d4e4154779f51b0d01fdd1fd9166e1`).
`../reference.png` defines identity and `../context.png` defines screen
composition. The approved PDF remains the authority for acting and composition.

`build.py` authors image-layer joints and masks over the original illustration.
It retains the painted fox identity and atlas, while moving the head, ears,
paws, tail and scarf gently around grounded feet. The Lottie composition is
512×512 with 110 layers. Its JSON is 710,323 bytes, within the app's exact
1 MiB (1,048,576 byte) cap.

| Marker | Duration | Acting |
|---|---:|---|
| resting | 8 s loop | Slow breathing, small ear/scarf/tail movement and embedded painted blink |
| attentive | 8 s loop | Quieter continuous movement while typing |
| thinking | 4 s loop | Restrained continuous movement while processing |
| recovery | 4 s loop | Calm, explanatory continuous movement so Pip stays alive |
| submitted / coach-submitted | 800 ms | Immediate ear perk, nod and paw lift; visible response targets the first 100 ms |
| saved | 800 ms | Gentle acknowledgment after durable capture, then resting |
| reviewed | 1 s | Gentle review acknowledgment, then resting |
| greeting | 1.2 s | Unhurried welcome, then resting |
| Coach states | Same timings | Original seated painting remains the pose in every state and fallback |

Apply Lottie timeline updates without UIKit view animation. UIKit view transitions
can interpolate unrelated atlas scenes and flash other Pip poses. Coach uses one
registered seated rig with neutral joins and no artwork dissolve. Today may fade
an explicit snapshot overlay over 350 ms; surface changes use the native tab
transition without cross-surface artwork fading. Native focus and keyboard sizing
may animate over 350 ms independently of the Lottie layer tree. The resting blink
is authored into the continuous loop; there is no presenter idle blink timer.
Use 4–5 second chest/head breaths, grounded idle/typing paws, asymmetric ears,
and tail/scarf follow-through. Keep motion gradual and readable, with grounded
feet and no abrupt movement.

Playback stops while Pip is hidden, covered, in the background, under Reduce
Motion or Low Power Mode, or at serious or critical thermal state. Static
fallback artwork remains available when animation stops or cannot load.

## Reproduce

Run `python3 design-system/mivu/characters/pip/lottie-source/build.py`, then
`python3 design-system/mivu/characters/pip/lottie-source/fallbacks.py` with
Pillow and NumPy installed. `pose-registration.json` records storyboard source
cells, bounds, scale and grounding. Native rendering and visual review are
needed to validate motion; marker metadata alone does not establish acceptance.

## Background and eyelid preparation

`matte-source.png` records the background-extraction authoring output. Only its
alpha is consumed as `pip-artwork-alpha.png`; the generated RGB was rejected.
The native image provider reconstructs foreground from the unchanged original
white-composited painting at load time. The source retains cream fur and white
eyes; image processing does not run on each animation frame.

`blink-source.png` is an eye-only edit of the original storyboard. Only two
small feathered eye regions are used in `pip-eyelids.png`, clipped to the
original character alpha. Other visible character pixels remain from the
original painted source.

## Coach pose provenance

Coach keeps the seated Pip shown in the approved `../context.png`, using the
original crop `(845, 612, 990, 754)`. `coach_pose.py` prepares the crop and
registered eye patches while retaining the original seated figure. The Coach
static fallback uses that same seated pose; all semantic states retain this
composition. The alternate generated Coach image is retained only as rejected
source material. See `asset-manifest.json` for recorded source boxes, hashes
and file sizes.

The source scripts and references are kept locally; runtime resources include
the original atlas, coverage matte, eyelid patches and authored JSON. Static
poses provide detailed artwork when motion is unavailable or disabled.

## Current verification notes

Coach shares one painted rig. JSON is now 110 layers / 710,323 bytes (SHA-256
`5a39809af6996b9a4c8eb6dc6a21776c90bf192de3071b35eeb75ac4dd54b06d`), reduced
from 162 / 976,470 bytes; original PNG and fallback bytes are unchanged. Source QA
at 88 pt Coach: submitted face 2.507 pt/paw tip 1.687 pt; saved face 2.474
pt/chest 2.214 pt. Today breathing is unchanged. These are not measured iPhone frame rates. Native submit
feedback starts before its first await in a separate profile/operation/attempt
signal; saved feedback waits for durable capture without delaying data work.
Submitted uses an explicit 80 ms snapshot bridge on both surfaces; other Today pose
changes use 350 ms. Cold load can take about one second, outlasting the 800 ms
submitted marker; expired feedback does not replay. Current motion-pass counts are recorded in
`docs/verification/2026-10-17-pip-idle-and-coach.md`.

## Historical baseline verification status

Simulator motion and reference checks passed. Final native source `c0623c3`
passed 523 tests with 0 failures and 1 expected interactive sign-in skip;
the isolated cold-load regression/lifecycle run passed 47 checks, and the final
light/dark capture journey passed after that fix. The complete UI suite passed
37 tests with 0 failures/skips at `6707440`, before the isolated cold-load change.
The private draft is [#17](https://github.com/yakov103/mivu/pull/17). Physical
frame pacing, energy, thermals and manual phone acceptance remain pending.
