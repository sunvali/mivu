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


class RigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rig = json.loads(RIG.read_text())
        cls.parts = cls.rig["parts"]
        cls.ids = {p["id"] for p in cls.parts}

    def test_head_parts_present(self):
        shapes = [f"mouth.{m}" for m in MOUTHS]
        shapes += [f"eye-{side}.{e}" for side in "lr" for e in EYES]
        for part_id in HEAD_IDS:
            self.assertIn(part_id, self.ids)
        for shape in shapes:
            self.assertIn(shape, {p["shape"] for p in self.parts})
        self.assertEqual(len(self.ids), len(self.parts), "part ids must be unique")

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
