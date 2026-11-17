# Pip Stickers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce 12 text-free, white-outlined Pip stickers (9 still, 3 animated) as WhatsApp, iMessage and generic files, rendered from the app's real rig.

**Architecture:** A Swift test in `MivuTests` renders each sticker with the
app's own `PipRigView` (`apply(_:animated: false)` + `layer.render(in:)`) to
raw 512 px transparent PNG frames. Stills are single poses. Animated stickers
are lists of per-frame `PipPose`s: two come from beat gestures baked by the
app's `PipBake.frames(of:loops:)`, and one (Good night) uses a computed
curled loop. A Python script (`design-system/mivu/stickers/pack.py`, Pillow)
adds the die-cut outline, fits each sticker to a consistent canvas and writes
every export. `check.py` validates the exports against platform limits.

**Tech Stack:** Swift Testing + UIKit/QuartzCore (iOS simulator via
XcodeBuildMCP); Python 3 + Pillow (repo `.venv`, which has WebP support);
`rig/build.py` (cairosvg) for rig art.

**Spec:** `docs/superpowers/specs/2026-11-15-pip-stickers-design.md`

## Global Constraints

- 12 stickers, ids and kinds fixed: `hi`★, `thanks`, `love-it`, `lol`, `ok`, `oops`, `good-night`★, `yum`, `hungry`, `hydrate`, `snack`, `you-got-it`★ (★ animated).
- No words on any sticker; symbols (hearts, zzz) allowed.
- White die-cut outline around the whole silhouette (Pip + props + symbols), transparent background, light-appearance fills only.
- WhatsApp: 512×512 WebP; still ≤ 100 KB; animated ≤ 500 KB, each frame ≥ 8 ms, total ≤ 10 s; tray 96×96 PNG ≤ 50 KB; 3–30 stickers per pack; still and animated in separate packs; 1–3 emoji per sticker.
- iMessage: 408×408 PNG (still) / APNG (animated), each ≤ 500 KB, transparent.
- Generic: 512×512 PNG per still; animated WebP + GIF per animated sticker.
- New rig art goes into `design-system/mivu/characters/pip/rig/pip.svg` as hidden-by-default parts. `rig/test_rig.py` passes and the app's Pip looks the same.
- No app (`ios/Mivu/`) behaviour change. Sticker code lives in `ios/MivuTests/` and `design-system/mivu/stickers/`.
- Never comment on food amounts; no confetti, points or streak counters.
- Branch `feat/pip-stickers`, Conventional Commit messages, no Claude/AI mention, PR to `main`.
- Read `.agents/skills/mivu-animation/SKILL.md` and `references/adding-a-gesture.md` before Task 1.

## Review Focus

1. **Animated sticker jitter:** a frame-by-frame crop or outline change makes Pip wobble. Use one fit box per sticker (union of all frames). Test: `test_animated_frames_share_one_fit_box` (Task 4).
2. **Loop seam:** the first and last frames of a looping sticker differ, so it pops on every loop. Test: `loopClosesWithinTolerance` (Task 3).
3. **Outline clipped by the canvas:** wide poses (arms up, props) push the white edge off the 512 canvas. Test: `test_outline_never_touches_canvas_edge` (Task 4).
4. **Holes and specks:** gaps between arm and body fill white unevenly, and stray anti-aliased pixels get outlined as dots. Test: `test_no_detached_outline_specks` (Task 4).
5. **Size limit overflow:** an animated WebP over 500 KB makes WhatsApp reject the whole pack. Test: `test_check_rejects_oversize_animated` (Task 5), and `check.py` on the real exports.

---

### Task 1: zzz art for Good night

**Files:**
- Modify: `design-system/mivu/characters/pip/rig/pip.svg` (add parts next to the existing `fx-*@upright` groups)
- Modify (generated): `ios/Mivu/Resources/Characters/pip/pip-rig.json` via `rig/build.py`
- Modify: `design-system/mivu/characters/pip/rig/test_rig.py`
- Modify: `design-system/mivu/characters/pip/asset-manifest.json` (provenance)

**Interfaces:**
- Produces: rig parts `fx-z-1@curled`, `fx-z-2@curled`, `fx-z-3@curled`, each with `data-set="curled"`, hidden by default, drawn above the head. `PipRigView.opacity` already shows an `fx-` part only when `pose.joints[part.id] != nil`, so no Swift change is needed. Letters are rounded "Z" glyph shapes in the cream/outline palette, sized small→large (about 18, 26, 34 rig units) and stacked up and to the right of the curled head.

The empty bowl needs no art: Task 2 hides the existing `prop-bowl.food@upright` layer.

