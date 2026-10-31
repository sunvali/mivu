"""Convert rig/pip.svg into pip-rig.json for iOS (ios/Mivu/Resources/Characters/pip/) and Android (android/app/src/main/assets/pip/).

Usage: python3 build.py [--png OUT_DIR]   (--png needs cairosvg, see README)
"""
import argparse
import copy
import json
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "pip.svg"
OUTPUT = HERE.parents[4] / "ios/Mivu/Resources/Characters/pip/pip-rig.json"
ANDROID_OUTPUT = HERE.parents[4] / "android/app/src/main/assets/pip/pip-rig.json"  # Android keeps its own copy
SVG = "{http://www.w3.org/2000/svg}"
SETS = ("standing", "seated", "curled")
IDENTITY = (1, 0, 0, 1, 0, 0)
FALLBACKS = {"PipResting": "standing", "PipPreview": "standing", "PipCoach": "seated"}  # imageset -> set
PARALLAX_SCALE = 20  # artboard units a parallax-1.0 part slides at a full in-view turn


def multiply(m, n):
    a, b, c, d, e, f = m
    p, q, r, s, t, u = n
    return (a * p + c * q, b * p + d * q, a * r + c * s, b * r + d * s,
            a * t + c * u + e, b * t + d * u + f)


def parse_transform(text):
    matrix = IDENTITY
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", text or ""):
        v = [float(x) for x in re.split(r"[\s,]+", args.strip())]
        if name == "matrix":
            step = tuple(v)
        elif name == "translate":
            step = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == "scale":
            step = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == "rotate":
            r = math.radians(v[0])
            cx, cy = (v[1], v[2]) if len(v) == 3 else (0, 0)
            step = multiply(multiply((1, 0, 0, 1, cx, cy),
                                     (math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0)),
                            (1, 0, 0, 1, -cx, -cy))
        else:
            raise ValueError(f"unsupported transform {name}")
        matrix = multiply(matrix, step)
    return matrix


def apply(m, x, y):
    a, b, c, d, e, f = m
    return a * x + c * y + e, b * x + d * y + f


def number(v):
    text = f"{v:.1f}".rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def flatten_path(d, m, part_id):
    """Apply matrix m to an absolute M/L/C/Q/Z path; any other command is an authoring error."""
    out, coords = [], []
    for token in re.findall(r"[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)", d):
        if token.isalpha():
            if token not in "MLCQZ":
                raise ValueError(f"{part_id}: use absolute M/L/C/Q/Z only, found {token}")
            out.append(token)
        else:
            coords.append(float(token))
            if len(coords) == 2:
                out.extend(number(v) for v in apply(m, *coords))
                coords = []
    if coords:
        raise ValueError(f"{part_id}: odd coordinate count")
    return " ".join(out)


def swap_side(text):
    """ear-l <-> ear-r: -l/-r always name the viewer's side, so a mirror swaps them."""
    return re.sub(r"-([lr])(?=[.@]|$)", lambda m: "-r" if m.group(1) == "l" else "-l", text)


def mirror_view(parts, source, target, hidden):
    """Append a copy of view `source` reflected about its head pivot x, renamed to view `target`."""
    rename = lambda part_id: part_id and swap_side(part_id.replace(f"@{source}", f"@{target}"))
    by_id = {p["id"]: p for p in parts}
    axis = by_id[f"head@{source}"]["pivot"][0]
    for p in [p for p in parts if p["view"] == source]:
        flip = (-1, 0, 0, 1, 2 * axis, 0)
        pivot_x = 2 * axis - p["pivot"][0]
        if "glint" in p["id"]:  # highlights keep the light on the same side: follow the parent unflipped
            shift = 2 * axis - 2 * by_id[p["parent"]]["pivot"][0]
            flip, pivot_x = (1, 0, 0, 1, shift, 0), p["pivot"][0] + shift
        parts.append(dict(p, id=rename(p["id"]), parent=rename(p["parent"]), z=len(parts), view=target,
                          shape=p["shape"] and swap_side(p["shape"]), visible=p["visible"] and not hidden,
                          pivot=[float(number(pivot_x)), p["pivot"][1]],
                          path=flatten_path(p["path"], flip, p["id"])))


def collect(node, matrix, parent, part_set, parts, hidden=False, view=None):
    for child in node:
        if child.tag != f"{SVG}g":
            continue
        m = multiply(matrix, parse_transform(child.get("transform")))
        child_set = child.get("data-set") or part_set
        # A view group is display="none" only so the SVG previews one head; the runtime picks the view.
        child_hidden = hidden or (child.get("display") == "none" and not child.get("data-view"))
        child_view = child.get("data-view") or view
        if child.get("data-mirror-of"):
            mirror_view(parts, child.get("data-mirror-of"), child_view, child_hidden)
            continue
        part_id = child.get("id")
        if part_id:
            path = child.find(f"{SVG}path")
            if path is None:
                raise ValueError(f"{part_id}: every part needs one direct <path>")
            if not child.get("data-pivot"):
                raise ValueError(f"{part_id}: every part needs data-pivot")
            pivot = [float(v) for v in child.get("data-pivot").split()]
            part = {
                "id": part_id,
                "parent": child.get("data-parent") or parent,
                "pivot": [float(number(v)) for v in apply(m, *pivot)],
                "z": len(parts),
                "set": child_set,
                "view": child_view,
                "shape": child.get("data-shape"),
                "visible": not child_hidden,
                "parallax": float(child.get("data-parallax", 0)),
                "fill": path.get("fill"),
                "fillDark": path.get("data-fill-dark") or path.get("fill"),
                "path": flatten_path(path.get("d"), m, part_id),
            }
            if child.get("data-mount"):  # body of a set: where the head views sit on it, art = k * head + t
                part["mount"] = [float(v) for v in child.get("data-mount").split()]
            parts.append(part)
        collect(child, m, part_id or parent, child_set, parts, child_hidden, child_view)


