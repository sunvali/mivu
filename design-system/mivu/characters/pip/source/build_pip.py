#!/usr/bin/env python3
"""Author the script-free Pip RML rig and matching vector fallback PDFs.

Run with the workspace Python runtime (ReportLab) then Rive CLI --verify/--once.
All shapes, timelines and bindings are editable source; no binary patching.
"""
from pathlib import Path
import json, math, xml.etree.ElementTree as ET
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from geometry import GROUPS, Group, Shape
from paths import commands

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[4]
ASSETS=REPO/'ios/Mivu/Assets.xcassets/Companion/Pip'
POSES=['Resting','Attentive','Thinking','Saved','Reviewed','Recovery','Greeting','Blink']
DURATION=[1,15,140,45,65,20,70,15]
DARK={'#FFE0B4':'#F6D6AF','#FFE2BC':'#F6D6AF','#FFF0D7':'#FBE5C7','#FFEACB':'#F8DDBB','#FFF8E8':'#FFF0D7','#FFA456':'#F39950','#FFFFFF':'#FFF4DF','#37939A':'#40969C','#287C88':'#318691'}
HEADPARTS={'Head','EarLeft','EarRight','Eyes','Brows','Lids','OpenMouth'}
groups=list(GROUPS)
back=next(g for g in groups if g.name=='ArmBack')
groups.remove(back)
groups.insert(next(i for i,g in enumerate(groups) if g.name=='ArmFront'),back)
groups.insert(next(i for i,g in enumerate(groups) if g.name=='Brows'),Group('Lids',(248,198),(
 Shape('Left closed lid','M 188 200 C 196 190 208 190 220 200','none','#67402B',3.4),
 Shape('Right closed lid','M 276 202 C 283 192 296 193 306 203','none','#67402B',3.4),
)))
groups.insert(next(i for i,g in enumerate(groups) if g.name=='Brows'),Group('OpenMouth',(254,242),(
 Shape('Happy mouth','M 240 240 C 250 245 262 246 277 240 C 273 257 265 262 257 261 C 248 260 242 251 240 240 Z','#583025'),
 Shape('Tongue','M 251 255 C 255 250 264 251 270 254 C 265 261 258 263 251 255 Z','#DD7B62'),
)))

serial=1000
nodes={};colors=[]
def E(parent,tag,**kw):
 global serial
 kw={k:str(v) for k,v in kw.items()}
 if 'id' not in kw:serial+=1;kw['id']=f'0:{serial}'
 return ET.SubElement(parent,tag,kw)

def contours(path):
 result=[];verts=[];closed=False
 for op,v in commands(path):
  if op=='M':
   if verts:result.append((verts,closed))
   verts=[{'p':v,'in':v,'out':v}];closed=False
  elif op=='L':verts.append({'p':v,'in':v,'out':v})
  elif op=='C':
   verts[-1]['out']=v[:2];p=v[4:6];verts.append({'p':p,'in':v[2:4],'out':p})
  elif op=='Z':
   closed=True
   if verts[-1]['p']==verts[0]['p']:
    verts[0]['in']=verts[-1]['in'];verts.pop()
 if verts:result.append((verts,closed))
 return result

def paint(parent,kind,color,width=0):
 args={'name':kind}
 if kind=='Stroke':args.update(thickness=width,cap='round',join='round')
 p=E(parent,kind,**args)
 col=E(p,'SolidColor',colorValue='FF'+color[1:],name='Color')
 colors.append((col.attrib['id'],color))

def draw(parent,g,parent_pivot=(0,0)):
 px,py=g.pivot
 node=E(parent,'Node',name=g.name,x=px-parent_pivot[0],y=py-parent_pivot[1],opacity=0 if g.name in {'Lids','OpenMouth'} else 1)
 nodes[g.name]=node.attrib['id']
 for s in reversed(g.shapes):
  shape=E(node,'Shape',name=s.name,x=-px,y=-py)
  for vertices,closed in contours(s.path):
   area=sum(a['p'][0]*b['p'][1]-b['p'][0]*a['p'][1] for a,b in zip(vertices,vertices[1:]+vertices[:1]))
   path=E(shape,'PointsPath',name='Path',isClosed=str(closed).lower(),isClockwise=str(area>=0).lower())
   for vertex in vertices:
    x,y=vertex['p'];ix,iy=vertex['in'];ox,oy=vertex['out']
    E(path,'CubicDetachedVertex',x=x,y=y,inRotation=math.atan2(iy-y,ix-x),inDistance=math.hypot(ix-x,iy-y),outRotation=math.atan2(oy-y,ox-x),outDistance=math.hypot(ox-x,oy-y))
  if s.color!='none':paint(shape,'Fill',s.color)
  if s.stroke:paint(shape,'Stroke',s.stroke,s.width)
 return node

