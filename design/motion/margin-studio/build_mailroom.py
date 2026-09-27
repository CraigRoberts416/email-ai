"""Reference-based pixel art and original stepped animation for native refresh.

Every pose is drawn on a 288 x 196 pixel grid in a 144 x 98 artboard. Rive Solo swaps drawings;
no interpolated rotations, sprite filtering, remote assets or scripts are used.
This also emits the identical resting drawings for SwiftUI Reduce Motion.
"""
from pathlib import Path

W, H = 144, 98
PALETTE = ['13132D', '354559', '51788C', '9EBFC7', 'FBF9E3', 'E9B681',
           'C4865B', 'C1A177', 'EDD6AA', '9E674B', 'D5A16A', 'FAF6EC',
           '9EAEB5', 'CED2C8', '99A69F', 'ECEBE2', '263449', '3D6077',
           '719CA9', 'C6DAD8', 'ECF2E4', '1D263F', '29354C', '614236',
           '80553C', 'B98451', 'DAB27B', 'B5A785']
INK, SHADE, BLUE, SKY, CREAM, SKIN, TAN, GOLD, SUN, WOOD, GRAIN, WHITE, EDGE, STONE, MORTAR, CHALK = range(16)
DEEP, STEEL, TEAL, MIST, GLEAM, GLASS, REFLECT, BARK, DARKWOOD, HEARTWOOD, CUTWOOD, BRASS = range(16,28)


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
    def poly(self, points, color):
        # Scan-convert into integer pixels: no softened/rotated sprite edges.
        for y in range(min(v[1] for v in points),max(v[1] for v in points)):
            xs=[]
            for a,b in zip(points,points[1:]+points[:1]):
                if min(a[1],b[1])<=y+.5<max(a[1],b[1]):
                    xs.append(a[0]+(y+.5-a[1])*(b[0]-a[0])/(b[1]-a[1]))
            xs.sort()
            for left,right in zip(xs[::2],xs[1::2]):
                for x in range(int(left),int(right)+1):
                    if left<=x+.5<right:self.p[x,y]=color
    def doubled(self):
        p=Pixels()
        for (x,y),c in self.p.items():p.box(x*2,y*2,2,2,c)
        return p
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
    shake={'nope_left':-1,'nope_right':1}.get(pose,0)
    if shake:pose='tired'
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
        'startled':(58,27,0,(79,62),(91,28),(56,48),(54,43),(79,51),(84,47)),
        'peek':  (59,31,2,(80,62),(88,34),(58,50),(65,51),(77,52),(84,49)),
        'settle':(60,29,1,(81,62),(88,28),(58,48),(64,51),(76,49),(84,47)),
    }
    hx,hy,s,base,tip,back_elbow,back_hand,elbow,hand=poses[pose]
    s*=2
    # Hip translation, upper-body lean, foot placement and rear-heel lift.
    # The leading toe receives the weight; the rear heel leaves the ground.
    hip_shift,lean,left_step,right_step,heel={
        'watch': (0,0,0,0,0),
        'brace': (-3,-1,-3,3,0),
        'windup':(-7,-3,-4,4,1),
        'lift':  (3,3,-3,5,4),
        'hit':   (7,4,-2,5,7),
        'recoil':(1,1,-3,4,2),
        'hard':  (9,5,-2,6,9),
        'duck':  (-5,-3,-4,4,0),
        'proud': (1,0,-1,1,0),
        'tired': (-2,-1,0,1,0),
        'startled':(-3,-2,-5,5,1),
        'peek':  (1,2,-2,3,0),
        'settle':(1,0,-1,3,0),
    }[pose]
    if pose=='duck':hip_shift,lean,left_step,right_step,heel=3,5,-5,8,0
    # Orientation is shared by the helmet, shoulder line, rib cage, pelvis and
    # boots. Translation/lean alone cannot make a character turn around.
    facing={
        'watch':'front', 'brace':'quarter', 'windup':'side',
        'lift':'back', 'hit':'back', 'hard':'back', 'recoil':'side',
        'duck':'quarter', 'startled':'quarter', 'peek':'quarter',
        'proud':'front', 'tired':'front', 'settle':'front',
    }[pose]
    if shake:
        hip_shift+=shake
        lean+=shake
    def finish():
        # Step into the clear center lane between the falling envelopes.
        offset={'duck':26,'peek':22,'settle':10}.get(pose,0)
        if offset:p.p={(x+offset,y):c for (x,y),c in p.p.items()}
        return p
    base,tip,back_elbow,back_hand,elbow,hand=[(x*2,y*2) for x,y in [base,tip,back_elbow,back_hand,elbow,hand]]
    def limb(a,b,c):
        p.line(a,b,INK,8);p.line(b,c,INK,8)
        p.line(a,b,STEEL,6);p.line(b,c,BLUE,6)
        p.line((a[0]-1,a[1]-2),(b[0]-1,b[1]-2),TEAL,3)
        p.line((b[0]-1,b[1]-2),(c[0]-1,c[1]-2),MIST,2)
        p.box(b[0]-3,b[1]-3,6,6,DEEP)
        p.box(b[0]-2,b[1]-2,4,3,BRASS)
        p.box(b[0]-1,b[1]-2,2,1,CREAM)
        p.box(c[0]-4,c[1]-3,8,7,INK)
        p.box(c[0]-3,c[1]-2,6,5,BLUE)
        p.box(c[0]-3,c[1]-2,6,2,MIST)
        p.box(c[0],c[1],3,1,STEEL)
        p.box(c[0]-3,c[1],2,2,TEAL)
    # A foot actually pivots: outward-facing toe caps at rest, narrow side
    # boots through the turn, and heel plates/toes receding on the rear pose.
    # The far leg/arm are painted first, then the rib cage, then the near arm.
    foot_layout={
        'front':[(116+left_step,0,128,'left'),(146+right_step,0,144,'right')],
        'quarter':[(120+left_step,3,129,'diagonal'),(144+right_step,0,144,'diagonal')],
        'side':[(129+left_step,5,134,'right'),(143+right_step,0,140,'right')],
        'back':[(116+left_step,2,126,'heel'),(145+right_step,0,145,'heel')],
    }[facing]
    for index,(x,depth,hip_x,direction) in enumerate(foot_layout):
        rise=heel if index==0 else 0
        ankle=(x+7,124-depth-rise)
        knee=(round((hip_x+hip_shift+ankle[0])/2),117-depth+max(s,0)//2-rise//2)
        hip=(hip_x+hip_shift,111+s)
        p.line(hip,knee,INK,11);p.line(knee,ankle,INK,9)
        p.line(hip,knee,STEEL,7);p.line(knee,ankle,BLUE,6)
        p.line((hip[0]-2,hip[1]),(knee[0]-2,knee[1]),TEAL,2)
        if facing=='back':
            # Rear knee hinges are dark; no forward-facing gold knee pads.
            p.box(knee[0]-3,knee[1]-2,6,4,DEEP)
            p.box(knee[0]-2,knee[1]-1,4,1,BLUE)
        else:
            p.box(knee[0]-3,knee[1]-2,6,4,DARKWOOD)
            p.box(knee[0]-2,knee[1]-2,5,2,BRASS)
        boot=Pixels()
        if direction=='heel':
            boot.poly([(3,0),(10,0),(14,5),(14,12),(0,12),(0,6)],INK)
            boot.poly([(4,2),(9,2),(11,5),(11,8),(2,8),(2,5)],BLUE)
            boot.box(3,2,6,2,TEAL)
            boot.box(2,7,10,3,STEEL);boot.box(4,8,6,2,DEEP)
            boot.box(2,10,10,1,MIST)
        elif direction=='diagonal':
            boot.poly([(7,0),(13,1),(17,5),(15,10),(3,12),(0,9),(2,5)],INK)
            boot.poly([(7,2),(12,3),(14,5),(12,8),(3,10),(2,8),(4,5)],BLUE)
            boot.line((7,2),(12,3),MIST,2)
            boot.line((3,9),(13,7),STEEL,2)
        else:
            boot.poly([(0,5-rise),(3,2-rise),(9,3-rise),(16,6),(17,10),(11,10),(0,9-rise)],INK)
            boot.poly([(2,5-rise),(5,4-rise),(13,6),(14,8),(10,8),(2,7-rise)],BLUE)
            boot.line((4,3-rise),(10,4-rise//2),MIST,2)
            boot.line((2,7-rise),(13,8),STEEL)
            if direction=='left':boot.p={(16-bx,by):c for (bx,by),c in boot.p.items()}
        boot_y=118 if direction in ['heel','diagonal'] else 120
        for (bx,by),c in boot.p.items():
            p.p[x+bx,boot_y-depth+by-(rise if direction in ['heel','diagonal'] else 0)]=c
    shoulder_far,shoulder_near={
        'front':((124,96),(148,98)),
        'quarter':((125,96),(149,100)),
        'side':((137,95),(141,101)),
        'back':((122,98),(151,97)),
    }[facing]
    def shoulder(point):return (point[0]+hip_shift+lean,point[1]+s)
    limb(shoulder(shoulder_far),back_elbow,back_hand)
    torso=Pixels()
    if facing=='front':
        # The supplied robot's chest recess and pale belt face the reader.
        torso.poly([(125,92),(146,92),(152,99),(152,112),(147,116),(124,116),(120,110),(120,100)],INK)
        torso.box(125,94,20,3,TEAL);torso.box(122,99,27,12,STEEL)
        torso.box(124,98,22,9,BLUE);torso.box(124,98,4,9,TEAL)
        torso.box(145,98,4,13,DEEP)
        torso.box(131,96,12,9,MIST);torso.box(134,98,6,6,GLASS)
        torso.box(135,98,4,1,REFLECT);torso.box(125,99,3,3,BRASS)
        torso.box(124,106,23,6,MIST);torso.box(124,106,22,2,CREAM)
        torso.box(129,109,14,2,DEEP);torso.box(125,113,22,1,BLUE)
    elif facing=='quarter':
        # The left side is broad; the chest and buckle recede around the right.
        torso.poly([(125,92),(140,91),(150,96),(153,107),(149,115),(131,118),(121,111),(120,100)],INK)
        torso.poly([(125,95),(138,94),(139,111),(132,115),(123,109),(123,100)],STEEL)
        torso.poly([(125,95),(129,94),(130,109),(126,110),(123,107),(123,100)],TEAL)
        torso.poly([(139,94),(148,98),(150,107),(147,111),(140,113)],BLUE)
        torso.poly([(142,97),(147,99),(148,105),(142,104)],MIST)
        torso.box(144,99,3,4,GLASS)
        torso.poly([(138,108),(150,105),(148,111),(138,114)],MIST)
        torso.line((139,108),(148,106),CREAM,2)
        torso.line((142,111),(147,109),DEEP,2)
        torso.line((124,111),(136,115),BLUE,3)
        torso.box(126,101,4,5,DEEP);torso.box(127,101,2,1,BRASS)
    elif facing=='side':
        # Narrow rib cage, overlapping hips and a single visible shoulder.
        # Only a sliver of pale chest armor remains at the far right edge.
        torso.poly([(132,91),(140,91),(147,98),(149,109),(143,117),(131,115),(127,107),(128,97)],INK)
        torso.poly([(132,94),(139,94),(143,100),(144,111),(139,114),(132,112),(130,105),(130,98)],STEEL)
        torso.line((132,95),(131,105),TEAL,3)
        torso.poly([(141,96),(145,99),(147,107),(143,112)],BLUE)
        torso.line((144,105),(146,108),MIST,2)
        torso.box(132,101,7,7,DEEP);torso.box(133,102,4,1,TEAL)
        torso.box(133,105,4,1,BLUE)
        torso.line((131,111),(140,114),BLUE,3)
    else:
        # A full rear shell: shoulder blades, central spine, vents and rear
        # hip plates replace the face-on chest badge/buckle completely.
        torso.poly([(124,92),(147,92),(154,99),(153,111),(147,118),(124,118),(118,110),(119,99)],INK)
        torso.poly([(125,94),(146,94),(150,99),(148,111),(142,114),(127,112),(122,106),(122,100)],STEEL)
        torso.poly([(125,94),(132,94),(130,108),(124,110),(122,105),(122,100)],TEAL)
        torso.poly([(139,95),(147,96),(150,100),(148,110),(140,113)],BLUE)
        torso.box(133,96,5,14,DEEP);torso.box(134,96,2,12,BLUE)
        for y in [101,104,107]:
            torso.box(124,y,6,1,DEEP);torso.box(141,y,6,1,DEEP)
        torso.box(125,95,3,2,MIST);torso.box(144,95,3,2,TEAL)
        torso.line((124,113),(132,115),BLUE,3)
        torso.line((139,115),(147,113),BLUE,3)
        torso.box(133,113,5,4,DEEP)
    for (x,y),c in torso.p.items():
        p.p[x+hip_shift+round(lean*(116-y)/24),y+s]=c
    # A lightly crooked wooden branch, with taper, bark knots, a cut end and
    # one trimmed twig. Its asymmetric silhouette stays readable at app size.
    dx,dy=tip[0]-base[0],tip[1]-base[1]
    def along(t,offset=0):return (round(base[0]+dx*t+offset),round(base[1]+dy*t))
    branch=[base,along(.25,-1),along(.52,1),along(.77,-1),tip]
    for i,(a,b) in enumerate(zip(branch,branch[1:])):
        width=6 if i<2 else 5
        p.line(a,b,BARK,width)
        p.line((a[0]-1,a[1]),(b[0]-1,b[1]),HEARTWOOD,width-2)
        p.line((a[0]-2,a[1]),(b[0]-2,b[1]),CUTWOOD,1)
    knot=along(.67);p.line(knot,(knot[0]+5,knot[1]-2),BARK,3)
    p.box(knot[0]+4,knot[1]-3,2,2,CUTWOOD)
    for t in [.15,.44,.83]:
        x,y=along(t);p.box(x-1,y,2,3,DARKWOOD);p.box(x-1,y,1,1,BARK)
    p.box(tip[0]-2,tip[1],4,2,CUTWOOD)
    limb(shoulder(shoulder_near),elbow,hand)
    # Turn through front, three-quarter, profile and a fully rear-facing
    # helmet. The eyes disappear while he watches the stick hit the phone.
    xx,yy=(hx-5)*2+hip_shift+lean,(hy+1)*2-2
    lift=pose in ['watch','lift','hit','hard','recoil','proud','startled','peek']
    tilt=-2 if lift else (2 if pose in ['duck','tired'] else 0)
    if shake:tilt=0
    def poly(points,c):p.poly([(xx+x,yy+y+round(tilt*(x-25)/25)) for x,y in points],c)
    def box(x,y,w,h,c):p.box(xx+x,yy+y+round(tilt*(x-25)/25),w,h,c)
    front=facing=='front'
    profile=facing=='side'
    away=facing=='back'
    if front:
        tilt=0
        box(19,32,14,7,INK);box(21,34,10,3,STEEL)
        for x in [0,45]:
            box(x,16,6,11,INK);box(x+1,17,4,8,BLUE);box(x+1,17,2,3,MIST)
        poly([(7,11),(12,5),(20,1),(31,1),(39,5),(44,11),(47,19),(45,28),(39,34),(31,37),(19,37),(11,33),(6,27),(4,19)],INK)
        poly([(9,11),(14,6),(21,3),(30,3),(38,7),(42,12),(45,19),(43,27),(37,32),(30,35),(20,35),(12,31),(8,25),(6,19)],STEEL)
        poly([(9,11),(14,6),(21,3),(30,3),(36,6),(21,6),(14,11),(10,19),(10,25),(8,24),(6,19)],TEAL)
        poly([(11,10),(16,6),(22,4),(30,4),(32,6),(22,7),(16,10),(12,15),(10,22),(8,22),(8,17)],MIST)
        box(21,4,9,1,GLEAM)
        # The quiet head shake is a small yaw: visor shifts inside the
        # rounded shell, with a two-pixel shoulder/hip counterturn below it.
        def face_poly(points,c):poly([(x+shake*2,y) for x,y in points],c)
        def face_box(x,y,w,h,c):box(x+shake*2,y,w,h,c)
        face_poly([(13,13),(18,9),(33,9),(39,13),(41,20),(39,28),(33,32),(18,32),(12,28),(10,20)],MIST)
        face_poly([(14,14),(19,11),(32,11),(37,14),(39,20),(37,27),(32,30),(19,30),(14,27),(12,20)],INK)
        face_poly([(15,14),(20,12),(31,12),(35,14),(23,15),(14,21),(13,20)],GLASS)
        face_poly([(16,27),(25,28),(36,24),(35,27),(30,29),(20,29)],GLASS)
        height=3 if pose=='tired' else 6
        for x in [19,31]:
            face_box(x,18,5,height,CREAM);face_box(x+1,18,4,1,GLEAM)
        return finish()
    # Neck connection and the larger rear ear establish the turned silhouette.
    box(22,32,14,7,INK);box(24,34,10,3,STEEL);box(24,34,2,3,BRASS)
    poly([(1,16),(5,12),(10,12),(12,26),(6,29),(1,25)],INK)
    box(3,17,6,8,STEEL);box(3,17,3,5,TEAL);box(4,17,2,2,MIST)
    poly([(43,10),(48,11),(51,16),(50,22),(45,25)],INK)
    box(47,15,2,6,BLUE);box(47,15,2,2,MIST)
    poly([(6,12),(11,6),(19,2),(31,0),(39,2),(46,8),(48,17),(46,27),(40,33),(30,37),(17,36),(9,31),(5,23)],INK)
    poly([(8,13),(13,7),(20,4),(31,2),(38,4),(44,9),(46,17),(44,26),(39,31),(29,35),(18,34),(11,29),(7,22)],STEEL)
    poly([(8,13),(13,7),(20,4),(31,2),(38,4),(41,7),(22,10),(16,18),(15,28),(11,27),(8,21)],TEAL)
    poly([(11,12),(15,8),(21,5),(31,3),(36,4),(33,6),(21,8),(15,13),(12,20),(10,21)],MIST)
    p.line((xx+16,yy+8),(xx+23,yy+5),GLEAM,1)
    poly([(17,30),(27,32),(37,28),(43,23),(44,27),(38,32),(29,35),(19,34)],BLUE)
    if away:
        # No eyes or front visor: broad rounded rear armor, center seam and
        # recessed neck joint make a full turn distinct from just moving pupils.
        poly([(12,15),(18,9),(28,6),(37,7),(43,12),(44,20),(41,28),(33,33),(22,33),(15,29),(11,22)],BLUE)
        poly([(13,15),(19,10),(28,7),(36,8),(39,10),(27,11),(20,15),(16,24),(13,23)],TEAL)
        poly([(16,15),(21,11),(28,9),(34,9),(30,11),(22,14),(18,20),(16,20)],SKY)
        poly([(17,28),(24,29),(34,27),(41,22),(40,27),(33,31),(23,32)],STEEL)
        p.line((xx+29,yy+9),(xx+26,yy+25),STEEL)
        p.line((xx+30,yy+9),(xx+27,yy+25),TEAL)
        box(21,28,13,4,DEEP);box(23,28,9,1,BLUE)
        for x in [24,27,30]:box(x,30,1,2,SHADE)
        box(12,23,2,2,MIST);box(39,22,2,2,SKY)
        return finish()
    if profile:
        # The visor is a narrow sliver at the far right during the turn.
        poly([(15,15),(23,8),(34,6),(41,9),(39,18),(35,28),(25,33),(17,29),(12,22)],BLUE)
        poly([(16,15),(23,10),(33,8),(35,9),(25,13),(20,20),(17,27),(14,22)],TEAL)
        p.line((xx+29,yy+10),(xx+23,yy+28),STEEL)
        poly([(37,9),(42,10),(45,14),(44,23),(38,29),(33,31),(35,23),(37,16)],MIST)
        poly([(39,12),(42,13),(43,16),(42,22),(38,27),(36,28),(38,21)],INK)
        box(39,15,2,5,CREAM);box(40,15,1,2,GLEAM)
        box(18,29,12,2,STEEL)
        return finish()
    # Rim and visor angle upward toward the far side, not a symmetric TV face.
    poly([(16,15),(22,9),(34,6),(41,7),(45,11),(45,22),(41,27),(31,31),(21,30),(16,26),(14,21)],MIST)
    poly([(18,15),(23,11),(34,8),(40,9),(43,12),(43,21),(39,25),(30,29),(22,28),(18,25),(16,21)],INK)
    poly([(18,16),(24,12),(35,9),(40,10),(41,12),(30,14),(20,20),(17,20)],GLASS)
    poly([(23,25),(33,24),(41,19),(41,22),(37,25),(29,27),(23,27)],GLASS)
    box(23,12,4,1,REFLECT)
    # Eyes shift within the sloping visor. Unequal width supplies perspective;
    # gaze/eyelid changes reinforce the head acting through each held pose.
    eyes={
        'watch':(27,14,38,11), 'brace':(26,17,37,14),
        'windup':(25,18,37,15), 'lift':(28,13,39,10),
        'hit':(28,13,39,10), 'hard':(28,12,39,9),
        'recoil':(27,15,38,12), 'duck':(23,20,35,17),
        'proud':(27,14,38,11), 'tired':(26,18,37,15),
        'startled':(25,13,37,10), 'peek':(27,14,38,11),
    }
    ex,ey,fx,fy=eyes[pose]
    eh=3 if pose in ['hit','hard','tired'] else (8 if pose=='startled' else 6)
    ew=7 if pose=='startled' else 5
    box(ex-1,ey-1,ew+2,eh+2,GLASS);box(fx-1,fy-1,ew,eh+1,GLASS)
    box(ex,ey,ew,eh,CREAM);box(fx,fy,ew-2,eh-1,CREAM)
    box(ex+2,ey,ew-2,1,GLEAM);box(fx+1,fy,ew-3,1,GLEAM)
    return finish()


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
                for xx,yy in [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]:el(path,'StraightVertex',x=xx/2,y=yy/2)
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
        solo,poses=swap(holder,'Paper tumble',{'face':envelope().doubled(),'edge':envelope(True).doubled()})
        letters.append((holder,solo,poses))
    sparkle=Pixels()
    for aa,bb in [((104,2),(101,4)),((114,2),(117,4)),((109,3),(109,5))]:sparkle.line(aa,bb,SKY)
    hit=pixels(a,'Contact sparks',sparkle.doubled())
    hit.set('opacity','0')
    hero,poses=swap(a,'Little robot poses',{name:character(name) for name in ['watch','brace','windup','lift','hit','recoil','hard','duck','proud','tired','startled','peek','settle','nope_left','nope_right']})
    floor=Pixels();floor.box(54,65,31,1,STONE);floor.box(48,65,3,1,CHALK);floor.box(89,65,7,1,CHALK)
    floor=floor.doubled()
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
    # The native 1.6s checking presentation covers both knocks and recoil;
    # fetched mail becomes usable independently of the presentation hold.
    work=timeline('Knock, recoil, knock harder',36,True,pose_keys=[(0,'brace'),(1,'windup'),(2,'lift'),(3,'hit'),(5,'recoil'),(8,'brace'),(10,'windup'),(11,'lift'),(12,'hard'),(14,'recoil'),(16,'brace'),(18,'watch'),(36,'brace')],impact_keys=[(0,0),(3,1),(5,0),(12,1),(14,0)])
    done=timeline('Mail breaks loose',14,pose_keys=[(0,'hard'),(2,'recoil'),(3,'startled'),(5,'duck'),(8,'peek'),(10,'settle'),(13,'proud')],impact_keys=[(0,1),(2,0)],mail=True)
    attention=timeline('Rest the stick',pose='tired')
    empty=timeline('Nothing to dislodge',14,pose_keys=[(0,'brace'),(2,'tired'),(4,'nope_left'),(6,'nope_right'),(8,'nope_left'),(10,'nope_right'),(12,'tired')])
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
            let scale = min(size.width / 288, size.height / 196)
            context.translateBy(x: (size.width - 288 * scale) / 2, y: (size.height - 196 * scale) / 2)
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
