"""Checks the sticker exports against the chat apps' limits. Exits 1 and lists each problem when any fails.

Usage: .venv/bin/python design-system/mivu/stickers/check.py design-system/mivu/stickers/exports
"""
import json
import sys
from pathlib import Path

from PIL import Image

# WhatsApp, checked 2026-11-15 against https://github.com/WhatsApp/stickers/blob/main/Android/README.md
WA_SIZE, WA_STILL_BYTES, WA_ANIMATED_BYTES = 512, 100_000, 500_000
WA_MIN_FRAME_MS, WA_MAX_MS = 8, 10_000
WA_TRAY, WA_TRAY_BYTES = 96, 50_000
WA_PACK = range(3, 31)
WA_EMOJI = range(1, 4)
# Messages stickers, from Apple's sticker guidance (regular size @3x, 500 KB per file); not re-checked online.
IM_SIZE, IM_BYTES = 408, 500_000


def frames(im):
    """Each frame's duration in ms (1 entry for a still)."""
    durations = []
    for i in range(getattr(im, "n_frames", 1)):
        im.seek(i)
        im.load()
        durations.append(im.info.get("duration", 0))
    return durations


def transparent_corner(im):
    im.seek(0)
    return im.convert("RGBA").getpixel((0, 0))[3] == 0


def problems(exports):
    exports, found = Path(exports), []
    for kind in ("still", "animated"):
        folder = exports / "whatsapp" / kind
        animated = kind == "animated"
        pack = json.loads((folder / "contents.json").read_text())["sticker_packs"][0]
        if pack.get("animated_sticker_pack", False) != animated:
            found.append(f"{kind}: animated_sticker_pack should be {animated}")
        if len(pack["stickers"]) not in WA_PACK:
            found.append(f"{kind}: {len(pack['stickers'])} stickers, WhatsApp needs 3-30")
        with Image.open(folder / pack["tray_image_file"]) as tray:
            if tray.size != (WA_TRAY, WA_TRAY) or (folder / pack["tray_image_file"]).stat().st_size > WA_TRAY_BYTES:
                found.append(f"{kind}: tray must be {WA_TRAY} px and at most {WA_TRAY_BYTES} bytes")
        for sticker in pack["stickers"]:
            path = folder / sticker["image_file"]
            name = f"{kind}/{path.name}"
            if len(sticker["emojis"]) not in WA_EMOJI:
                found.append(f"{name}: needs 1-3 emoji")
            limit = WA_ANIMATED_BYTES if animated else WA_STILL_BYTES
            if path.stat().st_size > limit:
                found.append(f"{name}: {path.stat().st_size} bytes, limit {limit}")
            with Image.open(path) as im:
                durations = frames(im)
                if im.size != (WA_SIZE, WA_SIZE):
                    found.append(f"{name}: {im.size}, must be {WA_SIZE} px square")
                if (len(durations) > 1) != animated:
                    found.append(f"{name}: {'still' if animated else 'animated'} sticker in the {kind} pack")
                if animated and (min(durations) < WA_MIN_FRAME_MS or sum(durations) > WA_MAX_MS):
                    found.append(f"{name}: frames need >= {WA_MIN_FRAME_MS} ms and <= {WA_MAX_MS} ms in all")
                if not transparent_corner(im):
                    found.append(f"{name}: background is not transparent")
    for path in sorted((exports / "imessage").glob("*.png")):
        if path.stat().st_size > IM_BYTES:
            found.append(f"imessage/{path.name}: {path.stat().st_size} bytes, limit {IM_BYTES}")
        with Image.open(path) as im:
            if im.size != (IM_SIZE, IM_SIZE) or not transparent_corner(im):
                found.append(f"imessage/{path.name}: must be {IM_SIZE} px square on a transparent background")
    return found


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    issues = problems(sys.argv[1])
    print("\n".join(issues) or "all sticker exports within limits")
    sys.exit(1 if issues else 0)