root=ET.Element('Rive',version='1',kind='fragment')
art=E(root,'Artboard',id='0:2',name='MivuCompanion',width=512,height=512,viewModelId='0:40',viewModelInstanceId='0:41',defaultStateMachineId='0:7',styleId='0:5')
E(art,'LayoutComponentStyle',id='0:5',name='Artboard style')
sm=E(art,'StateMachine',id='0:7',name='Companion')
rig=E(art,'Node',name='Pip',x=0,y=0)
# First declared siblings paint in front. HeadRig keeps eyes and ears on the head.
head_done=False
for g in reversed(groups):
 if g.name in HEADPARTS:
  if head_done:continue
  head_done=True
  head=E(rig,'Node',name='HeadRig',x=240,y=270)
  nodes['HeadRig']=head.attrib['id']
  for child in reversed(groups):
   if child.name in HEADPARTS:draw(head,child,(240,270))
 else:draw(rig,g)

# Exact keyed defaults in every pose make interruption restore all body parts.
DEFAULT={('HeadRig','rotation'):0,('HeadRig','y'):270,('Eyes','scaleY'):1,('Eyes','opacity'):1,('Lids','opacity'):0,('OpenMouth','opacity'):0,('ArmFront','rotation'):0,('ArmBack','rotation'):0,('Tail','rotation'):0,('ScarfEnds','rotation'):0,('EarLeft','rotation'):0,('EarRight','rotation'):0,('Body','scaleY'):1}
KEY={'rotation':15,'y':14,'scaleY':17,'opacity':18}
rad=math.radians
# Timecodes in hundredths of a second. All one-shots include their settle.
TRACKS={
 'Resting':{},
 'Attentive':{('HeadRig','rotation'):[(0,0),(15,rad(3))],('EarLeft','rotation'):[(0,0),(15,rad(5))]},
 'Thinking':{('HeadRig','rotation'):[(0,rad(1)),(35,rad(-4)),(70,rad(-3)),(105,rad(1)),(140,rad(1))],('ArmFront','rotation'):[(0,rad(-100)),(35,rad(-105)),(70,rad(-103)),(105,rad(-100)),(140,rad(-100))],('EarRight','rotation'):[(0,0),(35,rad(5)),(70,rad(2)),(105,0),(140,0)]},
 'Saved':{('HeadRig','rotation'):[(0,0),(7,rad(-2)),(19,rad(6)),(28,rad(2)),(45,0)],('Eyes','scaleY'):[(0,1),(12,1),(19,.08),(28,1),(45,1)],('ArmFront','rotation'):[(0,0),(7,rad(5)),(19,rad(35)),(28,rad(48)),(45,0)],('Tail','rotation'):[(0,0),(11,0),(28,rad(-7)),(45,0)],('ScarfEnds','rotation'):[(0,0),(12,rad(4)),(32,rad(-3)),(45,0)]},
 'Reviewed':{('Body','scaleY'):[(0,1),(9,.97),(26,1.03),(38,1.02),(65,1)],('HeadRig','y'):[(0,270),(9,273),(26,265),(38,267),(65,270)],('ArmFront','rotation'):[(0,0),(9,rad(-8)),(26,rad(123)),(38,rad(113)),(65,0)],('ArmBack','rotation'):[(0,0),(9,rad(8)),(26,rad(-105)),(38,rad(-100)),(65,0)],('Eyes','opacity'):[(0,1),(18,1),(22,0),(38,0),(48,1),(65,1)],('Lids','opacity'):[(0,0),(18,0),(22,1),(38,1),(48,0),(65,0)],('OpenMouth','opacity'):[(0,0),(18,0),(26,1),(38,1),(50,0),(65,0)],('Tail','rotation'):[(0,0),(12,rad(2)),(30,rad(-10)),(42,rad(-8)),(65,0)],('ScarfEnds','rotation'):[(0,0),(14,rad(4)),(32,rad(-6)),(45,rad(-2)),(65,0)]},
 'Recovery':{('HeadRig','rotation'):[(0,0),(20,rad(-4))],('ArmFront','rotation'):[(0,0),(20,rad(35))],('EarRight','rotation'):[(0,0),(20,rad(3))]},
 'Greeting':{('HeadRig','rotation'):[(0,0),(10,rad(-2)),(26,rad(5)),(44,rad(3)),(70,0)],('ArmFront','rotation'):[(0,0),(10,rad(15)),(26,rad(135)),(34,rad(112)),(44,rad(135)),(70,0)],('Tail','rotation'):[(0,0),(15,rad(-2)),(33,rad(-9)),(50,rad(-4)),(70,0)],('ScarfEnds','rotation'):[(0,0),(15,rad(3)),(40,rad(-4)),(70,0)],('EarLeft','rotation'):[(0,0),(20,rad(5)),(40,rad(-3)),(70,0)]},
 'Blink':{('Eyes','scaleY'):[(0,1),(5,.06),(7,.06),(15,1)]},
}
ANIMS={};STATES={}
for i,name in enumerate(POSES):
 anim=E(art,'LinearAnimation',name=name,duration=DURATION[i],fps=100,loopValue='loop' if name=='Thinking' else 'oneShot')
 ANIMS[name]=anim.attrib['id']
 for (node,prop),default in DEFAULT.items():
  keyed=E(anim,'KeyedObject',objectId=nodes[node]);propnode=E(keyed,'KeyedProperty',propertyKey=KEY[prop])
  for frame,value in TRACKS[name].get((node,prop),[(0,default)]):
   k=E(propnode,'KeyFrameDouble',frame=frame,value=value,interpolationType='cubic')
   E(k,'CubicEaseInterpolator',x1=.3,y1=0,x2=.4,y2=1)