def set_bounds(parts, name, below=None):
    """Union bounds of a set at rest: its visible parts plus the default head view on its mount (points above `below`)."""
    k, tx, ty = next(p["mount"] for p in parts if p["id"] == ("body" if name == "standing" else f"body@{name}"))
    xs, ys = [], []
    for p in parts:
        if p["visible"] and (p["set"] == name or p["view"] == "right"):
            v = [float(t) for t in re.findall(r"-?[\d.]+", p["path"])]
            px, py = v[0::2], v[1::2]
            if p["view"]:
                px, py = [k * x + tx for x in px], [k * y + ty for y in py]
            kept = [(x, y) for x, y in zip(px, py) if below is None or y <= below]
            xs += [x for x, _ in kept]
            ys += [y for _, y in kept]
    return min(xs), min(ys), max(xs), max(ys)


def coach_frame(root, parts):
    """Coach shows a bust peeking over the composer: down to the seated body's `data-peek` bar line, where the paws rest."""
    peek = float(next(g.get("data-peek") for g in root.iter(f"{SVG}g") if g.get("id") == "body@seated"))
    x0, y0, x1, _ = set_bounds(parts, "seated", below=peek)
    return frame((x0, y0, x1, peek), 6)[:3] + [float(number(peek - (y0 - 6)))]


def frame(bounds, pad, aspect=None):
    """[x, y, w, h] around bounds with padding, widened or heightened to `aspect` (w / h) if given."""
    x0, y0, x1, y1 = bounds[0] - pad, bounds[1] - pad, bounds[2] + pad, bounds[3] + pad
    if aspect:
        w, h = x1 - x0, y1 - y0
        grow_w, grow_h = max(0, h * aspect - w) / 2, max(0, w / aspect - h) / 2
        x0, x1, y0, y1 = x0 - grow_w, x1 + grow_w, y0 - grow_h, y1 + grow_h
    return [float(number(v)) for v in (x0, y0, x1 - x0, y1 - y0)]


def build():
    root = ET.parse(SOURCE).getroot()
    parts = []
    collect(root, IDENTITY, None, None, parts)
    rig = {"version": 2, "artboard": 512, "ground": 472, "parallaxScale": PARALLAX_SCALE,
           "frames": {"today": frame(set_bounds(parts, "standing"), 8), "coach": coach_frame(root, parts)},
           "parts": sorted(parts, key=lambda p: p["z"])}
    for output in (OUTPUT, ANDROID_OUTPUT):
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    return rig


def set_svg(name, dark=False, crop=None):
    """The SVG showing one body set at rest, with the head views mounted on its body.

    `crop` ([x, y, w, h]) clips to that frame and centres it in a square canvas of the usual size, the way the app
    centres a square fallback over the rig's crop."""
    ET.register_namespace("", SVG[1:-1])
    root = ET.parse(SOURCE).getroot()
    if crop:
        x, y, w, h = crop
        side = max(w, h)
        root.set("viewBox", " ".join(number(v) for v in (x - (side - w) / 2, y - (side - h) / 2, side, side)))
        clip = ET.SubElement(ET.SubElement(root, f"{SVG}defs"), f"{SVG}clipPath", id="crop")
        ET.SubElement(clip, f"{SVG}rect", x=number(x), y=number(y), width=number(w), height=number(h))
        for g in root.findall(f"{SVG}g"):
            g.set("clip-path", "url(#crop)")
    body = "body" if name == "standing" else f"body@{name}"
    mount = next((g.get("data-mount") for g in root.iter(f"{SVG}g") if g.get("id") == body), "1 0 0")
    k, tx, ty = mount.split()
    for g in root.iter(f"{SVG}g"):
        if g.get("data-set") not in (None, name):
            g.set("display", "none")
    for g in root.findall(f"{SVG}g"):
        if g.get("data-view") or g.get("data-parent") == "body":
            g.set("transform", f"matrix({k} 0 0 {k} {tx} {ty}) " + (g.get("transform") or ""))
    if dark:
        for path in root.iter(f"{SVG}path"):
            path.set("fill", path.get("data-fill-dark") or path.get("fill"))
    return ET.tostring(root)


def render_sets(out_dir, rig):
    import cairosvg

    out_dir.mkdir(parents=True, exist_ok=True)
    for name in SETS:
        for dark in (False, True):
            target = out_dir / f"pip-{name}{'-dark' if dark else ''}.png"
            cairosvg.svg2png(bytestring=set_svg(name, dark), write_to=str(target))
    for imageset, name in FALLBACKS.items():
        folder = OUTPUT.parents[3] / f"Assets.xcassets/Companion/Pip/{imageset}.imageset"
        for entry in json.loads((folder / "Contents.json").read_text())["images"]:
            dark = any(a.get("value") == "dark" for a in entry.get("appearances", []))
            crop = rig["frames"]["coach"] if imageset == "PipCoach" else None  # Coach's fallback is the same bust
            cairosvg.svg2png(bytestring=set_svg(name, dark, crop), write_to=str(folder / entry["filename"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--png", type=Path, help="also render each set (light, dark) to OUT_DIR and the fallback imagesets")
    args = parser.parse_args()
    rig = build()
    print(f"wrote {len(rig['parts'])} parts to {OUTPUT} and {ANDROID_OUTPUT}")
    if args.png:
        render_sets(args.png, rig)
