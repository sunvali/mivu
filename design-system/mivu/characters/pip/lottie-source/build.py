#!/usr/bin/env python3
"""Author Lottie joints/masks around the unchanged approved illustration atlas."""
from collections import defaultdict, deque
import hashlib
import json
from pathlib import Path
import shutil
from coach_pose import authored_peek

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[5]
SOURCE = ROOT / "design-system/mivu/characters/pip/storyboard.png"
DEST = ROOT / "ios/Mivu/Resources/Characters/pip"
EXPECTED = "5bef0e0459bf52c26fde44170c4b9419d0d4e4154779f51b0d01fdd1fd9166e1"

# Coordinates are in each 384x256 source cell, not a redrawn character.
POSES = {
    "resting": dict(cell=(0, 0), neck=(256, 131),
        tail=[(105,75),(187,75),(222,143),(239,175),(216,218),(162,231),(105,210)],
        ears=[[(188,10),(240,35),(250,57),(223,101),(203,96),(187,59)], [(272,45),(322,9),(328,68),(306,84)]],
        paw=[(237,146),(276,151),(276,250),(239,250)], pivot=(250,156)),
    "attentive": dict(cell=(0, 3), neck=(278, 103),
        tail=[(100,55),(191,55),(225,119),(234,153),(217,191),(143,199),(100,166)],
        ears=[[(216,13),(247,42),(265,73),(239,82),(209,62)], [(282,42),(341,11),(340,71),(313,88)]],
        paw=[(265,128),(301,128),(315,234),(273,238)], pivot=(278,144)),
    "thinking": dict(cell=(1, 3), neck=(229, 103),
        tail=[(104,66),(139,65),(159,73),(176,88),(191,111),(205,135),(216,159),(215,185),(198,207),(172,218),(130,207),(101,180),(85,143),(82,108),(91,80)],
        ears=[[(171,10),(212,35),(232,67),(205,83),(178,75)], [(226,49),(323,62),(302,102),(251,103)]],
        paw=[(210,104),(238,103),(247,143),(226,177),(206,166),(204,137)], pivot=(229,157)),
    "saved": dict(cell=(2, 1), neck=(185, 122),
        tail=[(218,88),(296,90),(323,140),(309,214),(263,240),(211,216),(199,177)],
        ears=[[(65,55),(121,48),(146,65),(139,105),(116,116),(80,89)], [(141,49),(153,0),(182,19),(205,60),(192,79),(164,62)]],
        paw=[(61,126),(88,127),(128,140),(153,124),(165,136),(147,156),(101,161),(66,157)], pivot=(155,139)),
    "reviewed": dict(cell=(1, 2), neck=(244, 112),
        tail=[(115,50),(192,50),(222,125),(238,180),(214,235),(150,242),(115,205)],
        ears=[[(207,12),(233,40),(245,64),(217,82),(198,61)], [(247,45),(295,32),(297,77),(275,91)]],
        paw=[(171,84),(194,83),(230,116),(244,132),(229,156),(201,138),(180,115)], pivot=(238,136),
        other_paw=[(263,118),(285,80),(310,89),(307,117),(281,147),(263,142)], other_pivot=(266,136)),
    "recovery": dict(cell=(2, 3), neck=(164, 107),
        tail=[(214,101),(283,99),(321,136),(324,206),(281,240),(216,228),(191,180)],
        ears=[[(108,9),(159,29),(182,52),(159,80),(121,67)], [(183,45),(268,41),(243,88),(202,104)]],
        paw=[(79,122),(108,122),(145,133),(169,145),(158,169),(125,163),(91,148)], pivot=(161,148)),
    "greeting": dict(cell=(2, 0), neck=(164, 141),
        tail=[(213,117),(266,118),(292,155),(279,217),(245,241),(194,231),(173,182)],
        ears=[[(118,6),(154,21),(171,69),(145,91),(116,82)], [(179,68),(274,60),(264,101),(218,131),(195,107)]],
        paw=[(65,98),(103,98),(108,128),(133,140),(144,149),(128,170),(108,165),(83,146),(71,129)], pivot=(132,150)),
}
# Long living loops and unhurried gestures. Every loop closes at its neutral pose.
CLIPS = []
frame = 0
for clip, duration in [("resting",480),("blink",18),("attentive",480),("submitted",48),("thinking",240),
                       ("saved",48),("reviewed",60),("recovery",240),("greeting",72)]:
    CLIPS.append((clip,frame,duration))
    frame += duration + 1
