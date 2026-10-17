"""Regression checks on the generated painted rig, in source and phone points."""
import json
import unittest

import numpy as np
from PIL import Image, ImageDraw

import build


def value(prop, frame):
    if not prop.get("a"):
        return np.asarray(prop["k"], dtype=float)
    keys = prop["k"]
    for index, key in enumerate(keys[:-1]):
        following = keys[index + 1]
        if key["t"] <= frame < following["t"]:
            progress = (frame - key["t"]) / (following["t"] - key["t"])
            # Authored cubic ease; solve time before evaluating displacement.
            lo, hi = 0., 1.
            for _ in range(24):
                t = (lo + hi) / 2
                x = 3*(1-t)**2*t*.32 + 3*(1-t)*t*t*.58 + t**3
                if x < progress: lo = t
                else: hi = t
            ease = 3*(1-t)*t*t + t**3
            return np.asarray(key["s"]) * (1-ease) + np.asarray(following["s"]) * ease
    return np.asarray(keys[-1 if frame >= keys[-1]["t"] else 0]["s"], dtype=float)


def matrix(layer, frame, layers):
    ks = layer["ks"]
    anchor, position = value(ks["a"], frame).ravel(), value(ks["p"], frame).ravel()
    scale = value(ks["s"], frame).ravel() / 100
    rotation = np.deg2rad(value(ks["r"], frame).ravel()[0])
    c, s = np.cos(rotation), np.sin(rotation)
    local = np.array([[c*scale[0], -s*scale[1], position[0]],
                      [s*scale[0], c*scale[1], position[1]], [0, 0, 1.]])
    local[:2, 2] -= local[:2, :2] @ anchor[:2]
    return matrix(layers[layer["parent"]], frame, layers) @ local if "parent" in layer else local


def coverage(layer, size=(145,142)):
    image = Image.new("L", size)
    for mask in layer["masksProperties"]:
        ImageDraw.Draw(image).polygon([tuple(p) for p in mask["pt"]["k"]["v"]],
                                      fill=255 if mask["mode"] == "a" else 0)
    return np.asarray(image) > 0


class PaintedMotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        build.build()
        cls.animation = json.loads((build.DEST / "pip.json").read_text())
        cls.layers = {layer["ind"]: layer for layer in cls.animation["layers"]}
        cls.markers = {marker["cm"]: marker for marker in cls.animation["markers"]}

    def layer(self, name, marker):
        frame = self.markers[marker]["tm"]
        return next(layer for layer in self.layers.values()
                    if layer["nm"] == name and layer["ip"] <= frame < layer["op"])

    def world(self, name, marker, frame, point):
        return (matrix(self.layer(name, marker), frame, self.layers) @ [*point, 1])[:2] * (100/512)

    def test_coach_ear_masks_leave_eyebrows_and_eye_paint_on_head(self):
        ear = coverage(self.layer("coach-right-ear", "coach-resting"))
        self.assertFalse(ear[45:59,105:121].any(), "Ear flick must not pull eyebrow paint")
        for name in ["coach-left-ear", "coach-right-ear"]:
            part = coverage(self.layer(name, "coach-resting"))
            self.assertGreater(part.sum(), 350, "An ear must retain its painted silhouette")
            self.assertFalse(part[64:85,75:125].any(), "Ear masks must exclude both eyes")

    def test_coach_head_does_not_retain_a_detached_upper_ear_sliver(self):
        head = coverage(self.layer("coach-head", "coach-resting"))
        self.assertFalse(head[:30,80:].any(), "All upper ear paint must travel with the ear")

    def test_coach_scarf_does_not_pull_isolated_paint_below_ground(self):
        scarf = coverage(self.layer("coach-scarf", "coach-saved"))
        torso = coverage(self.layer("coach-torso", "coach-saved"))
        self.assertFalse(scarf[136:138,98:102].any(),
                         "The isolated lower teal patch must not follow the nodding scarf")
        self.assertTrue(torso[136:138,98:102].all(),
                        "Original lower paint must stay on the ground-anchored torso")
        start = self.markers["coach-saved"]["tm"]
        ground = self.world("coach-right-paw","coach-saved",start,(111,140))[1]
        for frame in [0,6,12,18,24,36,48]:
            self.assertLessEqual(self.world("coach-torso","coach-saved",start+frame,(101,137))[1],ground,
                                 "The retained patch must stay above the planted paw sole")

    def test_coach_breath_is_readable_at_phone_scale_with_grounded_paws(self):
        marker = self.markers["coach-resting"]
        start = marker["tm"]
        peak = start + 120
        chest = self.world("coach-scarf", "coach-resting", peak, (96,113))
        chest0 = self.world("coach-scarf", "coach-resting", start, (96,113))
        head = self.world("coach-head", "coach-resting", peak, (95,78))
        head0 = self.world("coach-head", "coach-resting", start, (95,78))
        self.assertGreater(chest0[1]-chest[1], .8, "Chest rise must remain visible at 100pt")
        self.assertGreater(head0[1]-head[1], 1., "Head must inherit the breathing chest rise")
        for name, point in [("coach-left-paw", (88,137)), ("coach-right-paw", (111,137))]:
            np.testing.assert_allclose(self.world(name,"coach-resting",peak,point),
                                       self.world(name,"coach-resting",start,point), atol=.05)

    def test_submit_reacts_by_100ms_and_settles_within_850ms(self):
        for marker, prefix, point in [("submitted", "", (256,131)),
                                       ("coach-submitted", "coach-", (95,78))]:
            self.assertIn(marker, self.markers, "Accepted submit needs its own immediate marker")
            clip = self.markers[marker]
            self.assertGreaterEqual(clip["dr"],39)
            self.assertLessEqual(clip["dr"],51)
            start = clip["tm"]
            head0 = self.world(prefix+"head",marker,start,point)
            head6 = self.world(prefix+"head",marker,start+6,point)
            self.assertGreater(np.linalg.norm(head6-head0), .35,
                               "Submit movement must be visibly underway by 100ms")
            paw = self.layer(prefix+"left-paw",marker)
            self.assertGreater(abs(float(value(paw["ks"]["r"],start+6).ravel()[0])), .5)
            np.testing.assert_allclose(self.world(prefix+"head",marker,start+clip["dr"],point),head0,atol=.001)

    def test_submit_paw_lifts_instead_of_only_rotating_in_place(self):
        for marker, prefix, point in [("submitted", "", (254,240)),
                                       ("coach-submitted", "coach-", (88,137))]:
            start = self.markers[marker]["tm"]
            paw0 = self.world(prefix+"left-paw",marker,start,point)
            paw_peak = self.world(prefix+"left-paw",marker,start+13,point)
            self.assertGreater(paw0[1]-paw_peak[1], .8, "Small submit paw lift must read at 100pt")

    def test_coach_submit_face_reads_as_a_gesture_at_compact_88pt_size(self):
        marker = "coach-submitted"
        start = self.markers[marker]["tm"]
        origin = self.world("coach-head",marker,start,(95,78)) * .88
        movement = [np.linalg.norm(self.world("coach-head",marker,start+t,(95,78))*.88-origin)
                    for t in range(49)]
        self.assertGreaterEqual(max(movement),2.5,"Compact submit must be a visible head/chest action")

    def test_coach_saved_has_a_distinct_readable_nod_and_chest_action_at_88pt(self):
        marker = "coach-saved"
        start = self.markers[marker]["tm"]
        for layer, point in [("coach-head",(102,82)),("coach-scarf",(96,113))]:
            origin = self.world(layer,marker,start,point) * .88
            movement = [np.linalg.norm(self.world(layer,marker,start+t,point)*.88-origin)
                        for t in range(49)]
            self.assertGreaterEqual(max(movement),2.,"Saved needs a visible acknowledgment at 88pt")

    def test_coach_supporting_paw_stays_grounded_through_each_gesture(self):
        for marker, clip in self.markers.items():
            if not marker.startswith("coach-"): continue
            origin = self.world("coach-right-paw",marker,clip["tm"],(111,137))
            for frame in range(0,clip["dr"]+1,6):
                np.testing.assert_allclose(self.world("coach-right-paw",marker,clip["tm"]+frame,(111,137)),
                                           origin,atol=.001)

    def test_coach_painted_joints_keep_contact_during_larger_gestures(self):
        names = ["head","left-ear","right-ear","scarf","torso","left-paw","right-paw"]
        parts = {name:self.layer("coach-"+name,"coach-submitted") for name in names}
        masks = {name:Image.fromarray((coverage(layer)*255).astype("uint8")) for name,layer in parts.items()}
        contacts = [("head","left-ear"),("head","right-ear"),("head","scarf"),
                    ("scarf","torso"),("left-paw","torso"),("right-paw","torso")]
        for marker in ["coach-submitted","coach-saved","coach-reviewed"]:
            start = self.markers[marker]["tm"]
            for frame in range(0,self.markers[marker]["dr"]+1,3):
                rendered = {}
                for name,layer in parts.items():
                    inverse = np.linalg.inv(matrix(layer,start+frame,self.layers))
                    rendered[name] = np.asarray(masks[name].transform((512,512),Image.Transform.AFFINE,
                        tuple(inverse[:2].ravel()),Image.Resampling.NEAREST)) > 0
                for first,second in contacts:
                    self.assertGreater((rendered[first]&rendered[second]).sum(),400,
                                       f"{marker} frame{frame}: {first}/{second} must remain joined")

    def test_artifact_fits_runtime_and_all_coach_joins_are_neutral(self):
        self.assertLessEqual((build.DEST/"pip.json").stat().st_size, 1_048_576)
        for marker, clip in self.markers.items():
            if not marker.startswith("coach-"): continue
            for name in ["coach-head", "coach-scarf", "coach-left-ear", "coach-left-paw"]:
                layer = self.layer(name,marker)
                np.testing.assert_allclose(matrix(layer,clip["tm"],self.layers),
                                           matrix(layer,clip["tm"]+clip["dr"],self.layers),atol=.00001)


if __name__ == "__main__":
    unittest.main()
