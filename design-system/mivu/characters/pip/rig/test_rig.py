"""Asset checks for the generated Pip rig. Run: python3 rig/test_rig.py"""
import json
import re
import unittest
from pathlib import Path

RIG = Path(__file__).resolve().parents[5] / "ios/Mivu/Resources/Characters/pip/pip-rig.json"

HEAD_IDS = (
    "head ear-l ear-r ear-inner-l ear-inner-r muzzle nose brow-l brow-r eye-l eye-r "
    "iris-l iris-r pupil-l pupil-r glint-l glint-r lid-upper-l lid-upper-r "
    "cheek-blush-l cheek-blush-r"
).split()
MOUTHS = "closedSmile smallOpen bigOpen o concerned yawn".split()
EYES = "open half closedHappy closedSleepy wide heart".split()
VIEWS = ("right", "front", "left")
SETS = ("standing", "seated", "curled")
BODY_IDS = (
    "body chest chest-fluff arm-l forearm-l paw-l arm-r forearm-r paw-r leg-l leg-r foot-l foot-r "
    "tail-1 tail-2 tail-3 tail-4 scarf-knot scarf-end-l scarf-end-r shadow"
).split()
HEARTS = ("heart-1", "heart-2", "heart-3")


def name(part_id):
    return part_id.split("@")[0]


def swap_side(text):
    return re.sub(r"-([lr])(?=[.@]|$)", lambda m: "-r" if m.group(1) == "l" else "-l", text)


def x_bounds(path):
    xs = [float(v) for v in re.findall(r"-?[\d.]+", path)[0::2]]
    ys = [float(v) for v in re.findall(r"-?[\d.]+", path)[1::2]]
    return min(xs), max(xs), min(ys), max(ys)


def points(path):
    v = [float(t) for t in re.findall(r"-?[\d.]+", path)]
    return v[0::2], v[1::2]


def set_id(part, body_set):
    return part if body_set == "standing" else f"{part}@{body_set}"


class RigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rig = json.loads(RIG.read_text())
        cls.parts = cls.rig["parts"]
        cls.ids = {p["id"] for p in cls.parts}

    def test_each_view_has_all_slots(self):
        shapes = [f"mouth.{m}" for m in MOUTHS]
        shapes += [f"eye-{side}.{e}" for side in "lr" for e in EYES]
        for view in VIEWS:
            parts = [p for p in self.parts if p["view"] == view]
            for part_id in HEAD_IDS:
                self.assertIn(part_id, {name(p["id"]) for p in parts}, view)
            for shape in shapes:
                self.assertIn(shape, {p["shape"] for p in parts}, view)
        self.assertEqual(len(self.ids), len(self.parts), "part ids must be unique")

    def test_one_view_visible_by_default(self):
        self.assertEqual({p["view"] for p in self.parts if p["visible"]} - {None}, {"right"})

    def test_left_view_mirrors_right(self):
        by_id = {p["id"]: p for p in self.parts}
        axis = by_id["head@right"]["pivot"][0]
        for p in self.parts:
            if p["view"] != "right":
                continue
            twin = by_id[swap_side(name(p["id"])) + "@left"]
            if "glint" in p["id"]:  # highlights keep the light from the same side; checked below
                continue
            x0, x1, y0, y1 = x_bounds(p["path"])
            mx0, mx1, my0, my1 = x_bounds(twin["path"])
            for got, want in ((mx0, 2 * axis - x1), (mx1, 2 * axis - x0), (my0, y0), (my1, y1)):
                self.assertAlmostEqual(got, want, delta=2, msg=p["id"])

    def test_mirrored_glints_keep_light_side(self):
        by_id = {p["id"]: p for p in self.parts}
        for view in ("right", "left"):
            glint, iris = by_id[f"glint-l@{view}"], by_id[f"iris-l@{view}"]
            gx0, gx1, _, _ = x_bounds(glint["path"])
            ix0, ix1, _, _ = x_bounds(iris["path"])
            self.assertLess((gx0 + gx1) / 2, (ix0 + ix1) / 2, view)  # highlight on the iris's upper left

    def test_parallax_increases_toward_the_snout(self):
        by_id = {p["id"]: p for p in self.parts}

        def total(part_id):
            p, value = by_id[part_id], 0.0
            while p:
                value += p["parallax"]
                p = by_id.get(p["parent"])
            return value
        for view in VIEWS:
            self.assertEqual(total(f"head@{view}"), 0)
            self.assertAlmostEqual(total(f"nose@{view}"), 1.0)
            self.assertTrue(0 < total(f"eye-l.open@{view}") < 1, view)

    def test_body_parts_present(self):
        by_id = {p["id"]: p for p in self.parts}
        for body_set in SETS:
            for part in BODY_IDS:
                self.assertEqual(by_id[set_id(part, body_set)]["set"], body_set, part)
        for heart in HEARTS:
            self.assertFalse(by_id[heart]["visible"], heart)
        self.assertEqual(by_id["head@right"]["parent"], "body")

    def set_bounds(self, body_set):
        """A set at rest: its visible parts plus the default head view on the set's mount."""
        by_id = {p["id"]: p for p in self.parts}
        k, tx, ty = by_id[set_id("body", body_set)]["mount"]
        xs, ys = [], []
        for p in self.parts:
            if p["visible"] and (p["set"] == body_set or p["view"] == "right"):
                px, py = points(p["path"])
                if p["view"]:
                    px, py = [k * x + tx for x in px], [k * y + ty for y in py]
                xs += px
                ys += py
        return min(xs), min(ys), max(xs), max(ys)

    def test_feet_on_ground(self):
        for body_set in SETS:
            for foot in ("foot-l", "foot-r"):
                part = next(p for p in self.parts if p["id"] == set_id(foot, body_set))
                self.assertAlmostEqual(max(points(part["path"])[1]), 472, delta=2, msg=part["id"])

    def test_inside_safe_bounds(self):
        for body_set in SETS:
            x0, y0, x1, y1 = self.set_bounds(body_set)
            self.assertTrue(40 <= x0 and x1 <= 472 and 32 <= y0 and y1 <= 472, (body_set, x0, y0, x1, y1))

    def test_coach_frame_contains_seated_set(self):
        x, y, w, h = self.rig["frames"]["coach"]
        x0, y0, x1, y1 = self.set_bounds("seated")
        self.assertTrue(x <= x0 and y <= y0 and x1 <= x + w and y1 <= y + h)
        self.assertAlmostEqual(w / h, 76 / 66, delta=0.01)
        x, y, w, h = self.rig["frames"]["today"]
        x0, y0, x1, y1 = self.set_bounds("standing")
        self.assertTrue(x <= x0 and y <= y0 and x1 <= x + w and y1 <= y + h)

    def test_pivots_inside_artboard(self):
        for p in self.parts:
            for value in p["pivot"]:
                self.assertTrue(0 <= value <= 512, p["id"])

    def test_one_default_shape_per_slot(self):
        for slot in ("mouth", "eye-l", "eye-r"):
            shown = [p["id"] for p in self.parts
                     if p["shape"] and p["shape"].split(".")[0] == slot and p["visible"]]
            self.assertEqual(len(shown), 1, slot)

    def test_parts_under_hidden_shapes_are_hidden(self):
        by_id = {p["id"]: p for p in self.parts}
        for p in self.parts:
            ancestor = by_id.get(p["parent"])
            while ancestor:
                if ancestor["shape"] and not ancestor["visible"]:
                    self.assertFalse(p["visible"], p["id"])
                ancestor = by_id.get(ancestor["parent"])

    def test_parents_exist(self):
        for p in self.parts:
            self.assertIn(p["parent"], self.ids | {"body", None}, p["id"])

    def test_missing_pivot_names_part(self):
        import xml.etree.ElementTree as ET
        import build

        root = ET.fromstring('<svg xmlns="http://www.w3.org/2000/svg"><g id="ear-x"><path d="M 0 0 Z"/></g></svg>')
        with self.assertRaisesRegex(ValueError, "ear-x"):
            build.collect(root, build.IDENTITY, None, None, [])

    def test_size_budget(self):
        self.assertLess(RIG.stat().st_size, 524_288)

    def test_paths_use_supported_commands(self):
        for p in self.parts:
            self.assertRegex(p["path"], r"^[MLCQZ0-9.,\s-]+$", p["id"])


if __name__ == "__main__":
    unittest.main()