TODAY_END = frame


def polygon(points):
    image = Image.new("L", (384,352))
    ImageDraw.Draw(image).polygon([(x,y+48) for x,y in points], fill=255)
    return np.asarray(image) > 0


def silhouette(rgb):
    values = rgb.astype(int)
    color = ((values[:,:,0] - values[:,:,2] > 26) |
             ((values[:,:,1] - values[:,:,0] > 18) & (values[:,:,2] - values[:,:,0] > 9)) |
             (values.max(axis=2) < 155))
    height,width = color.shape
    # Keep the character, excluding neighboring-cell tips and the neutral shadow.
    visited = np.zeros_like(color)
    largest = []
    for y,x in zip(*np.where(color)):
        if visited[y,x]: continue
        queue = deque([(int(x),int(y))]); visited[y,x] = True; component = []
        while queue:
            px,py = queue.popleft(); component.append((px,py))
            for nx,ny in ((px-1,py),(px+1,py),(px,py-1),(px,py+1)):
                if 0 <= nx < width and 0 <= ny < height and color[ny,nx] and not visited[ny,nx]:
                    visited[ny,nx] = True; queue.append((nx,ny))
        if len(component) > len(largest): largest = component
    mask = Image.new("L", (width,height))
    pixels = mask.load()
    for x,y in largest: pixels[x,y] = 255
    exterior = mask.copy(); ImageDraw.floodfill(exterior, (0,0), 128)
    result = np.asarray(exterior) != 128
    assert 10_000 < result.sum() < 60_000, "Unexpected character silhouette"
    return result


def simplify(points, tolerance=0.45):
    if len(points) <= 3: return points
    a, b = np.array(points[0]), np.array(points[-1])
    vector = b-a; magnitude = float(np.linalg.norm(vector))
    distances = [float(np.linalg.norm(np.array(p)-a)) if magnitude == 0 else
                 abs(vector[0]*(p[1]-a[1])-vector[1]*(p[0]-a[0]))/magnitude for p in points]
    index = int(np.argmax(distances))
    if distances[index] <= tolerance: return [points[0],points[-1]]
    return simplify(points[:index+1],tolerance)[:-1] + simplify(points[index:],tolerance)


def contours(mask):
    edges = defaultdict(list)
    height,width = mask.shape
    for y,x in zip(*np.where(mask)):
        x,y = int(x),int(y)
        if y == 0 or not mask[y-1,x]: edges[(x,y)].append((x+1,y))
        if x == width-1 or not mask[y,x+1]: edges[(x+1,y)].append((x+1,y+1))
        if y == height-1 or not mask[y+1,x]: edges[(x+1,y+1)].append((x,y+1))
        if x == 0 or not mask[y,x-1]: edges[(x,y+1)].append((x,y))
    paths = []
    while edges:
        start = next(iter(edges)); current = start; points = []
        while True:
            points.append(current); following = edges[current].pop()
            if not edges[current]: del edges[current]
            current = following
            if current == start: break
        if len(points) < 4: continue
        area = sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(points,points[1:]+points[:1])) / 2
        if abs(area) < 1: continue
        points = simplify(points + points[:1])[:-1]
        paths.append((area,points))
    return sorted(paths, key=lambda item: -abs(item[0]))


def fixed(value): return {"a":0,"k":value}


