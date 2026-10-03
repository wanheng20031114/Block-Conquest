"""Author 水间花池, a saved native battlefield with continuous curving banks.

Run this, then bake_flower_pool_assets.gd and bake_block_war_routes.gd flower_pool.
Curves share one sampled contour between the visible shore and navigation.
"""
from __future__ import annotations
import json
import math
import random
from pathlib import Path
from block_war_bridge_authoring import author_bridges
from build_block_war_maps import vec, rects

ROOT = Path(__file__).resolve().parents[1]
ASSETS = "res://assets/block_war/flower_pool/"
ENV = "res://assets/block_war/environment/"
# Compact the settlement centres, retaining full-size houses and army clearance.
BUILDINGS = [(-32, 0, 0, 0, 60, 1), (32, -8, 0, 1, 40, 2), (32, 8, 0, 1, 40, 2),
             (-22, -14.5, 0, -1, 10, 1), (-22, 14.5, 0, -1, 10, 1), (-22, 0, 2, -1, 16, 1),
             (0, -14.5, 0, -1, 12, 1), (0, 14.5, 0, -1, 12, 1), (0, 0, 0, -1, 18, 1),
             (22, -14.5, 0, -1, 16, 1), (22, 14.5, 0, -1, 16, 1), (22, 0, 1, -1, 22, 1)]


def channel(i, z):
    if i == 0:
        return -12 + 1.6 * math.sin(z * .14) + .3 * math.sin(z * .31), 1.9 + .2 * math.cos(z * .2)
    return 12 + 1.6 * math.sin(z * .13 + .6), 1.9 + 1.05 * math.exp(-((z - 1) / 6) ** 2)


BRIDGES = [(channel(i, z)[0] - 4.0, z - 3.6, 8.0, 7.2) for i in range(2) for z in (-8.5, 8.5)]
PATHS = []
for z in (-8.5, 8.5):
    PATHS += [(-32, 0, -22, z), (-22, z, 0, z), (0, z, 22, z), (22, z, 32, z)]
for x, z, *_ in BUILDINGS:
    if x not in (-32, 32):
        for lane in ([-8.5, 8.5] if z == 0 else [-8.5 if z < 0 else 8.5]):
            PATHS.append((x, z, x, lane))


class Mesh:
    def __init__(self):
        self.vertices, self.normals, self.colors = [], [], []

    def quad(self, a, b, c, d, colors=None):
        # Clockwise winding from above, matching native Godot mesh culling.
        for points, indices in [((a, b, c), (0, 1, 2)), ((a, c, d), (0, 2, 3))]:
            u = [points[1][j] - points[0][j] for j in range(3)]
            v = [points[2][j] - points[0][j] for j in range(3)]
            n = [v[1]*u[2]-v[2]*u[1], v[2]*u[0]-v[0]*u[2], v[0]*u[1]-v[1]*u[0]]
            length = math.sqrt(sum(x*x for x in n))
            n = [x/length for x in n]
            for point, index in zip(points, indices):
                self.vertices.append(point)
                self.normals.append(n)
                self.colors.append(colors[index] if colors else (1, 1, 1))


def meshes():
    land, grass, stone, water = [Mesh() for _ in range(4)]
    for step in range(192):
        z, zz = -48 + step * .5, -48 + (step + 1) * .5
        row, next_row = [], []
        for at, edges in ((z, row), (zz, next_row)):
            edges.append(-64)
            for i in range(2):
                c, w = channel(i, at)
                edges.extend([c-w-.8, c+w+.8])
            edges.append(64)
        for j in (0, 2, 4):
            land.quad((row[j], 0, z), (row[j+1], 0, z), (next_row[j+1], 0, zz), (next_row[j], 0, zz))
        for i in range(2):
            c, w = channel(i, z)
            cc, ww = channel(i, zz)
            for side in (-1, 1):
                profiles = [(w+.8, 0, ww+.8), (w+.15, -.04, ww+.15), (w-.2, -.28, ww-.2), (w-.45, -1.55, ww-.45)]
                for j in range(3):
                    a, y, aa = profiles[j]
                    b, yy, bb = profiles[j+1]
                    points = [(c+side*a, y, z), (c+side*b, yy, z), (cc+side*bb, yy, zz), (cc+side*aa, y, zz)]
                    if side > 0:
                        points.reverse()
                    (grass if j < 2 else stone).quad(*points)
            for j in range(12):
                t, tt = j/12, (j+1)/12
                a, b = c+(2*t-1)*(w-.3), c+(2*tt-1)*(w-.3)
                aa, bb = cc+(2*t-1)*(ww-.3), cc+(2*tt-1)*(ww-.3)
                colors = [(0, min(t, 1-t)*w/4, 0), (0, min(tt, 1-tt)*w/4, 0),
                          (0, min(tt, 1-tt)*ww/4, 0), (0, min(t, 1-t)*ww/4, 0)]
                water.quad((a, -1.15, z), (b, -1.15, z), (bb, -1.15, zz), (aa, -1.15, zz), colors)
    return {k: vars(m) for k, m in zip(("land", "bank_grass", "bank_stone", "water"), (land, grass, stone, water))}