layer=E(sm,'StateMachineLayer',name='Pose')
E(layer,'AnyState',x=0,y=-180);E(layer,'ExitState',x=220,y=-180)
entry=E(layer,'EntryState',x=0,y=0)
for i,name in enumerate(POSES):
 state=E(layer,'AnimationState',animationId=ANIMS[name],reset='true',x=240+(i%4)*240,y=(i//4)*220)
 STATES[name]=state
E(entry,'StateTransition',stateToId=STATES['Resting'].attrib['id'])
def condition(transition,kind,value=None):
 con=E(transition,'TransitionViewModelCondition')
 compare=E(con,'TransitionPropertyViewModelComparator')
 typ={'pose':('Number','0:45','636'),'darkMode':('Boolean','0:46','634'),'react':('Trigger','0:47','686')}[kind]
 val=E(compare,'BindableProperty'+typ[0]);E(val,'DataBindContext',sourcePathIds='0:40-'+typ[1],propertyKey=typ[2])
 if kind=='react':E(con,'TransitionValueTriggerComparator')
 else:E(con,'TransitionValue'+typ[0]+'Comparator',value=str(value).lower())

for source,state in STATES.items():
 # Reactive branches precede plain rest; rest updates never manufacture a blink.
 for dest,pose in [('Saved',3),('Reviewed',4),('Greeting',6),('Blink',0)]:
  tr=E(state,'StateTransition',stateToId=STATES[dest].attrib['id'],duration=0,enableEarlyExit='true')
  condition(tr,'pose',pose);condition(tr,'react')
 for dest,pose,duration in [('Recovery',5,200),('Attentive',1,150),('Thinking',2,100),('Resting',0,100)]:
  if source==dest or (source=='Blink' and dest=='Resting'):continue
  tr=E(state,'StateTransition',stateToId=STATES[dest].attrib['id'],duration=duration,enableEarlyExit='true')
  condition(tr,'pose',pose)
 if source in ['Saved','Reviewed','Greeting','Blink']:
  E(state,'StateTransition',stateToId=STATES['Resting'].attrib['id'],duration=0,enableExitTime='true',exitTimeIsPercetange='true',exitTime=100,enableEarlyExit='true')

# Separate color-only layer; switching appearance never touches pose timelines.
colorlayer=E(sm,'StateMachineLayer',name='Appearance')
E(colorlayer,'AnyState',x=0,y=-180);E(colorlayer,'ExitState',x=240,y=-180)
colorentry=E(colorlayer,'EntryState',x=0,y=0)
colorstates=[]
for dark in [False,True]:
 anim=E(art,'LinearAnimation',name='Dark palette' if dark else 'Light palette',duration=1,fps=100)
 for cid,color in colors:
  obj=E(anim,'KeyedObject',objectId=cid);prop=E(obj,'KeyedProperty',propertyKey=37)
  E(prop,'KeyFrameColor',frame=0,value='FF'+(DARK.get(color,color) if dark else color)[1:],interpolationType='linear')
 colorstates.append(E(colorlayer,'AnimationState',animationId=anim.attrib['id'],reset='true',x=240 if not dark else 480,y=0))
E(colorentry,'StateTransition',stateToId=colorstates[0].attrib['id'])
for i,state in enumerate(colorstates):
 tr=E(state,'StateTransition',stateToId=colorstates[1-i].attrib['id'],duration=0)
 condition(tr,'darkMode',i==0)

vm=E(root,'ViewModel',id='0:40',name='CompanionModel',defaultInstanceId='0:41')
E(vm,'ViewModelPropertyNumber',id='0:45',name='pose')
E(vm,'ViewModelPropertyBoolean',id='0:46',name='darkMode')
E(vm,'ViewModelPropertyTrigger',id='0:47',name='react')
inst=E(vm,'ViewModelInstance',id='0:41',name='Default',exports='true')
E(inst,'ViewModelInstanceNumber',viewModelPropertyId='0:45',propertyValue=0)
E(inst,'ViewModelInstanceBoolean',viewModelPropertyId='0:46',propertyValue='false')
E(inst,'ViewModelInstanceTrigger',viewModelPropertyId='0:47')
ET.indent(root,space='    ')
(ROOT/'scene.rml').write_text(ET.tostring(root,encoding='unicode')+'\n')
(ROOT/'rive.yaml').write_text('name: mivu-companion\nmain: MivuCompanion\nexclude:\n  - __pycache__\n')
(ROOT/'.gitignore').write_text('build/\n__pycache__/\n')

# Static snapshots come from the same geometry and gesture keys, remain vectors.
SNAPSHOT={'Resting':0,'Attentive':15,'Thinking':35,'Saved':25,'Reviewed':30,'Recovery':20,'Greeting':30}
def value_at(name,key,frame):
 keys=TRACKS[name].get(key,[(0,DEFAULT[key])])
 for i,(t,v) in enumerate(keys):
  if frame<t:
   t0,v0=keys[i-1];return v0+(v-v0)*(frame-t0)/(t-t0)
 return keys[-1][1]
def transform(c,name,frame,group):
 pivot=(240,270) if group=='HeadRig' else next(g.pivot for g in groups if g.name==group)
 angle=value_at(name,(group,'rotation'),frame) if (group,'rotation') in DEFAULT else 0
 scale=value_at(name,(group,'scaleY'),frame) if (group,'scaleY') in DEFAULT else 1
 dy=value_at(name,('HeadRig','y'),frame)-270 if group=='HeadRig' else 0
 c.translate(pivot[0],pivot[1]+dy);c.rotate(math.degrees(angle));c.scale(1,scale);c.translate(-pivot[0],-pivot[1])

def pdf(name,appearance,dest):
 frame=SNAPSHOT[name];c=canvas.Canvas(str(dest),pagesize=(512,512));c.translate(0,512);c.scale(1,-1)
 for g in groups:
  alpha=value_at(name,(g.name,'opacity'),frame) if (g.name,'opacity') in DEFAULT else 1
  if alpha<.5:continue
  c.saveState()
  if g.name in HEADPARTS:transform(c,name,frame,'HeadRig')
  transform(c,name,frame,g.name)
  for s in g.shapes:
   path=c.beginPath()
   for op,v in commands(s.path):
    if op=='M':path.moveTo(*v)
    elif op=='L':path.lineTo(*v)
    elif op=='C':path.curveTo(*v)
    else:path.close()
   color=DARK.get(s.color,s.color) if appearance=='dark' else s.color
   if color!='none':c.setFillColor(HexColor(color))
   if s.stroke:c.setStrokeColor(HexColor(s.stroke));c.setLineWidth(s.width)
   c.setLineCap(1);c.setLineJoin(1);c.drawPath(path,fill=color!='none',stroke=bool(s.stroke))
  c.restoreState()
 c.save()
for name in POSES[:7]+['Preview']:
 folder=ASSETS/('Pip'+name+'.imageset');folder.mkdir(parents=True,exist_ok=True)
 for appearance in ['light','dark']:pdf('Resting' if name=='Preview' else name,appearance,folder/(appearance+'.pdf'))
 (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'light.pdf','idiom':'universal'},{'filename':'dark.pdf','idiom':'universal','appearances':[{'appearance':'luminosity','value':'dark'}]}],'info':{'author':'Mivu','version':1},'properties':{'preserves-vector-representation':True}},indent=2)+'\n')
print('Authored RML and 16 vector fallback PDFs:',ROOT)
