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
from pathlib import Path

from author_natural_terrain_sources import source
from block_war_height_authoring import height_at, supported_footprint, surface_segment_clear
from block_war_nature_authoring import PALETTES, author_nature
from build_block_war_maps import vec, write_definition
from build_natural_terrain import bake

ROOT = Path(__file__).resolve().parents[1]
ENV = "res://assets/block_war/environment/"


def layout():
    buildings = [(-51, 0, 0, 0, 60)]
    for lane in (-21, 21):
        buildings += [(x, lane, (2 if lane < 0 else 1) if x == 0 else 0, -1,
                       24 if x == 0 else 14 if abs(x) == 39 else 18)
                      for x in (-39, -13, 0, 13, 39)]
    buildings += [(51, -12, 0, 1, 48), (51, 12, 0, 1, 42), (51, 0, 2, 1, 32)]
    return dict(id="forest_fork", title="双径幽林", size=0, half=(60, 38), team=1,
                color=(.405, .49, .335), water=[], bridges=[],
                mountains=[(-25, -10, 50, 20)], terrain=True, buildings=buildings,
                description="古老的林脊将战场分成南北两路，四条宽坡通向中央高地。青蛙守军掌握两座住宅和一间工坊，选择一路突破，也可在两端换线牵制。")


def author_source(spec):
    shoulder = [(0, -31), (16, -31), (25, -27), (27, -17), (26, 0),
                (27, 17), (25, 28), (14, 31), (0, 31), (-14, 31),
                (-25, 28), (-27, 17), (-26, 0), (-27, -17), (-25, -27), (-16, -31)]
    ridge = [(0, -9), (12, -9.5), (22, -6.5), (24, 0), (21, 7), (11, 9),
             (0, 8.5), (-11, 9), (-21, 7), (-24, 0), (-22, -6.5), (-12, -9.5)]
    ramps = []
    for z in (-21, 21):
        for sign in (-1, 1):
            ramps.append(([(sign * 33, z), (sign * 28, z + .2),
                           (sign * 23, z - .2), (sign * 19, z)], (0, 3.5), (8.4, 7.5)))
    levels = [0] + [0, 3.5, 3.5, 3.5, 0] * 2 + [0] * 3
    source(spec["id"], [(shoulder, 3.5, 1.7), (ridge, 9.5, 1.9)], [], ramps,
           levels, [(0, 3.5, -21), (0, 9.5, 0), (0, 3.5, 21)])


def roads(spec):
    paths = []
    def line(*points):
        paths.extend((*a, *b) for a, b in zip(points, points[1:]))
    for z in (-21, 21):
        lane = z + 3.5
        line((-51, 2.5), (-46, z * .55 + 2.5), (-39, lane), (-26, lane),
             (-13, lane), (0, lane), (13, lane), (26, lane), (39, lane),
             (47, z * .6 + 2.5), (51, 2.5))
        for x in (-39, -13, 0, 13, 39):
            line((x, z + 2.5), (x, lane))
    line((51, -9.5), (51, 14.5))
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
    # A joined canopy atop the impassable ridge makes the lane split readable
    # from the normal camera. Tree sizes taper at both ends and at the rim.
    for index in range(55):
        x = rng.uniform(-21, 21)
        z = rng.uniform(-5.4, 5.4)
        scale = rng.uniform(.64, 1.02)
        if not supported_footprint(spec, x, z, 1.0, .3):
            continue
        species = ("wind_pine", "canopy_oak", "silver_birch")[index % 3]
        nodes.append(f'[node name="RidgeCanopy{index:02d}" parent="Nature" instance=ExtResource("nature_{species}")]\n'
                     f'position = {vec((x, height_at(spec, x, z), z))}\n'
                     f'rotation = {vec((0, rng.uniform(0, math.tau), 0))}\nscale = {vec((scale, scale, scale))}')
    # Low groundcover enriches the rock shoulders without hiding either lane.
    # Shared native MultiMeshes keep these numerous small plants inexpensive.
    groups = {"fern_patch": [], "bluebells": [], "meadow_tuft": []}
    for index in range(230):
        north = index % 2 == 0
        x = rng.uniform(-22, 22)
        z = (-28.2 if north else 28.7) + rng.uniform(-.65, .65)
        if not supported_footprint(spec, x, z, .42, .25):
            continue
        if any(math.hypot(x-b[0], z-b[1]) < 5.2 for b in spec["buildings"]):
            continue
        species = tuple(groups)[index % 3]
        scale = rng.uniform(.58, 1.12)
        yaw = rng.uniform(0, math.tau)
        c, s = math.cos(yaw)*scale, math.sin(yaw)*scale
        groups[species].append((c, 0, s, x, 0, scale, 0, height_at(spec,x,z)-.015,
                                -s, 0, c, z))
    for species, transforms in groups.items():
        values = ", ".join(f"{v:.6f}" for row in transforms for v in row)
        sub.append(f'[sub_resource type="MultiMesh" id="ForestVerge_{species}"]\ntransform_format = 1\n'
                   f'instance_count = {len(transforms)}\nmesh = ExtResource("nature_{species}_mesh")\n'
                   f'buffer = PackedFloat32Array({values})')
        nodes.append(f'[node name="ForestVerge_{species}" type="MultiMeshInstance3D" parent="Nature"]\n'
                     f'multimesh = SubResource("ForestVerge_{species}")\n'
                     'material_override = ExtResource("nature_grass_material")\ncast_shadow = 0')
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
