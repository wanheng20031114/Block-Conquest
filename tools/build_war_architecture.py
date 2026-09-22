"""Author the war-mode sculptures offline, reusing the environment modelling kit.

Requires numpy, trimesh and shapely, as does build_environment.py. Then bake the
saved glTF families with tools/build_war_architecture.gd; gameplay loads .res only.
The original environment assets and their palettes are never written by this tool.
"""
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parents[1]
import numpy as np
import trimesh as tm
import build_environment as env

env.OUT = ROOT / "assets/models/block_war/architecture"
env.OUT.mkdir(parents=True, exist_ok=True)
env.RNG = np.random.default_rng(47321)
BODY_SCALE = .82
env.C.update({
    "stone": (173, 173, 154), "stone_light": (201, 194, 164),
    "plaster": (205, 192, 158), "mortar": (128, 123, 103),
    "wood": (118, 72, 34), "wood_light": (162, 109, 57),
    "wood_dark": (83, 48, 26), "iron": (63, 78, 89),
    "iron_light": (139, 157, 165), "gold": (188, 135, 49),
    "slate": (67, 100, 124), "slate_light": (76, 111, 134),
    "terracotta": (171, 87, 49), "terracotta_light": (185, 99, 57),
    "grass": (117, 137, 44), "grass_light": (141, 153, 59),
    "leaf": (87, 112, 43), "leaf_light": (113, 132, 50),
    "dark": (27, 25, 23), "canvas": (134, 100, 67),
})


def foundation():
    m = env.Model()
    # No common plinth: a broken, partly buried approach and scattered wall stones.
    stones=[(-.27,1.83,.38,.27),(.16,2.25,.33,.25),(-.10,2.70,.30,.24),
            (-1.84,-.78,.27,.20),(1.89,-1.07,.28,.22),(-1.76,1.17,.22,.17),
            (.96,-1.77,.21,.17),(1.93,.53,.20,.17)]
    for x,z,rx,rz in stones:
        radii=env.RNG.uniform(.83,1.11,7)
        vertices=[]
        for y in (-.055,.045):
            for i in range(7):
                angle=i*math.tau/7
                vertices.append((x+math.cos(angle)*rx*radii[i],y+env.RNG.uniform(-.016,.016),z+math.sin(angle)*rz*radii[i]))
        m.add(tm.convex.convex_hull(np.asarray(vertices)),"stone",variation=env.RNG.uniform(-.025,.025))
    for x,z in [(-1.81,-1.25),(1.85,-1.36),(-1.88,.83),(1.93,.20),(.90,-1.72)]:
        for blade in range(5):
            yaw=env.RNG.uniform(0,math.tau)
            height=env.RNG.uniform(.16,.37)
            reach=env.RNG.uniform(.06,.17)
            root=np.array([x+env.RNG.uniform(-.12,.12),-.015,z+env.RNG.uniform(-.12,.12)])
            tangent=np.array([math.cos(yaw)*.044,0,math.sin(yaw)*.044])
            tip=root+np.array([-math.sin(yaw)*reach,height,math.cos(yaw)*reach])
            center=(root+tip)*.5+np.array([0,.055,0])
            verts=[root-tangent,root+tangent,center-tangent*.8,center+tangent*.8,tip]
            grass=tm.Trimesh(verts,[[0,1,3],[0,3,2],[2,3,4],[3,1,0],[2,3,0],[4,3,2]],process=False)
            m.add(grass,"grass_light" if blade%3==0 else "grass")
    for pieces in m.parts.values():
        for piece in pieces:
            piece.apply_scale(BODY_SCALE)
    # The banner remains large enough to read independently of the smaller body.
    m.cylinder(.085,4.21,(1.85,2.055,.28),"wood_dark",12)
    m.cylinder(.12,.19,(1.85,.095,.28),"iron",12)
    m.cone(.14,0,.30,(1.85,4.26,.28),"gold",8)
    for y in (3.27,4.20):
        m.ring(.082,.108,.075,(1.85,y,.28),"iron",12)
    return m


