"""Author the second campaign battlefield as saved, editable Godot resources.

Only this map is written. Curve2D outlines are the source of the rendered and
walkable height field; all trees and buildings are ordinary saved scene nodes.
Run this tool, then tools/bake_forest_fork.gd with the private desktop runner.

Native APIs reviewed: class_curve2d.html and class_arraymesh.html in the Godot
stable manual. No runtime geometry generation is added to the game.
"""
from __future__ import annotations

import argparse
import math
import random
import re
from pathlib import Path

from author_natural_terrain_sources import source
from block_war_height_authoring import height_at, supported_footprint, surface_segment_clear
from block_war_nature_authoring import PALETTES, author_nature, _distance_to_path
from build_block_war_maps import vec, write_definition
from build_natural_terrain import bake

ROOT = Path(__file__).resolve().parents[1]
ENV = "res://assets/block_war/environment/"


def layout():
    buildings = [(-38, 0, 0, 0, 60)]
    for lane in (-16.5, 16.5):
        buildings += [(x, lane, (2 if lane < 0 else 1) if x == 0 else 0, -1,
                       24 if x == 0 else 14 if abs(x) == 28 else 18)
                      for x in (-28, -10, 0, 10, 28)]
    buildings += [(38, -10, 0, 1, 48), (38, 10, 0, 1, 42), (38, 0, 2, 1, 32)]
    return dict(id="forest_fork", title="双径森林", size=0, half=(46, 31), team=1,
                color=(.405, .49, .335), water=[], bridges=[],
                mountains=[(-19, -7, 38, 14)], terrain=True, buildings=buildings,
                building_pad_radius=5.0, building_pad_blend=1.4,
                description="古老的林脊将战场分成南北两路，四条宽坡通向中央高地。青蛙守军掌握两座住宅和一间工坊，选择一路突破，也可在两端换线牵制。")


def author_source(spec):
    shoulder = [(0, -25), (12, -25), (19, -22), (20, -14), (19, 0),
                (20, 14), (19, 22), (11, 25), (0, 25), (-11, 25),
                (-19, 22), (-20, 14), (-19, 0), (-20, -14), (-19, -22), (-12, -25)]
    ridge = [(0, -6.5), (9, -6.7), (16, -4.7), (18, 0), (15.5, 5), (8, 6.5),
             (0, 6.2), (-8, 6.5), (-15.5, 5), (-18, 0), (-16, -4.7), (-9, -6.7)]
    ramps = []
    for z in (-16.5, 16.5):
        for sign in (-1, 1):
            ramps.append(([(sign * 24, z), (sign * 21, z),
                           (sign * 18, z), (sign * 14, z)], (0, 2.7), (7.5, 7.0)))
    levels = [0] + [0, 2.7, 2.7, 2.7, 0] * 2 + [0] * 3
    source(spec["id"], [(shoulder, 2.7, 1.5), (ridge, 8.5, 1.65)], [], ramps,
           levels, [(0, 2.7, -16.5), (0, 8.5, 0), (0, 2.7, 16.5)])


def roads(spec):
    paths = []
    def line(*points):
        paths.extend((*a, *b) for a, b in zip(points, points[1:]))
    for z in (-16.5, 16.5):
        lane = z + 3.5
        line((-38, 2.5), (-34, z * .55 + 2.5), (-28, lane), (-19, lane),
             (-10, lane), (0, lane), (10, lane), (19, lane), (28, lane),
             (34, z * .6 + 2.5), (38, 2.5))
        for x in (-28, -10, 0, 10, 28):
            line((x, z + 2.5), (x, lane))
    line((38, -7.5), (38, 12.5))
    assert len(paths) <= 64
    assert all(surface_segment_clear(spec, segment) for segment in paths), "Forest road crosses an authored cliff"
    return paths


