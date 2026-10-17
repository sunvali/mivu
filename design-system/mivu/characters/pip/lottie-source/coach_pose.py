"""Register the exact seated peek from the approved context, without its interface."""
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
    take('scarf',teal)
    take('left-paw',polygon([(76,119),(94,119),(102,139),(72,142),(69,129)]))
    take('right-paw',polygon([(107,120),(120,120),(126,139),(99,142),(99,129)]))
    take('tail',polygon([(0,92),(35,90),(37,113),(65,142),(0,142)]))
    head=remaining & polygon([(0,0),(145,0),(145,99),(118,103),(79,107),(56,105),(43,98),(0,84)])
    take('left-ear',head & polygon([(23,28),(48,31),(61,37),(63,52),(58,65),(50,78),(49,85),(38,80),(28,65)]))
    # The painted eyebrow starts at y=46 and belongs to the rigid face, not this ear.
    take('right-ear',head & polygon([(80,-1),(145,-1),(145,42),(119,42),(108,40),(89,42),(80,39)]))
    take('head',head)
    parts['torso']=remaining
    assert np.array_equal(np.logical_or.reduce(list(parts.values())),whole)
    parts={name:(np.asarray(Image.fromarray(part.astype('uint8')*255).filter(
                ImageFilter.MaxFilter(3 if name.endswith('ear') else 5)))>0)&whole
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
        chest_keys.extend((start+t,y) for t,y in chest_motion(name,duration,3.2))
        paw_keys.extend((start+t,y) for t,y in (chest_motion(name,duration,3.) if name=='submitted'
                                               else [(0,0),(duration,0)]))
        motion=rotations(name,duration)
        for part in parts:
            authored=motion.get(part,[(0,0),(duration,0)])
            if name!='submitted':
                authored=[(t,v*.65) for t,v in authored]
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
