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


def residence():
    m=env.Model()
    m.box((3.08,.30,2.75),(0,.18,-.08),"mortar",bevel=.12)
    m.box((2.98,2.32,2.55),(0,1.40,-.08),"plaster",bevel=.22)
    m.box((3.14,.28,2.73),(0,.41,-.08),"stone",bevel=.10)
    m.box((3.14,.23,2.70),(0,2.49,-.08),"stone_light",bevel=.08)
    for x in (-1.24,1.24):
        turned(m,[(.20,.52),(.31,.57),(.52,.57),(.64,.46),
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


def tower():
    m=env.Model()
    turned(m,[(.04,1.49),(.16,1.73),(.40,1.73),(.52,1.57),
              (1.87,1.57),(1.99,1.79),(2.23,1.79),(2.31,1.62)],"stone",sections=8)
    turned(m,[(.54,1.584),(.63,1.61),(.87,1.61),(.94,1.584)],"wood",sections=8)
    for i in range(8):
        angle=(i+.5)*math.tau/8
        if i in (0,7): continue
        m.box((.85,.61,.51),(math.sin(angle)*1.48,2.46,math.cos(angle)*1.48),
              "stone_light",rot=(0,angle,0),bevel=.105)
    for i in range(8):
        angle=i*math.tau/8
        joints=env.Model()
        wall_joints(joints,1.15,(0,.99,0),.82)
        m.absorb(joints,(math.sin(angle)*1.455,0,math.cos(angle)*1.455),angle)
    royal_gate(m,0,.15,1.48,.87,1.44)
    for side in (-1,1):
        detail=env.Model()
        shield(detail,0,1.37,0,.63)
        m.absorb(detail,(side*1.575,0,0),side*math.pi/2)
    m.cylinder(1.31,.12,(0,2.27,0),"wood_dark",16)
    m.cylinder(.77,.20,(0,2.38,0),"iron",16)
    m.ring(.63,.80,.10,(0,2.50,0),"gold",16)
    return m


def anvil(m,x,y,z,scale=1):
    shape=[(-.52,0),(.43,0),(.37,.18),(.18,.27),(.20,.47),
           (.50,.58),(.91,.73),(.46,.79),(-.55,.79),(-.61,.60),
           (-.20,.46),(-.18,.25),(-.44,.17)]
    contour(m,[(x+xx*scale,y+yy*scale) for xx,yy in shape],.38*scale,z,"iron_light")


def smithy():
    m=env.Model()
    m.box((3.34,.34,2.84),(0,.21,0),"mortar",bevel=.13)
    m.box((3.12,2.07,2.58),(0,1.36,-.07),"plaster",bevel=.20)
    m.box((3.28,.24,2.76),(0,.47,0),"stone",bevel=.075)
    m.box((3.32,.24,2.77),(0,2.40,0),"wood_dark",bevel=.07)
    sculpted_roof(m,3.65,3.12,2.54,3.85,(0,-.12),forge=True)
    m.box((1.64,2.12,.62),(-.57,1.31,1.24),"mortar",bevel=.16)
    royal_gate(m,-.57,.27,1.56,1.05,1.63,True)
    m.box((1.87,.27,.84),(-.57,2.40,1.36),"stone_light",bevel=.08)
    m.box((.91,2.20,.98),(-.92,3.67,-.47),"stone",bevel=.13)
    for y in (3.25,3.97):
        m.box((1.01,.16,1.08),(-.92,y,-.47),"stone_light",bevel=.055)
    m.box((1.24,.29,1.30),(-.92,4.78,-.47),"iron",bevel=.09)
    m.box((.85,.05,.91),(-.92,4.95,-.47),"dark",bevel=.06)
    m.box((.16,.65,.16),(1.28,2.51,1.37),"gold",bevel=.035)
    m.box((1.24,.14,.17),(1.10,2.78,1.37),"gold",bevel=.04)
    contour(m,[(.59,1.77),(1.68,1.77),(1.76,2.60),(.50,2.60)],.14,1.43,"gold")
    contour(m,[(.65,1.84),(1.62,1.84),(1.68,2.52),(.59,2.52)],.07,1.54,"wood_dark")
    anvil(m,1.04,1.92,1.64,.65)
    m.cylinder(.32,.54,(.80,.64,1.32),"wood",10)
    m.ring(.30,.35,.09,(.80,.45,1.32),"gold",12)
    anvil(m,.80,.91,1.34,.69)
    side=env.Model()
    wall_joints(side,1.90,(0,.44,0),1.71)
    window(side,0,1.55,0,.46,.85)
    m.absorb(side,(1.585,0,-.10),math.pi/2)
    return m


def bellows():
    m=env.Model()
    for i in range(4):
        m.cone(.22-i*.02,.20-i*.02,.09,(0,i*.072,0),"canvas",10)
    m.box((.43,.08,.39),(0,.30,0),"wood_light",bevel=.03)
    m.box((.08,.09,.52),(0,.35,.22),"wood",bevel=.018)
    return m


def gun_mount():
    m=env.Model()
    m.cylinder(.85,.24,(0,.17,0),"iron",16)
    m.ring(.68,.89,.13,(0,.27,0),"gold",16)
    for x in (-.64,.64):
        m.box((.30,.99,1.14),(x,.76,.03),"wood",bevel=.10)
        m.cylinder(.24,.16,(x,1.18,.04),"gold",12,rot=(0,0,math.pi/2))
        m.cylinder(.13,.19,(x,1.18,.04),"iron_light",12,rot=(0,0,math.pi/2))
    return m


def gun_barrel():
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
    return m


if __name__ == "__main__":
    for name,build in [("foundation",foundation),("house",residence),
                       ("tower",tower),("smithy",smithy),("bellows",bellows),
                       ("gun_mount",gun_mount),("gun_barrel",gun_barrel)]:
        model=build()
        if name in ("house","tower","smithy","bellows"):
            for pieces in model.parts.values():
                for piece in pieces:
                    piece.apply_scale(BODY_SCALE)
        model.save(name,wrapper=False)