def authored_woodland(spec, paths):
    # The central ridge is a sculpted field, so do not add the old rectangular
    # ridge prop template. Its conservative navigation rectangle remains in
    # the map definition. Woodland clearance still respects all road spines.
    nature_spec = dict(spec, mountains=[])
    PALETTES[spec["id"]] = ("wind_pine", "silver_birch", "canopy_oak", "wind_pine")
    ext, sub, nodes = author_nature(nature_spec, paths)
    rng = random.Random(39127)
    # Fill genuine interior woodland pockets. The earlier border groves alone
    # made the battlefield read as a bare lawn despite its overall tree count.
    occupied = []
    for node in nodes:
        if any(f'instance=ExtResource("nature_{name}")' in node
               for name in ("wind_pine", "canopy_oak", "silver_birch", "weeping_willow")):
            position = re.search(r'position = Vector3\(([^)]+)\)', node)
            if position:
                x, _, z = map(float, position[1].split(','))
                occupied.append((x, z, .85))
    added_trees = []

    def road_distance(x, z):
        return min(_distance_to_path(x, z, segment) for segment in paths)

    def planting_site(x, z, radius, road_gap=3.1, yard=5.8):
        return (supported_footprint(spec, x, z, min(radius, 1.0), .22)
                and road_distance(x, z) >= radius + road_gap
                and all(math.hypot(x-b[0], z-b[1]) >= radius + yard for b in spec["buildings"]))

    def plant_tree(x, z, size, species, label):
        if not planting_site(x, z, 1.9*size):
            return False
        if any(math.hypot(x-ox, z-oz) < 1.12*(size+old_size) for ox, oz, old_size in occupied):
            return False
        occupied.append((x, z, size))
        added_trees.append((x, z, size))
        node = (f'[node name="{label}{len(added_trees):03d}" parent="Nature" instance=ExtResource("nature_{species}")]\n'
                f'position = {vec((x, height_at(spec,x,z), z))}\n'
                f'rotation = {vec((0, rng.uniform(0, math.tau), 0))}\n'
                f'scale = {vec((size, size*rng.uniform(.94,1.12), size))}')
        # The ridge is already a blocked terrain area. Only traversable
        # interior tree trunks need navigation radii in the saved scene.
        if abs(x) < spec["half"][0] and abs(z) < spec["half"][1] and not (abs(x) < 19 and abs(z) < 7):
            node += '\nmetadata/route_radius = 0.72'
        nodes.append(node)
        return True

    # The long ridge is now a densely joined mixed canopy with real sapling
    # edges; no randomly stacked trunks and no trees rooted on a cliff face.
    for _ in range(700):
        x, z = rng.uniform(-16.4,16.4), rng.uniform(-4.4,4.4)
        size = rng.uniform(.62,.90) if abs(z)>2.8 or abs(x)>13.5 else rng.uniform(.90,1.18)
        plant_tree(x,z,size,("wind_pine","canopy_oak","silver_birch")[rng.randrange(3)],"RidgeCanopy")

    # Layered groves occupy the valley pockets and both actual lane verges,
    # then merge naturally into the outer forest. Building scale is unchanged.
    grove_centers = [(x,z) for x in (-26,26) for z in (-1.5,3.2)]
    grove_centers += [(x,z) for x in (-33,-18,-5,8,22,35) for z in (-28.5,29)]
    grove_centers += [(x,z) for x in (-39,-22,-5,12,29,44) for z in (-37,37)]
    for grove_index,(cx,cz) in enumerate(grove_centers):
        for index in range(22):
            angle = index*2.399963 + grove_index*.81
            radius = 1.18*math.sqrt(index)
            x,z = cx+math.cos(angle)*radius, cz+math.sin(angle)*radius*.76
            size = rng.uniform(.55,.76) if index>=10 else rng.uniform(.85,1.1)
            species = ("wind_pine","silver_birch","canopy_oak","wind_pine")[(index+grove_index)%4]
            plant_tree(x,z,size,species,"LaneWoodland")

    # Ferns, bluebells, thickets and moss stones anchor every new grove. Low
    # groundcover uses shared native MultiMeshes, with clear walking surfaces.
    groups = {"fern_patch": [], "bluebells": [], "meadow_tuft": [], "daisies": []}
    def cover(species,x,z,size):
        if not supported_footprint(spec,x,z,.48*size,.25) or road_distance(x,z)<1.9:
            return
        if any(math.hypot(x-b[0],z-b[1])<4.4 for b in spec["buildings"]):
            return
        yaw = rng.uniform(0,math.tau)
        c,s=math.cos(yaw)*size,math.sin(yaw)*size
        groups[species].append((c,0,s,x,0,size,0,height_at(spec,x,z)-.015,-s,0,c,z))

    detail_count=0
    for index,(x,z,size) in enumerate(added_trees):
        for part in range(5):
            angle = part*2.399963+index*.74
            distance = rng.uniform(.65,1.75)
            cover(("fern_patch","bluebells","meadow_tuft","fern_patch","daisies")[part],
                  x+math.cos(angle)*distance,z+math.sin(angle)*distance,size*rng.uniform(.55,.85))
        if index % 4:
            continue
        dx,dz=x+.9,z+1.15
        prop_size = size*rng.uniform(.43,.64)
        if not planting_site(dx,dz,prop_size,.0 if abs(x)<19 and abs(z)<7 else 3.5,5):
            continue
        species="moss_boulder" if index%12==0 else "hazel_thicket"
        detail_count+=1
        node=(f'[node name="WoodlandDetail{detail_count:03d}" parent="Nature" instance=ExtResource("nature_{species}")]\n'
              f'position = {vec((dx,height_at(spec,dx,dz)-(.08 if species=="moss_boulder" else 0),dz))}\n'
              f'rotation = {vec((0,rng.uniform(0,math.tau),0))}\nscale = {vec((prop_size,prop_size,prop_size))}')
        if abs(dx)<46 and abs(dz)<31 and not(abs(dx)<19 and abs(dz)<7):
            node+='\nmetadata/route_radius = 0.7'
        nodes.append(node)
    for segment in paths:
        ax,az,bx,bz=segment
        length=math.hypot(bx-ax,bz-az)
        if length<3:
            continue
        nx,nz=-(bz-az)/length,(bx-ax)/length
        for index in range(max(2,int(length*1.4))):
            t=rng.uniform(.05,.95)
            side=-1 if index%2 else 1
            spread=side*rng.uniform(2.7,5.5)
            cover(("fern_patch","bluebells","meadow_tuft")[index%3],
                  ax+(bx-ax)*t+nx*spread,az+(bz-az)*t+nz*spread,rng.uniform(.45,.82))
    for species, transforms in groups.items():
        values = ", ".join(f"{v:.6f}" for row in transforms for v in row)
        sub.append(f'[sub_resource type="MultiMesh" id="ForestVerge_{species}"]\ntransform_format = 1\n'
                   f'instance_count = {len(transforms)}\nmesh = ExtResource("nature_{species}_mesh")\n'
                   f'buffer = PackedFloat32Array({values})')
        nodes.append(f'[node name="ForestVerge_{species}" type="MultiMeshInstance3D" parent="Nature"]\n'
                     f'multimesh = SubResource("ForestVerge_{species}")\n'
                     'material_override = ExtResource("nature_grass_material")\ncast_shadow = 0')
    inside=sum(abs(x)<46 and abs(z)<31 for x,z,_ in occupied)
    print(f"FOREST_PLANTING trees={len(occupied)} interior_trees={inside} added_cover={sum(map(len,groups.values()))} details={detail_count}")
    return ext, sub, nodes


