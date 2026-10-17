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

def authored_peek(animation, index):
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
    for name,start,duration,end in [('coach-resting',400,1,410),('coach-blink',410,9,440)]:
        transform=dict(a=fixed([0,0,0]),p=fixed(position),s=fixed([scale*100,scale*100,100]),r=fixed(0),o=fixed(100))
        animation['layers'].append(dict(ddd=0,ind=index,ty=2,nm='approved-coach-peek',refId='coach-peek',ks=transform,ip=start,op=end,st=0))
        index+=1
        if name=='coach-blink':
            eyelid_transform=transform.copy()
            eyelid_transform['o']=dict(a=1,k=[dict(t=start+t,s=[value],i=dict(x=[.58],y=[1]),o=dict(x=[.32],y=[0])) for t,value in [(0,0),(4,100),(5,100),(9,0)]])
            animation['layers'].insert(0,dict(ddd=0,ind=index,ty=2,nm='coach-painted-eyelids',refId='coach-eyelids',ks=eyelid_transform,ip=start,op=end,st=0))
            index+=1
        animation['markers'].append(dict(cm=name,tm=start,dr=duration))
    animation['op']=440
    animation['meta']['contextSHA256']=SHA
    fallback=Image.new('RGBA',(512,512))
    resized=art.resize((round(art.width*scale),356),Image.Resampling.LANCZOS)
    fallback.alpha_composite(resized,(round(position[0]),16))
    folder=ROOT/'ios/Mivu/Assets.xcassets/Companion/Pip/PipCoach.imageset'
    folder.mkdir(exist_ok=True)
    fallback.save(folder/'pip.png')
    (folder/'Contents.json').write_text(json.dumps(dict(images=[dict(filename='pip.png',idiom='universal')],info=dict(author='xcode',version=1)))+'\n')
