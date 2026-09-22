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
env.C.update({
    "stone": (149, 145, 127), "stone_light": (187, 181, 158),
    "plaster": (214, 202, 177), "mortar": (84, 83, 76),
    "wood": (103, 71, 45), "wood_light": (149, 110, 69),
    "wood_dark": (64, 45, 32), "iron": (56, 66, 66),
    "iron_light": (127, 139, 135), "gold": (163, 122, 62),
    "slate": (53, 61, 65), "slate_light": (72, 82, 85),
    "terracotta": (135, 67, 44), "terracotta_light": (166, 86, 54),
    "dark": (27, 25, 23), "canvas": (134, 100, 67),
})


def foundation():
    m = env.Model()
    m.cylinder(2.56, .20, (0, .1, 0), "mortar", 48)
    m.cylinder(2.43, .10, (0, .23, 0), "stone", 48)
    for i in range(24):
        a = i * math.tau / 24
        m.box((.58, .19, .28), (math.sin(a)*2.42, .14, math.cos(a)*2.42), "stone_light", rot=(0,a,0), bevel=.035, variation=env.RNG.uniform(-.11,.05))
    for x in range(-3, 4):
        for z in range(-3, 4):
            xx, zz = x * .59, z * .59
            if xx*xx + zz*zz < 4.3:
                m.box((.565,.055,.565),(xx,.292,zz),"stone",bevel=.024,variation=env.RNG.uniform(-.10,.10))
    for i in range(3):
        m.box((1.52,.10,.37),(0,.08+i*.065,2.78-i*.31),"stone_light",bevel=.035)
    m.cylinder(.065,4.55,(-2.05,2.45,.35),"wood_dark",12)
    m.cylinder(.105,.16,(-2.05,.46,.35),"iron",12)
    m.cone(.11,0,.28,(-2.05,4.85,.35),"gold",8)
    for y in (3.93,4.76):
        m.ring(.063,.082,.06,(-2.05,y,.35),"iron",12)
    return m


def residence():
    m = env.Model()
    # The existing refined house supplies true roof slopes, individual tiles,
    # arched timber gate, iron hinges, shutters and stone/wood joinery.
    m.absorb(env.house(), pos=(0,.30,0), scale=(.70,.70,.70))
    for x in (-.62,.62):
        m.box((.12,1.55,.12),(x,1.04,1.95),"wood_dark",bevel=.016)
        m.box((.25,.16,.25),(x,.36,1.95),"stone_light",bevel=.025)
    env.tiled_roof(m,1.72,1.0,1.89,2.21,center=(0,1.85))
    # A small woodpile and bound water cask ground the house without widening it.
    for y,z in ((.46,-.3),(.46,.0),(.71,-.15)):
        m.cylinder(.13,.88,(1.90,y,z),"wood",10,rot=(math.pi/2,0,0))
        m.cylinder(.12,.016,(1.90,y,z+.45),"wood_light",10,rot=(math.pi/2,0,0))
    return m


