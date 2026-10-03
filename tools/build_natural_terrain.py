"""Bake editable native Curve2D controls into one float32 terrain field.

The geometry data supplies native ArrayMesh, CPU Resource and RF shader texture.
"""
from pathlib import Path
import argparse
import json
import re
import numpy as np
from build_block_war_maps import layouts

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.local/natural-terrain'
CELL = 0.5


def packed(text, key):
    match = re.search(r'^' + re.escape(key) + r' = Packed\w+Array\(([^)]*)\)', text, re.M)
    return np.fromstring(match[1], sep=',') if match else np.empty(0)


def read_source(map_id):
    text = (ROOT / 'tools/terrain' / (map_id + '.tres')).read_text(encoding='utf-8')
    curves = {}
    for name, body in re.findall(r'\[sub_resource type="Curve2D" id="([^"]+)"\]([\s\S]*?)(?=\n\[|\Z)', text):
        values = re.search(r'"points": PackedVector2Array\(([^)]*)\)', body)[1]
        controls = np.fromstring(values, sep=',').reshape(-1, 3, 2)
        points = []
        for a,b in zip(controls, controls[1:]):
            pa,pb,pc,pd=a[2],a[2]+a[1],b[2]+b[0],b[2]
            steps=max(4, int(np.ceil((np.linalg.norm(pb-pa)+np.linalg.norm(pc-pb)+np.linalg.norm(pd-pc))/.35)))
            t=np.linspace(0,1,steps,endpoint=False)[:,None]
            points.extend((1-t)**3*pa + 3*(1-t)**2*t*pb + 3*(1-t)*t*t*pc + t**3*pd)
        points.append(controls[-1,2])
        curves[name]=np.asarray(points)
    return text,curves


def smooth(value):
    t=np.clip(value,0,1)
    return t*t*(3-2*t)


def signed_distance(x,z,points):
    squared=np.full_like(x,np.inf)
    inside=np.zeros(x.shape,dtype=bool)
    for a,b in zip(points,points[1:]):
        delta=b-a
        norm=float(delta@delta)
        if norm < 1e-12: continue
        t=np.clip(((x-a[0])*delta[0]+(z-a[1])*delta[1])/norm,0,1)
        squared=np.minimum(squared,(x-a[0]-delta[0]*t)**2+(z-a[1]-delta[1]*t)**2)
        if abs(delta[1])>1e-9:
            inside ^= ((a[1]>z)!=(b[1]>z)) & (x < a[0]+(z-a[1])*delta[0]/delta[1])
    return np.sqrt(squared)*np.where(inside,1,-1)


def ramp_coordinates(x,z,points):
    lengths=np.linalg.norm(np.diff(points,axis=0),axis=1)
    total=float(lengths.sum())
    squared=np.full_like(x,np.inf)
    progress=np.zeros_like(x)
    distance=0.0
    for a,b,length in zip(points,points[1:],lengths):
        if length<1e-9: continue
        delta=b-a
        local=np.clip(((x-a[0])*delta[0]+(z-a[1])*delta[1])/(length*length),0,1)
        d2=(x-a[0]-delta[0]*local)**2+(z-a[1]-delta[1]*local)**2
        closer=d2<squared
        progress=np.where(closer,(distance+local*length)/total,progress)
        squared=np.minimum(squared,d2)
        distance+=length
    return np.sqrt(squared),progress


def bake(layout):
    map_id=layout['id']
    text,curves=read_source(map_id)
    hx,hz=layout['half']
    origin=(-hx-24,-hz-24)
    xs=np.arange(origin[0],hx+24+CELL*.5,CELL)
    zs=np.arange(origin[1],hz+24+CELL*.5,CELL)
    x,z=np.meshgrid(xs,zs)
    height=np.zeros_like(x)
    # Large silhouettes are authored. Smaller irregularities break up rock,
    # while retaining exact left/right fairness.
    fracture=.40*np.sin(np.abs(x)*.91+z*.47)+.22*np.cos(np.abs(x)*1.63-z*.71)
    for i,(level,width) in enumerate(zip(packed(text,'plateau_heights'),packed(text,'cliff_widths'))):
        d=signed_distance(x,z,curves[f'Plateau{i}'])+fracture
        height=np.maximum(height,level*smooth((d+width)/(2*width)))
    for i,level in enumerate(packed(text,'basin_heights')):
        d=signed_distance(x,z,curves[f'Basin{i}'])+fracture*.65
        blend=smooth((d+1.3)/2.6)
        height=height*(1-blend)+level*blend
    guides=[]
    for i,(levels,widths) in enumerate(zip(packed(text,'ramp_levels').reshape(-1,2),packed(text,'ramp_widths').reshape(-1,2))):
        points=curves[f'Ramp{i}']
        distance,t=ramp_coordinates(x,z,points)
        half_width=widths[0]*(1-t)+widths[1]*t
        blend=1-smooth((distance-half_width)/2.8)
        rise=levels[0]+(levels[1]-levels[0])*smooth(t)
        height=height*(1-blend)+rise*blend
        guides.extend([*points[0],*points[-1]])
    site_heights=packed(text,'building_heights')
    assert len(site_heights)==len(layout['buildings'])
    pad_radius=layout.get('building_pad_radius',6.1)
    pad_blend=layout.get('building_pad_blend',1.9)
    for building,level in zip(layout['buildings'],site_heights):
        distance=np.maximum(np.abs(x-building[0]),np.abs(z-building[1]))
        blend=1-smooth((distance-pad_radius)/pad_blend)
        height=height*(1-blend)+level*blend
    height=(height+height[:,::-1])*.5
    height[height<1e-5]=0
    height=height.astype('<f4')
    OUT.mkdir(parents=True,exist_ok=True)
    np.save(OUT/(map_id+'.npy'),height)
    height.tofile(OUT/(map_id+'.rf'))
    metadata={'map_id':map_id,'origin':origin,'cell_size':CELL,'width':len(xs),'depth':len(zs),
              'ramp_guides':guides,'labels':packed(text,'labels').tolist(),'max_height':float(height.max()),
              'water':layout['water'],'color':layout['color']}
    (OUT/(map_id+'.json')).write_text(json.dumps(metadata),encoding='utf-8')
    dz,dx=np.gradient(height,CELL)
    print(map_id,'grid',height.shape,'height',float(height.max()),'steep cells',int((np.hypot(dx,dz)>.5).sum()))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--map',choices=['terraces','switchback','crown'])
    args=parser.parse_args()
    for layout in layouts():
        if layout['id'] in ['terraces','switchback','crown'] and (not args.map or args.map==layout['id']): bake(layout)