def animated(keys, start):
    return {"a":1,"k":[{"t":start+t,"s":[value],"e":[keys[min(i+1,len(keys)-1)][1]],
                         "i":{"x":[0.58],"y":[1]},"o":{"x":[0.32],"y":[0]}}
                        for i,(t,value) in enumerate(keys)]}


def translated(keys, pivot, start):
    return {"a":1,"k":[{"t":start+t,"s":[pivot[0],pivot[1]+y,0],
        "i":{"x":[.58],"y":[1]},"o":{"x":[.32],"y":[0]}} for t,y in keys]}


def chest_motion(name, duration, rise):
    if name in ["resting","attentive"]:
        quiet = .75 if name == "attentive" else 1
        return [(t*duration,-v*rise*quiet) for t,v in [(0,0),(.25,1),(.5,0),(.75,.92),(1,0)]]
    if name in ["thinking","recovery"]:
        return [(0,0),(.5*duration,-rise*.55),(duration,0)]
    if name == "submitted":
        return [(0,0),(6,-rise*.85),(13,-rise),(25,rise*.18),(38,-rise*.08),(duration,0)]
    return [(0,0),(duration,0)]


def transform(pivot=(0,0), rotation=None):
    return {"a":fixed([*pivot,0]),"p":fixed([*pivot,0]),"s":fixed([100,100,100]),
            "r":rotation or fixed(0),"o":fixed(100)}


def masks_for(mask, offset):
    output = []
    for area,vertices in contours(mask):
        points = [[x+offset[0],y+offset[1]] for x,y in vertices]
        outgoing = [[round((points[(i+1)%len(points)][j]-points[i-1][j])*0.12,3) for j in (0,1)] for i in range(len(points))]
        incoming = [[-x,-y] for x,y in outgoing]
        output.append({"mode":"a" if area > 0 else "s","inv":False,"o":fixed(100),
                       "pt":fixed({"c":True,"v":points,"i":incoming,"o":outgoing})})
    return output


def split_parts(rgb, whole, pose):
    remaining = whole.copy(); parts = {}
    def take(name, region):
        part = remaining & region; remaining[part] = False; parts[name] = part
    # A slight overlap at painted scarf edges avoids losing its anti-aliasing.
    values = rgb.astype(int)
    teal = ((values[:,:,1]-values[:,:,0] > 12) & (values[:,:,2]-values[:,:,0] > 5)).astype("uint8")*255
    take("scarf", np.asarray(Image.fromarray(teal).filter(ImageFilter.MaxFilter(3))) > 0)
    take("left-paw", polygon(pose["paw"]))
    neck_x,neck_y = pose["neck"]
    other = pose.get("other_paw",[(neck_x+18,neck_y+40),(neck_x+55,neck_y+40),(neck_x+58,250),(neck_x+18,250)])
    if pose not in [POSES["saved"],POSES["recovery"],POSES["greeting"]]:
        take("right-paw",polygon(other))
    candidate = remaining & polygon([(neck_x-105,-48),(neck_x+118,-48),(neck_x+118,neck_y+4),(neck_x-105,neck_y+4)])
    if pose is POSES["thinking"]: candidate &= ~polygon(pose["tail"])
    target=(neck_x,neck_y-32+48)
    points=list(zip(*np.where(candidate)))
    sy,sx=min(points,key=lambda p:(p[1]-target[0])**2+(p[0]-target[1])**2)
    face=np.zeros_like(whole); queue=deque([(int(sx),int(sy))]); face[sy,sx]=True
    while queue:
        x,y=queue.popleft()
        for nx,ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if 0<=nx<384 and 0<=ny<352 and candidate[ny,nx] and not face[ny,nx]:
                face[ny,nx]=True; queue.append((nx,ny))
    for name,ear in zip(["left-ear","right-ear"],pose["ears"]): take(name,face & polygon(ear))
    take("head",face)
    take("tail", polygon(pose["tail"]))
    parts["torso"] = remaining
    union = np.zeros_like(whole)
    for part in parts.values(): union |= part
    assert np.array_equal(union,whole), "Every original character pixel must belong to a part"
    assert all(p.sum() > 3 for p in parts.values()), str({n:int(p.sum()) for n,p in parts.items()})
    # Overlap painted internal edges, retaining the exact exterior silhouette.
    return {name:(np.asarray(Image.fromarray(part.astype("uint8")*255).filter(ImageFilter.MaxFilter(5)))>0)&whole
            for name,part in parts.items()}


