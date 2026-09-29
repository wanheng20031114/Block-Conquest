"""Offline queries of exactly the same saved triangulated field as Godot."""
from functools import lru_cache
from pathlib import Path
import json
import math
import numpy as np

ROOT=Path(__file__).resolve().parents[1]

@lru_cache(maxsize=3)
def field(map_id):
    base=ROOT/'.local/natural-terrain'
    meta=json.loads((base/(map_id+'.json')).read_text(encoding='utf-8'))
    return meta,np.load(base/(map_id+'.npy'))

def triangle(layout,x,z):
    meta,grid=field(layout['id'])
    u=(x-meta['origin'][0])/meta['cell_size']
    v=(z-meta['origin'][1])/meta['cell_size']
    if not 0<=u<=meta['width']-1 or not 0<=v<=meta['depth']-1: return (0,0,0)
    ix=min(int(u),meta['width']-2); iz=min(int(v),meta['depth']-2)
    u-=ix;v-=iz
    a,b,c,d=(float(grid[iz,ix]),float(grid[iz,ix+1]),float(grid[iz+1,ix]),float(grid[iz+1,ix+1]))
    step=meta['cell_size']
    if u+v<=1: return a+(b-a)*u+(c-a)*v,(b-a)/step,(c-a)/step
    return d+(c-d)*(1-u)+(b-d)*(1-v),(d-c)/step,(d-b)/step

def height_at(layout,x,z):
    return triangle(layout,x,z)[0] if layout.get('terrain') else 0.0

def supported_footprint(layout,x,z,radius,tolerance=.15):
    center=height_at(layout,x,z)
    return all(abs(height_at(layout,x+dx*radius,z+dz*radius)-center)<=tolerance
               for dx,dz in ((-1,-1),(-1,1),(1,-1),(1,1),(0,-1),(0,1),(-1,0),(1,0)))

def surface_segment_clear(layout,segment):
    if not layout.get('terrain'): return True
    ax,az,bx,bz=segment
    distance=math.hypot(bx-ax,bz-az)
    steps=max(1,math.ceil(distance/.15))
    for i in range(steps+1):
        _,dx,dz=triangle(layout,ax+(bx-ax)*i/steps,az+(bz-az)*i/steps)
        if math.hypot(dx,dz)>.5001: return False
    return True