def chunky_roof(m,w,d,eave,peak,center=(0,0),slate=False):
    """Large bevelled clay shingles: broad readable forms without micro-detail."""
    x,z=center
    hw,hd=w*.5,d*.5
    verts=[[x-hw,eave,z-hd],[x+hw,eave,z-hd],[x-hw,peak,z],[x+hw,peak,z],[x-hw,eave,z+hd],[x+hw,eave,z+hd]]
    mesh=tm.Trimesh(verts,[[0,1,3],[0,3,2],[2,3,5],[2,5,4],[0,2,4],[1,5,3],[0,4,5],[0,5,1]],process=False)
    mesh.fix_normals()
    material="slate" if slate else "terracotta"
    m.add(mesh,material)
    slope=(peak-eave)/hd
    angle=math.atan(slope)
    rows=max(2,round(hd/.55))
    cols=max(3,round(w/.72))
    for sign in (-1,1):
        for row in range(rows):
            divisions=[-hw]+[-hw+(i+.5*(row%2))*w/cols for i in range(cols+1) if -hw+.045 < -hw+(i+.5*(row%2))*w/cols < hw-.045]+[hw]
            zz=(row+.53)*hd/rows
            yy=peak-slope*zz+.105
            for left,right in zip(divisions,divisions[1:]):
                m.box((right-left-.018,.16,hd/rows/math.cos(angle)+.055),
                      (x+(left+right)*.5,yy,z+sign*zz),
                      material,rot=(sign*angle,0,0),bevel=.065,
                      variation=env.RNG.uniform(-.02,.02))
    for i in range(cols):
        m.cylinder(.18,w/cols-.023,(x-hw+(i+.5)*w/cols,peak+.07,z),material,sections=12,rot=(0,0,math.pi/2))
    for sign in (-1,1):
        m.box((w+.06,.25,.25),(x,eave-.10,z+sign*hd),"wood_dark",bevel=.06)
        for slope_sign in (-1,1):
            length=math.sqrt(hd*hd+(peak-eave)**2)
            m.box((.25,.24,length+.12),(x+sign*hw,(eave+peak)*.5-.08,z+slope_sign*hd*.5),"wood_dark",rot=(slope_sign*angle,0,0),bevel=.055)


def cartoon_gate(m,width,height,center):
    x,base,z=center
    r=width*.5
    spring=height-r
    m.box((width,spring,.15),(x,base+spring*.5,z),"dark",bevel=.025)
    cap=[(x-r,base+spring)]+[(x+math.cos(a)*r,base+spring+math.sin(a)*r) for a in np.linspace(math.pi,0,13)]+[(x+r,base+spring)]
    m.add(tm.convex.convex_hull(np.asarray([[xx,yy,zz] for zz in (z-.065,z+.065) for xx,yy in cap])),"dark")
    for col in range(3):
        xx=-r+(col+.5)*width/3
        hh=spring+math.sqrt(r*r-xx*xx)-.04
        m.box((width/3-.012,hh,.13),(x+xx,base+hh*.5,z+.09),"wood_light",bevel=.035,variation=(col-1)*.015)
    for sign in (-1,1):
        for row in range(2):
            m.box((.32,spring*.5-.025,.35),(x+sign*(r+.16),base+(row+.5)*spring*.5,z+.11),"stone_light",bevel=.065)
    for i in range(7):
        a=(i+.5)*math.pi/7
        m.box((.34,.40,.36),(x+math.cos(a)*(r+.16),base+spring+math.sin(a)*(r+.16),z+.11),"stone_light",rot=(0,0,a-math.pi*.5),bevel=.066)
    for y in (.43,1.13):
        m.box((width-.09,.13,.07),(x,base+y,z+.19),"iron",bevel=.026)
    m.ring(.055,.085,.034,(x+.15,base+.91,z+.245),"gold",12,rot=(math.pi/2,0,0))


def cartoon_window(m,x,y,z):
    m.box((.77,.90,.21),(x,y,z),"wood_light",bevel=.065)
    m.box((.54,.64,.06),(x,y+.015,z+.135),"dark",bevel=.04)
    m.box((.09,.66,.07),(x,y+.015,z+.183),"wood_light",bevel=.02)
    m.box((.58,.08,.07),(x,y+.015,z+.185),"wood_light",bevel=.02)
    m.box((.94,.17,.35),(x,y-.47,z+.08),"stone_light",bevel=.06)