def rotations(name, duration):
    def keys(*values): return [(round(t*duration,3),v) for t,v in values]
    neutral = keys((0,0),(1,0))
    if name == "submitted":
        return {"head":keys((0,0),(.125,-1.4),(.27,-1.8),(.52,1.2),(.79,-.25),(1,0)),
                "left-ear":keys((0,0),(.125,-3),(.29,-3.4),(.6,.5),(1,0)),
                "right-ear":keys((0,0),(.125,2.4),(.32,2.8),(.68,-.3),(1,0)),
                "left-paw":keys((0,0),(.125,-2.7),(.3,-4),(.58,.6),(.85,0),(1,0)),
                "tail":keys((0,0),(.16,0),(.42,2),(.72,-.6),(1,0)),
                "scarf":keys((0,0),(.14,0),(.4,-1.2),(.7,.4),(1,0))}
    if name in ["resting","attentive"]:
        quiet = .75 if name == "attentive" else 1
        return {"head":keys((0,0),(.25,-.45*quiet),(.5,0),(.75,.35*quiet),(1,0)),
                "tail":keys((0,0),(.25,1.1*quiet),(.5,0),(.75,-.8*quiet),(1,0)),
                "scarf":keys((0,0),(.3,-.7*quiet),(.6,.55*quiet),(1,0)),
                "left-ear":keys((0,0),(.64,0),(.69,-2*quiet),(.77,.35*quiet),(.85,0),(1,0)),
                "right-ear":keys((0,0),(.18,0),(.23,1.6*quiet),(.32,-.25*quiet),(.4,0),(1,0))}
    if name == "greeting":
        return {"left-paw":keys((0,0),(.2,-4),(.44,4),(.66,-3),(.86,0),(1,0)),
                "head":keys((0,0),(.3,-1.2),(.65,.5),(1,0)),
                "tail":keys((0,0),(.35,2.5),(.7,-1.5),(1,0)),
                "scarf":keys((0,0),(.4,-1.5),(.75,.7),(1,0))}
    if name == "saved":
        return {"head":keys((0,0),(.35,2.5),(.7,-.5),(1,0)),
                "left-paw":keys((0,0),(.4,-2.5),(.75,.7),(1,0)),
                "tail":keys((0,0),(.5,2),(1,0)),"scarf":keys((0,0),(.45,1),(1,0))}
    if name == "reviewed":
        return {"left-paw":keys((0,0),(.35,-3),(.7,1),(1,0)),
                "right-paw":keys((0,0),(.35,3),(.7,-1),(1,0)),
                "head":keys((0,0),(.4,-1.4),(.75,.4),(1,0)),
                "tail":keys((0,0),(.4,-2.5),(.75,1),(1,0)),"scarf":keys((0,0),(.5,1.5),(1,0))}
    if name == "thinking":
        return {"head":keys((0,0),(.25,-1),(.5,0),(.75,.7),(1,0)),
                "left-paw":keys((0,0),(.35,1.2),(.7,-.6),(1,0)),
                "left-ear":keys((0,0),(.15,1),(.3,0),(1,0)),
                "right-ear":keys((0,0),(.55,-1),(.75,0),(1,0)),
                "tail":keys((0,0),(.5,1.3),(1,0))}
    if name == "recovery":
        return {"head":keys((0,0),(.4,1.5),(1,0)),"left-paw":keys((0,0),(.45,-2),(1,0))}
    return {"head":neutral}