- [ ] **Step 1: Write the failing test** in `test_rig.py`:

```python
def test_sleep_z_parts(self):
    for n in (1, 2, 3):
        part = self.by_id[f"fx-z-{n}@curled"]
        self.assertEqual(part["set"], "curled")
        self.assertFalse(part["visible"])
```

(Adapt `self.by_id` to however the suite indexes parts.)

- [ ] **Step 2: Run it and confirm it fails.** `.venv/bin/python design-system/mivu/characters/pip/rig/test_rig.py` → FAIL (KeyError `fx-z-1@curled`).
- [ ] **Step 3: Draw the three groups in `pip.svg`** using absolute `M L C Q Z` paths, one `<path>` per group, with `data-pivot` at each letter's centre. Keep them inside x 40–472 / y 32–472.
- [ ] **Step 4: Rebuild and test.** Run `.venv/bin/python design-system/mivu/characters/pip/rig/build.py --png build/pip-sets` and then `test_rig.py`. Expected: all pass. Fallback imagesets may be rewritten; `git diff --stat` must show only `pip-rig.json`, `pip.svg`, `test_rig.py`, the manifest, and no changed fallback PNG bytes (the parts are hidden).
- [ ] **Step 5: Run the existing native rig tests.** Use XcodeBuildMCP `test_sim` with `-only-testing:MivuTests/PipRigSnapshotTests` and `-only-testing:MivuTests/PipRigAssetTests`. Expected: pass, with result counts recorded.
- [ ] **Step 6: Commit.** `feat(pip): sleep z parts for the curled set`

### Task 2: Sticker catalog (still poses)

**Files:**
- Create: `ios/MivuTests/PipStickerCatalog.swift`
- Create: `ios/MivuTests/PipStickerExportTests.swift` (still half; Task 3 adds animated)

(The project uses file-system-synchronized groups, so new test files join `MivuTests` automatically.)

**Interfaces:**
- Produces:

```swift
struct PipSticker {
    enum Kind { case still(PipPose), animated(frames: [PipPose], fps: Double) }
    let id: String          // e.g. "yum"
    let emoji: [String]     // 1...3, e.g. ["😋", "🥗"]
    let kind: Kind
    var hidden: [String] = []   // layer ids hidden after apply, e.g. ["prop-bowl.food@upright"]
}
enum PipStickerCatalog { static let all: [PipSticker] }   // exactly the 12 ids, in lineup order
@MainActor func renderSticker(_ pose: PipPose, hidden: [String]) throws -> UIImage   // 512×512 @1x, transparent, light fills
```

- Poses are built from `PipPose.rest` with the existing helpers (`nod`, `tilt`, `earPerk`, `pawUp`, `eyes`, `mouth`, `blushing`, `hearts`, `holding`, `hop`, `squash`, `tailWag`, `look`…). Reuse a key or beat pose from the named library gesture where one exists. Sources:
  - `love-it`: `idle-hug-tail` key + `.hearts(3)`
  - `lol`: `tap-giggle` peak key
  - `ok`: `tap-wink` peak key
  - `yum`: `eat-yum` / `eat-bowl` beat with bowl
  - `hydrate`: `sip-water` sip beat
  - `snack`: `eat-apple` hold-up beat, `bites` 0
  - `thanks`, `oops`, `hungry`: new compositions. `hungry` holds the bowl with `hidden: ["prop-bowl.food@upright"]`, one paw toward the tummy, and a concerned mouth.
- Take a beat's pose through `PipBake.frames(of:loops:)` at the beat's time, or through `beat.pose` with `set` set as `PipRigView.play` does (`grounded ? resting : .upright`), so props mount correctly.

- [ ] **Step 1: Write the failing test** `catalogHasTheApprovedLineup`: assert that `PipStickerCatalog.all.map(\.id)` equals the 12 ids in Global Constraints order. Assert that `hi`, `good-night` and `you-got-it` are `.animated` and the rest are `.still`. Assert that every `emoji.count` is in `1...3`.
- [ ] **Step 2: Write the failing test** `stillsRenderInsideTheArtboard`: for every still, `renderSticker` returns 512×512, has ink, and has no ink outside x 40–472 / y 32–472. Reuse the `hasInk` approach from `PipRigSnapshotTests`; copy the helper, don't import it.
- [ ] **Step 3: Run both** with XcodeBuildMCP `test_sim -only-testing:MivuTests/PipStickerExportTests`. Expected: FAIL (types undefined).
- [ ] **Step 4: Implement the catalog and `renderSticker`.** Build `PipRigView(asset: PipRigAsset.load(bundled data), set: pose.set)` at 512×512, `isDark = false`, then `apply(pose, animated: false)`, then `layer(named:)?.isHidden = true` for each id in `hidden`, then render on a clear `UIGraphicsImageRenderer` (scale 1, `opaque = false`).
- [ ] **Step 5: Run the tests.** Expected: PASS.
- [ ] **Step 6: Commit.** `feat(stickers): still Pip sticker poses`

