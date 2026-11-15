# Pip sticker pack: design

Date: 2026-11-15. Status: draft for owner approval.

## Intent

People should be able to send Pip, Mivu's fox companion, as stickers in
WhatsApp, iMessage and other chat apps. That's a small, friendly way to
spread Mivu: everyday reactions, a little food and health, and a cheer for a
friend. Pip in a chat should look exactly like Pip in the app.

## Scope: two steps

1. **This project:** the sticker artwork plus export-ready files, committed
   to the repo for owner review.
2. **Later, a separate project:** an iMessage sticker extension in the iOS
   app, and an "Add to WhatsApp" button in both the iOS and Android apps.
   Android gets its own copy of the files and never reads `ios/` (see the
   Android/iOS separation rule). Not built now. Step 1 only has to produce
   files that step 2 can drop in unchanged.

## Goals

- 12 Pip stickers: 9 still, 3 animated (owner-approved lineup below).
- No words on any sticker. Pip's pose and face carry the meaning. Small
  symbols such as hearts or "zzz" are allowed *(my call: symbols aren't
  text)*.
- White die-cut outline style: a thick white border around Pip's silhouette
  (and any prop or symbol) on a transparent background, so it reads on any
  chat wallpaper, light or dark.
- Food & health stickers show Pip holding real props.
- Every frame comes from Pip's real rig and gesture data, never redrawn by
  hand, so stickers match the app.

## Non-goals

- No app code, extensions, share sheets or store listings in this step.
- No captions or localisation (the stickers are language-free).
- No new characters and no changes to Pip's in-app behaviour.
- No public posting or distribution. Mivu isn't publicly launched, and the
  owner decides when it goes out.

## Anti-goals (failure even if it "works")

- A Pip that looks off-model: different proportions, colours, or a face that
  doesn't match `reference.png` and the character sheet.
- Stiff or jittery animation. The bar is Duolingo-level fluency, judged on
  real frame strips.
- Anything that comments on how much someone eats, or uses diet-shaming,
  confetti, points or streak counters (same rules as Pip in the app).
- Files that WhatsApp or iMessage would reject.

## Lineup (owner-approved)

| # | Sticker | Kind | Pose | Likely source on `main` |
|---|---|---|---|---|
| 1 | Hi | animated | waving paw | `greeting` |
| 2 | Thanks | still | paws together, small bow | new pose from existing helpers |
| 3 | Love it | still | hugging tail, heart(s) above head | `idle-hug-tail` + `heart-*` parts / `progress-tap-heart-eyes` |
| 4 | LOL | still | eyes squeezed shut, laughing | `tap-giggle` |
| 5 | OK | still | confident paw up, wink | `tap-wink` |
| 6 | Oops | still | ears flat, sheepish grin | new pose from existing helpers |
| 7 | Good night | animated | curls up, slow breathing, zzz | `curl-up` + resting breath; zzz is new art |
| 8 | Yum | still | holding salad bowl, licking lips | `eat-bowl` / `eat-yum` (`prop-bowl`, `prop-bowl-spoon`) |
| 9 | Hungry | still | paw on tummy, looking at an empty bowl | new pose; `prop-bowl` without food |
| 10 | Hydrate | still | sipping from a water glass | `sip-water` (`prop-cup`) |
| 11 | Snack | still | holding up an apple proudly | `eat-apple` (`prop-apple`) |
| 12 | You got it | animated | arms up cheer, hop | `presenting-cheer` / `day-complete` |

"Likely source" is a pointer, not a requirement. The builder picks the
frame or gesture that reads best at sticker size. Reusing existing props is
expected. New art is limited to what's missing: the "zzz", an empty-bowl
variant if the current bowl can't be shown empty, and anything a new pose
needs. New art goes into Pip's main rig, `pip.svg` (owner's decision), as
hidden-by-default parts following the rig README conventions. That keeps
one source of truth, and the app can reuse the parts later. Committing the
rebuilt `pip-rig.json` and fallback images in this PR is expected. Any rig
change must keep `test_rig.py` passing and leave the app's Pip looking the
same.

The tray/pack icon is Pip's head or the "Hi" still *(my call)*.

## Output files

Everything lives under `design-system/mivu/stickers/`: sources (pose and
frame definitions), the build script, and committed exports.

| Target | Format |
|---|---|
| WhatsApp | 512×512 WebP, transparent; stills ≤ 100 KB; animated WebP ≤ 500 KB, ≥ 8 ms per frame, ≤ 10 s; tray icon 96×96 PNG ≤ 50 KB; a pack needs 3–30 stickers, and still and animated stickers go in **separate packs**. Each sticker gets 1–3 emoji tags. |
| iMessage | 408×408 @3x PNG for stills, APNG for animated (≤ 500 KB each), transparent: ready to drop into a Sticker Pack asset catalog. |
| Anywhere else | 512×512 transparent PNG of each still, and an animated WebP or GIF of each animated one. |

The builder should check current WhatsApp and Apple sticker limits at build
time; the numbers above are the expected values, not verified today.

Build is one reproducible command (same style as `rig/build.py`; use the
repo's existing `.venv` with `cairosvg`/`pillow`). A small self-check script
verifies sizes, dimensions, transparency, frame timing and pack counts.

## Constraints

- Pip art source: `design-system/mivu/characters/pip/rig/pip.svg` →
  `rig/build.py`. Gestures are data in `ios/Mivu/Design/PipGestureLibrary.swift`.
  A Python port of the gesture system already exists for films
  (`reports/reels/*/src/pipact.py`). The builder chooses how to drive poses and
  frames. The output must match the app rig (shapes, colours, joints,
  springs), and that has to be shown with side-by-side comparisons against
  native renders.
- Light-appearance colours only *(my call: the white outline makes stickers
  work on dark wallpapers)*.
- Animated stickers loop seamlessly. Ignore Reduce Motion here: the chat
  apps control playback.
- Read `.agents/skills/mivu-animation/SKILL.md` and its references before
  touching the rig or gestures.
- Feature branch `feat/pip-stickers` and a PR, Conventional Commit title.
  No hosted macOS CI.

## Review and done

- Contact sheet: all 12 on a light, a dark and a busy chat-like background,
  at full size and at about 120 pt (typical chat size).
- Frame strips for each animated sticker.
- Owner reviews these before any app integration starts.
- Done = all files export, the self-check passes, the owner approves the look.

## Calls made during review *(my calls)*

- Any sticker can be built as still or animated by changing one setting, so
  changing the 9/3 split later is cheap. The animated pack must keep at
  least 3 stickers to stay valid.
- All 3 animated stickers ship. If one goes over a size limit, cut frame
  rate, loop length or colours. Don't drop the sticker.
- Showing the rig matches the app means eyeballing side-by-side native
  stills for a few stickers. A pixel-diff gate isn't required.
- The tray icon is committed with the exports.

## Left to the builder

The exact frame or gesture moment per sticker, outline thickness and
smoothing, the rendering approach (Python port vs native capture), frame
rate and loop length within the limits, the emoji tags, and the folder
layout under `stickers/`.
