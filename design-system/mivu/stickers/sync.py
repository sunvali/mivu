"""Copies the sticker exports into both apps and the Messages pack; --check exits 1 on drift.

Usage: .venv/bin/python design-system/mivu/stickers/sync.py [--check]
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

from pack import LINEUP

HERE = Path(__file__).resolve().parent
PACK = "ios/MivuStickers/Stickers.xcstickers/Sticker Pack.stickerpack"
APP_DIRS = ["ios/Mivu/Resources/Stickers", "android/app/src/main/assets/stickers"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copies(exports, repo):
    """(source, destination) pairs: the flat app folders and the Messages pack images."""
    wa = exports / "whatsapp"
    tray = wa / "still" / "tray.png"
    assert sha(tray) == sha(wa / "animated" / "tray.png"), "the two trays differ"
    flat = [(tray, "tray.png"), (wa / "still" / "contents.json", "pip-still.json"),
            (wa / "animated" / "contents.json", "pip-animated.json")]
    for i in LINEUP:
        animated = (wa / "animated" / f"{i}.webp").exists()
        flat.append((wa / ("animated" if animated else "still") / f"{i}.webp", f"{i}.webp"))
        flat.append((exports / ("gif" if animated else "png") / (f"{i}.gif" if animated else f"{i}.png"),
                     f"{i}.gif" if animated else f"{i}.png"))
    pairs = [(src, repo / d / name) for d in APP_DIRS for src, name in flat]
    pairs += [(exports / "imessage" / f"{i}.png", repo / PACK / f"{i}.sticker" / f"{i}.png") for i in LINEUP]
    return pairs


def generated(repo):
    """Messages pack manifests: destination -> text."""
    out = {repo / PACK / "Contents.json": json.dumps(
        {"info": {"author": "xcode", "version": 1}, "properties": {"grid-size": "regular"},
         "stickers": [{"filename": f"{i}.sticker"} for i in LINEUP]}, indent=2) + "\n"}
    for i in LINEUP:
        out[repo / PACK / f"{i}.sticker" / "Contents.json"] = json.dumps(
            {"info": {"author": "xcode", "version": 1}, "properties": {"filename": f"{i}.png"}}, indent=2) + "\n"
    return out


def drift(exports, repo):
    expected = {dst: sha(src) for src, dst in copies(exports, repo)}
    expected.update({p: hashlib.sha256(t.encode()).hexdigest() for p, t in generated(repo).items()})
    lines = []
    for dst, want in sorted(expected.items()):
        if not dst.exists():
            lines.append(f"missing {dst.relative_to(repo)}")
        elif sha(dst) != want:
            lines.append(f"changed {dst.relative_to(repo)}")
    for root in [repo / d for d in APP_DIRS] + [repo / PACK]:
        for f in sorted(root.rglob("*")) if root.exists() else []:
            if f.is_file() and f not in expected and f.name != ".DS_Store":
                lines.append(f"extra {f.relative_to(repo)}")
    return lines


def write(exports, repo):
    for src, dst in copies(exports, repo):
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    for dst, text in generated(repo).items():
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(text)


if __name__ == "__main__":
    exports, repo = HERE / "exports", HERE.parents[2]
    if "--check" in sys.argv:
        found = drift(exports, repo)
        print("\n".join(found) or "no drift")
        sys.exit(1 if found else 0)
    write(exports, repo)
