"""Initial authored control points. Ordinary rebakes read the saved Curve2D resources.

Run explicitly to reset the three terrain sources, never as part of an ordinary bake.
"""
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def closed(points):
    p = np.asarray(points, float)
    handles = (np.roll(p, -1, axis=0) - np.roll(p, 1, axis=0)) / 6.0
    return [(-h, h, at) for at, h in zip(p, handles)] + [(-handles[0], handles[0], p[0])]


def open_curve(points):
    p = np.asarray(points, float)
    rows = []
    for i, at in enumerate(p):
        tangent = (p[min(i + 1, len(p)-1)] - p[max(i-1, 0)]) / (3.0 if i in (0, len(p)-1) else 6.0)
        rows.append((-tangent if i else tangent * 0, tangent if i < len(p)-1 else tangent * 0, at))
    return rows


def symmetrical(right):
    """Clockwise contour from top centre down the right bank and up the left."""
    return right + [(-x, z) for x, z in right[-2:0:-1]]


def source(map_id, plateaus, basins, ramps, building_heights, labels):
    curves = []
    def add(name, points, loop):
        controls = closed(points) if loop else open_curve(points)
        data = ', '.join(f'{float(v):.7f}' for row in controls for pair in row for v in pair)
        curves.append(f'[sub_resource type="Curve2D" id="{name}"]\nbake_interval = 0.25\n_data = {{\n"points": PackedVector2Array({data})\n}}\npoint_count = {len(controls)}')
    for i, (points, _, _) in enumerate(plateaus): add(f'Plateau{i}', points, True)
    for i, (points, _) in enumerate(basins): add(f'Basin{i}', points, True)
    for i, (points, _, _) in enumerate(ramps): add(f'Ramp{i}', points, False)
    def refs(name, count): return 'Array[Curve2D]([' + ', '.join(f'SubResource("{name}{i}")' for i in range(count)) + '])'
    def packed(kind, values): return kind + '(' + ', '.join(str(float(v)) for v in values) + ')'
    text = '[gd_resource type="Resource" format=3]\n\n[ext_resource type="Script" path="res://tools/war_terrain_authoring.gd" id="script"]\n\n'
    text += '\n\n'.join(curves) + '\n\n[resource]\nscript = ExtResource("script")\n'
    text += 'plateaus = ' + refs('Plateau', len(plateaus)) + '\n'
    text += 'plateau_heights = ' + packed('PackedFloat32Array', (v[1] for v in plateaus)) + '\n'
    text += 'cliff_widths = ' + packed('PackedFloat32Array', (v[2] for v in plateaus)) + '\n'
    text += 'basins = ' + refs('Basin', len(basins)) + '\n'
    text += 'basin_heights = ' + packed('PackedFloat32Array', (v[1] for v in basins)) + '\n'
    text += 'ramps = ' + refs('Ramp', len(ramps)) + '\n'
    text += 'ramp_levels = ' + packed('PackedVector2Array', (v for r in ramps for v in r[1])) + '\n'
    text += 'ramp_widths = ' + packed('PackedVector2Array', (v for r in ramps for v in r[2])) + '\n'
    text += 'building_heights = ' + packed('PackedFloat32Array', building_heights) + '\n'
    text += 'labels = ' + packed('PackedVector3Array', (v for p in labels for v in p)) + '\n'
    path = ROOT / 'tools/terrain' / (map_id + '.tres')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')


def main():
    island = symmetrical([(0,-15.8),(8,-15.5),(15,-12.5),(17,-4),(16,7),(11,15),(0,17)])
    ramps = []
    for sign in (-1,1):
        ramps.append(([(sign*28,0),(sign*23,0),(sign*18.25,0),(sign*13.5,0)],(0,4.5),(7.8,6.0)))
    ramps += [([(0,-29),(0,-24),(0,-19),(0,-14)],(0,4.5),(7.3,5.7)),
              ([(0,29),(0,24),(0,19),(0,14)],(0,4.5),(7.8,5.8))]
    source('terraces',[(island,4.5,1.15)],[],ramps,[0]*10+[4.5]+[0]*4+[4.5]*4,[(0,4.5,0)])
    north = symmetrical([(0,-36.2),(11,-36.2),(20,-33),(22.5,-27),(19.5,-19),(10,-16.5),(0,-17.5)])
    south = [(x,-z) for x,z in north]
    peak = symmetrical([(0,-11),(6,-10),(11,-6),(12.0,0),(10.5,7),(5.5,11.0),(0,11.5)])
    ramps=[]
    for z in (-27,27):
        for s in (-1,1):
            ramps.append(([(s*37,z),(s*30,z-0.7),(s*23,z+0.6),(s*15,z)],(0,4.5),(7.7,6.0)))
    ramps += [([(0,-21),(0,-16.5),(0,-11.5),(0,-7)],(4.5,8),(6.3,5.5)),
              ([(0,21),(0,16.5),(0,11.5),(0,7)],(4.5,8),(6.7,5.5))]
    source('switchback',[(north,4.5,1.2),(south,4.5,1.25),(peak,8,1.3)],[],ramps,[0]*10+[4.5]*4+[8]+[0]*4,[(0,4.5,-29),(0,8,0),(0,4.5,29)])
    outer = symmetrical([(0,-41.5),(15,-41),(28,-37.5),(38,-29),(40,-16),(39.5,0),(40,16),(37,30),(25,39.5),(11,41),(0,40.5)])
    inner = symmetrical([(0,-20.5),(10,-21),(18,-18.5),(20.6,-12),(21,0),(20.4,12),(17,19),(8,20.5),(0,21)])
    ramps=[]
    for z in (-30,0,30):
        for s in (-1,1):
            points = [(s*57,z),(s*49,z-0.6),(s*42,z+0.5),(s*35,z)] if z == 0 else [(s*57,z),(s*48,z-0.8),(s*39,z+0.6),(s*29,z)]
            ramps.append((points,(0,5),(8.0,6.3)))
    ramps += [([(0,-6.5),(0,-13),(0,-21),(0,-29)],(0,5),(5.6,6.3)),
              ([(0,6.5),(0,13),(0,21),(0,29)],(0,5),(5.6,6.3))]
    source('crown',[(outer,5,1.45)],[(inner,0)],ramps,[0]*10+[5]*6+[0]*17,[(-28,5,0),(28,5,0),(0,5,-34),(0,5,34)])


if __name__ == '__main__': main()
