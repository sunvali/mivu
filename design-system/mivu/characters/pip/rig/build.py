"""Convert rig/pip.svg into ios/Mivu/Resources/Characters/pip/pip-rig.json.

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
SVG = "{http://www.w3.org/2000/svg}"
SETS = ("standing", "seated", "curled")
IDENTITY = (1, 0, 0, 1, 0, 0)
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
        child_hidden = hidden or child.get("display") == "none"
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
            parts.append({
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
            })
        collect(child, m, part_id or parent, child_set, parts, child_hidden, child_view)


def build():
    root = ET.parse(SOURCE).getroot()
    parts = []
    collect(root, IDENTITY, None, None, parts)
    rig = {"version": 2, "artboard": 512, "ground": 472, "parallaxScale": PARALLAX_SCALE,
           "frames": {"today": [40, 32, 432, 440], "coach": [40, 32, 432, 440]},
           "parts": sorted(parts, key=lambda p: p["z"])}
    OUTPUT.write_text(json.dumps(rig, separators=(",", ":")) + "\n")
    return rig


def render_sets(out_dir):
    import cairosvg

    out_dir.mkdir(parents=True, exist_ok=True)
    ET.register_namespace("", SVG[1:-1])
    source = ET.parse(SOURCE).getroot()
    for name in SETS:
        root = copy.deepcopy(source)
        for g in root.iter(f"{SVG}g"):
            if g.get("data-set") not in (None, name):
                g.set("display", "none")
        cairosvg.svg2png(bytestring=ET.tostring(root), write_to=str(out_dir / f"pip-{name}.png"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--png", type=Path, help="also render each part set to OUT_DIR")
    args = parser.parse_args()
    rig = build()
    print(f"wrote {len(rig['parts'])} parts to {OUTPUT}")
    if args.png:
        render_sets(args.png)
