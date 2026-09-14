"""Author the three forest dioramas as editable, native Godot resources.

This is an OFFLINE modelling tool, never a game-time scene generator. All colour
is on real mesh vertices; no raster images or generated textures are involved.
Run with Python 3, optionally --godot PATH. Geometry is saved by Godot's native
ArrayMesh / ResourceSaver APIs. Understory uses native MultiMesh resources.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import re
import subprocess
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/environment/rogue_forest"
SCENES = ROOT / "scenes/rogue"
LOCAL = ROOT / ".local/rogue_forest"
TAU = math.tau
PALETTE = {
    "bark": (.36, .27, .19), "cut": (.72, .59, .39),
    "birch": (.83, .82, .67), "stripe": (.32, .35, .31),
    "oak": (.40, .57, .29), "oak_light": (.54, .66, .35),
    "birch_leaf": (.63, .69, .36), "pine": (.24, .44, .33),
    "pine_light": (.34, .54, .39), "grass": (.48, .61, .34),
    "fern": (.31, .51, .33), "stone": (.53, .57, .48),
    "moss": (.46, .59, .32), "wood": (.51, .39, .25),
    "flower": (.86, .77, .48), "lavender": (.68, .62, .76),
    "canvas": (.80, .73, .52), "rope": (.60, .49, .31),
}
MESHES = {}
MULTIMESHES = {}


def write(path: Path, value: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text(encoding="utf-8") == value:
        return
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(value, encoding="utf-8")
    temporary.replace(path)


def vec(a):
    return "Vector3(" + ", ".join(f"{v:.4f}" for v in a) + ")"


def add(a, b): return tuple(x+y for x, y in zip(a, b))
def sub(a, b): return tuple(x-y for x, y in zip(a, b))
def mul(a, s): return tuple(x*s for x in a)
def dot(a, b): return sum(x*y for x, y in zip(a, b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def unit(a): return mul(a, 1/max(math.sqrt(dot(a, a)), .00001))
def mix(a, b, t): return tuple(x+(y-x)*t for x, y in zip(a, b))
def clamp(v, lo=0., hi=1.): return max(lo, min(hi, v))
def smooth(a, b, x):
    t = clamp((x-a)/(b-a))
    return t*t*(3-2*t)


class Mesh:
    def __init__(self, name):
        self.name = name
        self.v, self.n, self.c, self.uv = [], [], [], []

    def tri(self, a, b, c, colour, outward=(0, 1, 0), colours=None, normal=None):
        n = unit(cross(sub(c, a), sub(b, a)))  # Godot clockwise front faces.
        if dot(n, outward) < 0:
            b, c = c, b
            n = mul(n, -1)
            if colours:
                colours = (colours[0], colours[2], colours[1])
        for index, p in enumerate((a, b, c)):
            self.v.extend(round(x, 5) for x in p)
            self.n.extend(round(x, 5) for x in (normal or n))
            self.c.extend((*[round(x, 5) for x in (colours[index] if colours else colour)], 1))
            self.uv.extend((round(p[0]/6,5),round(p[2]/6,5)))

    def ball(self, p, scale, colour, seed=0, rings=5, sides=9):
        rng = random.Random(seed)
        colour = PALETTE.get(colour, colour)
        rows = []
        for j in range(rings+1):
            phi = math.pi*j/rings
            rows.append([add(p, (scale[0]*math.sin(phi)*math.cos(TAU*i/sides)*(.94+rng.random()*.12),
                                 scale[1]*math.cos(phi),
                                 scale[2]*math.sin(phi)*math.sin(TAU*i/sides)*(.94+rng.random()*.12))) for i in range(sides)])
        for j in range(rings):
            for i in range(sides):
                a, b, c, d = rows[j][i], rows[j][(i+1)%sides], rows[j+1][(i+1)%sides], rows[j+1][i]
                shade = .94+rng.random()*.13
                tint = mul(colour, shade)
                self.tri(a, b, c, tint, sub(mul(add(add(a,b),c),1/3),p))
                self.tri(a, c, d, tint, sub(mul(add(add(a,c),d),1/3),p))

    def beam(self, a, b, radius, top, colour, sides=7):
        colour = PALETTE.get(colour, colour)
        axis = unit(sub(b,a))
        u = unit(cross(axis, (0,0,1) if abs(axis[2]) < .9 else (1,0,0)))
        v = cross(axis,u)
        ring = lambda center,r: [add(center, add(mul(u,r*math.cos(TAU*i/sides)),mul(v,r*math.sin(TAU*i/sides)))) for i in range(sides)]
        low, high = ring(a,radius), ring(b,top)
        for i in range(sides):
            j=(i+1)%sides
            radial=sub(low[i],a)
            tint=mul(colour,.94+(i%3)*.045)
            self.tri(low[i],high[i],high[j],tint,radial)
            self.tri(low[i],high[j],low[j],tint,radial)
            self.tri(a,low[j],low[i],colour,mul(axis,-1))
            self.tri(b,high[i],high[j],colour,axis)

    def box(self, center, size, colour):
        colour = PALETTE.get(colour, colour)
        vertices=[add(center,(x*size[0]/2,y*size[1]/2,z*size[2]/2)) for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for face in [(0,1,2,3),(5,4,7,6),(4,0,3,7),(1,5,6,2),(3,2,6,7),(4,5,1,0)]:
            a,b,c,d=[vertices[i] for i in face]
            outward=sub(mul(add(add(a,b),c),1/3),center)
            self.tri(a,b,c,colour,outward)
            self.tri(a,c,d,colour,outward)

    def save(self):
        MESHES[self.name] = {"vertices":self.v,"normals":self.n,"colors":self.c,"uv":self.uv}
        write(OUT/f"{self.name}.tscn", f'''[gd_scene format=3]
[ext_resource type="ArrayMesh" path="res://assets/models/environment/rogue_forest/{self.name}.res" id="mesh"]
[node name="{self.name.title().replace('_','')}" type="Node3D"]
[node name="SculptedMesh" type="MeshInstance3D" parent="."]
mesh = ExtResource("mesh")
''')


def build_models():
    for kind in ["oak", "birch", "pine", "aspen"]:
        m=Mesh("tree_"+kind)
        height={"oak":4.8,"birch":5.9,"pine":6.4,"aspen":5.1}[kind]
        radius=.27 if kind in ["birch","aspen"] else .40
        trunk="birch" if kind=="birch" else "bark"
        m.beam((0,0,0),(.12,height*.73,-.06),radius,radius*.44,trunk)
        for i in range(5):
            a=i*TAU/5
            m.beam((0,.35,0),(math.cos(a)*.9,.05,math.sin(a)*.9),radius*.48,.045,trunk)
        if kind=="pine":
            for layer in range(5):
                y=1.75+layer*.78
                r=2.05-layer*.31
                # Sculpted, uneven skirts, with a lifted tip instead of identical cones.
                for i in range(10):
                    angle=i*TAU/10
                    a=(math.cos(angle)*r,y+(.12 if i%2 else 0),math.sin(angle)*r)
                    b=(math.cos(angle+TAU/10)*r,y+(.12 if not i%2 else 0),math.sin(angle+TAU/10)*r)
                    tip=(.06,y+1.75,0)
                    m.tri(a,b,tip,PALETTE["pine_light" if (i+layer)%4==0 else "pine"],(math.cos(angle),.4,math.sin(angle)))
                    m.tri((0,y-.12,0),b,a,mul(PALETTE["pine"],.87),(0,-1,0))
        else:
            leaf={"oak":"oak","birch":"birch_leaf","aspen":"oak_light"}[kind]
            width=1.65 if kind=="oak" else 1.2
            for i,(x,y,z,s) in enumerate([(-.95,height*.65,.12,.89),(.8,height*.75,.14,.87),(.1,height*.89,-.25,1.0),(0,height*.70,-.82,.76)]):
                m.beam((0,height*.37,0),(x,y,z),.12,.035,trunk)
                m.ball((x,y,z),(width*s,1.35*s,width*.85*s),leaf,seed=i+len(kind))
            if kind=="birch":
                for i in range(8):
                    y=.45+i*.39
                    m.beam((.02,y,0),(.025,y+.065+(i%2)*.035,0),radius*(1-y/height*.4)+.012,radius*(1-y/height*.4)+.012,"stripe",sides=6)
        m.save()
    m=Mesh("bush")
    for i,(x,z,s) in enumerate([(-.42,0,.75),(.32,.1,.85),(0,-.35,.75)]):
        m.ball((x,.38,z),(s,.62,s*.8),"oak",i,rings=4,sides=7)
    m.save()
    m=Mesh("camp_supplies")
    for x,z,s in [(-.55,.12,.70),(.19,.22,.52),(-.4,-.48,.46)]:
        m.box((x,s*.5,z),(s,s,s*.80),"wood")
        for y in [s*.15,s*.83]:
            m.box((x,y,z+s*.41),(s*.95,.055,.025),"cut")
        for side in [-1,1]:
            m.box((x+side*s*.37,s*.5,z+s*.415),(.055,s*.92,.03),"cut")
    for i in range(3):
        m.ball((.72+i*.22,.25,-.26),( .23,.29,.20),"canvas",i,4,7)
        m.beam((.72+i*.22,.43,-.26),(.72+i*.22,.55,-.26),.075,.025,"rope",6)
    m.beam((-.25,.19,1.0),(.6,.19,1.0),.18,.18,(.42,.53,.45),9)
    for x in [-.10,.43]: m.beam((x,.195,1.0),(x+.055,.195,1.0),.19,.19,"rope",9)
    m.save()
    m=Mesh("fire_circle")
    for i in range(10):
        a=i*TAU/10
        m.ball((math.cos(a)*.9,.16,math.sin(a)*.9),(.24,.20,.18),"stone",i,3,6)
    m.beam((-.53,.12,-.28),(.51,.12,.29),.12,.10,"bark",6)
    m.beam((-.48,.27,.32),(.41,.27,-.36),.11,.09,"bark",6)
    for i in range(4):
        a=i*TAU/4
        m.beam((math.cos(a)*.21,.23,math.sin(a)*.21),(0,.88+(i%2)*.22,0),.18,0,(.92,.53,.22),5)
    m.save()
    m=Mesh("mushrooms")
    for i,(x,z,h) in enumerate([(-.35,0,.45),(.25,.1,.64),(0,-.27,.28)]):
        m.beam((x,0,z),(x,h,z),.06,.055,"birch",6)
        m.ball((x,h,z),(.24,.13,.23),(.77,.43,.27),i,3,8)
        for j in range(3):
            a=j*TAU/3
            m.ball((x+math.cos(a)*.10,h+.11,z+math.sin(a)*.10),(.04,.013,.034),"birch",j,2,5)
    m.save()
    m=Mesh("root_arch")
    arch=[(-3.1,.25,0),(-2.35,1.4,.12),(-1.25,2.3,.2),(.1,2.6,.15),(1.5,2.0,.1),(2.9,.4,0)]
    for a,b in zip(arch,arch[1:]):
        m.beam(a,b,.38,.31,"bark",8)
        mid=mul(add(a,b),.5)
        m.ball(add(mid,(0,.18,0)),(.58,.20,.33),"moss",4,3,7)
    for x in [-3.1,2.9]:
        m.beam((x,.4,0),(x+.7,.03,.8),.17,.04,"bark",6)
        m.beam((x,.4,0),(x-.6,.02,-.8),.17,.04,"bark",6)
    m.save()
    for kind in ["grass","fern","flowers","leaf_litter"]:
        m=Mesh(kind)
        rng=random.Random(len(kind)*23)
        for i in range(11 if kind=="grass" else 7):
            a=rng.random()*TAU
            dx,dz=math.cos(a),math.sin(a)
            r=rng.uniform(.05,.35)
            x,z=dx*r,dz*r
            if kind=="grass":
                h=rng.uniform(.25,.65)
                m.tri((x-dz*.055,0,z+dx*.055),(x+dz*.055,0,z-dx*.055),(x+dx*.22,h,z+dz*.22),mul(PALETTE["grass"],rng.uniform(.85,1.1)),(dx,0,dz))
                m.tri((x+dz*.055,0,z-dx*.055),(x-dz*.055,0,z+dx*.055),(x+dx*.22,h,z+dz*.22),mul(PALETTE["grass"],rng.uniform(.85,1.1)),(-dx,0,-dz))
            elif kind=="fern":
                end=(dx*.87,.38+(.12 if i%2 else 0),dz*.87)
                m.beam((0,.05,0),end,.018,.009,"fern",sides=4)
                for j in range(1,5):
                    t=j/5
                    p=mul(end,t)
                    length=.24*(1-t*.65)
                    for sign in [-1,1]:
                        q=add(p,(sign*dz*length,.02,-sign*dx*length))
                        m.tri(add(p,(-dx*.09,0,-dz*.09)),q,add(p,(dx*.12,.04,dz*.12)),PALETTE["fern"])
            elif kind=="flowers":
                p=(x,rng.uniform(.25,.56),z)
                m.beam((x,0,z),p,.016,.008,"fern",4)
                for j in range(5):
                    angle=j*TAU/5
                    m.ball(add(p,(math.cos(angle)*.085,0,math.sin(angle)*.085)),(.085,.035,.07),"flower" if i%2 else "lavender",j,2,5)
                m.ball(add(p,(0,.024,0)),(.045,.03,.045),"cut",i,2,5)
            else:
                m.tri((x-.13,.025,z),(x,.034,z-.07),(x+.19,.026,z+.07),(.62+rng.random()*.10,.50+rng.random()*.06,.29))
        m.save()
    for kind in ["moss_rock","pebbles"]:
        m=Mesh(kind)
        rng=random.Random(733)
        for i in range(3 if kind=="moss_rock" else 5):
            s=(1.2 if kind=="moss_rock" else .19)*rng.uniform(.7,1.1)
            x,z=(i-1)*s*.83,rng.uniform(-.2,.2)
            m.ball((x,s*.42,z),(s,s*.68,s*.75),"stone",i,3,7)
            if kind=="moss_rock":
                m.ball((x-.16,s*.86,z),(.72*s,.17*s,.54*s),"moss",i,3,7)
        m.save()
    m=Mesh("stump")
    m.beam((0,0,0),(0,.63,0),.53,.45,"bark",9)
    m.beam((0,.63,0),(0,.66,0),.40,.39,"cut",9)
    m.beam((0,.665,0),(0,.675,0),.17,.17,"wood",9)
    for i in range(5):
        a=TAU*i/5
        m.beam((0,.35,0),(.77*math.cos(a),.03,.77*math.sin(a)),.19,.045,"bark")
    m.save()
    m=Mesh("fallen_log")
    m.beam((-1.6,.33,0),(1.6,.37,.16),.37,.31,"bark",9)
    m.beam((1.61,.37,.16),(1.63,.37,.16),.27,.27,"cut",9)
    m.beam((-.8,.4,.0),(-.9,1.03,.4),.13,.055,"bark")
    m.ball((-.4,.60,.01),(1.05,.12,.27),"moss",5,3,8)
    m.save()
    m=Mesh("split_fence")
    for x in [-1.5,1.5]:
        m.beam((x,0,0),(x,1.28,0),.12,.105,"wood",5)
    for y in [.46,.97]: m.beam((-1.65,y,0),(1.65,y+.08,0),.09,.09,"cut",4)
    m.save()
    m=Mesh("waystone")
    m.ball((0,.3,0),(1.25,.48,.9),"stone",2,3,7)
    m.box((0,1.23,0),(.65,1.7,.38),"stone")
    m.box((0,1.52,.20),(.34,.085,.02),"cut")
    m.box((0,1.33,.20),(.34,.085,.02),"cut")
    m.ball((.2,.57,.12),(.52,.14,.43),"moss",3,3,7)
    m.save()
    m=Mesh("canvas_tent")
    for z in [-1.35,1.35]:
        m.beam((0,0,z),(0,1.75,z),.06,.05,"wood")
    m.beam((0,1.75,-1.48),(0,1.75,1.48),.055,.055,"cut")
    for sign in [-1,1]:
        a,b,c,d=(0,1.72,-1.35),(0,1.72,1.35),(sign*1.38,.15,1.35),(sign*1.38,.15,-1.35)
        m.tri(a,b,c,PALETTE["canvas"],(sign,1,0)); m.tri(a,c,d,PALETTE["canvas"],(sign,1,0))
    m.tri((-1.36,.15,1.35),(0,1.72,1.35),(-.18,.1,1.35),mul(PALETTE["canvas"],.9),(0,0,1))
    m.tri((1.36,.15,1.35),(.18,.1,1.35),(0,1.72,1.35),mul(PALETTE["canvas"],.9),(0,0,1))
    for x in [-1.9,1.9]:
        for z in [-1.55,1.55]:
            m.beam((x,0,z),(x,.3,z),.035,.035,"wood",4)
            m.beam((x,.18,z),(x*.65,1.0,z*.75),.012,.012,"rope",3)
    m.save()


def segment_distance(x,z,a,b):
    dx,dz=b[0]-a[0],b[1]-a[1]
    t=clamp(((x-a[0])*dx+(z-a[1])*dz)/max(dx*dx+dz*dz,.0001))
    return math.hypot(x-a[0]-dx*t,z-a[1]-dz*t)


def route_graph():
    text=(ROOT/"data/rogue/first_floor.tres").read_text(encoding="utf-8")
    coords=[float(v.strip()) for v in re.search(r"coordinates = PackedVector2Array\(([^)]+)\)",text).group(1).split(",")]
    points=[((coords[i]-3.5)*9,(coords[i+1]-2)*10) for i in range(0,len(coords),2)]
    values=[int(v.strip()) for v in re.search(r"edges = PackedInt32Array\(([^)]+)\)",text).group(1).split(",")]
    return points,[(points[values[i]],points[values[i+1]]) for i in range(0,len(values),2)]


def composition(kind):
    if kind=="exploration":
        points,edges=route_graph()
        return {"width":100,"depth":72,"roads":[([a,b],.75) for a,b in edges],"clearings":[(x,z,2.35) for x,z in points]+[(-5,29,4.6)],"nodes":points}
    if kind=="outpost":
        # The middle artery, the two flanking lanes, and small camp approaches.
        roads=[([(-55,0),(-40,-.2),(-27,1.1),(-14,-1.1),(0,0),(14,0),(28,1.0),(43,0),(53,0)],3.1),
               ([(-30,-1),(-23,-9),(-19,-20),(-9,-24),(6,-25),(20,-22),(35,-23),(45,-16),(45,0)],2.6),
               ([(-30,1),(-23,9),(-19,20),(-9,24),(6,25),(20,22),(35,23),(45,16),(45,0)],2.6),
               ([(9,-24),(9,24)],2.3)]
        return {"width":112,"depth":64,"roads":roads,"clearings":[(-43,0,13.5),(11,-20,6.5),(11,20,6.5),(42,0,7)],"nodes":[]}
    return {"width":80,"depth":80,"roads":[([(-40,0),(-27,-.8),(-17,1),(0,0),(17,-1),(27,.8),(40,0)],3.7), ([(0,-40),(.8,-27),(-1,-17),(0,0),(1,17),(-.8,27),(0,40)],3.7)],"clearings":[(0,0,15)],"nodes":[]}


def distance_to_roads(config,x,z):
    return min(segment_distance(x,z,a,b)-width for points,width in config["roads"] for a,b in zip(points,points[1:]))


def ground_colour(kind,config,x,z):
    # Continuous brush fields, sampled into vertices: the geometry carries paint.
    broad=math.sin(x*.095+z*.063)*math.cos(z*.14-x*.028)
    detail=math.sin(x*1.43+z*.73)*math.cos(z*1.15-x*.67)
    grass=mix((.38,.52,.35),(.57,.66,.41),broad*.5+.5)
    grass=mul(grass,1+detail*.022)
    if kind=="exploration":
        grass=mix(grass,(.32,.49,.41),smooth(0,34,x)*smooth(-5,-25,z)*.43)
    d=distance_to_roads(config,x,z)+.20*math.sin(x*1.7+z*.8)+.13*math.cos(z*2.2)
    clearing=max(1-smooth(r*.65,r+1.5,math.hypot(x-cx,z-cz)) for cx,cz,r in config["clearings"])
    earth=mix((.64,.56,.39),(.76,.67,.48),.5+.5*math.sin(x*.41+z*.37))
    dirt=max(1-smooth(-.6,1.3,d),clearing*(.58 if kind=="exploration" else .72))
    colour=mix(grass,earth,dirt*.88)
    # Wheel tracks follow each road's nearest segment; grass survives at its centre.
    if kind!="exploration":
        track=0.
        for points,width in config["roads"]:
            raw=min(segment_distance(x,z,a,b) for a,b in zip(points,points[1:]))
            track=max(track,1-smooth(.18,.46,abs(raw-min(width*.46,1.35))))
        colour=mix(colour,(.47,.42,.29),track*.34*(.72+.28*math.sin(x*.33+z*.27)))
    return colour


def build_ground(kind,config):
    mesh=Mesh("ground_"+kind)
    width,depth=config["width"],config["depth"]
    base=-.24 if kind=="exploration" else -.035
    def point(x,z):
        return (x,base+.018*math.sin(x*.51)*math.cos(z*.47),z)
    # One-metre terrain quads are independent of (and coincide with) nav source grid.
    for z in range(-depth//2,depth//2):
        for x in range(-width//2,width//2):
            coords=[(x,z),(x+1,z),(x+1,z+1),(x,z+1)]
            points=[point(*p) for p in coords]
            colours=[ground_colour(kind,config,*p) for p in coords]
            for a,b,c in [(0,1,2),(0,2,3)]:
                mesh.tri(points[a],points[b],points[c],None,colours=(colours[a],colours[b],colours[c]),normal=(0,1,0))
    mesh.save()
    if kind=="exploration":
        creek=Mesh("creek_exploration")
        samples=[(-43.5+math.sin(z*.13)*1.8,z) for z in range(-36,37)]
        for i,((x,z),(xx,zz)) in enumerate(zip(samples,samples[1:])):
            for half,color,y in [(2.2,(.50,.58,.39),-.16),(1.5,(.34,.55,.56),-.12),(.87,(.43,.63,.62),-.11)]:
                left=half+.18*math.sin(z*.74)+.11*math.sin(z*1.9)
                right=half+.24*math.sin(z*.49+1)+.12*math.cos(z*1.3)
                next_left=half+.18*math.sin(zz*.74)+.11*math.sin(zz*1.9)
                next_right=half+.24*math.sin(zz*.49+1)+.12*math.cos(zz*1.3)
                a,b,c,d=(x-left,y,z),(x+right,y,z),(xx+next_right,y,zz),(xx-next_left,y,zz)
                creek.tri(a,b,c,color);creek.tri(a,c,d,color)
            if i%4==0:
                creek.tri((x-.7,-.095,z+.3),(x+.4,-.095,z+.45),(x+.8,-.095,z+.52),(.69,.79,.70))
        creek.save()


def add_instance(lines,name,asset,x,z,scale=1.,angle=0.,y=0.,parent="Landmarks"):
    lines.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{asset}")]\nposition = {vec((x,y,z))}\nrotation = {vec((0,angle,0))}\nscale = {vec((scale,)*3)}\n')


def projected_tree_overlaps_routes(config, asset, x, z, scale, angle):
    """Reserve the silhouette on the actual 60-degree exploration camera plane.

    Ground distance alone misses tall crowns south of a node. Use every sculpted
    vertex, including roots/branches, to reserve its projected rectangle instead.
    """
    vertices=MESHES[asset]["vertices"]
    c,s=math.cos(angle)*scale,math.sin(angle)*scale
    xs,zs=[],[]
    for i in range(0,len(vertices),3):
        vx,vy,vz=vertices[i:i+3]
        xs.append(x+c*vx+s*vz)
        zs.append(z-s*vx+c*vz-(vy*scale-.22)/math.sqrt(3))
    lo_x,hi_x,lo_z,hi_z=min(xs),max(xs),min(zs),max(zs)
    def distance(a,b):
        return math.hypot(max(lo_x-a,0,a-hi_x),max(lo_z-b,0,b-hi_z))
    if any(distance(a,b)<2.55 for a,b in config["nodes"]): return True
    for points,width in config["roads"]:
        for a,b in zip(points,points[1:]):
            length=math.hypot(b[0]-a[0],b[1]-a[1])
            for i in range(math.ceil(length)+1):
                t=i/math.ceil(length)
                if distance(a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t)<width+.3: return True
    return False


def build_landscape(kind):
    config=composition(kind)
    width,depth=config["width"],config["depth"]
    rng=random.Random({"exploration":8432,"outpost":301,"siege":303}[kind])
    build_ground(kind,config)
    origin_y=-.22 if kind=="exploration" else 0.
    resources=[]
    assets=["tree_oak","tree_birch","tree_pine","tree_aspen","bush","fern","grass","flowers","leaf_litter","mushrooms","moss_rock","pebbles","stump","fallen_log","split_fence","waystone","canvas_tent","root_arch","camp_supplies","fire_circle"]
    if kind=="exploration": assets.append("creek_exploration")
    for asset in assets:
        resources.append(f'[ext_resource type="PackedScene" path="res://assets/models/environment/rogue_forest/{asset}.tscn" id="{asset}"]')
    resources.append(f'[ext_resource type="ArrayMesh" path="res://assets/models/environment/rogue_forest/ground_{kind}.res" id="ground"]')
    lines=[f'[node name="Forest{kind.title()}" type="Node3D"]\nmetadata/terrain_grid_spacing = 1.0\nmetadata/forest_palette = "sage_birch_pine"\n', '[node name="Ground" type="MeshInstance3D" parent="."]\nmesh = ExtResource("ground")\n', '[node name="Canopy" type="Node3D" parent="."]\n', '[node name="Landmarks" type="Node3D" parent="."]\n', '[node name="Understory" type="Node3D" parent="."]\n']
    if kind=="exploration": add_instance(lines,"Creek","creek_exploration",0,0,y=0)
    # Battlefield physical obstructions and visible props use the same coordinates.
    obstacles=[]
    trees=[]
    buildings=[(-8,-15,3),(-8,15,3),(15,0,3),(36,-16,3),(36,16,3),(9,-20,5),(9,20,5),(42,0,5)] if kind=="outpost" else []
    def protected(x,z,padding=0):
        if kind=="exploration":
            landmarks=[(-5,29,5.7),(38,4,3.9),(18,-30,3.9),(-40,-20,3.9)]
            return any(math.hypot(x-a,z-b)<4.0+padding for a,b in config["nodes"]) or distance_to_roads(config,x,z)<2.4+padding or abs(x-(-43.5+math.sin(z*.13)*1.8))<3.4 or any(math.hypot(x-a,z-b)<r for a,b,r in landmarks)
        if kind=="outpost":
            defenders=[(-1,-14),(-1,14),(18,-8),(18,8),(36,-6),(36,6),(3,-17),(3,17),(29,-12),(29,12),(6,-8),(8,-8),(7,-10),(6,8),(8,8),(7,10),(24,7),(26,7),(28,7),(30,7),(-12,15),(-12,-15)]
            return (-56-padding<x<-29+padding and abs(z)<14+padding) or any(math.hypot(x-a,z-b)<r+2.4+padding for a,b,r in buildings) or distance_to_roads(config,x,z)<2.5+padding or any(math.hypot(x-a,z-b)<2.7+padding for a,b in defenders)
        return (abs(x)<14.6+padding and abs(z)<14.6+padding) or distance_to_roads(config,x,z)<2.6+padding
    # Jittered groves with deliberate openings, not one uniform border of pines.
    for z0 in range(-depth//2+2,depth//2-1,3):
        for x0 in range(-width//2+2,width//2-1,3):
            x,z=x0+rng.uniform(-1.05,1.05),z0+rng.uniform(-1.05,1.05)
            if protected(x,z): continue
            edge=min(width/2-abs(x),depth/2-abs(z))
            density=.82 if edge<7 else (.40 if kind=="exploration" else .44)
            grove=math.sin(x*.22)*math.cos(z*.20)
            if rng.random()>density+(grove*.18): continue
            s=rng.uniform(.72,1.13)
            if any(math.hypot(x-a,z-b)<2.35 for a,b,_,_ in trees): continue
            model="tree_birch" if x<-width*.14 else ("tree_pine" if z<-depth*.08 else "tree_oak")
            if rng.random()<.20: model="tree_aspen"
            angle=rng.random()*TAU
            if kind=="exploration" and projected_tree_overlaps_routes(config,model,x,z,s,angle): continue
            add_instance(lines,f"{model.title().replace('_','')}{len(trees):03}",model,x,z,s,angle,origin_y,"Canopy")
            trees.append((x,z,s,model))
            if kind!="exploration": obstacles.append((x,z,.40*s,"tree"))
    # Landmarks occupy unused pockets; none block the wide road or deployment box.
    landmark_sets={
        "outpost":[("moss_rock",-25,-27,1.45,.4),("moss_rock",-26,27,1.35,2.1),("fallen_log",-21,-15,1.2,1.1),("stump",-18,13,1.1,0),("waystone",-25,6,1.0,.2),("canvas_tent",-48,-18,1.2,0),("canvas_tent",-43,-20,1.0,-.2),("canvas_tent",48,-11,1.0,-.3),("canvas_tent",48,10,1.0,3.0),("moss_rock",23,-14,1.35,.6),("moss_rock",24,14,1.2,1.5),("fallen_log",3,-11,1.0,.9)],
        "siege":[("moss_rock",-21,-21,1.7,.4),("moss_rock",22,22,1.65,1.2),("moss_rock",-25,22,1.3,2.2),("moss_rock",23,-24,1.45,.8),("fallen_log",-17,25,1.4,.7),("fallen_log",26,16,1.2,2.3),("stump",17,-18,1.4,0),("waystone",-7,26,1.1,-.3),("canvas_tent",-16,-11,1.0,1.5),("canvas_tent",16,11,1.0,-1.5)],
        "exploration":[("moss_rock",-40,-20,1.8,.2),("moss_rock",38,4,1.6,2.3),("moss_rock",18,-30,1.7,1.2),("fallen_log",-18,5,1.1,.3),("fallen_log",27,15,1.2,1.4),("waystone",-40,8,1.25,0),("canvas_tent",-5,29,1.15,.4),("stump",-9,-27,1.35,0),("root_arch",-43,-3,1.1,.1)]}
    for i,(asset,x,z,s,angle) in enumerate(landmark_sets[kind]):
        add_instance(lines,f"{asset.title().replace('_','')}{i}",asset,x,z,s,angle,origin_y)
        if kind!="exploration" and asset in ["moss_rock","canvas_tent","fallen_log","waystone"]:
            obstacles.append((x,z,2.0*s if asset in ["moss_rock","canvas_tent"] else 1.7*s,"rock"))
    # Low campsite dressing stays inside existing side pockets, outside movement lanes.
    camp_details={"outpost":[("camp_supplies",-45.4,-18.6,1.25,0),("camp_supplies",50,-12.5,1.05,1.0),("fire_circle",-39.7,-20.5,1.15,0),("fire_circle",49.5,13.3,1.0,0)],
                  "siege":[("camp_supplies",-17.5,-12.3,1.15,.5),("camp_supplies",17.7,12.5,1.0,-.5),("fire_circle",-17,-8.7,1.0,0),("fire_circle",17,8.7,1.0,0)],
                  "exploration":[("camp_supplies",-7.0,28.0,1.25,.3),("camp_supplies",-2.0,30.5,1.05,-.5),("fire_circle",-3.8,25.2,1.3,0),("mushrooms",-39.5,-4,1.5,0),("fern",-40.2,0,1.4,0)]}
    for i,(asset,x,z,s,angle) in enumerate(camp_details[kind]):
        add_instance(lines,f"CampDetail{i}",asset,x,z,s,angle,origin_y)
    fences=[]
    if kind=="outpost":
        fences=[(-49,-15,0),(-45,-15,0),(-40,-17,-.4),(50,-9,math.pi/2),(50,9,math.pi/2),(28,-28,0),(32,-28,0),(28,28,0),(32,28,0)]
    elif kind=="siege": fences=[(-11,-15,0),(-7,-15,0),(7,15,0),(11,15,0),(-15,7,math.pi/2),(15,-7,math.pi/2)]
    else: fences=[(-9,28,0),(-13,28,0),(-40,13,.2)]
    for i,(x,z,angle) in enumerate(fences):
        add_instance(lines,f"SplitFence{i}","split_fence",x,z,1,angle,origin_y)
        if kind!="exploration":
            for d in [-1.1,0,1.1]: obstacles.append((x+math.cos(angle)*d,z-math.sin(angle)*d,.23,"fence"))
    # Keep the broad staging squares entirely free of undergrowth and tall props.
    batches=defaultdict(list)
    for _ in range(int(width*depth*.22)):
        x,z=rng.uniform(-width/2+1,width/2-1),rng.uniform(-depth/2+1,depth/2-1)
        road=distance_to_roads(config,x,z)
        if kind=="exploration" and any(math.hypot(x-a,z-b)<2.6 for a,b in config["nodes"]): continue
        if kind=="outpost" and -55<x<-31 and abs(z)<12: continue
        if kind=="siege" and abs(x)<12.5 and abs(z)<12.5: continue
        if any(math.hypot(x-a,z-b)<r+1.0 for a,b,r in buildings): continue
        if road<-.5:
            if rng.random()>.14: continue
            asset="pebbles"
        elif road<2:
            asset=rng.choices(["grass","flowers","pebbles","leaf_litter"],[4,1,2,2])[0]
        else:
            asset=rng.choices(["grass","fern","bush","flowers","leaf_litter","mushrooms"],[6,2,1,1,3,1])[0]
        if kind=="exploration" and abs(x-(-43.5+math.sin(z*.13)*1.8))<2: continue
        scale=rng.uniform(.65,1.15)
        if kind=="exploration": scale*=.85
        batches[asset].append([x,origin_y,z,scale,rng.random()*TAU])
    for asset,transforms in sorted(batches.items()):
        key=f"{kind}_{asset}"
        MULTIMESHES[key]={"mesh":asset,"transforms":transforms}
        resources.append(f'[ext_resource type="MultiMesh" path="res://assets/models/environment/rogue_forest/{key}.tres" id="batch_{asset}"]')
        lines.append(f'[node name="{asset.title().replace("_", "")}" type="MultiMeshInstance3D" parent="Understory"]\nmultimesh = ExtResource("batch_{asset}")\ncast_shadow = {0 if asset in ["grass","flowers","leaf_litter","pebbles"] else 1}\n')
    write(SCENES/f"forest_{kind}.tscn","[gd_scene format=3]\n"+"\n".join(resources)+"\n"+"\n".join(lines))
    return {"trees":len(trees),"understory":sum(map(len,batches.values())),"obstacles":obstacles,"config":config}


def navigation(kind,width,depth,obstacles):
    vertices,polygons,lookup=[],[],{}
    for z in range(-depth//2+2,depth//2-2):
        for x in range(-width//2 if kind=="outpost" else -width//2+2,width//2-2):
            if any((x+.5-ox)**2+(z+.5-oz)**2 < (radius+1.15)**2 for ox,oz,radius,_ in obstacles): continue
            indices=[]
            for corner in [(x,z),(x,z+1),(x+1,z+1),(x+1,z)]:
                if corner not in lookup:
                    lookup[corner]=len(vertices)
                    vertices.append((corner[0],0,corner[1]))
                indices.append(lookup[corner])
            polygons.append(indices)
    text='[gd_resource type="NavigationMesh" format=3]\n\n[resource]\n'
    text+='vertices = PackedVector3Array('+', '.join(str(v) for p in vertices for v in p)+')\n'
    text+='polygons = Array[PackedInt32Array](['+', '.join('PackedInt32Array('+', '.join(map(str,p))+')' for p in polygons)+'])\n'
    text+='agent_radius = 1.15\ncell_size = 1.0\ncell_height = 0.2\n'
    write(SCENES/f"battle_{kind}_navigation.tres",text)
    return len(polygons)


def integrate_battle(kind,summary):
    path=SCENES/f"battle_{kind}_map.tscn"
    text=path.read_text(encoding="utf-8")
    # Preserve all scenario markers byte-for-byte. Only replace Environment children.
    _,nodes=text.split('[node name=',1)
    width,depth=summary["config"]["width"],summary["config"]["depth"]
    resources=f'''[gd_scene format=3]
[ext_resource type="NavigationMesh" path="res://scenes/rogue/battle_{kind}_navigation.tres" id="nav"]
[ext_resource type="PackedScene" path="res://scenes/rogue/forest_{kind}.tscn" id="forest"]
[sub_resource type="BoxShape3D" id="floor"]
size = Vector3({width}, 1, {depth})
'''
    for i,(_x,_z,r,_asset) in enumerate(summary["obstacles"]):
        resources+=f'[sub_resource type="CylinderShape3D" id="obstacle{i}"]\nradius = {r:.5f}\nheight = 2.0\n'
    nodes='[node name='+nodes
    blocks=re.split(r'(?=\[node name=)',nodes)
    kept=[]
    for block in blocks:
        header=block.split('\n',1)[0]
        if 'parent="Environment' in header and 'parent="Environment/Ground"' not in header: continue
        if 'parent="Environment/Ground"' in header and 'name="Mesh"' in header: continue
        kept.append(block)
    # Ground collision is deliberately kept flat at y=0 for all existing units.
    env_index=next(i for i,b in enumerate(kept) if '[node name="Environment"' in b)
    kept.insert(env_index+1,'[node name="Ground" type="StaticBody3D" parent="Environment"]\ncollision_layer = 1\ncollision_mask = 0\n')
    kept.append('[node name="ForestLandscape" parent="Environment" instance=ExtResource("forest")]\n')
    kept.append('[node name="NaturalObstacles" type="Node3D" parent="Environment"]\n')
    for i,(x,z,r,asset) in enumerate(summary["obstacles"]):
        kept.append(f'[node name="Obstacle{i}" type="StaticBody3D" parent="Environment/NaturalObstacles"]\nposition = {vec((x,0,z))}\ncollision_layer = 128\ncollision_mask = 0\n[node name="Shape" type="CollisionShape3D" parent="Environment/NaturalObstacles/Obstacle{i}"]\nposition = Vector3(0, 1, 0)\nshape = SubResource("obstacle{i}")\n')
    write(path,resources+''.join(kept))
    summary["nav_cells"]=navigation(kind,summary["config"]["width"],summary["config"]["depth"],summary["obstacles"])


BAKER = '''extends SceneTree
func _initialize() -> void:
    var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.local/rogue_forest/geometry.json"))
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.vertex_color_is_srgb = true
    material.roughness = 1.0
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.resource_name = "Soft forest vertex paint"
    var result := ResourceSaver.save(material, "res://assets/models/environment/rogue_forest/vertex_paint.tres")
    if result != OK:
        push_error("Cannot save forest material")
        quit(1)
        return
    var ground_material := material.duplicate() as StandardMaterial3D
    ground_material.resource_name = "Painted grass, soil and wheel tracks"
    if not str(manifest.ground_texture).is_empty():
        ground_material.albedo_texture = load(str(manifest.ground_texture))
        if ground_material.albedo_texture == null:
            push_error("Import the ground texture in Godot before running the forest authoring tool")
            quit(1)
            return
        ground_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    ResourceSaver.save(ground_material, "res://assets/models/environment/rogue_forest/ground_paint.tres")
    for key: String in manifest.meshes:
        var source: Dictionary = manifest.meshes[key]
        var arrays: Array = []
        arrays.resize(Mesh.ARRAY_MAX)
        var vertices := PackedVector3Array()
        var normals := PackedVector3Array()
        var colors := PackedColorArray()
        var uvs := PackedVector2Array()
        for i: int in range(0, source.vertices.size(), 3):
            vertices.append(Vector3(source.vertices[i], source.vertices[i+1], source.vertices[i+2]))
            normals.append(Vector3(source.normals[i], source.normals[i+1], source.normals[i+2]))
        for i: int in range(0, source.colors.size(), 4):
            colors.append(Color(source.colors[i], source.colors[i+1], source.colors[i+2], source.colors[i+3]))
        for i: int in range(0, source.uv.size(), 2):
            uvs.append(Vector2(source.uv[i], source.uv[i+1]))
        arrays[Mesh.ARRAY_VERTEX] = vertices
        arrays[Mesh.ARRAY_NORMAL] = normals
        arrays[Mesh.ARRAY_COLOR] = colors
        arrays[Mesh.ARRAY_TEX_UV] = uvs
        var mesh := ArrayMesh.new()
        mesh.resource_name = key
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        mesh.surface_set_material(0, ground_material if key.begins_with("ground_") else material)
        result = ResourceSaver.save(mesh, "res://assets/models/environment/rogue_forest/" + key + ".res")
        if result != OK:
            push_error("Cannot save forest mesh " + key)
            quit(1)
            return
    print("FOREST_NATIVE_BAKE meshes=", manifest.meshes.size(), " batches=", manifest.multimeshes.size())
    quit(0)
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--maps-only",action="store_true",help="Explicit alias for the default: geometry only; preserve balance and battle/HUD scenes")
    parser.add_argument("--godot",default="C:/Program Files/Godot/Godot_console.exe")
    parser.add_argument("--ground-texture",default="res://assets/textures/rogue_forest/painted_ground_detail.png",help="Generated seamless albedo texture, res:// path")
    args=parser.parse_args()
    LOCAL.mkdir(parents=True,exist_ok=True)
    build_models()
    summary={kind:build_landscape(kind) for kind in ["exploration","outpost","siege"]}
    for kind in ["outpost","siege"]: integrate_battle(kind,summary[kind])
    write(LOCAL/"geometry.json",json.dumps({"meshes":MESHES,"multimeshes":MULTIMESHES,"ground_texture":args.ground_texture},separators=(",",":")))
    write(LOCAL/"bake.gd",BAKER)
    subprocess.run([args.godot,"--headless","--path",str(ROOT),"--script","res://.local/rogue_forest/bake.gd"],check=True,timeout=120)
    # A headless RenderingServer does not retain GPU instance buffers for saving.
    # Store native row-major Transform3D buffers explicitly, without GPU readback.
    for key,source in MULTIMESHES.items():
        buffer=[]
        for x,y,z,s,angle in source["transforms"]:
            c,sn=math.cos(angle)*s,math.sin(angle)*s
            buffer.extend((c,0,sn,x,0,s,0,y,-sn,0,c,z))
        mesh=source["mesh"]
        count=len(source["transforms"])
        text=f'''[gd_resource type="MultiMesh" format=3]
[ext_resource type="ArrayMesh" path="res://assets/models/environment/rogue_forest/{mesh}.res" id="mesh"]
[resource]
transform_format = 1
instance_count = {count}
mesh = ExtResource("mesh")
buffer = PackedFloat32Array('''+', '.join(f'{v:.5f}' for v in buffer)+')\n'
        write(OUT/f"{key}.tres",text)
    report={kind:{k:v for k,v in value.items() if k!="config"} for kind,value in summary.items()}
    write(LOCAL/"layout_report.json",json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({kind:{k:v for k,v in values.items() if k!="obstacles"} for kind,values in report.items()},ensure_ascii=False))


if __name__=="__main__": main()