def path_distance(x, z):
    result = 1000
    for ax, az, bx, bz in PATHS:
        dx, dz = bx-ax, bz-az
        t = max(0, min(1, ((x-ax)*dx+(z-az)*dz)/(dx*dx+dz*dz)))
        result = min(result, math.hypot(x-ax-dx*t, z-az-dz*t))
    return result


def clear(x, z, radius=0):
    if any(abs(x-channel(i,z)[0]) < channel(i,z)[1]+1.1+radius for i in range(2)):
        return False
    if any(math.hypot(x-b[0], z-b[1]) < 6.5+radius for b in BUILDINGS):
        return False
    if any(bx-1-radius < x < bx+bw+1+radius and bz-1-radius < z < bz+bh+1+radius for bx,bz,bw,bh in BRIDGES):
        return False
    return path_distance(x,z) > 3+radius


def main():
    output = ROOT / "artifacts/flower-pool-authoring"
    output.mkdir(parents=True, exist_ok=True)
    (output / "meshes.json").write_text(json.dumps(meshes(), separators=(",", ":")), encoding="utf-8")
    polygons = []
    for i in range(2):
        points = []
        for side, values in ((-1, range(-96,97)), (1, range(96,-97,-1))):
            for step in values:
                z = step*.5
                c,w = channel(i,z)
                points.extend((c+side*(w+.15), z))
        polygons.append("PackedVector2Array("+", ".join(f"{v:.4f}" for v in points)+")")
    positions = [v for x,z,*_ in BUILDINGS for v in (x,0,z)]
    definition = f'''[gd_resource type="Resource" script_class="WarMapDefinition" format=3]
[ext_resource type="Script" path="res://scripts/block_war/war_map_definition.gd" id="script"]
[resource]
script = ExtResource("script")
map_id = "flower_pool"
title = "水间花池"
size_class = 0
team_size = 1
asymmetric_start = true
scene_path = "res://scenes/block_war/maps/flower_pool.tscn"
routes_path = "res://data/block_war/routes/flower_pool.res"
description = "紫阳花沿两条曲水盛开，四座拱石桥连接花池之间的九处中立建筑。左侧一座初级住宅，对阵右侧两座二级住宅；适合逐桥推进的非对称 1v1 战场。"
half_size = Vector2(40, 24)
camera_bounds = Rect2(-64, -48, 128, 96)
ground_color = Color(0.42, 0.53, 0.36, 1)
water_polygons = Array[PackedVector2Array]([{', '.join(polygons)}])
bridges = {rects(BRIDGES)}
building_positions = PackedVector3Array({', '.join(map(str, positions))})
building_kinds = PackedInt32Array({', '.join(str(b[2]) for b in BUILDINGS)})
building_factions = PackedInt32Array({', '.join(str(b[3]) for b in BUILDINGS)})
'''
    (ROOT / "data/block_war/maps/flower_pool.tres").write_text(definition, encoding="utf-8")
    externals = [
        '[ext_resource type="Script" path="res://scripts/block_war/war_map.gd" id="script"]',
        '[ext_resource type="Script" path="res://scripts/block_war/war_flower_detail.gd" id="flower_detail"]',
        '[ext_resource type="Resource" path="res://data/block_war/maps/flower_pool.tres" id="definition"]',
        '[ext_resource type="PackedScene" path="res://scenes/block_war/building.tscn" id="building"]']
    for name in ("land", "bank_grass", "bank_stone", "water"):
        externals.append(f'[ext_resource type="ArrayMesh" path="{ASSETS}{name}.res" id="{name}"]')
    for name,kind,path in [("ground_shader","Shader",ENV+"map_ground.gdshader"), ("noise","Texture2D",ENV+"meadow_noise.tres"),
                           ("water_shader","Shader",ENV+"map_water.gdshader"), ("water_noise","Texture2D",ENV+"water_noise.tres"),
                           ("normals","Texture2D",ENV+"water_normals.tres"), ("rock","Material",ENV+"shore_rock.tres")]:
        externals.append(f'[ext_resource type="{kind}" path="{path}" id="{name}"]')
    resources = ['''[sub_resource type="ShaderMaterial" id="Ground"]
shader = ExtResource("ground_shader")
shader_parameter/meadow_noise = ExtResource("noise")
shader_parameter/half_size = Vector2(40, 24)
shader_parameter/meadow = Color(0.43, 0.54, 0.365, 1)
shader_parameter/grass_shadow = Color(0.413, 0.515, 0.35, 1)
shader_parameter/grass_sunlit = Color(0.45, 0.558, 0.388, 1)
shader_parameter/soil = Color(0.62, 0.575, 0.44, 1)'''
        +f'\nshader_parameter/site_count = {len(BUILDINGS)}\nshader_parameter/sites = PackedVector2Array('+', '.join(str(v) for b in BUILDINGS for v in b[:2])+')'
        +f'\nshader_parameter/path_count = {len(PATHS)}\nshader_parameter/paths = PackedVector4Array('+', '.join(str(v) for p in PATHS for v in p)+')'
        +'\nshader_parameter/bridge_count = 4\nshader_parameter/bridge_regions = PackedVector4Array('+', '.join(str(v) for p in BRIDGES for v in p)+')',
        '''[sub_resource type="ShaderMaterial" id="Water"]
shader = ExtResource("water_shader")
shader_parameter/surface_noise = ExtResource("water_noise")
shader_parameter/wave_normals = ExtResource("normals")''']
    nodes = ['''[node name="WaterFlowerPool" type="Node3D"]
script = ExtResource("script")
definition = ExtResource("definition")
water_paths = Array[NodePath]([NodePath("Terrain/Water")])''']
    for name in ("Terrain", "Bridges", "Nature", "Buildings"):
        nodes.append(f'[node name="{name}" type="Node3D" parent="."]')
        if name == "Nature":
            nodes[-1] += '\nscript = ExtResource("flower_detail")'
    for name,asset,material in [("Land","land",'SubResource("Ground")'), ("SoftBanks","bank_grass",'SubResource("Ground")'),
                               ("BankStone","bank_stone",'ExtResource("rock")'), ("Water","water",'SubResource("Water")')]:
        nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="Terrain"]\nlayers = 524289\nmesh = ExtResource("{asset}")\nmaterial_override = {material}')
    ext, sub, children = author_bridges(dict(id="flower_pool", bridges=BRIDGES, water=[(-16,-48,8,96),(8,-48,10,96)]))
    externals += ext
    resources += sub
    nodes += children
    for palette in ("blue", "violet", "pink"):
        for variant in range(3):
            key=f'hydrangea_{palette}_{variant}'
            externals.append(f'[ext_resource type="PackedScene" path="{ASSETS}{key}.scn" id="{key}"]')
    species=("weeping_willow", "silver_birch", "canopy_oak", "moss_boulder", "daisies", "bluebells", "fern_patch", "reed_cluster")
    for name in species:
        externals.append(f'[ext_resource type="PackedScene" path="res://assets/models/block_war/nature/{name}.tscn" id="{name}"]')
    rng=random.Random(41026)
    placed=[]
    beds=[(-28,-25,11,7),(-26,25,13,8),(-4,-26,7,8),(3,27,7,8),(-6,0,3,5),
          (6,0,3,5),(25,-27,11,7),(28,27,11,7),(-41,7,5,17),(41,-3,5,18)]
    for bed_id,(cx,cz,rx,rz) in enumerate(beds):
        for _ in range(650):
            x,z=cx+rng.uniform(-rx,rx),cz+rng.uniform(-rz,rz)
            if ((x-cx)/rx)**2+((z-cz)/rz)**2 > 1+.12*math.sin(x*.9+z*.7): continue
            if not clear(x,z,.5) or any(math.hypot(x-a,z-b)<1.4 for a,b in placed): continue
            placed.append((x,z))
            palette=("blue","violet","pink")[(bed_id+(rng.random()>.75))%3]
            size=rng.uniform(.92,1.26)
            nodes.append(f'[node name="Hydrangea{len(placed):03}" parent="Nature" instance=ExtResource("hydrangea_{palette}_{rng.randrange(3)}")]\nposition = {vec((x,0,z))}\nrotation = {vec((0,rng.uniform(0,6.28),0))}\nscale = {vec((size,size,size))}')
    trees=[]
    for j in range(750):
        x,z=rng.uniform(-58,58),rng.uniform(-41,41)
        if abs(x)<40 and abs(z)<28: continue
        if not clear(x,z,2) or any(math.hypot(x-a,z-b)<5.5 for a,b in trees): continue
        if any(math.hypot(x-a,z-b)<2.7 for a,b in placed): continue
        trees.append((x,z))
        size=rng.uniform(.8,1.2)
        tree=species[j%3]
        nodes.append(f'[node name="GardenTree{j}" parent="Nature" instance=ExtResource("{tree}")]\nposition = {vec((x,0,z))}\nrotation = {vec((0,rng.uniform(0,6.28),0))}\nscale = {vec((size,size,size))}\nmetadata/route_radius = 1.35')
    for j in range(460):
        x,z=rng.uniform(-46,46),rng.uniform(-34,34)
        if not clear(x,z,.1): continue
        if any(math.hypot(x-a,z-b)<1 for a,b in placed): continue
        name=("daisies","bluebells","fern_patch")[j%3]
        size=rng.uniform(.8,1.35)
        nodes.append(f'[node name="Meadow{j}" parent="Nature" instance=ExtResource("{name}")]\nposition = {vec((x,0,z))}\nrotation = {vec((0,rng.uniform(0,6.28),0))}\nscale = {vec((size,size,size))}')
    # Broken limestone and reeds follow both curved edges, leaving bridge mouths clear.
    for i in range(2):
        for j in range(58):
            z=-41+j*1.43+rng.uniform(-.5,.5)
            c,w=channel(i,z)
            for side in (-1,1):
                if rng.random()<.4: continue
                x=c+side*(w+1.25)
                if any(bx-2<x<bx+bw+2 and bz-2<z<bz+bh+2 for bx,bz,bw,bh in BRIDGES): continue
                name="moss_boulder" if j%3 else "reed_cluster"
                size=rng.uniform(.26,.7) if name=="moss_boulder" else rng.uniform(.65,.95)
                nodes.append(f'[node name="BankDetail{i}_{j}_{side}" parent="Nature" instance=ExtResource("{name}")]\nposition = {vec((x,-.07,z))}\nrotation = {vec((0,rng.uniform(0,6.28),0))}\nscale = {vec((size,size*.65,size))}')
    for i,(x,z,kind,faction,population,level) in enumerate(BUILDINGS):
        nodes.append(f'[node name="Building{i}" parent="Buildings" instance=ExtResource("building")]\nposition = {vec((x,0,z))}\nbuilding_id = {i}\nfaction = {faction}\nkind = {kind}\npopulation = {float(population)}\nlevel = {level}')
    target=ROOT/"scenes/block_war/maps/flower_pool.tscn"
    target.write_text("\n\n".join(['[gd_scene format=3]']+externals+resources+nodes)+"\n",encoding="utf-8")
    print(f'FLOWER_POOL_AUTHORED buildings={len(BUILDINGS)} hydrangeas={len(placed)} trees={len(trees)} bridges=4')


if __name__ == "__main__":
    main()
