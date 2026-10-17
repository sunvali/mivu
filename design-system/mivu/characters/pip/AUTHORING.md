# Pip authoring handoff

Pip is the original orange fox with a cream muzzle, chest and tail tip, brown
eyes and paws, and a teal scarf. The approved identity is `reference.png`,
screen composition is documented in `context.png`, and `storyboard.png`
provides the pose source atlas. Preserve those approved painted pixels; the
editable source and rigging instructions are in
[`lottie-source/README.md`](lottie-source/README.md).

## Source and outputs

`lottie-source/build.py` authors independent image-layer joints and vector
masks over the original atlas. It produces the app's `pip.json` Lottie
animation and the unchanged `pip-artwork.png` atlas. The registered poses,
including grounded placement, are recorded in
`lottie-source/pose-registration.json`. `lottie-source/fallbacks.py` creates
the detailed transparent PNG static poses and preview used when animation is
unavailable or reduced motion is active.

`lottie-source/coach_pose.py` builds the distinct Coach pose from the exact
seated Pip crop in the approved `context.png`, with a check that all opaque
interior RGB remains identical to that source. It adds the `PipCoach` static
fallback and Coach resting/blink markers. The alternate generated Coach blink
image changed layout, scale and body colors and is rejected; only two small
hand-painted eye edits are used. The Coach face and body outside those eye
patches remain original context pixels. See the source and target eye boxes in
[`lottie-source/README.md`](lottie-source/README.md).

From the repository root, run the authoring scripts with Python 3, Pillow and
NumPy installed:

```sh
python3 design-system/mivu/characters/pip/lottie-source/build.py
python3 design-system/mivu/characters/pip/lottie-source/fallbacks.py
```

The generated app resources are under `ios/Mivu/Resources/Characters/pip/`;
static poses, including the context-matched `PipCoach`, live in
`ios/Mivu/Assets.xcassets/Companion/Pip/`. The source artwork and masks are
local bundled resources. There are no network images.

## Runtime and validation status

The app uses the official Airbnb Lottie iOS runtime 4.6.1 with Core Animation.
The authored JSON contains 81 image and joint layers on a 512×512 canvas,
including its Coach resting and blink poses.
The native unit suite passed 520 tests with 0 failures and 1 expected
interactive-authentication skip. Prior UI runs passed the new Coach composition
and largest-text checks. Full UI validation and broader visual/accessibility
review remain pending, as does physical-device performance acceptance.
Simulator results do not establish device frame time, power use or thermal
behavior.

`asset-manifest.json` records provenance, hashes and sizes for the original
references, runtime JSON, source atlas, matte, both eyelid patches, Coach pose,
all static fallback PNGs and the Coach authoring sources. Retain the reference
drawings, context sheet, storyboard, character sheet and prompt record when
refreshing generated outputs.
