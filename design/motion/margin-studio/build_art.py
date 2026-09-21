#!/usr/bin/env python3
"""Author the three production Margin Studio artboards; no scripts or external assets.

The RML and this source are editable. Native code owns all words and actions.
Run from anywhere; `rive . --once` compiles the generated source separately.
"""
from pathlib import Path
import xml.etree.ElementTree as E

ROOT = E.Element('Rive', version='1', kind='fragment')
seq = 0
INK, LIGHT, PAPER, SOFT = 'FF171717', 'FF969696', 'FFFFFFFF', 'FFF1F1EF'
def el(parent, tag, **attrs):
    global seq
    if 'id' not in attrs:
        seq += 1
        attrs['id'] = f'0:{seq}'
    return E.SubElement(parent, tag, {k:str(v).lower() if isinstance(v,bool) else str(v) for k,v in attrs.items()})
def fill(parent, color):
    return el(el(parent,'Fill',name='Paper' if color==PAPER else 'Ink'),'SolidColor',colorValue=color)
def stroke(parent,color=INK,width=1.7):
    return el(el(parent,'Stroke',name='Contour',thickness=width,cap='round',join='round'),'SolidColor',colorValue=color)
def rect(parent,name,x,y,w,h,color=INK,r=0,border=False):
    sh=el(parent,'Shape',name=name,x=x,y=y)
    el(sh,'Rectangle',width=w,height=h,cornerRadiusTL=r)
    fill(sh,color)
    if border: stroke(sh)
    return sh

def path(parent,name,points,color=INK,width=1.7,closed=False,solid=None):
    sh=el(parent,'Shape',name=name)
    p=el(sh,'PointsPath',name='Outline',isClosed=closed)
    for x,y in points: el(p,'StraightVertex',x=x,y=y)
    if solid: fill(sh,solid)
    if width: stroke(sh,color,width)
    return sh

def dot(parent,name,x,y,d=4,color=INK):
    sh=el(parent,'Shape',name=name,x=x,y=y)
    el(sh,'Ellipse',width=d,height=d);fill(sh,color)
    return sh

def node(parent,name,x=0,y=0):return el(parent,'Node',name=name,x=x,y=y)
def key(obj,prop,val):return (obj.attrib['id'],prop,val)

def timeline(a,name,props,duration=1,loop=False):
    t=el(a,'LinearAnimation',name=name,duration=duration,fps=60,loopValue='loop' if loop else 'oneShot')
    objects={}
    for ident,prop,values in props:
        ob=objects.setdefault(ident, None)
        if ob is None: ob=objects[ident]=el(t,'KeyedObject',objectId=ident)
        k=el(ob,'KeyedProperty',propertyKey=prop)
        if not isinstance(values,list):values=[(0,values)]
        for frame,value in values:
            f=el(k,'KeyFrameDouble',frame=frame,value=value,interpolationType='cubic')
            el(f,'CubicEaseInterpolator',x1='.25',y1='.1',x2='.25',y2='1')
    return t

def vm(a,name):
    v=el(ROOT,'ViewModel',name=name+'Model')
    phase=el(v,'ViewModelPropertyNumber',name='phase')
    pull=el(v,'ViewModelPropertyNumber',name='pull')
    active=el(v,'ViewModelPropertyBoolean',name='active')
    inst=el(v,'ViewModelInstance',name='Default',exports=True)
    for tag,p,val in [('Number',phase,0),('Number',pull,0),('Boolean',active,True)]:
        el(inst,'ViewModelInstance'+tag,viewModelPropertyId=p.attrib['id'],propertyValue=val)
    v.set('defaultInstanceId',inst.attrib['id']);a.set('viewModelId',v.attrib['id']);a.set('viewModelInstanceId',inst.attrib['id'])
    return v,phase,pull,active

def condition(trans,v,p,value):
    boolean=p.tag.endswith('Boolean');typ='Boolean' if boolean else 'Number'
    c=el(trans,'TransitionViewModelCondition',opValue='equal')
    b=el(el(c,'TransitionPropertyViewModelComparator'),'BindableProperty'+typ)
    el(b,'DataBindContext',sourcePathIds=v.attrib['id']+'-'+p.attrib['id'],propertyKey=634 if boolean else 636)
    el(c,'TransitionValue'+typ+'Comparator',value=value)

