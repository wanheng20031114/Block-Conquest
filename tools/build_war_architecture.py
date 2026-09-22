"""Offline original toy-kingdom architecture for the compact war arena.

All silhouettes are authored offline and baked into native ArrayMesh resources.
The world-space scale and scene interaction nodes remain the original size.
"""
from pathlib import Path
import math
import numpy as np
import trimesh as tm
import build_environment as env

ROOT = Path(__file__).resolve().parents[1]
env.OUT = ROOT / "assets/models/block_war/architecture"
env.OUT.mkdir(parents=True, exist_ok=True)
env.RNG = np.random.default_rng(47321)
BODY_SCALE = .82
env.C.update({
    "stone": (185, 186, 167), "stone_light": (216, 211, 183),
    "plaster": (203, 200, 173), "mortar": (133, 141, 130),
    "wood": (118, 90, 63), "wood_light": (151, 120, 82),
    "wood_dark": (73, 60, 47), "iron": (75, 91, 89),
    "iron_light": (138, 152, 144), "gold": (176, 139, 80),
    "gold_light": (197, 166, 103), "gold_dark": (134, 101, 65),
    "slate": (72, 107, 115), "slate_light": (101, 132, 138),
    "terracotta": (70, 103, 101), "terracotta_light": (97, 128, 121),
    "dark": (37, 52, 47), "canvas": (130, 120, 95),
    "blue": (92, 115, 105), "ember": (229, 115, 45), "ember_light": (244, 182, 83),
    "stone_joint": (148, 153, 133),
})


def contour(m, points, depth, z, material):
    return m.add(env.extruded_contour(points, depth, z), material)


def octagon(width, depth, bevel=.16):
    x, z = width / 2, depth / 2
    b = min(width, depth) * bevel
    return [(-x+b,-z),(x-b,-z),(x,-z+b),(x,z-b),
            (x-b,z),(-x+b,z),(-x,z-b),(-x,-z+b)]


def sculpted_roof(m, width, depth, eave, peak, center=(0, 0), forge=False):
    """Broad curved hip-roof courses with sculpted, rolled edges."""
    cx, cz = center
    color = "terracotta" if forge else "slate"
    light = "terracotta_light" if forge else "slate_light"
    profile = [(0,1,1),(.13,.96,.89),(.39,.84,.67),
               (.69,.64,.39),(1,.43,.085)]
    for level in range(len(profile)-1):
        t0,wx0,dz0 = profile[level]
        t1,wx1,dz1 = profile[level+1]
        rings = [(eave+(peak-eave)*t0-.085,width*wx0,depth*dz0),
                 (eave+(peak-eave)*t0+.075,width*wx0,depth*dz0),
                 (eave+(peak-eave)*t1+.06,width*wx1,depth*dz1)]
        verts = [[x+cx,y,z+cz] for y,w,d in rings for x,z in octagon(w,d,.13)]
        faces = []
        for row in range(2):
            for side in range(8):
                a=row*8+side; b=row*8+(side+1)%8
                faces += [[a,b,b+8],[a,b+8,a+8]]
        faces += [[0,i+1,i] for i in range(1,7)]
        faces += [[16,16+i,17+i] for i in range(1,7)]
        mesh=tm.Trimesh(verts,faces,process=False)
        mesh.fix_normals()
        m.add(mesh,color)
        # Discrete thick tiles follow each hip face. Narrow real gaps show the
        # darker roof below; broad staggered tiles remain readable from above.
        lower=np.asarray(octagon(width*wx0,depth*dz0,.13))
        upper=np.asarray(octagon(width*wx1,depth*dz1,.13))
        y0=eave+(peak-eave)*t0
        y1=eave+(peak-eave)*t1
        for side in range(8):
            count=max(1,round(np.linalg.norm(lower[(side+1)%8]-lower[side])/.72))
            divisions=[0]+[(i+.5*(level%2))/count for i in range(count+1)
                          if .04<(i+.5*(level%2))/count<.96]+[1]
            for left,right in zip(divisions,divisions[1:]):
                vertices=[]
                for along,height in [(0,y0-.02),(0,y0+.075),(.08,y0+.115),(1,y1+.10)]:
                    for fraction in (left+.009,right-.009):
                        a=lower[side]*(1-fraction)+lower[(side+1)%8]*fraction
                        b=upper[side]*(1-fraction)+upper[(side+1)%8]*fraction
                        x,z=a*(1-along)+b*along
                        vertices.append((x+cx,height,z+cz))
                m.add(tm.convex.convex_hull(np.asarray(vertices)),light,
                      variation=env.RNG.uniform(-.025,.025))
    ridge_width=width*.45
    for cap in range(4):
        m.cylinder(.145,ridge_width/4-.018,
                   (cx-ridge_width/2+(cap+.5)*ridge_width/4,peak+.12,cz),
                   light,12,rot=(0,0,math.pi/2))
    for side in (-1,1):
        m.cylinder(.17,.085,(cx+side*ridge_width/2,peak+.12,cz),
                   color,12,rot=(0,0,math.pi/2))