def author_scene(spec):
    paths = roads(spec)
    ext = [
        '[ext_resource type="Script" path="res://scripts/block_war/war_map.gd" id="map_script"]',
        '[ext_resource type="Resource" path="res://data/block_war/maps/forest_fork.tres" id="definition"]',
        '[ext_resource type="PackedScene" path="res://scenes/block_war/building.tscn" id="building"]',
        f'[ext_resource type="ArrayMesh" path="{ENV}maps/forest_fork_upland.res" id="terrain_mesh"]',
        f'[ext_resource type="Shader" path="{ENV}map_ground.gdshader" id="ground_shader"]',
        f'[ext_resource type="Texture2D" path="{ENV}meadow_noise.tres" id="noise"]',
    ]
    sites = [b[:2] for b in spec["buildings"]]
    sub = ['[sub_resource type="ShaderMaterial" id="ForestGround"]\n'
           'shader = ExtResource("ground_shader")\n'
           'shader_parameter/meadow_noise = ExtResource("noise")\n'
           f'shader_parameter/half_size = {vec(spec["half"], "Vector2")}\n'
           'shader_parameter/natural_terrain = true\n'
           'shader_parameter/meadow = Color(0.405, 0.49, 0.335, 1)\n'
           'shader_parameter/grass_shadow = Color(0.38, 0.463, 0.316, 1)\n'
           'shader_parameter/grass_sunlit = Color(0.43, 0.515, 0.358, 1)\n'
           'shader_parameter/soil = Color(0.55, 0.505, 0.395, 1)\n'
           'shader_parameter/cliff_shadow = Color(0.335, 0.365, 0.31, 1)\n'
           'shader_parameter/cliff_sunlit = Color(0.545, 0.53, 0.435, 1)\n'
           f'shader_parameter/site_count = {len(sites)}\n'
           f'shader_parameter/sites = PackedVector2Array({", ".join(str(v) for p in sites + [(0, 0)] * (64-len(sites)) for v in p)})\n'
           f'shader_parameter/path_count = {len(paths)}\n'
           f'shader_parameter/paths = PackedVector4Array({", ".join(str(v) for p in paths + [(0, 0, 0, 0)] * (64-len(paths)) for v in p)})']
    nodes = ['[node name="ForestFork" type="Node3D"]\nscript = ExtResource("map_script")\n'
             'definition = ExtResource("definition")\nwater_paths = Array[NodePath]([])']
    nodes += [f'[node name="{name}" type="Node3D" parent="."]' for name in ("Terrain", "Nature", "Buildings")]
    nodes.append('[node name="Upland" type="MeshInstance3D" parent="Terrain"]\nlayers = 524289\n'
                 'mesh = ExtResource("terrain_mesh")\nmaterial_override = SubResource("ForestGround")')
    nature_ext, nature_sub, nature_nodes = authored_woodland(spec, paths)
    ext += nature_ext
    sub += nature_sub
    nodes += nature_nodes
    for index, (x, z, kind, faction, population) in enumerate(spec["buildings"]):
        assert supported_footprint(spec, x, z, 4.5), (index, "uneven building site")
        nodes.append(f'[node name="Building{index}" parent="Buildings" instance=ExtResource("building")]\n'
                     f'position = {vec((x, height_at(spec, x, z), z))}\nbuilding_id = {index}\n'
                     f'faction = {faction}\nkind = {kind}\npopulation = {float(population)}\n'
                     f'level = {2 if index == 11 else 1}')
    output = ROOT / "scenes/block_war/maps/forest_fork.tscn"
    output.write_text("\n\n".join([f'[gd_scene load_steps={len(ext)+len(sub)+1} format=3]'] + ext + sub + nodes) + "\n", encoding="utf-8")
    print(f"FOREST_SCENE buildings={len(spec['buildings'])} nodes={len(nodes)} roads={len(paths)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reset-curves", action="store_true", help="Explicitly reset editable native terrain controls")
    args = parser.parse_args()
    spec = layout()
    if args.reset_curves or not (ROOT / "tools/terrain/forest_fork.tres").exists():
        author_source(spec)
    bake(spec)
    write_definition(spec)
    definition = ROOT / "data/block_war/maps/forest_fork.tres"
    definition.write_text(definition.read_text(encoding="utf-8").replace('team_size = 1\n',
                          'team_size = 1\nasymmetric_start = true\n'), encoding="utf-8")
    author_scene(spec)


if __name__ == "__main__":
    main()