def machine(a,v,phase,pull,active,animations,blend=None,working=1):
    m=el(a,'StateMachine',name='Motion');a.set('defaultStateMachineId',m.attrib['id'])
    l=el(m,'StateMachineLayer',name='Paper and ink')
    el(l,'AnyState',x=0,y=-160);el(l,'ExitState',x=240,y=-160)
    en=el(l,'EntryState',x=0,y=0)
    states=[]
    for i,t in enumerate(animations):
        if i==0 and blend:
            st=el(l,'BlendState1DViewModel',x=180+i*200,y=0)
            b=el(st,'BindablePropertyNumber')
            el(b,'DataBindContext',sourcePathIds=v.attrib['id']+'-'+pull.attrib['id'],propertyKey=636)
            for value,pose in blend:el(st,'BlendAnimation1D',animationId=pose.attrib['id'],value=value)
        else: st=el(l,'AnimationState',animationId=t.attrib['id'],x=180+i*200,y=0,reset=True)
        states.append(st)
    el(en,'StateTransition',stateToId=states[0].attrib['id'])
    for i,st in enumerate(states):
        for j,to in enumerate(states):
            if i==j:continue
            # Final slot is a motionless version of working, for lifecycle tests.
            target_phase=working if j==len(states)-1 else j
            tr=el(st,'BlendStateTransition' if st.tag.startswith('Blend') else 'StateTransition',stateToId=to.attrib['id'],duration=0 if j==len(states)-1 else 240,enableEarlyExit=True)
            condition(tr,v,phase,target_phase)
            if j==working or j==len(states)-1:condition(tr,v,active,j==working)

def board(name,w=240,h=160):
    a=el(ROOT,'Artboard',name=name,width=w,height=h,x=len(list(ROOT))*300,y=0)
    style=el(a,'LayoutComponentStyle',name='Artboard Style');a.set('styleId',style.attrib['id'])
    return a,vm(a,name)

# Receipt: the sheet rises with the actual pull; the status rule breathes only
# while the mailbox request is active. No percentage represents network work.
a,(v,phase,pull,active)=board('Receipt')
dot(a,'Left registration',57,112,3,LIGHT);dot(a,'Right registration',183,112,3,LIGHT)
path(a,'Resting slot',[(66,114),(174,114)],LIGHT,1.5)
paper=node(a,'Receipt',120,80)
# Foreground content is before the sheet: Rive draws earlier siblings in front.
flag=node(paper,'Attention tab',27,-22)
path(flag,'Open bookmark',[(-5,-8),(5,-8),(5,11),(0,7),(-5,11)],closed=True,solid=INK,width=0)
seal=node(paper,'Confirmation',0,15)
path(seal,'Receipt mark',[(-9,0),(-2,7),(11,-7)],width=2.3)
rule=rect(paper,'Working margin',-23,-5,2.5,31)
lines=node(paper,'Typeset lines')
for i,w in enumerate([30,39,25,34]):rect(lines,f'Line {i}',4,-20+i*10,w,2,LIGHT,1)
rect(paper,'Perforation 1',-22,43,3,1.2,LIGHT)
for x in range(-14,25,8):rect(paper,'Perforation',x,43,3,1.2,LIGHT)
path(paper,'Cut paper',[(-39,-49),(39,-49),(39,49),(32,46),(25,49),(18,46),(11,49),(4,46),(-3,49),(-10,46),(-17,49),(-24,46),(-31,49),(-39,46)],closed=True,solid=PAPER)
rect(a,'Soft print shadow',124,86,82,96,SOFT,4)

def receipt(y=78,rotation=0,sy=1,confirmed=0,attention=0,work=1,opacity=1):
    return [key(paper,14,y),key(paper,15,rotation),key(paper,17,sy),key(paper,18,opacity),key(seal,18,confirmed),key(flag,18,attention),key(rule,18,work),key(lines,18,1-confirmed)]
low=timeline(a,'Pull tucked',receipt(107,-.13,.72,work=.35))
high=timeline(a,'Pull aligned',receipt(76,0,1,work=1))
wait=timeline(a,'Checking',[*receipt(),key(rule,17,[(0,.64),(54,1),(108,.64)])],108,True)
done=timeline(a,'Freshness receipt',receipt(78,0,1,confirmed=1,work=0))
attention=timeline(a,'Needs attention',receipt(82,-.045,1,attention=1,work=.25))
static=timeline(a,'Checking still',[*receipt(),key(rule,17,.82)])
# Every state writes scaleY; otherwise leaving a loop retains the last value.
for t in [low,high,done,attention]:
    ko=el(t,'KeyedObject',objectId=rule.attrib['id']);kp=el(ko,'KeyedProperty',propertyKey=17);el(kp,'KeyFrameDouble',value=1,frame=0)