def turned(m, profile, material, center=(0, 0, 0), sections=16, axis="y"):
    """Surface of revolution, including rolled rims and hollow cannon muzzles."""
    vertices=[]
    for height,radius in profile:
        for i in range(sections):
            a=(i+.5)*math.tau/sections
            vertices.append((math.sin(a)*radius,height,math.cos(a)*radius))
    faces=[]
    for row in range(len(profile)-1):
        for i in range(sections):
            a=row*sections+i; b=row*sections+(i+1)%sections
            faces.extend([[a,b,b+sections],[a,b+sections,a+sections]])
    vertices=np.asarray(vertices)
    if axis=="z": vertices=vertices[:,[0,2,1]]
    mesh=tm.Trimesh(vertices,faces,process=False)
    mesh.fix_normals()
    return m.add(mesh,material,center)


def turret_cap(m,x,z,y,radius=.61):
    turned(m,[(y-.11,.92*radius),(y,1.04*radius),(y+.15,radius),
              (y+.48,.69*radius),(y+.79,.37*radius),(y+1.05,.03)],"slate",(x,0,z))
    turned(m,[(y-.12,.91*radius),(y-.09,1.045*radius),(y+.02,1.045*radius),
              (y+.055,.95*radius)],"slate_light",(x,0,z))
    m.add(tm.creation.icosphere(subdivisions=1,radius=.095),"gold_light",(x,y+1.12,z))


def arch_panel(m,width,height,base,z,material,x=0,depth=.12):
    radius=width/2
    spring=base+height-radius
    points=[(x-radius,base),(x+radius,base),(x+radius,spring)]
    points += [(x+math.cos(a)*radius,spring+math.sin(a)*radius)
               for a in np.linspace(0,math.pi,13)[1:]]
    contour(m,points,depth,z,material)


def royal_gate(m,x,base,z,width=1.05,height=1.65,furnace=False):
    arch_panel(m,width+.39,height+.20,base,z,"stone_light",x,.23)
    arch_panel(m,width,height,base+.025,z+.145,"dark",x,.09)
    if furnace:
        arch_panel(m,width*.75,height*.73,base+.07,z+.203,"ember",x,.06)
        arch_panel(m,width*.52,height*.57,base+.08,z+.243,"ember_light",x,.03)
        for dx in (-.31,0,.31):
            m.box((.085,.47,.12),(x+dx,base+.30,z+.29),"iron",bevel=.02)
    else:
        arch_panel(m,width-.12,height-.12,base+.04,z+.205,"wood",x,.07)
        m.box((.045,height-.21,.035),(x,base+(height-.21)/2+.04,z+.26),"wood_dark",bevel=.008)
        for yy in (.37,.91):
            m.box((width-.09,.105,.07),(x,base+yy,z+.285),"gold",bevel=.025)
        for dx in (-.12,.12):
            m.add(tm.creation.icosphere(subdivisions=1,radius=.067),"gold_light",(x+dx,base+.72,z+.335))
    m.box((width+.40,.18,.47),(x,base+.035,z+.13),"stone",bevel=.05)


def window(m,x,y,z,width=.39,height=.82):
    arch_panel(m,width+.20,height+.20,y-height/2-.07,z,"stone_light",x,.14)
    arch_panel(m,width,height,y-height/2,z+.095,"dark",x,.07)
    m.box((.06,height-.10,.05),(x,y-.045,z+.15),"gold",bevel=.012)
    m.box((width+.30,.14,.26),(x,y-height/2-.12,z+.08),"stone_light",bevel=.045)


