"""Reference-based pixel art and original stepped animation for native refresh.

Every pose is drawn on the same 144 x 98 pixel grid. Rive Solo swaps drawings;
no interpolated rotations, sprite filtering, remote assets or scripts are used.
This also emits the identical resting drawings for SwiftUI Reduce Motion.
"""
from pathlib import Path

W, H = 144, 98
PALETTE = ['13132D', '354559', '51788C', '9EBFC7', 'FBF9E3', 'E9B681',
           'C4865B', 'C1A177', 'EDD6AA', '9E674B', 'D5A16A', 'FAF6EC',
           '9EAEB5', 'CED2C8', '99A69F', 'ECEBE2']
INK, SHADE, BLUE, SKY, CREAM, SKIN, TAN, GOLD, SUN, WOOD, GRAIN, WHITE, EDGE, STONE, MORTAR, CHALK = range(16)


class Pixels:
    def __init__(self): self.p = {}
    def box(self, x, y, w, h, color):
        for yy in range(y, y+h):
            for xx in range(x, x+w): self.p[xx, yy] = color
    def line(self, a, b, color, width=1):
        x,y = a; endx,endy = b
        dx,dy = abs(endx-x),-abs(endy-y)
        sx,sy = (1 if x<endx else -1),(1 if y<endy else -1)
        err = dx+dy
        while True:
            self.box(x-width//2,y-width//2,width,width,color)
            if x==endx and y==endy: break
            e=2*err
            if e>=dy: err+=dy; x+=sx
            if e<=dx: err+=dx; y+=sy
    def runs(self):
        # Merge vertically adjacent runs so the native static path stays small.
        rects=[]; previous={}
        for y in sorted({xy[1] for xy in self.p}):
            row=[]; xs=sorted(x for x,yy in self.p if yy==y)
            for x in xs:
                c=self.p[x,y]
                if row and row[-1][0]+row[-1][2]==x and row[-1][4]==c: row[-1][2]+=1
                else: row.append([x,y,1,1,c])
            current={}
            for r in row:
                k=(r[0],r[2],r[4]); prior=previous.get(k)
                if prior is not None and rects[prior][1]+rects[prior][3]==y:
                    rects[prior][3]+=1;current[k]=prior
                else: current[k]=len(rects);rects.append(r)
            previous=current
        return rects


def character(pose):
    p=Pixels()
    # head origin, torso squat, pole endpoints, rear/front elbows and hands.
    poses={
        'watch': (60,29,0,(78,58),(99,12),(62,52),(82,49),(78,51),(85,43)),
        'brace': (59,31,2,(77,60),(98,16),(61,54),(81,52),(77,55),(83,47)),
        'windup':(57,33,3,(75,62),(96,20),(59,55),(79,54),(75,57),(81,50)),
        'lift':  (60,27,-1,(79,52),(106,4),(65,48),(85,42),(80,47),(89,34)),
        'hit':   (61,25,-2,(80,48),(108,0),(68,45),(87,36),(82,43),(91,30)),
        'recoil':(59,30,1,(77,57),(103,11),(62,51),(82,47),(78,52),(85,41)),
        'hard':  (62,24,-3,(81,47),(110,-1),(69,44),(88,35),(83,42),(92,29)),
        'duck':  (58,34,4,(79,58),(99,32),(56,51),(74,48),(74,53),(83,49)),
        'proud': (60,28,0,(82,62),(88,26),(58,47),(64,50),(76,47),(84,45)),
        'tired': (59,31,1,(80,62),(87,29),(57,49),(63,52),(75,49),(83,47)),
    }
    hx,hy,s,base,tip,back_elbow,back_hand,elbow,hand=poses[pose]
    def limb(a,b,c):
        p.line(a,b,INK,5);p.line(b,c,INK,5)
        p.line(a,b,SKY,3);p.line(b,c,SKY,3)
        p.box(b[0],b[1],1,1,WHITE)
        p.box(b[0]-1,b[1],2,1,GOLD)
        p.box(c[0]-2,c[1]-1,4,3,INK)
        p.box(c[0]-1,c[1]-1,3,1,CREAM)
        p.box(c[0]-1,c[1],2,2,BLUE)
    # Planted soles stay fixed; bent legs absorb every blow.
    for hip,knee,ankle in [((64,55+s),(62-s//2,59),(61,62)),((72,55+s),(74+s//2,59),(75,62))]:
        p.line(hip,knee,INK,6);p.line(knee,ankle,INK,5)
        p.line(hip,knee,BLUE,4);p.line(knee,ankle,BLUE,3)
        p.box(knee[0]-1,knee[1]-1,3,1,GOLD)
        p.box(ankle[0]-1,ankle[1]-1,3,1,CREAM)
    p.box(58,63,8,2,INK);p.box(73,63,8,2,INK)
    p.box(59,62,6,1,SKY);p.box(74,62,6,1,SKY)
    limb((62,48+s),back_elbow,back_hand)
    # Reference robot: compact armored torso, upper recess and pale waist belt.
    p.box(62,46+s,12,2,INK);p.box(60,48+s,16,8,INK);p.box(62,56+s,12,2,INK)
    p.box(63,47+s,10,2,BLUE);p.box(61,49+s,14,6,BLUE)
    p.box(65,48+s,7,4,SKY);p.box(67,49+s,3,3,INK)
    p.box(62,49+s,2,2,GOLD);p.box(73,49+s,1,2,GOLD)
    p.box(62,53+s,12,3,CREAM);p.box(64,54+s,8,1,INK)
    p.box(62,56+s,12,1,SHADE)
    # Pole is a pixel staircase, with a bright edge, not a rotated smooth line.
    p.line(base,tip,INK,3);p.line(base,tip,WOOD,1)
    p.line((base[0]+1,base[1]),(tip[0]+1,tip[1]),GRAIN,1)
    limb((74,49+s),elbow,hand)
    # User-supplied reference: large round helmet, navy face, two light eyes,
    # blue ear caps. No antenna, mouth or added facial decoration.
    xx,yy=hx-5,hy+1
    p.box(xx,yy+7,3,5,INK);p.box(xx+22,yy+7,3,5,INK)
    p.box(xx+1,yy+8,2,3,BLUE);p.box(xx+22,yy+8,2,3,BLUE)
    p.box(xx+1,yy+8,1,1,SKY);p.box(xx+22,yy+8,1,1,SKY)
    rows=[(9,16),(7,18),(5,20),(4,21),(3,22),(3,22),(2,23),
          (2,23),(2,23),(2,23),(2,23),(3,22),(3,22),(4,21),(5,20),(7,18),(9,16)]
    for row,(left,right) in enumerate(rows):
        p.box(xx+left,yy+row,right-left,1,INK)
        if 1<=row<=15:p.box(xx+left+1,yy+row,right-left-2,1,BLUE)
        if 2<=row<=14:
            p.box(xx+left+1,yy+row,1,1,CREAM if row<9 else SKY)
            p.box(xx+right-2,yy+row,1,1,SKY)
    p.box(xx+9,yy+2,7,1,SKY);p.box(xx+10,yy+2,1,1,CREAM)
    for row,left,right in [(3,8,18),(4,6,20),(5,5,21),(6,4,21),(7,4,21),
                            (8,4,21),(9,4,21),(10,4,21),(11,5,21),(12,5,20),(13,6,20),(14,8,18)]:
        p.box(xx+left,yy+row,right-left,1,SKY)
        if 4<=row<=13:p.box(xx+left+1,yy+row,right-left-2,1,INK)
    p.box(xx+8,yy+7,2,3,CREAM);p.box(xx+15,yy+7,2,3,CREAM)
    if pose in ['hit','hard']:
        p.box(xx+8,yy+7,2,3,INK);p.box(xx+15,yy+7,2,3,INK)
        p.box(xx+8,yy+8,2,1,CREAM);p.box(xx+15,yy+8,2,1,CREAM)
    if pose=='tired':
        p.box(xx+8,yy+7,2,1,INK);p.box(xx+15,yy+7,2,1,INK)
    return p


def envelope(edge=False):
    p=Pixels()
    if edge:
        p.box(-5,-1,11,3,INK);p.box(-4,-1,9,1,WHITE);p.box(-3,0,7,1,EDGE)
    else:
        p.box(-6,-4,13,9,INK);p.box(-5,-3,11,7,WHITE)
        p.line((-5,-2),(0,1),EDGE);p.line((0,1),(5,-2),EDGE)
        p.line((-5,3),(-2,1),CREAM);p.line((5,3),(2,1),CREAM)
        p.box(3,-2,2,2,GOLD)
    return p


def author(root,el,board):
    a,(vm,phase,pull,active)=board('Mailroom',W,H)
    def pixels(parent,name,drawing):
        n=el(parent,'Node',name=name)
        for c in range(len(PALETTE)):
            runs=[r for r in drawing.runs() if r[4]==c]
            if not runs: continue
            sh=el(n,'Shape',name=f'{name} · palette {c}')
            for x,y,w,h,_ in runs:
                path=el(sh,'PointsPath',isClosed=True)
                for xx,yy in [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]:el(path,'StraightVertex',x=xx,y=yy)
            el(el(sh,'Fill'),'SolidColor',colorValue='FF'+PALETTE[c])
        return n
    def swap(parent,name,drawings):
        solo=el(parent,'Solo',name=name)
        poses={n:pixels(solo,n,p) for n,p in drawings.items()}
        solo.set('activeComponentId',next(iter(poses.values())).attrib['id'])
        return solo,poses
    # Foreground appears first in Rive. Mail arrives from above the phone edge.
    letters=[]
    for i in range(4):
        holder=el(a,'Node',name=f'Falling envelope {i+1}',opacity=0)
        solo,poses=swap(holder,'Paper tumble',{'face':envelope(),'edge':envelope(True)})
        letters.append((holder,solo,poses))
    sparkle=Pixels()
    for aa,bb in [((104,2),(101,4)),((114,2),(117,4)),((109,3),(109,5))]:sparkle.line(aa,bb,SKY)
    hit=pixels(a,'Contact sparks',sparkle)
    hero,poses=swap(a,'Little robot poses',{name:character(name) for name in ['watch','brace','windup','lift','hit','recoil','hard','duck','proud','tired']})
    floor=Pixels();floor.box(54,65,31,1,STONE);floor.box(48,65,3,1,CHALK);floor.box(89,65,7,1,CHALK)
    pixels(a,'Footing',floor)
    # This scene lives on the feed's white surface. Author that ground too so
    # standalone playback has the same contrast as the native app.
    background=el(a,'Shape',name='Feed surface',x=W/2,y=H/2)
    el(background,'Rectangle',width=W,height=H)
    el(el(background,'Fill'),'SolidColor',colorValue='FFFFFFFF')

    def timeline(name,duration=1,loop=False,pose='watch',pose_keys=None,impact_keys=None,mail=False):
        t=el(a,'LinearAnimation',name=name,fps=12,duration=duration,quantize=True,loopValue='loop' if loop else 'oneShot')
        objects={}
        def keyed(obj,prop,keys,ids=False):
            ident=obj.attrib['id']
            if ident not in objects:objects[ident]=el(t,'KeyedObject',objectId=ident)
            kp=el(objects[ident],'KeyedProperty',propertyKey=prop)
            for frame,val in keys:el(kp,'KeyFrameId' if ids else 'KeyFrameDouble',frame=frame,value=val,interpolationType='hold')
        keyed(hero,296,[(f,poses[n].attrib['id']) for f,n in (pose_keys or [(0,pose)])],True)
        keyed(hit,18,impact_keys or [(0,0)])
        for i,(holder,solo,lp) in enumerate(letters):
            delay=[1,2,3,4][i]
            keyed(holder,18,[(0,0),(delay,1),(delay+9,0)] if mail else [(0,0)])
            keyed(holder,13,[(0,85),(delay,85),(delay+1,85+(-1 if i%2==0 else 1)*5),(delay+3,[62,104,41,117][i]),(delay+5,[53,115,28,126][i]),(delay+8,[49,122,21,134][i])] if mail else [(0,85)])
            keyed(holder,14,[(0,-6),(delay,-6),(delay+1,3),(delay+2,13),(delay+3,24),(delay+4,36),(delay+5,49),(delay+6,63),(delay+7,78),(delay+8,96),(delay+9,112)] if mail else [(0,-6)])
            keyed(solo,296,[(0,lp['face'].attrib['id']),(delay+2,lp['edge'].attrib['id']),(delay+4,lp['face'].attrib['id']),(delay+6,lp['edge' if i%2 else 'face'].attrib['id'])] if mail else [(0,lp['face'].attrib['id'])],True)
        return t
    rest=timeline('Look up')
    brace=timeline('Feet planted',pose='brace')
    wind=timeline('Pull winds the swing',pose='windup')
    # The first contact lands within the existing 400ms refresh floor; a fast
    # response still gets one readable knock without delaying the network UI.
    work=timeline('Knock, recoil, knock harder',36,True,pose_keys=[(0,'brace'),(1,'windup'),(2,'lift'),(3,'hit'),(5,'recoil'),(8,'brace'),(10,'windup'),(11,'lift'),(12,'hard'),(14,'recoil'),(18,'watch'),(36,'brace')],impact_keys=[(0,0),(3,1),(5,0),(12,1),(14,0)])
    done=timeline('Mail breaks loose',14,pose_keys=[(0,'hard'),(2,'recoil'),(4,'duck'),(8,'watch'),(11,'proud')],impact_keys=[(0,1),(2,0)],mail=True)
    attention=timeline('Rest the pole',pose='tired')
    empty=timeline('Nothing to dislodge',10,pose_keys=[(0,'watch'),(3,'recoil'),(6,'tired')])
    still=timeline('Working held',pose='watch')
    m=el(a,'StateMachine',name='Motion');a.set('defaultStateMachineId',m.attrib['id'])
    layer=el(m,'StateMachineLayer',name='Pixel performance')
    el(layer,'AnyState',x=0,y=-160);el(layer,'ExitState',x=250,y=-160);entry=el(layer,'EntryState',x=0,y=0)
    animations=[rest,brace,wind,work,done,attention,empty,still]
    states=[el(layer,'AnimationState',animationId=t.attrib['id'],reset=True,x=220+i%4*240,y=i//4*180) for i,t in enumerate(animations)]
    el(entry,'StateTransition',stateToId=states[0].attrib['id'],duration=0)
    def cond(tr,p,value,op='equal'):
        boolean=p.tag.endswith('Boolean');typ='Boolean' if boolean else 'Number'
        c=el(tr,'TransitionViewModelCondition',opValue=op)
        b=el(el(c,'TransitionPropertyViewModelComparator'),'BindableProperty'+typ)
        el(b,'DataBindContext',sourcePathIds=vm.attrib['id']+'-'+p.attrib['id'],propertyKey=634 if boolean else 636)
        el(c,'TransitionValue'+typ+'Comparator',value=value)
    for i,st in enumerate(states):
        for j,dest in enumerate(states):
            if i==j:continue
            tr=el(st,'StateTransition',stateToId=dest.attrib['id'],duration=0,enableEarlyExit=True)
            cond(tr,phase,[0,0,0,1,2,3,4,1][j])
            if j==0:cond(tr,pull,33,'lessThan')
            if j==1:cond(tr,pull,33,'greaterThanOrEqual');cond(tr,pull,70,'lessThan')
            if j==2:cond(tr,pull,70,'greaterThanOrEqual')
            if j in [3,7]:cond(tr,active,j==3)

    # Same pixel drawings in a static native Canvas: no Rive player under Reduce Motion.
    static=[]
    for pose in ['watch','proud','tired']:
        p=Pixels();p.p.update(floor.p)
        p.p.update(character(pose).p)
        static.append(p.runs())
    target=Path(__file__).resolve().parents[3]/'apple/DecisionInbox/Design/Components/MailroomStill.swift'
    palettes=', '.join('0x'+c for c in PALETTE)
    arrays=',\n'.join('        [\n'+',\n'.join('            ['+', '.join(map(str,r))+']' for r in runs)+'\n        ]' for runs in static)
    target.write_text('''// Generated by design/motion/margin-studio/build_mailroom.py. Edit that source.
import SwiftUI

/// The same authored pixels, held still for Reduce Motion or a render failure.
struct MailroomStill: View {
    let phase: Int
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 144, size.height / 98)
            context.translateBy(x: (size.width - 144 * scale) / 2, y: (size.height - 98 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let drawing = Self.drawings[phase == 2 ? 1 : (phase >= 3 ? 2 : 0)]
            for (index, hex) in Self.palette.enumerated() {
                var path = Path()
                for r in drawing where r[4] == index {
                    path.addRect(CGRect(x: r[0], y: r[1], width: r[2], height: r[3]))
                }
                context.fill(path, with: .color(Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)))
            }
        }
    }
    private static let palette: [Int] = ['''+palettes+''']
    private static let drawings: [[[Int]]] = [
'''+arrays+'''
    ]
}
''')