### Task 3: Animated stickers and frame export

**Files:**
- Modify: `ios/MivuTests/PipStickerCatalog.swift`
- Modify: `ios/MivuTests/PipStickerExportTests.swift`

**Interfaces:**
- Consumes: `PipSticker`, `renderSticker` (Task 2); `PipBake.frames(of:loops:)`, `PipBake.rate` (60); `PipGesture(beats:loops:_:)`.
- Produces: when the directory `<repo>/build/pip-stickers/frames/` exists (repo root found from `#filePath`, two levels up from `ios/MivuTests`), the test `exportFrames` writes for every sticker:
  - `frames/<id>/0000.png …` (still: one frame)
  - `frames/<id>/meta.json` = `{"id": "...", "emoji": [...], "animated": bool, "fps": number}`

  Otherwise it renders in memory only.
- Animated definitions:
  - `hi`: a sticker-local looping beat gesture on the upright stance. One paw raised and waving (2 swings), a smile, a slight lean, `loops: true`, total 1.2–1.6 s. Baked with `PipBake.frames(of:loops: true)`, mapped to poses as in `PipRigView.play`, and decimated 60→20 fps (every 3rd frame).
  - `you-got-it`: a looping beat gesture: both arms up, a hop (`lift`), `closedHappy` eyes, a `bigOpen` mouth, 1.0–1.4 s, baked and decimated the same way.
  - `good-night`: the curled set with sleepy eyes, 3.0 s at 20 fps. A breath is computed per frame as `sin(2π·t/3.0)` applied as a small `squash` (about 0.02). Each `fx-z-n@curled` joint drifts up and right and fades by key position, staggered by a third of the period, so the loop closes exactly.
  - Author new beat gestures with the same builder and parameters as `PipGestureLibrary` upright gestures. Do not add them to the app library.

- [ ] **Step 1: Write the failing test** `loopClosesWithinTolerance`: for each animated sticker, render frame 0 and the frame after the last (the wrap). Their per-pixel alpha mean difference is under 2 % of the frame-to-frame mean difference across the loop, so the seam is no bigger than a normal step. Also assert `frames.count / fps <= 10` and `1000 / fps >= 8`.
- [ ] **Step 2: Write the failing test** `exportFrames` as described in Produces. It asserts that the frame count matches the catalog for each sticker, and that every written PNG is 512×512 with alpha.
- [ ] **Step 3: Run them.** Expected: FAIL.
- [ ] **Step 4: Implement the three animated entries.**
- [ ] **Step 5: Run with export on.** `mkdir -p build/pip-stickers/frames`, then XcodeBuildMCP `test_sim -only-testing:MivuTests/PipStickerExportTests`. Expected: PASS, with 12 frame folders on disk.
- [ ] **Step 6: Make a frame strip.** Build a raw contact strip of every 3rd frame per animated sticker (a quick Pillow one-off in the scratchpad), look at it, and fix stiff or jittery motion before going on (bar: Duolingo-level fluency).
- [ ] **Step 7: Commit.** `feat(stickers): animated Pip stickers and frame export`

### Task 4: Outline and pack exports

**Files:**
- Create: `design-system/mivu/stickers/pack.py`
- Create: `design-system/mivu/stickers/test_pack.py` (synthetic images only)
- Create: `design-system/mivu/stickers/README.md`: the two commands (export test, then `pack.py`), and the output layout

**Interfaces:**
- Consumes: `build/pip-stickers/frames/<id>/{NNNN.png, meta.json}` (Task 3).
- Produces: `pack.py FRAMES_DIR OUT_DIR` writes to `OUT_DIR = design-system/mivu/stickers/exports`:

```
whatsapp/still/{<id>.webp, tray.png, contents.json}
whatsapp/animated/{<id>.webp, tray.png, contents.json}
imessage/{<id>.png | <id>.apng}
png/<id>.png        gif/<id>.gif        webp/<id>.webp   (animated only for gif/webp)
```

  `contents.json` follows WhatsApp's sample-app schema: `identifier` (`mivu-pip-still` / `mivu-pip-animated`), `name` ("Pip" / "Pip moves"), `publisher` "Mivu", `tray_image_file` "tray.png", `animated_sticker_pack` bool, `stickers: [{image_file, emojis}]`. The tray image is the `hi` still (first frame for animated) at 96×96.