def shield(m,x,y,z,size=.6):
    points=[(-.50,.50),(.50,.50),(.46,-.12),(0,-.53),(-.46,-.12)]
    contour(m,[(x+xx*size,y+yy*size) for xx,yy in points],.17,z,"gold")
    contour(m,[(x+xx*size*.72,y+yy*size*.72) for xx,yy in points],.06,z+.12,"wood")
    crown=[(-.30,-.06),(.30,-.06),(.34,.27),(.12,.13),(0,.36),(-.12,.13),(-.34,.27)]
    contour(m,[(x+xx*size,y+yy*size) for xx,yy in crown],.035,z+.17,"gold_light")


def wall_joints(m,width,center,height=2.16):
    """A few broad masonry joints instead of brick noise or painted textures."""
    x,base,z=center
    step=height/3
    for row in range(3):
        y=base+(row+1)*step
        m.box((width,.018,.012),(x,y,z),"stone_joint",bevel=.003)
        joint_x=x+(.28 if row%2 else -.32)*width
        m.box((.018,step-.015,.013),(joint_x,y-step/2,z),"stone_joint",bevel=.003)


def foundation():
    m=env.Model()
    for row in range(3):
        m.box((1.14-row*.10,.085,.30),(0,.032,1.51+row*.30),"stone_light",bevel=.05)
    # Keep the original flag location and readable faction size.
    m.cylinder(.064,4.21,(1.85,2.055,.28),"wood_dark",12)
    m.cylinder(.12,.19,(1.85,.095,.28),"iron",12)
    m.cone(.14,0,.30,(1.85,4.26,.28),"gold_light",8)
    for y in (3.27,4.20):
        m.ring(.064,.096,.075,(1.85,y,.28),"gold",12)
    return m


def residence(level=1):
    if level < 3:
        return cottage(level)
    m=env.Model()
    # Extend only the footing below ground; keep the original top and bevel.
    m.box((3.08,.43,2.75),(0,.115,-.08),"mortar",bevel=.072)
    m.box((2.98,2.32,2.55),(0,1.40,-.08),"plaster",bevel=.22)
    m.box((3.14,.28,2.73),(0,.41,-.08),"stone",bevel=.10)
    m.box((3.14,.23,2.70),(0,2.49,-.08),"stone_light",bevel=.08)
    for x in (-1.24,1.24):
        turned(m,[(-.10,.52),(.01,.57),(.52,.57),(.64,.46),
                  (2.52,.46),(2.61,.55),(2.82,.55),(2.86,.47)],"stone",(x,0,.83),12)
        m.ring(.45,.50,.14,(x,1.08,.83),"stone_light",12)
        turret_cap(m,x,.83,2.84,.64)
        window(m,x,1.88,1.28,.29,.65)
    royal_gate(m,0,.18,1.28,1.02,1.67)
    shield(m,0,2.24,1.30,.50)
    for side in (-1,1):
        section=env.Model()
        wall_joints(section,1.76,(0,.37,.0),1.99)
        window(section,0,1.55,0,.52,.98)
        m.absorb(section,(side*1.51,0,-.24),side*math.pi/2)
    sculpted_roof(m,3.38,2.94,2.67,4.08,(0,-.18))
    crest=[(-.32,0),(.32,0),(.36,.26),(.12,.13),(0,.37),(-.12,.13),(-.36,.26)]
    contour(m,[(x,y+4.17) for x,y in crest],.15,-.18,"gold")
    return m


