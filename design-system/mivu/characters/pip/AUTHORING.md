# Pip authoring handoff

Pip is the original illustrated orange fox with a cream muzzle, chest and tail
tip, brown eyes and paws, and a teal scarf. `reference.png` records identity,
`context.png` records screen composition, and `storyboard.png` supplies the
painted pose atlas. Preserve those painted pixels and identity. Rig and render
instructions are in [`lottie-source/README.md`](lottie-source/README.md).

## Source and outputs

`lottie-source/build.py` authors independent image-layer joints, masks and
continuous motion over the original atlas. It produces the app's `pip.json`
Lottie animation and unchanged `pip-artwork.png` atlas. `pose-registration.json`
records pose registration and grounding. `fallbacks.py` creates detailed
transparent PNG static poses for stopped or unavailable animation.

The runtime uses slow, continuous breathing and restrained ear, scarf and tail
movement. Chest/head breathing cycles take 4–5 seconds. Resting loops over 8
seconds and includes the painted blink. Attentive loops over 8 seconds with
quieter movement; thinking and recovery loop over 4 seconds. Submitted resolves
after 800 ms, saved after 800 ms of durable capture, reviewed after 1 second and
greeting after 1.2 seconds. Keep idle/typing paws grounded, ears asymmetric, and
tail/scarf follow-through visible.
The presenter has no separate idle blink timer. Apply all timeline updates
without UIKit view animation so unrelated atlas scenes cannot blend through
the character. Coach uses one registered seated rig with neutral joins and no
artwork dissolve. Submitted uses an explicit 80 ms snapshot bridge on both
surfaces. Other Today pose changes use 350 ms; surface changes use the native tab
transition without cross-surface artwork fading. Accepted submit feedback begins
before its first await using a separate profile/operation/attempt signal. A fresh
accepted retry receives a new transient attempt ID without changing durable
capture identity. Re-observing the same attempt does not replay it. Saved
feedback queues behind durable capture without delaying data work. Errors, typing,
hidden or background state, and Reduce Motion cancel stale feedback. An
approximately one-second cold load can outlast the 800 ms submitted reaction,
which then expires without replay. The separate 350 ms native focus and keyboard
sizing animation does not animate the Lottie layer tree.

Coach keeps the seated composition from the original `context.png` crop in all
states, including static fallback. Coach pose preparation and eye-patch source
details remain documented in `lottie-source/README.md`; retain the original
seated painting rather than substituting a new pose.

From the repository root, reproduce the authored resources with Python 3,
Pillow and NumPy:

```sh
python3 design-system/mivu/characters/pip/lottie-source/build.py
python3 design-system/mivu/characters/pip/lottie-source/fallbacks.py
```

The generated app resources are under `ios/Mivu/Resources/Characters/pip/`;
static poses live in `ios/Mivu/Assets.xcassets/Companion/Pip/`. Source artwork
and masks are bundled locally; there are no network images.

## Runtime and validation status

Coach-specific source QA at 88 pt: submitted face 2.507 pt and paw 1.687 pt;
saved face 2.474 pt and chest 2.214 pt. Today breathing is unchanged. These do not measure iPhone FPS. Coach shares one
painted rig; JSON changed from 162 layers / 976,470 bytes to 110 / 710,323 bytes
(SHA-256 `5a39809af6996b9a4c8eb6dc6a21776c90bf192de3071b35eeb75ac4dd54b06d`).
Original PNG and fallback bytes are unchanged. Current motion-pass counts and revision boundaries are recorded in
`docs/verification/2026-10-17-pip-idle-and-coach.md`; results below are historical.

The app uses Lottie iOS 4.6.1 with Core Animation. The current JSON is 710,323
bytes, has 110 layers on a 512×512 canvas, and stays below the 1 MiB runtime cap.
Coach uses the same seated source painting for every semantic state and its
static fallback.

Simulator motion and reference checks passed. Final native source `c0623c3`
passed 523 tests with 0 failures and 1 expected interactive sign-in skip;
the isolated cold-load regression/lifecycle run passed 47 checks, and the final
light/dark capture journey passed after that fix. The complete UI suite passed
37 tests with 0 failures/skips at `6707440`, before the isolated cold-load change.
The private draft is [#17](https://github.com/yakov103/mivu/pull/17). Physical
frame pacing, energy, thermals and manual phone acceptance remain pending.

`asset-manifest.json` records available source and generated asset provenance,
file sizes and hashes, along with the current Lottie layer count and markers.
