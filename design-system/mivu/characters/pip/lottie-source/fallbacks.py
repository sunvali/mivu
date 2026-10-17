#!/usr/bin/env python3
"""Extract detailed static Pip fallbacks from the approved white storyboard."""
import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[5]
SOURCE = ROOT / "design-system/mivu/characters/pip/storyboard.png"
ALPHA = ROOT / "ios/Mivu/Resources/Characters/pip/pip-artwork-alpha.png"
REGISTRATION = Path(__file__).with_name("pose-registration.json")
CATALOG = ROOT / "ios/Mivu/Assets.xcassets/Companion/Pip"
EXPECTED_SOURCE = "5bef0e0459bf52c26fde44170c4b9419d0d4e4154779f51b0d01fdd1fd9166e1"
POSES = {
    "PipResting": "resting",
    "PipAttentive": "attentive",
    "PipThinking": "thinking",
    "PipSaved": "saved",
    "PipReviewed": "reviewed",
    "PipRecovery": "recovery",
    "PipGreeting": "greeting",
}


def load_build():
    spec = importlib.util.spec_from_file_location("pip_lottie_build", Path(__file__).with_name("build.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def extract(name, pose_name, rgb_atlas, alpha_atlas, registration, build):
    pose = build.POSES[pose_name]
    col, row = pose["cell"]
    x0, y0 = col * 384, row * 256 - 48
    rgb = np.full((352, 384, 3), 255, dtype=np.uint8)
    alpha = np.zeros((352, 384), dtype=np.uint8)
    top, bottom = max(0, y0), min(rgb_atlas.shape[0], y0 + 352)
    rgb[top - y0:bottom - y0] = rgb_atlas[top:bottom, x0:x0 + 384]
    alpha[top - y0:bottom - y0] = alpha_atlas[top:bottom, x0:x0 + 384]

    # Recover foreground from the white composite without changing its painted colors.
    a = alpha.astype(np.int16)
    channels = np.clip(rgb.astype(np.int16) - (255 - a[:, :, None]), 0, a[:, :, None]).astype(np.uint8)
    a[a >= 250] = 255
    spread = channels.max(axis=2).astype(np.int16) - channels.min(axis=2).astype(np.int16)
    neutral_glow = (a < 200) & (spread < 18) & (channels.min(axis=2) > 210)
    a[neutral_glow] = 0

    # The authored connected silhouette rejects stray paint from neighboring cells;
    # the supplied matte retains the original antialiased outer edge.
    whole = build.silhouette(rgb)
    a[~whole] = 0
    rgba = np.dstack((channels, a.astype(np.uint8)))
    ys, xs = np.where(whole)
    bounds = registration[pose_name]["bounds"]
    assert [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] == bounds, (
        f"{name}: silhouette bounds {xs.min(), ys.min(), xs.max(), ys.max()} do not match registration {bounds}"
    )

    scale = 440 / (ys.max() + 1 - ys.min())
    center_x = (xs.min() + xs.max()) / 2
    ground_y = ys.max() + 1
    # Match build.py's root transform: source center to (256,472), then uniform scale.
    full = Image.fromarray(rgba, "RGBA")
    full = full.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    size = (max(1, round(full.width * scale)), max(1, round(full.height * scale)))
    scaled = full.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    left = round(256 - (center_x - xs.min()) * scale)
    top = round(472 - (ground_y - ys.min()) * scale)
    # Cropping at canvas edges is intentional for poses whose scale extends past x=0.
    canvas.alpha_composite(scaled, (left, top))
    return canvas


def write_imageset(folder, image):
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / "pip.png", optimize=True)
    # Both luminosity appearances intentionally use the same approved artwork.
    (folder / "Contents.json").write_text(json.dumps({
        "images": [
            {"filename": "pip.png", "idiom": "universal"},
            {"filename": "pip.png", "idiom": "universal", "appearances": [
                {"appearance": "luminosity", "value": "dark"}
            ]},
        ],
        "info": {"author": "Mivu", "version": 1},
    }, indent=2) + "\n")


def main():
    source_bytes = SOURCE.read_bytes()
    assert hashlib.sha256(source_bytes).hexdigest() == EXPECTED_SOURCE, "Storyboard source hash changed"
    rgb_atlas = np.asarray(Image.open(SOURCE).convert("RGB"))
    alpha_atlas = np.asarray(Image.open(ALPHA).convert("L"))
    registration = json.loads(REGISTRATION.read_text())
    build = load_build()
    outputs = {}
    for asset, pose in POSES.items():
        image = extract(asset, pose, rgb_atlas, alpha_atlas, registration, build)
        write_imageset(CATALOG / f"{asset}.imageset", image)
        outputs[asset] = image
    # Preview shows the full-detail resting artwork at the same registered scale.
    write_imageset(CATALOG / "PipPreview.imageset", outputs["PipResting"])
    print(json.dumps({"assets": len(POSES) + 1, "canvas": "512x512 RGBA", "sourceSHA256": EXPECTED_SOURCE}))


if __name__ == "__main__":
    main()
