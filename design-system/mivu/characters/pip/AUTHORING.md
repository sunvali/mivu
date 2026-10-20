# Pip authoring handoff

Pip is the orange fox with a cream muzzle, chest and tail tip, brown eyes and
paws, and a teal scarf. `reference.png` records identity, `context.png` records
screen composition, and `storyboard.png` is the painted pose reference the vector
rig was traced from. The app renders Pip as a native Core Animation rig; there is
no Lottie and no painted atlas at runtime.

## Source and outputs

`rig/pip.svg` is the editable source of truth (named parts, pivots, parents, pose
sets, head views, face shapes). `rig/build.py` converts it to
`ios/Mivu/Resources/Characters/pip/pip-rig.json`, which the app bundles; never
hand-edit the JSON. With `--png` it also writes the static fallback images in
`ios/Mivu/Assets.xcassets/Companion/Pip/`. Conventions and part lists are in
[`rig/README.md`](rig/README.md); the motion contract is in
[`MOTION.md`](MOTION.md).

From the repository root:

```sh
python3 -m venv .venv && .venv/bin/pip install cairosvg pillow   # once
.venv/bin/python design-system/mivu/characters/pip/rig/build.py --png OUT
.venv/bin/python design-system/mivu/characters/pip/rig/test_rig.py
```

Motion lives in Swift as data: `PipPose`, `PipGesture` and `PipGestureLibrary`
under `ios/Mivu/Design/`. To add a gesture, a moment or a rig part, follow
[`adding-a-gesture.md`](../../../../.agents/skills/mivu-animation/references/adding-a-gesture.md).
Review changes on a simulator with the `-PipRigPreview` launch argument.

## Constraints

Artboard 512x512, ground line y 472, content inside x 40-472 / y 32-472; readable
at 40, 64, 88 and 200 pt in light and dark. `pip-rig.json` should stay under
512 KiB (the loader rejects more than 1,048,576 bytes). Keep Pip the same fox as
`reference.png`.

## Provenance

`asset-manifest.json` records source and generated asset hashes and byte sizes.
It is not refreshed by the builder: update it after intended changes. Historical
validation blocks describe the retired Lottie pipeline and are not current
evidence. Current native results are recorded under `docs/verification/`.