- Functions (all pure on `PIL.Image`):
  - `outline(img: Image, width: int = 14) -> Image`: dilate alpha by `width` px (a round kernel, e.g. a blurred threshold), fill it white, and composite the original on top.
  - `fit_box(frames: list[Image]) -> tuple[int,int,int,int]`: the union of alpha bounds over all frames.
  - `place(img, box, size=512, margin=16) -> Image`: crop to `box`, scale to fit `size - 2*margin` keeping aspect, and centre on a transparent canvas.
  - Stage order: `outline` at 512 raw, then `fit_box` over the outlined frames, then `place`. This keeps the outline thickness the same across stickers within about ±20 %.
  - `remove_specks(alpha, min_area=40)` before outlining.

- [ ] **Step 1: Write the failing tests** in `test_pack.py` with synthetic shapes made by Pillow `ImageDraw`:
  - `test_outline_adds_white_ring`: a red disc gains a white ring of `width ± 2` px, and the centre stays red.
  - `test_animated_frames_share_one_fit_box`: two frames with discs at different x, after `place` with the shared box, keep a constant x offset between them.
  - `test_outline_never_touches_canvas_edge`: a shape that fills the frame, after outline + place, has zero alpha on the 1 px border.
  - `test_no_detached_outline_specks`: a disc plus a 2 px stray dot yields one connected alpha component.
  - `test_writes_whatsapp_contents`: two fake stills plus one fake animated sticker produce both `contents.json` files with correct `animated_sticker_pack` flags and emoji copied from meta.
- [ ] **Step 2: Run them.** `.venv/bin/python -m unittest design-system/mivu/stickers/test_pack.py` → FAIL.
- [ ] **Step 3: Implement `pack.py`.** Encoder settings: WebP stills lossless (or quality 90 if a file goes over 100 KB); animated WebP lossy at quality 75–85 with `duration` from fps and `loop=0`; APNG via Pillow `save(format="PNG", save_all=True)`; GIF with a transparency index and `disposal=2`. iMessage files are 408×408 resized from the 512 placement.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Run on the real frames.** `.venv/bin/python design-system/mivu/stickers/pack.py build/pip-stickers/frames design-system/mivu/stickers/exports`.
- [ ] **Step 6: Commit** (code and exports). `feat(stickers): die-cut outline and WhatsApp, iMessage exports`

### Task 5: Export check, review sheet, PR

**Files:**
- Create: `design-system/mivu/stickers/check.py`
- Modify: `design-system/mivu/stickers/test_pack.py`
- Modify: `design-system/mivu/characters/pip/asset-manifest.json` (sticker provenance: source SHA, command)

**Interfaces:**
- Produces: `check.py EXPORTS_DIR` exits 0 when all limits in Global Constraints hold. Otherwise it prints one line per violation and exits 1. Limits are module constants. Before finalising, check them against WhatsApp's current sticker docs and sample-app README and Apple's sticker-pack guidance, and record the source URLs in a comment.

- [ ] **Step 1: Write the failing tests:** `test_check_rejects_oversize_animated` (a padded 600 KB fake animated WebP fails), `test_check_rejects_mixed_pack` (an animated file in the still pack fails), and `test_check_passes_minimal_valid_export` (3 tiny valid stills, 3 animated, trays, and contents pass).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement `check.py`.** Check dimensions, byte sizes, frame durations, total duration, pack counts, emoji counts, transparency (corner pixel alpha 0), and that each pack has one kind only.
- [ ] **Step 4: Run the unit tests and `check.py` on the real exports.** Expected: tests pass, and `check.py design-system/mivu/stickers/exports` exits 0.
- [ ] **Step 5: Make the review sheet.** In the scratchpad, build a contact sheet of all 12 on white, near-black (#111), and a busy WhatsApp-like wallpaper, at 512 px and about 120 pt (360 px @3x). Add frame strips for the 3 animated stickers and side-by-side renders of `love-it`, `snack` and `hydrate` against native app stills from Task 2. Show it to the owner with `html_render`. Apply owner fixes, then rerun Tasks 4–5 commands.
- [ ] **Step 6: Commit.** `feat(stickers): export checks and provenance`
- [ ] **Step 7: Open the PR.** Push `feat/pip-stickers` and open a PR titled `feat(stickers): Pip sticker pack for WhatsApp and iMessage`. The body lists the source SHA, the XcodeBuildMCP result counts for `PipStickerExportTests`, `PipRigSnapshotTests` and `PipRigAssetTests`, the `test_rig.py`, `test_pack.py` and `check.py` results, and notes that app integration is a follow-up. Run Ponytail Review before merge, as AGENTS.md requires.
