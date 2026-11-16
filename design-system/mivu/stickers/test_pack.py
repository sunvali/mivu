"""Checks for the sticker packer, on synthetic shapes only. Run: .venv/bin/python design-system/mivu/stickers/test_pack.py"""
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import check
import pack
import sync

RED = (220, 60, 50, 255)


def disc(cx=256, cy=256, r=80, size=512):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((cx - r, cy - r, cx + r, cy + r), fill=RED)
    return img


class PackTests(unittest.TestCase):
    def test_outline_adds_white_ring(self):
        out = np.array(pack.outline(disc(), width=14))
        self.assertEqual(tuple(out[256, 256]), RED)
        ring = out[256, 256 + 80 + 7]  # halfway through the ring
        self.assertEqual(tuple(ring), (255, 255, 255, 255))
        self.assertEqual(out[256, 256 + 80 + 18][3], 0)  # clear past the ring

    def test_animated_frames_share_one_fit_box(self):
        frames = [pack.outline(disc(cx=200)), pack.outline(disc(cx=300))]
        box = pack.fit_box(frames)
        placed = [np.array(pack.place(f, box))[:, :, 3] for f in frames]
        lefts = [np.nonzero(a.any(axis=0))[0][0] for a in placed]
        widths = [np.nonzero(a.any(axis=0))[0][-1] - l for a, l in zip(placed, lefts)]
        self.assertGreater(lefts[1] - lefts[0], 50)  # still moves within the frame, not re-centred
        self.assertLessEqual(abs(widths[0] - widths[1]), 1)  # and keeps its size

    def test_outline_never_touches_canvas_edge(self):
        full = Image.new("RGBA", (512, 512), RED)
        out = pack.prepare([full])[0]
        self.assertEqual(out.size, (512, 512))
        a = np.array(out)[:, :, 3]
        self.assertEqual(int(a[0].max()) + int(a[-1].max()) + int(a[:, 0].max()) + int(a[:, -1].max()), 0)

    def test_no_detached_outline_specks(self):
        img = disc()
        ImageDraw.Draw(img).rectangle((20, 20, 21, 21), fill=RED)
        out = np.array(pack.outline(img))[:, :, 3]
        count, _ = __import__("cv2").connectedComponents((out > 0).astype(np.uint8))
        self.assertEqual(count - 1, 1)

    def test_animated_files_drop_frames_to_fit_the_limit(self):
        noisy = [Image.fromarray(np.random.default_rng(i).integers(0, 255, (128, 128, 4), np.uint8), "RGBA") for i in range(12)]
        with tempfile.TemporaryDirectory() as tmp:
            for name, save in [("a.webp", pack.save_webp), ("a.png", pack.save_apng)]:
                path = Path(tmp) / name
                save(noisy, path, 50, limit=10**9)
                limit = int(path.stat().st_size * 0.45)  # below what lower quality alone can reach
                save(noisy, path, 50, limit=limit)
                with Image.open(path) as out:
                    out.load()
                    self.assertLessEqual(path.stat().st_size, limit, name)
                    self.assertLess(out.n_frames, 12, name)
                    self.assertEqual(out.info.get("duration"), 50 * 12 // out.n_frames, name)

    def test_writes_whatsapp_contents(self):
        with tempfile.TemporaryDirectory() as tmp:
            frames, out = Path(tmp) / "frames", Path(tmp) / "out"
            for sticker, n, animated in [("a", 1, False), ("b", 1, False), ("hi", 12, True)]:
                folder = frames / sticker
                folder.mkdir(parents=True)
                for i in range(n):
                    disc(cx=200 + i * 4).save(folder / f"{i:04d}.png")
                meta = {"id": sticker, "emoji": ["🙂"], "animated": animated, "fps": 20 if animated else 0}
                (folder / "meta.json").write_text(json.dumps(meta))
            pack.build(frames, out, order=["hi", "a", "b"])
            still = json.loads((out / "whatsapp/still/contents.json").read_text())["sticker_packs"][0]
            moving = json.loads((out / "whatsapp/animated/contents.json").read_text())["sticker_packs"][0]
            self.assertFalse(still["animated_sticker_pack"])
            self.assertTrue(moving["animated_sticker_pack"])
            self.assertEqual([s["image_file"] for s in still["stickers"]], ["a.webp", "b.webp"])
            self.assertEqual(moving["stickers"], [{"image_file": "hi.webp", "emojis": ["🙂"]}])
            self.assertEqual(Image.open(out / "whatsapp/still/tray.png").size, (96, 96))
            self.assertEqual(Image.open(out / "imessage/a.png").size, (408, 408))
            self.assertEqual(getattr(Image.open(out / "imessage/hi.png"), "n_frames", 1), 12)
            self.assertEqual(Image.open(out / "gif/hi.gif").n_frames, 12)
            self.assertTrue((out / "png/a.png").is_file())


class CheckTests(unittest.TestCase):
    def export(self, tmp, still=3, moving=3):
        frames, out = Path(tmp) / "frames", Path(tmp) / "out"
        order = []
        for n in range(still + moving):
            sticker, animated = f"s{n}", n >= still
            folder = frames / sticker
            folder.mkdir(parents=True)
            for i in range(12 if animated else 1):
                disc(cx=200 + i * 4, r=60).save(folder / f"{i:04d}.png")
            (folder / "meta.json").write_text(json.dumps({"id": sticker, "emoji": ["🙂"], "animated": animated, "fps": 20 if animated else 0}))
            order.append(sticker)
        pack.build(frames, out, order=order)
        return out

    def test_check_passes_minimal_valid_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(check.problems(self.export(tmp)), [])

    def test_check_rejects_oversize_animated(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = self.export(tmp)
            big = out / "whatsapp/animated/s3.webp"
            big.write_bytes(big.read_bytes() + b"\0" * 600_000)  # RIFF readers ignore trailing bytes; the size is what counts
            self.assertTrue(any("s3.webp" in p and "bytes" in p for p in check.problems(out)))

    def test_check_rejects_mixed_pack(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = self.export(tmp)
            (out / "whatsapp/still/s0.webp").write_bytes((out / "whatsapp/animated/s3.webp").read_bytes())
            self.assertTrue(any("s0.webp" in p and "animated" in p for p in check.problems(out)))

    def test_check_rejects_short_pack(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertTrue(any("3-30" in p for p in check.problems(self.export(tmp, still=2))))


EXPORTS = Path(__file__).resolve().parent / "exports"
REPO = Path(__file__).resolve().parents[3]


class SyncTests(unittest.TestCase):
    def test_bundled_copies_match_exports(self):
        self.assertEqual(sync.drift(EXPORTS, REPO), [])

    def test_drift_names_a_changed_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            sync.write(EXPORTS, repo)
            ok = repo / "android/app/src/main/assets/stickers/ok.webp"
            ok.write_bytes(bytes([ok.read_bytes()[0] ^ 1]) + ok.read_bytes()[1:])
            self.assertEqual(sync.drift(EXPORTS, repo), ["changed android/app/src/main/assets/stickers/ok.webp"])


if __name__ == "__main__":
    unittest.main()