def breathe(ks, pivot, motion, neck_y, start):
    # Only the torso stretches toward a fixed ground anchor; the feet never translate.
    ks["a"] = fixed([*pivot,0]); ks["p"] = fixed([*pivot,0])
    ks["s"] = {"a":1,"k":[{"t":start+t,"s":[100,100-y/(pivot[1]-neck_y)*100,100],
        "i":{"x":[.58],"y":[1]},"o":{"x":[.32],"y":[0]}}
        for t,y in motion]}


def build():
    source = SOURCE.read_bytes(); assert hashlib.sha256(source).hexdigest() == EXPECTED
    atlas = Image.open(SOURCE).convert("RGB"); rgb_atlas = np.asarray(atlas)
    layers = []; manifests = {}; next_index = 1
    for clip_index,(name,start,duration) in enumerate(CLIPS):
        pose = POSES["resting" if name in ["blink","submitted"] else name]
        col,row = pose["cell"]; offset = (col*384,row*256-48)
        rgb=np.full((352,384,3),255,dtype=np.uint8)
        low=max(0,offset[1]); high=min(1024,offset[1]+352)
        rgb[low-offset[1]:high-offset[1]]=rgb_atlas[low:high,offset[0]:offset[0]+384]
        whole = silhouette(rgb)
        try: parts = split_parts(rgb,whole,pose)
        except AssertionError as error: raise AssertionError(f"{name}: {error}") from error
        ys,xs = np.where(whole); center=(float(xs.min()+xs.max())/2,float(ys.max()+1))
        scale=440/(ys.max()+1-ys.min())
        end = CLIPS[clip_index+1][1] if clip_index+1 < len(CLIPS) else TODAY_END
        root_id=next_index; chest_id=next_index+1; head_id=next_index+2; next_index+=3
        root_transform=transform()
        root_transform.update({"a":fixed([center[0]+offset[0],center[1]+offset[1],0]),
                               "p":fixed([256,472,0]),"s":fixed([scale*100]*2+[100])})
        layers.append({"ddd":0,"ind":root_id,"ty":3,"nm":name+"-root","ks":root_transform,"ip":start,"op":end,"st":0})
        motion=rotations(name,duration)
        neck=(pose["neck"][0]+offset[0],pose["neck"][1]+48+offset[1])
        chest=chest_motion(name,duration,4.)
        chest_transform=transform(neck); chest_transform["p"]=translated(chest,neck,start)
        layers.append({"ddd":0,"ind":chest_id,"ty":3,"nm":name+"-chest-joint","parent":root_id,
                       "ks":chest_transform,"ip":start,"op":end,"st":0})
        layers.append({"ddd":0,"ind":head_id,"ty":3,"nm":name+"-head-joint","parent":chest_id,
                       "ks":transform(neck,animated(motion["head"],start) if "head" in motion else None),
                       "ip":start,"op":end,"st":0})
        for part in ["scarf","head","left-ear","right-ear","left-paw","right-paw","torso","tail"]:
            if part not in parts: continue
            if part in ["left-ear","right-ear"]:
                vertices=pose["ears"][0 if part=="left-ear" else 1]
                pivot=tuple(sum(v[k] for v in vertices[-2:])/2 for k in (0,1))
            elif part=="left-paw": pivot=pose["pivot"]
            elif part=="right-paw": pivot=pose.get("other_pivot",(pose["neck"][0]+30,pose["neck"][1]+45))
            elif part=="tail":
                pivots={"resting":(219,186),"blink":(219,186),"attentive":(218,151),"thinking":(211,183),
                        "submitted":(219,186),"saved":(205,183),"reviewed":(222,184),"recovery":(209,177),"greeting":(188,188)}
                pivot=pivots[name]
            else: pivot=pose["neck"]
            pivot=(pivot[0]+offset[0],pivot[1]+48+offset[1])
            rotation=animated(motion[part],start) if part in motion and part!="head" else None
            part_transform=transform(pivot,rotation)
            if part == "left-paw" and name == "submitted":
                part_transform["p"]=translated(chest_motion(name,duration,3.),pivot,start)
            if part == "torso":
                breathe(part_transform,(center[0]+offset[0],center[1]+offset[1]),chest,neck[1],start)
            layers.append({"ddd":0,"ind":next_index,"ty":2,"nm":part,"refId":"approved-artwork",
                           "parent":head_id if part in ["head","left-ear","right-ear"] else chest_id if part=="scarf" else root_id,
                           "ks":part_transform,"masksProperties":masks_for(parts[part],offset),
                           "ip":start,"op":end,"st":0,"sr":1,"bm":0})
            next_index+=1
        if name in ["resting","blink"]:
            lid_transform=transform()
            lid_transform["p"]=fixed([230,70,0])
            blink_keys = [(0,0),(300,0),(306,100),(310,100),(318,0),(duration,0)] if name == "resting" else [(0,0),(6,100),(10,100),(18,0)]
            lid_transform["o"]=animated(blink_keys,start)
            layers.insert(0,{"ddd":0,"ind":next_index,"ty":2,"nm":"blink-painted-eyelids",
                "refId":"painted-eyelids","parent":head_id,"ks":lid_transform,
                "ip":start,"op":end,"st":0})
            next_index+=1
        manifests[name]={"cell":pose["cell"],"ground":center[1],"bounds":[int(xs.min()),int(ys.min()),int(xs.max()),int(ys.max())],"scale":scale}
    animation={"v":"5.12.2","fr":60,"ip":0,"op":TODAY_END,"w":512,"h":512,"nm":"Pip approved illustration",
               "ddd":0,"assets":[{"id":"approved-artwork","w":1536,"h":1024,"u":"","p":"pip-artwork.png","e":0}],
               "layers":layers,"markers":[{"cm":n,"tm":s,"dr":d} for n,s,d in CLIPS],
               "meta":{"sourceSHA256":EXPECTED,"authoring":"Original illustration pixels, authored joint transforms and vector masks"}}
    lids=Image.open(Path(__file__).parent/"blink-source.png").convert("RGBA").crop((230,70,320,110))
    coverage=Image.new("L",(90,40))
    draw=ImageDraw.Draw(coverage)
    draw.ellipse((5,3,48,37),fill=255); draw.ellipse((58,2,87,36),fill=255)
    coverage=coverage.filter(ImageFilter.GaussianBlur(1.4))
    source_alpha=Image.open(DEST/"pip-artwork-alpha.png").convert("L").crop((230,70,320,110))
    coverage=Image.fromarray((np.asarray(coverage).astype(float)*np.asarray(source_alpha)/255).astype("uint8"))
    lids.putalpha(coverage)
    animation["assets"].append({"id":"painted-eyelids","w":90,"h":40,"u":"","p":"pip-eyelids.png","e":0})
    DEST.mkdir(parents=True,exist_ok=True)
    lids.save(DEST/"pip-eyelids.png")
    shutil.copy2(SOURCE,DEST/"pip-artwork.png")
    authored_peek(animation,next_index,TODAY_END,animated,masks_for,transform,breathe,
                  translated,chest_motion,rotations,[(n,d) for n,_,d in CLIPS])
    (DEST/"pip.json").write_text(json.dumps(animation,separators=(",",":"))+"\n")
    (Path(__file__).parent/"pose-registration.json").write_text(json.dumps(manifests,indent=2)+"\n")
    print(json.dumps({"layers":len(layers),"animationBytes":(DEST/"pip.json").stat().st_size,
                      "artworkBytes":len(source),"sourceSHA256":EXPECTED}))


if __name__ == "__main__": build()
