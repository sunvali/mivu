# Pip layered rig

`pip.svg` is the editable source of truth for Pip's vector rig. `build.py`
converts it to `ios/Mivu/Resources/Characters/pip/pip-rig.json`, which the app
bundles. Never hand-edit the JSON.

## Commands

```sh
python3 -m venv .venv && .venv/bin/pip install cairosvg pillow   # once, at repo root
.venv/bin/python design-system/mivu/characters/pip/rig/build.py              # write pip-rig.json
.venv/bin/python design-system/mivu/characters/pip/rig/build.py --png OUT    # also render each set
.venv/bin/python design-system/mivu/characters/pip/rig/test_rig.py           # asset checks
```

`build.py` itself needs only the standard library; `--png` needs `cairosvg`.

## SVG conventions

- Artboard 512 × 512, ground line y 472.
- Every `<g id="…">` is one part and holds exactly one direct `<path>`; its
  `fill` is the light fill, optional `data-fill-dark` the dark-appearance fill.
- `data-pivot="x y"` is the rotation/scale pivot, in the group's own coordinates.
- Group `transform`s (matrix/translate/scale/rotate) are flattened into the
  JSON paths and pivots. Paths use absolute `M L C Q Z` commands only.
- Parent = nearest ancestor group with an id. `data-parent` overrides it, so a
  part can be drawn behind its parent (ears, neck and rims sit before `head` in
  the file but move with it). `head`'s parent is `body`, drawn later.
- Draw order: `z` is document order. A child drawn after its parent's own path
  is in front of it; use `data-parent` for parts that must sit behind.
- `data-set="standing|seated|curled"` marks pose-set parts (inherited by
  children); no attribute means shared.
- Face alternatives: `data-shape="slot.name"` (`mouth.closedSmile`,
  `eye-l.half`…). `display="none"` means `visible: false` in the JSON; exactly
  one shape per slot is shown by default. Sub-parts of a shape (iris, glint,
  tongue) are its children and need no `data-shape`. Hidden-by-default extras
  (cheek blush) also use `display="none"`.
- `-l`/`-r` mean the viewer's left/right. The head faces slightly to the
  viewer's left: `ear-l` stands up, `ear-r` splays out, like the waving Pip in
  `../reference.png`.
- Eyes are authored once around their own centre and placed by a transform.
