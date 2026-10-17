# Pip illustration rig

This source replaces the rejected simplified character. The original `../storyboard.png` is the painted artwork authority (SHA-256 `5bef0e0459bf52c26fde44170c4b9419d0d4e4154779f51b0d01fdd1fd9166e1`). `../reference.png` defines identity; `../context.png` defines screen composition. The approved PDF is `output/pdf/Mivu-Pip-Motion-Guide.pdf` in the primary artifact workspace.

`build.py` authors independent image-layer joints and vector masks over original illustration pixels. It preserves the original atlas byte-for-byte in `pip-artwork.png`. The joints move the head, ears, paws, tail and scarf; the feet remain grounded at artboard y472. Each semantic clip has a distinct original pose and a named marker. Core Animation runs the transforms; SwiftUI never publishes frame updates.

| Marker | Duration | Acting |
|---|---:|---|
| resting | held | Original quiet four-foot stance |
| blink | 150 ms | Painted eyelids close and reopen after twelve eligible resting seconds |
| attentive | 150 ms then held | Small head/ear settle; stays quiet during typing |
| thinking | 1,400 ms loop | Restrained head, ear, paw and tail movement |
| saved | 450 ms | Small nod and open-paw acknowledgment |
| reviewed | 650 ms | Brief raised-paw celebration, then rest |
| recovery | 200 ms then held | Gentle explanatory open paw; no success celebration |
| greeting | 700 ms | Short wave with restrained head, tail and scarf follow-through |
| coach-resting | held | Original seated Coach composition from `context.png` |
| coach-blink | 150 ms | Registered Coach eyelid patches close and reopen |

Use 100 ms interruptible transitions between semantic poses. The app cancels obsolete reactions, hidden playback and suspended loads. Saving and navigation never wait for a gesture. Reduce Motion and constrained power/thermal states show matching detailed static artwork.

## Reproduce

Run `python3 design-system/mivu/characters/pip/lottie-source/build.py`, then `python3 design-system/mivu/characters/pip/lottie-source/fallbacks.py` and `python3 design-system/mivu/characters/pip/lottie-source/coach_pose.py` with Pillow and NumPy installed. `pose-registration.json` records storyboard source cells, bounds, scale and ground. Native tests decode and render the actual bundled timelines with the pinned official Lottie runtime. Inspect native light/dark output and recordings; marker assertions alone are insufficient.

## Background and eyelid preparation

`matte-source.png` is the background-extraction authoring output. Only its alpha is consumed as `pip-artwork-alpha.png`; its generated RGB was rejected. The native image provider reconstructs premultiplied foreground from the unchanged original white-composited painting once at load. It removes neutral background glow, preserving opaque cream fur and white eyes. No image processing occurs per animation frame.

Extraction prompt: remove only the white background and gray ground shadows from the supplied 1536×1024 storyboard; preserve all sixteen original foxes at exact positions, sizes, poses, faces, shading and scarf colors; retain cream fur and white eyes, with real transparency and no edge fringe. The retained generated file documents coverage provenance, not a new character identity.

`blink-source.png` is an eye-only edit of the original storyboard: close both eyes of the top-left fox in the existing painted closed-eye style; preserve its face proportions, head angle, brows, mouth, nose, ears, pose and scarf, all fifteen other foxes, positions and canvas. No oval patches, borders or redesign. Only two small feathered eye regions are consumed in `pip-eyelids.png`, clipped to the original character alpha. All other visible character pixels remain original. Earlier flat eyelid experiments were rejected after native inspection.

## Coach pose and blink provenance

`coach_pose.py` registers the seated peek shown in the approved `../context.png`
using its original pixel crop `(845, 612, 990, 754)`. Edge coverage is
reconstructed against the dark app background `(13, 19, 22)`; an assertion
verifies every opaque interior RGB pixel exactly matches the context crop.
This produces `pip-coach.png`, its
small `pip-coach-eyelids.png` patch, two Lottie markers (`coach-resting` and
`coach-blink`), and the `PipCoach` static fallback.

`coach-blink-source.png` was generated with a different layout, scale and body
RGB, so that full image is rejected. The Coach figure, including its face and
body outside the eyes, comes from the original context crop. Only two small
hand-painted closed-eye edits are consumed, using these explicit source and
target boxes in full context-image coordinates:

| Eye | Source box | Target box |
| --- | --- | --- |
| Left | `(954, 654, 1007, 696)` | `(918, 676, 946, 702)` |
| Right | `(1030, 642, 1072, 676)` | `(954, 668, 975, 692)` |

The target patches are feathered and clipped to the original Coach pose alpha.
No generated body, face, framing or layout pixels are used. The complete
recipe and source hashes are recorded in `asset-manifest.json`.

Generated authoring sources are retained locally in this folder; shipping
resources contain the original atlas, coverage matte, small eyelid patches and
authored JSON. Static pose assets are detailed transparent PNGs registered to
the animation. Coach uses its distinct context-matched seated source pose.