machine(a,v,phase,pull,active,[low,wait,done,attention,static],[(0,low),(100,high)])

# Reading: one piece of correspondence becomes an annotation, not a magic
# claim about arbitrary mail. Only the labeled synthetic example uses phase 2.
a,(v,phase,pull,active)=board('Reading',280,160)
front=node(a,'Reading sheet',150,80)
bookmark=node(front,'Saved place',29,-37)
path(bookmark,'Bookmark',[(-6,-8),(6,-8),(6,18),(0,12),(-6,18)],closed=True,solid=INK,width=0)
annotation=node(front,'Annotation',-19,-21)
path(annotation,'Opening mark',[(3,0),(-3,0),(-3,11),(3,11)],width=2)
path(annotation,'Closing mark',[(32,0),(38,0),(38,11),(32,11)],width=2)
margin=rect(front,'Margin',-27,7,2.5,58,INK,1)
text=[]
for i,w in enumerate([42,49,34,46,38,28]):text.append(rect(front,'Source line '+str(i),5,-26+i*11,w,2.3,INK if i<2 else LIGHT,1))
rect(front,'Sheet',0,0,102,120,PAPER,3,True)
back=node(a,'Source sheet',118,80)
for i,w in enumerate([35,44,31,39]):rect(back,'Correspondence line',0,-25+i*12,w,2,LIGHT,1)
rect(back,'Original sheet',0,0,102,120,SOFT,3,True)
path(a,'Ground rule',[(58,145),(222,145)],LIGHT,1)
dot(a,'Registration',47,145,3,LIGHT)

def reading(mode):
    meaning=mode==2;empty=mode==4;needs=mode==3
    props=[key(front,13,154 if meaning else 144),key(front,15,.045 if meaning else -.025),key(back,13,106 if meaning else 132),key(back,15,-.11 if meaning else -.065),key(annotation,18,1 if meaning else 0),key(bookmark,18,1 if empty or needs else 0),key(margin,18,0 if empty else 1),key(margin,17,1)]
    for i,t in enumerate(text):
        props += [key(t,18,0 if empty else (1 if not meaning or i<3 else .18)),key(t,14,(-1+i*13) if meaning else (-26+i*11)),key(t,16,.8 if meaning else 1)]
    return props
source=timeline(a,'Original correspondence',reading(0))
props=reading(1);props=[x for x in props if not (x[0]==margin.attrib['id'] and x[1]==17)]
work=timeline(a,'Reading',[*props,key(margin,17,[(0,.58),(64,1),(128,.58)])],128,True)
meaning=timeline(a,'Annotation',reading(2))
needs=timeline(a,'Return to your page',reading(3))
empty=timeline(a,'A place for later',reading(4))
static=timeline(a,'Reading still',reading(1))
machine(a,v,phase,pull,active,[source,work,meaning,needs,empty,static])

# Closing: two open margin marks come to rest around a full stop, once.
a,(v,phase,pull,active)=board('Closing',240,128)
left=node(a,'Opening margin',83,61);right=node(a,'Closing margin',157,61)
path(left,'Opening bracket',[(8,-22),(-8,-22),(-8,22),(8,22)],width=2)
path(right,'Closing bracket',[(-8,-22),(8,-22),(8,22),(-8,22)],width=2)
stop=dot(a,'Full stop',120,61,7)
text=node(a,'Unfinished lines',120,61)
for i,w in enumerate([29,21,25]):rect(text,'Remaining line',0,-10+i*10,w,1.6,LIGHT,1)
path(a,'Baseline',[(72,98),(168,98)],LIGHT,1)

def closing(done=False,animated=False):
    def val(before,after):return [(0,before),(34,after)] if animated else (after if done else before)
    return [key(left,13,val(83,108)),key(right,13,val(157,132)),key(left,17,val(1,.16)),key(right,17,val(1,.16)),key(left,18,val(1,0)),key(right,18,val(1,0)),key(text,18,val(1,0)),key(stop,18,val(0,1)),key(stop,16,val(.6,1)),key(stop,17,val(.6,1))]
opened=timeline(a,'Open ending',closing())
close=timeline(a,'Closing mark',closing(True,True),34)
closed=timeline(a,'Settled',closing(True))
static=timeline(a,'Closing still',closing(True))
machine(a,v,phase,pull,active,[opened,close,closed,static])

E.indent(ROOT,space='  ')
Path(__file__).with_name('scene.rml').write_text(E.tostring(ROOT,encoding='unicode')+'\n')
print('Authored Receipt, Reading, Closing — script-free vector state machines')