def cottage(level):
    """A timber cottage becomes a stone lodge before gaining twin corner bays."""
    m=env.Model()
    height=2.05 if level==1 else 2.37
    m.box((3.04,.43,2.70),(0,.115,-.08),"mortar",bevel=.072)
    m.box((2.84,height,2.40),(0,height/2+.19,-.08),"plaster",bevel=.16)
    m.box((3.00,.30,2.59),(0,.34,-.08),"stone",bevel=.08)
    if level==1:
        for x in (-1.30,1.30):
            for z in (-1.18,1.04):
                m.box((.19,height+.06,.19),(x,height/2+.16,z),"wood",bevel=.035)
        m.box((2.87,.17,2.44),(0,1.03,-.08),"wood_light",bevel=.04)
        royal_gate(m,0,.15,1.15,.96,1.54)
    else:
        m.box((3.06,.20,2.61),(0,2.47,-.08),"stone_light",bevel=.06)
        turned(m,[(-.10,.46),(.06,.52),(.47,.52),(.61,.42),
                  (2.28,.42),(2.41,.51),(2.61,.51)],"stone",(-1.16,0,.78),12)
        turret_cap(m,-1.16,.78,2.61,.56)
        window(m,-1.16,1.73,1.20,.29,.68)
        royal_gate(m,.30,.17,1.15,1.03,1.68)
        shield(m,.30,2.27,1.27,.40)
    for side in (-1,1):
        panel=env.Model()
        if level==2:
            wall_joints(panel,1.97,(0,.43,0),1.81)
        window(panel,0,1.39 if level==1 else 1.62,0,.48,.77 if level==1 else .98)
        m.absorb(panel,(side*1.43,0,-.21),side*math.pi/2)
    eave=2.29 if level==1 else 2.58
    peak=3.52 if level==1 else 3.87
    sculpted_roof(m,3.29,2.85,eave,peak,(0,-.13))
    # A squat chimney and broad timber barge board identify the domestic tier.
    m.box((.43,.87,.48),(.87,peak-.06,-.68),"stone",bevel=.065)
    m.box((.54,.16,.57),(.87,peak+.40,-.68),"stone_light",bevel=.04)
    m.box((.34,.035,.36),(.87,peak+.49,-.68),"dark",bevel=.025)
    if level==2:
        for x in (-.52,.10,.72):
            m.box((.37,.12,.16),(x,2.52,1.21),"wood_dark",bevel=.025)
    return m


def tower(level=1):
    m=env.Model()
    deck=(1.84,2.50,2.77)[level-1]
    wall=deck-.22
    radius=(1.49,1.57,1.66)[level-1]
    turned(m,[(-.10,radius-.06),(.04,radius+.16),(.33,radius+.16),
              (.46,radius),(wall-.42,radius),(wall-.29,radius+.15),
              (wall-.08,radius+.15),(wall,radius)],"stone",sections=12 if level==1 else 8)
    turned(m,[(.49,radius+.01),(.59,radius+.055),(.77,radius+.055),
              (.86,radius+.01)],"wood" if level<3 else "iron",sections=8)
    for i in range(8):
        angle=(i+.5)*math.tau/8
        if i in (0,7): continue
        if level==1 and i%2==0: continue
        m.box((.72 if level==1 else .85,.43 if level==1 else .61,.48),
              (math.sin(angle)*(radius-.09),wall+.19,math.cos(angle)*(radius-.09)),
              "wood" if level==1 else "stone_light",rot=(0,angle,0),bevel=.095)
        if level==3:
            m.box((.62,.17,.55),(math.sin(angle)*(radius-.09),wall+.48,math.cos(angle)*(radius-.09)),
                  "iron",rot=(0,angle,0),bevel=.05)
    for i in range(8):
        angle=i*math.tau/8
        joints=env.Model()
        wall_joints(joints,1.06,(0,.47,0),wall-.56)
        m.absorb(joints,(math.sin(angle)*radius*.927,0,math.cos(angle)*radius*.927),angle)
    royal_gate(m,0,.13,radius*.93,.79,.98 if level==1 else 1.44)
    for side in (-1,1):
        detail=env.Model()
        shield(detail,0,wall*.63,0,.42 if level==1 else .63)
        m.absorb(detail,(side*radius,0,0),side*math.pi/2)
    if level==3:
        for x,z in [(-1.08,-1.08),(1.08,-1.08),(-1.08,1.08),(1.08,1.08)]:
            # Grounded splayed buttresses make the heavy tier visibly fortified.
            buttress=tm.convex.convex_hull(np.asarray([
                (x+dx,y,z+dz) for y,r in [(-.10,.37),(.15,.38),(1.87,.25)]
                for dx,dz in [(-r,-r),(-r,r),(r,r),(r,-r)]]))
            m.add(buttress,"stone_light")
    m.cylinder(radius-.23,.12,(0,deck-.20,0),"wood_dark",16)
    m.cylinder(.77,.20,(0,deck-.12,0),"iron",16)
    m.ring(.63,.80,.10,(0,deck,0),"gold",16)
    return m


