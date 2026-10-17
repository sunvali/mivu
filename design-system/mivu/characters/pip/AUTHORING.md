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
movement. Resting loops over 8 seconds and includes the painted blink. Attentive
loops over 6 seconds with quieter movement; thinking and recovery loop over 4
seconds. Saved, reviewed and greeting resolve after 1.5, 1.8 and 2.2 seconds.
Semantic pose changes cross-dissolve over 350 ms. There is no separate idle
blink timer in the presenter.

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

The app uses Lottie iOS 4.6.1 with Core Animation. The current JSON is 976,470
bytes, has 162 layers on a 512×512 canvas, and stays below the 1 MiB runtime cap.
Coach uses the same seated source painting for every semantic state and its
static fallback.

The 520-test native unit result predates the latest motion changes. Verification
of the latest source and runtime asset is pending, as are full UI validation,
broader visual/accessibility review and physical-device performance acceptance.
Simulator results do not establish device frame time, power use or thermal
behavior.

`asset-manifest.json` records available source and generated asset provenance,
file sizes and hashes, along with the current Lottie layer count and markers.
