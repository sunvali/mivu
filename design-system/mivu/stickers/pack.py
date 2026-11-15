"""Turns the raw Pip sticker frames into chat-ready packs.

Usage: .venv/bin/python design-system/mivu/stickers/pack.py build/pip-stickers/frames design-system/mivu/stickers/exports
Frames come from MivuTests/PipStickerExportTests/exportFrames (see README.md beside this file).
"""
import json
import shutil
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

LINEUP = ["hi", "thanks", "love-it", "lol", "ok", "oops", "good-night", "yum", "hungry", "hydrate", "snack", "you-got-it"]
OUTLINE = 14  # px at the rig's 512 artboard
SIZE, MARGIN = 512, 16
IMESSAGE = 408
STILL_BYTES, ANIMATED_BYTES = 100_000, 500_000


def remove_specks(mask, min_area=40):
    """Drops detached bits smaller than `min_area` px (a z shrunk to a dot), so they never get outlined as blobs."""
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=8)
    keep = np.zeros(count, bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= min_area
    return keep[labels]


def outline(img, width=OUTLINE):
    """The die-cut look: a round white border `width` px wide behind the whole silhouette, gaps between limbs filled."""
    rgba = np.array(img.convert("RGBA"))
    solid = remove_specks(rgba[:, :, 3] > 8)
    rgba[:, :, 3] = np.where(cv2.dilate(solid.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0, rgba[:, :, 3], 0)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * width + 1, 2 * width + 1))
    border = cv2.GaussianBlur(cv2.dilate(solid.astype(np.uint8) * 255, kernel), (0, 0), 0.8)
    white = np.dstack([np.full_like(border, 255)] * 3 + [border])
    out = Image.fromarray(white, "RGBA")
    out.alpha_composite(Image.fromarray(rgba, "RGBA"))
    return out


def fit_box(frames):
    """One crop for every frame, so an animated sticker never shifts or rescales between frames."""
    boxes = [f.getchannel("A").getbbox() for f in frames]
    boxes = [b for b in boxes if b]
    return min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)


def place(img, box, size=SIZE, margin=MARGIN):
    w, h = box[2] - box[0], box[3] - box[1]
    scale = min((size - 2 * margin) / w, (size - 2 * margin) / h)
    art = img.crop(box).resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
    return canvas


def prepare(frames):
    """Pads (so the border never hits the edge), outlines, then fits all frames into one 512 canvas."""
    pad = OUTLINE + 4
    padded = []
    for f in frames:
        canvas = Image.new("RGBA", (f.width + 2 * pad, f.height + 2 * pad), (0, 0, 0, 0))
        canvas.alpha_composite(f.convert("RGBA"), (pad, pad))
        padded.append(outline(canvas))
    box = fit_box(padded)
    return [place(f, box) for f in padded]


def fit(frames, path, duration, limit, write, qualities):
    """Cheapest loss first: lower quality, then every other frame (each held longer), until the file fits.
    A file that still does not fit is left as the last try; check.py reports it."""
    for step in (1, 2, 3, 4) if duration else (1,):
        for quality in qualities:
            write(frames[::step], path, duration * step if duration else None, quality)
            if path.stat().st_size <= limit:
                return


def save_webp(frames, path, duration=None, limit=None):
    """Stills start lossless; animated stickers start lossy, which is what fits."""
    def write(kept, path, ms, quality):
        extra = dict(save_all=True, append_images=kept[1:], duration=ms, loop=0) if ms else {}
        kept[0].save(path, "WEBP", method=4, **(dict(lossless=True) if quality is None else dict(quality=quality)), **extra)
    qualities = (80, 70, 60) if duration else (None, 90, 80)
    fit(frames, path, duration, limit or (ANIMATED_BYTES if duration else STILL_BYTES), write, qualities)


def save_apng(frames, path, duration, limit=ANIMATED_BYTES):
    """iMessage's animated sticker: a 256-colour APNG (alpha kept) stays far smaller than full colour."""
    def write(kept, path, ms, colors):
        kept = [f.quantize(colors, method=Image.Quantize.FASTOCTREE) for f in kept]
        kept[0].save(path, "PNG", save_all=True, append_images=kept[1:], duration=ms, loop=0, optimize=True)
    fit(frames, path, duration, limit, write, (256, 128))


def build(frames_dir, out_dir, order=LINEUP):
    frames_dir, out_dir = Path(frames_dir), Path(out_dir)
    for sub in ("whatsapp", "imessage", "png", "gif"):
        shutil.rmtree(out_dir / sub, ignore_errors=True)
    for sub in ("whatsapp/still", "whatsapp/animated", "imessage", "png", "gif"):
        (out_dir / sub).mkdir(parents=True, exist_ok=True)
    packs = {False: [], True: []}
    tray = None
    for sticker in order:
        folder = frames_dir / sticker
        meta = json.loads((folder / "meta.json").read_text())
        frames = prepare([Image.open(p) for p in sorted(folder.glob("*.png"))])
        tray = tray or frames[0]
        small = [f.resize((IMESSAGE, IMESSAGE), Image.LANCZOS) for f in frames]
        if meta["animated"]:
            ms = round(1000 / meta["fps"])
            save_webp(frames, out_dir / "whatsapp/animated" / f"{sticker}.webp", duration=ms)
            save_apng(small, out_dir / "imessage" / f"{sticker}.png", ms)
            frames[0].save(out_dir / "gif" / f"{sticker}.gif", save_all=True, append_images=frames[1:], duration=ms, loop=0, disposal=2)
        else:
            save_webp(frames, out_dir / "whatsapp/still" / f"{sticker}.webp")
            small[0].save(out_dir / "imessage" / f"{sticker}.png", optimize=True)
            frames[0].save(out_dir / "png" / f"{sticker}.png", optimize=True)
        packs[meta["animated"]].append({"image_file": f"{sticker}.webp", "emojis": meta["emoji"]})
    for animated, stickers in packs.items():
        folder = out_dir / "whatsapp" / ("animated" if animated else "still")
        tray.resize((96, 96), Image.LANCZOS).save(folder / "tray.png", optimize=True)
        pack = {
            "identifier": "mivu-pip-animated" if animated else "mivu-pip-still",
            "name": "Pip moves" if animated else "Pip",
            "publisher": "Mivu",
            "tray_image_file": "tray.png",
            "image_data_version": "1",
            "avoid_cache": False,
            "publisher_email": "", "publisher_website": "", "privacy_policy_website": "", "license_agreement_website": "",
            "animated_sticker_pack": animated,
            "stickers": stickers,
        }
        (folder / "contents.json").write_text(json.dumps({"sticker_packs": [pack]}, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2])