def anvil(m,x,y,z,scale=1):
    shape=[(-.52,0),(.43,0),(.37,.18),(.18,.27),(.20,.47),
           (.50,.58),(.91,.73),(.46,.79),(-.55,.79),(-.61,.60),
           (-.20,.46),(-.18,.25),(-.44,.17)]
    contour(m,[(x+xx*scale,y+yy*scale) for xx,yy in shape],.38*scale,z,"iron_light")


def shed_roof(m,width,depth,center_x,front,back):
    """A single open-workshop lean-to, with actual staggered thick clay tiles."""
    rows=4
    cols=4
    for row in range(rows):
        z0=depth/2-row*depth/rows
        z1=depth/2-(row+1)*depth/rows-.045
        y0=front+(back-front)*row/rows
        y1=front+(back-front)*(row+1)/rows
        divisions=[0]+[(i+.5*(row%2))/cols for i in range(cols+1)
                       if 0<(i+.5*(row%2))/cols<1]+[1]
        for left,right in zip(divisions,divisions[1:]):
            x0=center_x-width/2+left*width+.012
            x1=center_x-width/2+right*width-.012
            vertices=[(x,y,z) for x in (x0,x1) for y,z in
                      [(y0-.08,z0+.04),(y0+.04,z0+.04),(y1+.04,z1),(y1-.08,z1)]]
            m.add(tm.convex.convex_hull(np.asarray(vertices)),"terracotta_light",
                  variation=env.RNG.uniform(-.035,.02))
            m.cylinder(.055,x1-x0,(.5*(x0+x1),y0+.03,z0+.04),
                       "terracotta",10,rot=(0,0,math.pi/2))
    for x in (center_x-width/2,center_x+width/2):
        m.beam((x,front-.09,depth/2),(x,back-.09,-depth/2),.15,"wood_dark")
    m.box((width+.12,.14,.19),(center_x,front-.06,depth/2+.02),"wood_light",bevel=.035)
    m.box((width+.12,.13,.17),(center_x,back+.03,-depth/2),"terracotta",bevel=.035)