def residence():
    m = env.Model()
    m.box((3.28,2.65,2.74),(0,1.585,0),"plaster",bevel=.14)
    # One buried stone course is the wall's footing, with no display platform.
    for z in (-1.39,1.39):
        for x in (-1.19,-.4,.4,1.19):
            m.box((.78,.48,.22),(x,.48,z),"stone",bevel=.075)
        m.box((3.42,.24,.24),(0,2.83,z),"wood",bevel=.052)
        for x in (-1.57,1.57):
            m.box((.25,2.64,.26),(x,1.57,z),"wood",bevel=.055)
    for x in (-1.65,1.65):
        m.box((.23,.23,2.78),(x,2.83,0),"wood",bevel=.05)
        side=env.Model()
        cartoon_window(side,0,1.77,0)
        m.absorb(side,(x,0,0),math.copysign(math.pi*.5,x))
    for x in (-1.09,1.09):
        cartoon_window(m,x,1.85,1.43)
    # Projecting entry gives a large, readable door below a broad little canopy.
    m.box((1.54,2.20,.56),(0,1.35,1.53),"plaster",bevel=.08)
    cartoon_gate(m,1.15,2.00,(0,.29,1.87))
    chunky_roof(m,1.94,1.02,2.49,2.81,center=(0,1.81))
    chunky_roof(m,3.97,3.45,2.97,4.15)
    m.box((.65,1.07,.67),(-1.03,3.97,-.36),"stone",bevel=.08)
    m.box((.84,.23,.85),(-1.03,4.44,-.36),"stone_light",bevel=.07)
    m.box((.49,.045,.49),(-1.03,4.57,-.36),"dark",bevel=.05)
    return m


def tower():
    m = env.Model()
    m.cylinder(1.74,.48,(0,.39,0),"mortar",32)
    m.cylinder(1.74,2.62,(0,1.80,0),"mortar",32)
    # Few broad stones with rolled top/bottom edges, rather than fine masonry.
    for row in range(4):
        for side in range(12):
            a = (side + .5*(row%2)) * math.tau/12
            da = math.tau/12*.48
            y0=.45+row*.66
            vertices=[]
            for y,inset in [(y0,.04),(y0+.065,0),(y0+.565,0),(y0+.63,.04)]:
                for r in (1.64+inset,1.83-inset):
                    for angle in np.linspace(a-da+inset*.3,a+da-inset*.3,5):
                        vertices.append([math.sin(angle)*r,y,math.cos(angle)*r])
            stone=tm.convex.convex_hull(np.asarray(vertices))
            m.add(stone,"stone",variation=env.RNG.uniform(-.018,.018))
    m.ring(1.58,1.97,.30,(0,3.16,0),"stone_light",32)
    m.cylinder(1.67,.10,(0,3.20,0),"wood_dark",32)
    for side in range(10):
        a = side*math.tau/10
        # The +Z doorway and the cannon's -Z barrel remain visually open.
        if side in (0,5):
            continue
        m.box((.69,.58,.56),(math.sin(a)*1.69,3.62,math.cos(a)*1.69),"stone_light",rot=(0,a,0),bevel=.12)
    cartoon_gate(m,1.15,1.95,(0,.30,1.84))
    for yaw in (math.pi/2,-math.pi/2,math.pi):
        slit=env.Model()
        slit.box((.23,.73,.08),(0,2.14,0),"dark",bevel=.035)
        slit.box((.52,.15,.23),(0,1.72,.035),"stone_light",bevel=.04)
        m.absorb(slit,(math.sin(yaw)*1.83,0,math.cos(yaw)*1.83),yaw)
    m.cylinder(1.0,.12,(0,3.35,0),"iron",32)
    m.ring(.89,1.025,.055,(0,3.43,0),"gold",32)
    return m


