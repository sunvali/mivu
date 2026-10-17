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

def authored_peek(animation, index, first_frame, animated, masks_for, transform, breathe):
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
    head=remaining & polygon([(0,0),(145,0),(145,109),(54,109),(0,84)])
    take('left-ear',head & polygon([(21,25),(69,39),(59,82),(29,82)]))
    take('right-ear',head & polygon([(87,41),(111,0),(127,0),(133,55),(116,65)]))
    take('head',head)
    parts['torso']=remaining
    assert np.array_equal(np.logical_or.reduce(list(parts.values())),whole)
    parts={name:(np.asarray(Image.fromarray(part.astype('uint8')*255).filter(ImageFilter.MaxFilter(3)))>0)&whole
           for name,part in parts.items()}
    clips=[('resting',480),('blink',18),('attentive',360),('thinking',240),
           ('saved',90),('reviewed',108),('recovery',240),('greeting',132)]
    start=first_frame
    for name,duration in clips:
        end=start+duration+1
        root=index;head_joint=index+1;index+=2
        root_transform=transform()
        root_transform.update(p=fixed(position),s=fixed([scale*100,scale*100,100]))
        animation['layers'].append(dict(ddd=0,ind=root,ty=3,nm='coach-'+name+'-root',ks=root_transform,ip=start,op=end,st=0))
        def keys(*values):return [(round(t*duration,3),v) for t,v in values]
        quiet=.4 if name=='attentive' else 1
        head_motion=keys((0,0),(.25,-.4*quiet),(.5,0),(.75,.3*quiet),(1,0))
        if name=='saved': head_motion=keys((0,0),(.35,1.6),(.7,-.4),(1,0))
        if name=='reviewed': head_motion=keys((0,0),(.4,-1.3),(.75,.4),(1,0))
        if name=='greeting': head_motion=keys((0,0),(.35,-1.2),(.7,.4),(1,0))
        if name=='recovery': head_motion=keys((0,0),(.4,1),(1,0))
        animation['layers'].append(dict(ddd=0,ind=head_joint,ty=3,nm='coach-head-joint',parent=root,
            ks=transform((94,105),animated(head_motion,start)),ip=start,op=end,st=0))
        pivots={'head':(94,105),'left-ear':(53,65),'right-ear':(113,52),
                'tail':(55,138),'scarf':(101,112),'left-paw':(88,138),'right-paw':(111,138),'torso':(98,141)}
        for part in ['scarf','left-paw','right-paw','head','left-ear','right-ear','torso','tail']:
            motion=None
            if part=='tail':motion=keys((0,0),(.25,.7*quiet),(.5,0),(.75,-.5*quiet),(1,0))
            if part=='scarf':motion=keys((0,0),(.3,-.6*quiet),(.6,.4*quiet),(1,0))
            if part=='left-ear':motion=keys((0,0),(.63,0),(.72,-.7*quiet),(.86,0),(1,0))
            if part=='right-ear':motion=keys((0,0),(.18,0),(.28,.6*quiet),(.4,0),(1,0))
            if part=='left-paw' and name=='greeting':motion=keys((0,0),(.25,-3),(.48,1.5),(.7,-2),(1,0))
            ks=transform(pivots[part],animated(motion,start) if motion else None)
            if part=='torso':breathe(ks,pivots[part],duration,start,.45*quiet)
            animation['layers'].append(dict(ddd=0,ind=index,ty=2,nm='coach-'+part,refId='coach-peek',
                parent=head_joint if part in ['head','left-ear','right-ear'] else root,
                ks=ks,masksProperties=masks_for(parts[part],(0,0)),ip=start,op=end,st=0))
            index+=1
        blink_keys=None
        if name=='resting':blink_keys=[(0,0),(300,0),(306,100),(310,100),(318,0),(duration,0)]
        if name=='attentive':blink_keys=[(0,0),(240,0),(246,100),(250,100),(258,0),(duration,0)]
        if name=='blink':blink_keys=[(0,0),(6,100),(10,100),(18,0)]
        if blink_keys:
            ks=transform();ks['o']=animated(blink_keys,start)
            animation['layers'].insert(0,dict(ddd=0,ind=index,ty=2,nm='coach-painted-eyelids',refId='coach-eyelids',
                parent=head_joint,ks=ks,ip=start,op=end,st=0));index+=1
        animation['markers'].append(dict(cm='coach-'+name,tm=start,dr=duration))
        start=end
    animation['op']=start
    animation['meta']['contextSHA256']=SHA
    fallback=Image.new('RGBA',(512,512))
    resized=art.resize((round(art.width*scale),356),Image.Resampling.LANCZOS)
    fallback.alpha_composite(resized,(round(position[0]),16))
    folder=ROOT/'ios/Mivu/Assets.xcassets/Companion/Pip/PipCoach.imageset'
    folder.mkdir(exist_ok=True)
    fallback.save(folder/'pip.png')
    (folder/'Contents.json').write_text(json.dumps(dict(images=[dict(filename='pip.png',idiom='universal')],info=dict(author='xcode',version=1)))+'\n')