def smithy(level=1):
    m=env.Model()
    chimney_top=(3.27,4.29,4.69)[level-1]
    front=(2.04,2.56,2.71)[level-1]
    back=front+(.48 if level==1 else .57)
    width=(1.68,2.11,2.21)[level-1]
    depth=2.28 if level==1 else 2.76
    m.box((3.34,.42,2.88),(0,.11,0),"mortar",bevel=.072)
    # Open stone apron: the gaps beneath the roof are deliberate, not dark walls.
    for x in (-1.12,-.38,.38,1.12):
        for z in (-.94,0,.94):
            m.box((.71,.10,.90),(x,.35,z),"stone",bevel=.035,
                  variation=env.RNG.uniform(-.025,.025))
    furnace_height=(1.43,1.84,2.02)[level-1]
    furnace_width=(1.23,1.37,1.50)[level-1]
    m.box((furnace_width,furnace_height,1.45),(-.84,.30+furnace_height/2,-.26),
          "stone",bevel=.16)
    royal_gate(m,-.84,.36,.54,.90,1.18,True)
    # Tapered hood flows into a visibly massive masonry chimney.
    hood=tm.convex.convex_hull(np.asarray([
        (x-.84,y,z-.26) for y,r in [(furnace_height+.21,.78),(furnace_height+.71,.46)]
        for x,z in [(-r,-r),(-r,r),(r,r),(r,-r)]]))
    m.add(hood,"iron" if level==3 else "mortar")
    stack_bottom=furnace_height+.58
    if level<3:
        m.box((.91,chimney_top-stack_bottom,.98),
              (-.84,(chimney_top+stack_bottom)/2,-.26),"stone",bevel=.10)
        for y in np.arange(stack_bottom+.25,chimney_top-.14,.45):
            m.box((.92,.022,1.00),(-.84,y,-.26),"stone_joint",bevel=.004)
        m.box((1.17,.23,1.22),(-.84,chimney_top,-.26),"iron",bevel=.07)
        m.box((.80,.03,.85),(-.84,chimney_top+.13,-.26),"dark",bevel=.025)
    else:
        # Twin round metal flues create a different top-down silhouette, rather
        # than hiding another upgrade under the same rectangular canopy.
        m.box((1.15,.62,1.10),(-.84,2.87,-.26),"stone",bevel=.09)
        upper_hood=tm.convex.convex_hull(np.asarray([
            (x-.84,y,z-.26) for y,rx,rz in [(3.09,.78,.66),(3.48,.63,.46)]
            for x,z in [(-rx,-rz),(-rx,rz),(rx,rz),(rx,-rz)]]))
        m.add(upper_hood,"iron")
        m.box((1.58,.14,1.34),(-.84,3.13,-.26),"gold_dark",bevel=.045)
        for x in (-1.17,-.51):
            turned(m,[(3.40,.24),(3.57,.27),(chimney_top-.23,.27),
                      (chimney_top-.17,.34),(chimney_top,.34),
                      (chimney_top+.04,.25),(chimney_top+.04,.20),
                      (chimney_top-.17,.20)],"iron",(x,0,-.26),16)
            m.ring(.265,.30,.13,(x,3.72,-.26),"gold_dark",16)
            m.cylinder(.195,.025,(x,chimney_top-.18,-.26),"dark",16)
    if level>=2:
        if level==2:
            for y in (3.16,3.74):
                m.box((1.06,.18,1.12),(-.84,y,-.26),"stone_light",bevel=.045)
        m.box((furnace_width+.12,.16,1.52),(-.84,.44,-.26),"stone_light",bevel=.06)
    # Four grounded posts carry a narrow, asymmetrical tiled canopy beside the forge.
    for x in (-.12,1.44):
        for z in (-depth*.41,depth*.41):
            top=front+(back-front)*(depth/2-z)/depth-.15
            m.box((.35,.39,.35),(x,.095,z),"stone_light",bevel=.055)
            m.box((.20,top-.24,.20),(x,(top+.24)/2,z),"wood",bevel=.04)
            m.box((.25,.12,.25),(x,top-.17,z),"iron",bevel=.02)
            if level>=2:
                toward=1 if x<0 else -1
                m.beam((x,top-.55,z),(x+toward*.44,top-.10,z),.14,"wood_light")
    for z in (-depth*.41,depth*.41):
        y=front+(back-front)*(depth/2-z)/depth-.12
        m.box((1.97,.18,.19),(.66,y,z),"wood_dark",bevel=.035)
    shed_roof(m,width,depth,.66,front,back)
    # The exposed anvil is a real work station with a broad, readable horn.
    m.cylinder(.38,.57,(.48,.66,.77),"wood",12)
    for y in (.45,.89):
        m.ring(.35,.40,.09,(.48,y,.77),"iron",12)
    anvil(m,.48,.98,.78,.69 if level==1 else .96)
    m.box((.32,.19,.21),(.20,1.73 if level>1 else 1.62,.79),"iron",bevel=.045)
    m.beam((.24,1.60,.75),(.61,1.29,.80),.065,"wood_light")
    # Quench tub has a visible hollow water surface, dark staves and two hoops.
    turned(m,[(.36,.32),(.43,.40),(.94,.43),(1.01,.40),(1.01,.32),(.49,.28)],
           "wood",(1.02,0,-.74),12)
    for y in (.49,.88):
        m.ring(.36,.43,.085,(1.02,y,-.74),"iron",12)
    m.cylinder(.32,.018,(1.02,.88,-.74),"dark",12)
    if level>=2:
        # A side lifting frame rises above the canopy, visible at gameplay zoom.
        m.box((.37,.39,.37),(1.62,.095,1.22),"stone_light",bevel=.055)
        m.box((.20,2.74,.20),(1.62,1.58,1.22),"wood",bevel=.035)
        m.box((1.09,.20,.24),(1.23,2.99,1.22),"wood_light",bevel=.045)
        m.beam((1.62,2.36,1.22),(1.10,2.91,1.22),.16,"wood")
        m.cylinder(.037,.35,(.86,2.70,1.22),"iron",8)
        m.ring(.095,.135,.065,(.86,2.45,1.22),"iron",12,rot=(math.pi/2,0,0))
        # Open rack and iron stock replace the residence-like wall/sign façade.
        for x in (.22,1.08):
            m.box((.14,.82,.14),(x,.78,-1.10),"wood",bevel=.025)
        m.box((1.18,.18,.50),(.65,1.23,-1.10),"wood_light",bevel=.04)
        for x in (.22,.58,.94):
            m.box((.22,.18,.37),(x,1.40,-1.10),"iron_light",bevel=.04)
    if level==3:
        for x in (-1.49,-.18):
            m.box((.16,1.52,.12),(x,1.23,.52),"iron",bevel=.035)
        m.box((1.57,.13,.17),(-.84,1.99,.58),"gold_dark",bevel=.035)
        # A second low striking block and stacked billets mark the master forge.
        m.box((.50,.48,.48),(1.17,.61,.36),"stone_light",bevel=.08)
        anvil(m,1.17,.89,.39,.48)
        for x in (-1.30,-.98,-.66):
            m.box((.25,.15,.57),(x,.53,-1.13),"iron_light",bevel=.025)
    return m