def smithy():
    m=env.Model()
    m.box((3.50,.27,3.10),(0,.44,0),"stone",bevel=.085)
    m.box((3.26,2.1,.27),(0,1.60,-1.39),"plaster",bevel=.075)
    for sign in (-1,1):
        m.box((.27,2.10,2.80),(sign*1.56,1.60,0),"plaster",bevel=.075)
        for z in (-1.41,1.34):
            m.box((.29,2.24,.29),(sign*1.57,1.61,z),"wood",bevel=.065)
        m.box((.29,.27,3.04),(sign*1.57,2.62,-.02),"wood",bevel=.065)
    m.box((3.42,.29,.29),(0,2.61,1.34),"wood_dark",bevel=.065)
    for sign in (-1,1):
        m.beam((sign*1.55,1.87,1.35),(sign*.97,2.59,1.35),.24,"wood_light")
    chunky_roof(m,3.92,3.36,2.76,3.87,slate=True)
    # A genuine open hearth: two side piers and an arch, with a recessed back.
    for x in (-1.37,-.32):
        env.stone_rows(m,.33,1.30,.76,(x,.59,.12),rows=2,block=.35)
    m.box((.94,1.13,.12),(-.845,1.14,-.28),"dark",bevel=.014)
    m.box((1.40,.26,.96),(-.845,.60,.12),"stone_light",bevel=.04)
    for i in range(9):
        coal=tm.creation.icosphere(subdivisions=1,radius=.105)
        m.add(coal,"dark",(-1.16+(i%3)*.28,.79+(i//3)*.045,.23+(i//3)*.16),scale=(1.1,.7,1.0))
    for i in range(5):
        a1=i*math.pi/5+.015
        a2=(i+1)*math.pi/5-.015
        points=[(-.845+math.cos(a)*r,1.53+math.sin(a)*r)
                for r,a in ((.43,a1),(.65,a1),(.65,a2),(.43,a2))]
        arch=tm.convex.convex_hull(np.asarray([[x,y,z] for z in (.40,.69) for x,y in points]))
        m.add(arch,"stone_light",variation=env.RNG.uniform(-.08,.03))
    m.box((1.17,2.77,.97),(-.845,3.26,.0),"mortar",bevel=.06)
    for row in range(5):
        y=2.03+row*.52
        for face in (0,math.pi/2,math.pi,-math.pi/2):
            wall=env.Model()
            env.stone_rows(wall,1.14,.49,.14,(0,y,.51),rows=1,block=.65)
            m.absorb(wall,(-.845,0,0),face)
    m.box((1.40,.22,1.22),(-.845,4.80,0),"stone_light",bevel=.065)
    m.box((.89,.05,.71),(-.845,4.93,0),"dark",bevel=.025)
    # Forged anvil on a bound timber block, with actual tapered horn.
    m.cylinder(.34,.65,(.72,.83,1.13),"wood",12)
    for y in (.58,1.03):
        m.ring(.326,.354,.07,(.72,y,1.13),"iron",16)
    m.box((.63,.12,.42),(.72,1.18,1.13),"iron",bevel=.035)
    m.box((.29,.32,.27),(.72,1.39,1.13),"iron",bevel=.04)
    m.box((.83,.18,.38),(.72,1.64,1.13),"iron_light",bevel=.045)
    m.cone(.14,0,.52,(1.37,1.65,1.13),"iron_light",12,rot=(0,0,-math.pi/2))
    m.box((.07,.45,.07),(1.38,.73,-.55),"wood_light",rot=(0,0,.18),bevel=.01)
    m.box((.31,.13,.14),(1.38,.97,-.55),"iron",rot=(0,0,.18),bevel=.018)
    return m


def bellows():
    m=env.Model()
    for i in range(5):
        m.cone(.24-i*.024,.23-i*.024,.09,(0,i*.073,0),"canvas",12)
        m.ring(.216-i*.024,.245-i*.024,.034,(0,i*.073,0),"wood_dark",12)
    m.box((.54,.07,.46),(0,.39,0),"wood_light",bevel=.025)
    m.box((.08,.09,.63),(0,.43,.35),"wood",bevel=.015)
    return m


if __name__ == "__main__":
    for name,model in [("foundation",foundation()),("house",residence()),("tower",tower()),("smithy",smithy()),("bellows",bellows())]:
        if name in ("house","tower","smithy"):
            for pieces in model.parts.values():
                for piece in pieces:
                    piece.apply_translation((0,-.28,0))
                    piece.apply_scale(BODY_SCALE)
        elif name == "bellows":
            for pieces in model.parts.values():
                for piece in pieces:
                    piece.apply_scale(BODY_SCALE)
        model.save(name,wrapper=False)
        print("WAR_ARCHITECTURE",name,"triangles=",sum(len(piece.faces) for pieces in model.parts.values() for piece in pieces))