def tower():
    m = env.Model()
    m.cylinder(1.92,.24,(0,.41,0),"stone_light",24)
    m.cylinder(1.74,2.62,(0,1.80,0),"mortar",32)
    # Staggered wedge masonry courses give a continuous round silhouette.
    for row in range(7):
        for side in range(18):
            a = (side + .5*(row%2)) * math.tau/18
            da = math.tau/18*.48
            y0=.52+row*.365
            vertices = [[math.sin(angle)*r,y,math.cos(angle)*r]
                        for y in (y0,y0+.341) for r in (1.64,1.82)
                        for angle in (a-da,a+da)]
            stone=tm.convex.convex_hull(np.asarray(vertices))
            m.add(stone,"stone_light" if (side+row)%5==0 else "stone",variation=env.RNG.uniform(-.065,.065))
    m.ring(1.68,1.96,.22,(0,3.14,0),"stone_light",32)
    m.ring(1.68,1.90,.09,(0,3.29,0),"mortar",32)
    m.cylinder(1.67,.10,(0,3.20,0),"wood_dark",32)
    for side in range(12):
        a = side*math.tau/12
        # The +Z doorway and the cannon's -Z barrel remain visually open.
        if side in (0,6):
            continue
        m.box((.52,.46,.40),(math.sin(a)*1.72,3.56,math.cos(a)*1.72),"stone",rot=(0,a,0),bevel=.05)
        m.box((.59,.10,.46),(math.sin(a)*1.72,3.82,math.cos(a)*1.72),"stone_light",rot=(0,a,0),bevel=.027)
    env.arched_gate(m,.92,1.77,.22,(0,.33,1.84))
    for yaw in (math.pi/2,-math.pi/2,math.pi):
        slit=env.Model()
        slit.box((.15,.68,.035),(0,2.21,0),"dark",bevel=.015)
        slit.box((.42,.09,.15),(0,1.82,.035),"stone_light",bevel=.02)
        m.absorb(slit,(math.sin(yaw)*1.83,0,math.cos(yaw)*1.83),yaw)
    m.cylinder(1.0,.12,(0,3.35,0),"iron",32)
    m.ring(.89,1.025,.055,(0,3.43,0),"gold",32)
    return m


def smithy():
    m=env.Model()
    m.box((3.50,.27,3.10),(0,.44,0),"stone",bevel=.085)
    m.box((3.26,2.1,.22),(0,1.60,-1.39),"plaster",bevel=.035)
    for sign in (-1,1):
        m.box((.20,2.10,2.80),(sign*1.56,1.60,0),"plaster",bevel=.028)
        for z in (-1.41,1.34):
            m.box((.20,2.18,.20),(sign*1.57,1.61,z),"wood_dark",bevel=.022)
        m.box((.22,.20,3.04),(sign*1.57,2.62,-.02),"wood",bevel=.024)
    m.box((3.42,.24,.23),(0,2.61,1.34),"wood_dark",bevel=.028)
    for sign in (-1,1):
        m.beam((sign*1.55,1.87,1.35),(sign*.97,2.59,1.35),.15,"wood_light")
    env.tiled_roof(m,3.92,3.36,2.70,3.85,blue=True)
    # A genuine open hearth: two side piers and an arch, with a recessed back.
    for x in (-1.37,-.32):
        env.stone_rows(m,.30,1.30,.76,(x,.59,.12),rows=4,block=.35)
    m.box((.94,1.13,.12),(-.845,1.14,-.28),"dark",bevel=.014)
    m.box((1.40,.26,.96),(-.845,.60,.12),"stone_light",bevel=.04)
    for i in range(9):
        coal=tm.creation.icosphere(subdivisions=1,radius=.105)
        m.add(coal,"dark",(-1.16+(i%3)*.28,.79+(i//3)*.045,.23+(i//3)*.16),scale=(1.1,.7,1.0))
    for i in range(9):
        a1=i*math.pi/9+.015
        a2=(i+1)*math.pi/9-.015
        points=[(-.845+math.cos(a)*r,1.53+math.sin(a)*r)
                for r,a in ((.43,a1),(.65,a1),(.65,a2),(.43,a2))]
        arch=tm.convex.convex_hull(np.asarray([[x,y,z] for z in (.40,.69) for x,y in points]))
        m.add(arch,"stone_light",variation=env.RNG.uniform(-.08,.03))
    m.box((1.17,2.77,.97),(-.845,3.26,.0),"mortar",bevel=.06)
    for row in range(9):
        y=2.03+row*.29
        for face in (0,math.pi/2,math.pi,-math.pi/2):
            wall=env.Model()
            env.stone_rows(wall,1.14,.265,.10,(0,y,.51),rows=1,block=.48)
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
        model.save(name,wrapper=False)
        print("WAR_ARCHITECTURE",name,"triangles=",sum(len(piece.faces) for pieces in model.parts.values() for piece in pieces))
