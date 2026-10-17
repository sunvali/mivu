"""Register the exact seated peek from the approved context, without its interface."""
from collections import deque
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT=Path(__file__).resolve().parents[5]
SOURCE=ROOT/'design-system/mivu/characters/pip/context.png'
DEST=ROOT/'ios/Mivu/Resources/Characters/pip'
SHA='1b3b0ec7ffdb43fa2993732ab836857c785b3f1a0da158f3f06dca1935345408'

def authored_peek(animation, index, first_frame, animated, masks_for, transform, breathe,
                  translated, chest_motion, rotations, clips):
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SHA
    crop=(845,612,990,754)
    rgb=np.asarray(Image.open(SOURCE).convert('RGB').crop(crop)).astype(float)
    mask=Image.fromarray((rgb.max(axis=2)>55).astype('uint8')*255)
    filled=mask.copy(); ImageDraw.floodfill(filled,(0,0),128)
    mask=Image.fromarray((np.asarray(filled)!=128).astype('uint8')*255)
    inner=np.asarray(mask.filter(ImageFilter.MinFilter(3)))>0
    outer=np.asarray(mask.filter(ImageFilter.MaxFilter(3)))>0
    alpha=inner.astype(float)
    background=np.array([13.,19.,22.])
    # Solve coverage only along the source contour; every opaque painted interior stays original.
    for y,x in zip(*np.where(outer & ~inner)):
        candidates=[]
        for ny in range(max(0,y-3),min(rgb.shape[0],y+4)):
            for nx in range(max(0,x-3),min(rgb.shape[1],x+4)):
                if inner[ny,nx]: candidates.append(((nx-x)**2+(ny-y)**2,ny,nx))
        if not candidates: continue
        _,ny,nx=min(candidates)
        foreground=rgb[ny,nx]-background
        alpha[y,x]=np.clip(np.dot(rgb[y,x]-background,foreground)/max(1,np.dot(foreground,foreground)),0,1)
    paint=np.clip((rgb-background*(1-alpha[:,:,None]))/np.maximum(alpha[:,:,None],1/255),0,255)
    rgba=np.dstack([paint,alpha*255]).astype('uint8')
    art=Image.fromarray(rgba)
    art.save(DEST/'pip-coach.png')
    assert np.all(rgba[inner,:3]==rgb[inner]), 'Opaque original painting must be preserved'
    # Only two registered painted eye edits are used; the generated layout/RGB body was rejected.
    edited=Image.open(Path(__file__).parent/'coach-blink-source.png').convert('RGBA')
    lids=Image.new('RGBA',art.size)
    for source,target in [((954,654,1007,696),(918,676,946,702)),((1030,642,1072,676),(954,668,975,692))]:
        patch=edited.crop(source).resize((target[2]-target[0],target[3]-target[1]),Image.Resampling.LANCZOS)
        coverage=Image.new('L',patch.size)
        ImageDraw.Draw(coverage).ellipse((1,1,patch.width-2,patch.height-2),fill=255)
        patch.putalpha(coverage.filter(ImageFilter.GaussianBlur(1.1)))
        lids.alpha_composite(patch,(target[0]-crop[0],target[1]-crop[1]))
    lids.putalpha(Image.fromarray((np.asarray(lids.getchannel('A')).astype(float)*alpha).astype('uint8')))
    lids.save(DEST/'pip-coach-eyelids.png')
    animation['assets'] += [dict(id='coach-peek',w=art.width,h=art.height,u='',p='pip-coach.png',e=0),
                            dict(id='coach-eyelids',w=art.width,h=art.height,u='',p='pip-coach-eyelids.png',e=0)]
    fixed=lambda value:dict(a=0,k=value)
    scale=356/art.height
    position=[256-art.width*scale/2,16,0]
    whole=np.asarray(art.getchannel('A'))>0
    remaining=whole.copy(); parts={}
    def polygon(points):
        coverage=Image.new('L',art.size);ImageDraw.Draw(coverage).polygon(points,fill=255)
        return np.asarray(coverage)>0
    def take(name,region):
        part=remaining & region;remaining[part]=False;parts[name]=part
    teal=(rgb[:,:,1]-rgb[:,:,0]>12)&(rgb[:,:,2]-rgb[:,:,0]>5)
    seen=np.zeros_like(whole); scarf=np.zeros_like(whole)
    for sy,sx in zip(*np.where(teal & whole)):
        if seen[sy,sx]: continue
        queue=deque([(int(sx),int(sy))]); seen[sy,sx]=True; component=[]
        while queue:
            x,y=queue.popleft(); component.append((y,x))
            for nx,ny in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                if 0<=nx<art.width and 0<=ny<art.height and teal[ny,nx] and whole[ny,nx] and not seen[ny,nx]:
                    seen[ny,nx]=True; queue.append((nx,ny))
        if len(component)>scarf.sum():
            scarf[:]=False
            for y,x in component: scarf[y,x]=True
    grounded_teal=teal & whole & ~scarf
    take('scarf',scarf)
    take('left-paw',polygon([(76,119),(94,119),(102,139),(72,142),(69,129)]))
    take('right-paw',polygon([(107,120),(120,120),(126,139),(99,142),(99,129)]))
    take('tail',polygon([(0,92),(35,90),(37,113),(65,142),(0,142)]))
    head=remaining & polygon([(0,0),(145,0),(145,99),(118,103),(79,107),(56,105),(43,98),(0,84)])
    take('left-ear',head & polygon([(23,28),(48,31),(61,37),(63,52),(58,65),(50,78),(49,85),(38,80),(28,65)]))
    # The painted eyebrow starts at y=46 and belongs to the rigid face, not this ear.
    take('right-ear',head & polygon([(80,-1),(145,-1),(145,42),(119,42),(108,40),(89,42),(80,39)]))
    take('head',head)
    parts['torso']=remaining
    # The six-pixel teal patch under the wrists is ground paint, not hanging scarf.
    for name,part in parts.items(): part[grounded_teal]=name=='torso'
    assert np.array_equal(np.logical_or.reduce(list(parts.values())),whole)
    parts={name:(np.asarray(Image.fromarray(part.astype('uint8')*255).filter(
                ImageFilter.MaxFilter(3 if name.endswith('ear') else 5)))>0)&whole&(~grounded_teal if name!='torso' else True)
           for name,part in parts.items()}
    # One rig shares its painted masks across all clips, keeping the JSON below 1 MiB.
    timeline=[]; start=first_frame
    for name,duration in clips:
        timeline.append((name,start,duration))
        animation['markers'].append(dict(cm='coach-'+name,tm=start,dr=duration))
        start+=duration+1
    end=start
    root=index; chest_joint=index+1; head_joint=index+2; index+=3
    def layer(identifier,name,ks,parent=None,**extra):
        result=dict(ddd=0,ind=identifier,ty=3,nm='coach-'+name,ks=ks,ip=first_frame,op=end,st=0)
        if parent is not None: result['parent']=parent
        result.update(extra)
        return result
    root_transform=transform()
    root_transform.update(p=fixed(position),s=fixed([scale*100,scale*100,100]))
    animation['layers'].append(layer(root,'root',root_transform))
    chest_keys=[]; paw_keys=[]; rotation_keys={name:[] for name in parts}; blink_keys=[]
    for name,start,duration in timeline:
        motion=rotations(name,duration)
        strength=.78 if name in ['resting','attentive'] else .65
        motion={part:[(t,v*strength) for t,v in keys] for part,keys in motion.items()}
        chest=chest_motion(name,duration,3.84 if name in ['resting','attentive'] else 3.2)
        paw=[(0,0),(duration,0)]
        def keys(*values): return [(round(t*duration,3),v) for t,v in values]
        if name=='submitted':
            chest=[(0,0),(6,-5.2),(13,-5.5),(25,1.3),(38,-.35),(duration,0)]
            paw=[(0,0),(6,-3.2),(13,-3.6),(25,.5),(38,0),(duration,0)]
            motion={'head':keys((0,0),(.125,-3.8),(.27,-4),(.52,4),(.79,-.6),(1,0)),
                    'left-ear':keys((0,0),(.125,-6),(.27,-6.5),(.6,1.2),(1,0)),
                    'right-ear':keys((0,0),(.125,5),(.32,5.5),(.68,-.8),(1,0)),
                    'left-paw':keys((0,0),(.125,-4.5),(.27,-6),(.52,2),(.79,-.3),(1,0)),
                    'tail':keys((0,0),(.16,0),(.42,2.6),(.72,-.9),(1,0)),
                    'scarf':keys((0,0),(.14,0),(.4,-2),(.7,1.3),(1,0))}
        if name=='saved':
            chest=keys((0,0),(.27,5.2),(.58,-2.6),(.82,.4),(1,0))
            paw=keys((0,0),(.27,.5),(.58,-.4),(1,0))
            motion={'head':keys((0,0),(.27,4.4),(.58,-2),(.82,.35),(1,0)),
                    'left-paw':keys((0,0),(.27,5.5),(.58,-1.5),(1,0)),
                    'left-ear':keys((0,0),(.32,1.2),(.68,-.4),(1,0)),
                    'right-ear':keys((0,0),(.37,-.8),(.72,.25),(1,0)),
                    'tail':keys((0,0),(.18,0),(.48,1.8),(.78,-.5),(1,0)),
                    'scarf':keys((0,0),(.15,0),(.42,1.5),(.73,-.6),(1,0))}
        if name=='reviewed':
            chest=keys((0,0),(.32,-3.8),(.66,.8),(1,0))
            motion['head']=keys((0,0),(.32,-3),(.66,.7),(1,0))
        # The supporting paw stays planted while the other wrist supplies the gesture.
        motion['right-paw']=[(0,0),(duration,0)]
        chest_keys.extend((start+t,y) for t,y in chest)
        paw_keys.extend((start+t,y) for t,y in paw)
        for part in parts:
            authored=motion.get(part,[(0,0),(duration,0)])
            rotation_keys[part].extend((start+t,v) for t,v in authored)
        blink=[(0,0),(duration,0)]
        if name in ['resting','attentive']:
            blink=[(0,0),(300,0),(306,100),(310,100),(318,0),(duration,0)]
        if name=='blink': blink=[(0,0),(6,100),(10,100),(18,0)]
        blink_keys.extend((start+t,v) for t,v in blink)
    chest_transform=transform((94,105))
    chest_transform['p']=translated(chest_keys,(94,105),0)
    animation['layers'].append(layer(chest_joint,'chest-joint',chest_transform,root))
    animation['layers'].append(layer(head_joint,'head-joint',
        transform((94,105),animated(rotation_keys['head'],0)),chest_joint))
    pivots={'head':(94,105),'left-ear':(53,70),'right-ear':(110,40),
            'tail':(55,138),'scarf':(101,112),'left-paw':(88,124),'right-paw':(111,124),'torso':(98,141)}
    for part in ['scarf','left-paw','right-paw','head','left-ear','right-ear','torso','tail']:
        ks=transform(pivots[part],animated(rotation_keys[part],0) if part!='head' else None)
        if part=='left-paw': ks['p']=translated(paw_keys,pivots[part],0)
        if part=='torso': breathe(ks,pivots[part],chest_keys,105,0)
        parent=head_joint if part in ['head','left-ear','right-ear'] else chest_joint if part=='scarf' else root
        animation['layers'].append(layer(index,part,ks,parent,ty=2,refId='coach-peek',
            masksProperties=masks_for(parts[part],(0,0))))
        index+=1
    ks=transform();ks['o']=animated(blink_keys,0)
    animation['layers'].insert(0,layer(index,'painted-eyelids',ks,head_joint,ty=2,refId='coach-eyelids'))
    animation['op']=end
    animation['meta']['contextSHA256']=SHA
    fallback=Image.new('RGBA',(512,512))
    resized=art.resize((round(art.width*scale),356),Image.Resampling.LANCZOS)
    fallback.alpha_composite(resized,(round(position[0]),16))
    folder=ROOT/'ios/Mivu/Assets.xcassets/Companion/Pip/PipCoach.imageset'
    folder.mkdir(exist_ok=True)
    fallback.save(folder/'pip.png')
    (folder/'Contents.json').write_text(json.dumps(dict(images=[dict(filename='pip.png',idiom='universal')],info=dict(author='xcode',version=1)))+'\n')