def bellows():
    m=env.Model()
    for i in range(4):
        m.cone(.22-i*.02,.20-i*.02,.09,(0,i*.072,0),"canvas",10)
    m.box((.43,.08,.39),(0,.30,0),"wood_light",bevel=.03)
    m.box((.08,.09,.52),(0,.35,.22),"wood",bevel=.018)
    return m


def gun_mount(level=1):
    m=env.Model()
    width=(.51,.64,.69)[level-1]
    m.cylinder(.73 if level==1 else .85,.24,(0,.17,0),"iron",16)
    m.ring(.58 if level==1 else .68,.76 if level==1 else .89,.13,(0,.27,0),"gold",16)
    for x in (-width,width):
        m.box((.25 if level==1 else .30,.99,1.14),(x,.76,.03),"wood",bevel=.10)
        m.cylinder(.24,.16,(x,1.18,.04),"gold",12,rot=(0,0,math.pi/2))
        m.cylinder(.13,.19,(x,1.18,.04),"iron_light",12,rot=(0,0,math.pi/2))
        if level==3:
            m.box((.14,.73,1.10),(x*1.22,.69,.06),"iron",bevel=.075)
            for z in (-.32,.35):
                m.add(tm.creation.icosphere(subdivisions=1,radius=.085),"gold",(x*1.34,.90,z))
    return m


def gun_barrel(level=1):
    m=env.Model()
    turned(m,[(.72,.08),(.68,.36),(.45,.55),(.05,.60),(-.68,.57),
              (-1.65,.50),(-1.93,.60),(-2.23,.70),(-2.42,.70),
              (-2.48,.61),(-2.48,.43),(-2.13,.38)],"iron",sections=24,axis="z")
    m.cylinder(.38,.025,(0,0,-2.10),"dark",24,rot=(math.pi/2,0,0))
    turned(m,[(-2.22,.705),(-2.30,.755),(-2.44,.755),(-2.50,.68),
              (-2.50,.44),(-2.45,.415)],"gold",sections=24,axis="z")
    turned(m,[(-.25,.605),(-.30,.67),(-.52,.67),(-.56,.58)],"blue",sections=24,axis="z")
    m.add(tm.creation.icosphere(subdivisions=1,radius=.15),"gold",(0,.15,.77))
    m.box((.23,.05,1.10),(0,.548,-1.13),"iron_light",bevel=.012)
    if level==3:
        turned(m,[(.28,.566),(.25,.635),(.05,.65),(-.01,.605)],"gold_dark",sections=24,axis="z")
        for side in (-1,1):
            m.box((.12,.44,.63),(side*.56,0,.12),"iron_light",bevel=.045)
    radial=(.72,1.0,1.08)[level-1]
    length=(.72,1.0,1.12)[level-1]
    for pieces in m.parts.values():
        for piece in pieces:
            piece.apply_scale((radial,radial,length))
    return m


if __name__ == "__main__":
    builds=[("foundation",foundation()),("bellows",bellows())]
    for level in range(1,4):
        suffix="" if level==1 else f"_{level}"
        for name,build in [("house",residence),("tower",tower),("smithy",smithy),
                           ("gun_mount",gun_mount),("gun_barrel",gun_barrel)]:
            # Each tier is deterministic even when rebuilt independently.
            env.RNG=np.random.default_rng(47321+level*101)
            builds.append((name+suffix,build(level)))
    for name,model in builds:
        if name.startswith(("house","tower","smithy","bellows")):
            for pieces in model.parts.values():
                for piece in pieces:
                    piece.apply_scale(BODY_SCALE)
        model.save(name,wrapper=False)
