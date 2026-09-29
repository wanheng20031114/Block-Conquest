"""Author editable battlefields and their shared Resource catalog.

All terrain, bridges, buildings and scenery are saved as native scene nodes.
Layouts are explicit inputs, including the original rift's stable building IDs.
No runtime node or image generation is used.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from block_war_bridge_authoring import author_bridges
from block_war_nature_authoring import author_nature
from block_war_path_authoring import author_paths
from block_war_height_authoring import height_at, supported_footprint

ROOT = Path(__file__).resolve().parents[1]
ENV = "res://assets/block_war/environment/"


def vec(values, kind="Vector3"):
    return kind + "(" + ", ".join(f"{v:.5f}".rstrip("0").rstrip(".") if v else "0" for v in values) + ")"


def rects(values):
    return "Array[Rect2]([" + ", ".join(vec(v, "Rect2") for v in values) + "])"


def building(x, z, kind=0, faction=-1, population=14):
    return (x, z, kind, faction, 60 if faction >= 0 else population)


def mirrored(xs, zs, kind=0, population=14):
    return [building(sign * x, z, kind, population=population) for z in zs for x in xs for sign in (-1, 1)]


def starts(x, rows):
    return [building(sign * x, z, faction=row * 2 + side) for row, z in enumerate(rows) for side, sign in enumerate((-1, 1))]


def layouts():
    # Bring settlements inward independently of the terrain: army clearances,
    # bridge road widths and the model footprints retain their authored sizes.
    common = dict(size=0, half=(36, 26), team=1, water=[], mountains=[], bridges=[], color=(0.36, 0.465, 0.2))
    rift_homes = [building(-27, 0, faction=0), building(27, 0, faction=1),
                  building(-26, -17), building(-24, 15), building(24, -15), building(26, 17),
                  building(-18, 0, 1, population=25), building(18, 0, 1, population=25),
                  building(-20, -10, 2, population=20), building(20, 10, 2, population=20),
                  building(0, -15, population=20), building(0, 15, population=20),
                  building(0, 0, 1, population=40)]
    maps = [dict(common, id="rift", title="裂谷交汇", description="四座石桥围绕中央塔台，两处内湾收紧谷心。近岸据点更紧凑，抢桥与绕后可以同时展开。", buildings=rift_homes,
                 water=[(-14, -54, 5, 108), (9, -54, 5, 108), (-9, -4, 2, 8), (7, -4, 2, 8)],
                 bridges=[(x, z - 3.6, 5, 7.2) for x in (-14, 9) for z in (-12, 12)])]
    maps.append(dict(common, id="lake", title="林湖回廊", half=(36, 28), description="十字湖湾伸向两侧工坊，南北回廊形成两条完整包抄线。贴湖争夺前哨，也能沿林缘调兵。",
                     water=[(-8, -11, 16, 22), (-12, -4, 4, 8), (8, -4, 4, 8)],
                     buildings=starts(26, [0]) + mirrored([26], [-18, 18]) + mirrored([16], [0], 2, 18)
                     + [building(0, z, population=20) for z in (-20, 20)] + mirrored([12], [-20, 20], 1, 22)))
    medium = dict(common, size=1, half=(54, 40), team=2)
    # Preserve central outpost / tower spacing while compacting the outer villages;
    # overlapping tower fire otherwise turns the middle lanes into prolonged sieges.
    maps.append(dict(medium, id="rivers", title="双河平原", description="六座宽桥串起三条战线，河湾把中央平原收成两段狭长前哨。抢下中桥，可在上下战线之间快速转兵。",
                     water=[(-15, -60, 6, 120), (9, -60, 6, 120)]
                     + [(x, z, 2, 10) for x in (-9, 7) for z in (-17, 7)],
                     bridges=[(x, z - 4, 6, 8) for x in (-15, 9) for z in (-23, 0, 23)],
                     buildings=starts(42, [-23, 23]) + mirrored([42], [-5.5, 5.5]) + mirrored([25], [-27, 27])
                     + mirrored([25], [-7, 7], 1, 22) + mirrored([34], [-15, 15], 2, 18)
                     + [building(0, z, 1 if z == 0 else 0, population=30 if z == 0 else 20) for z in (-29, -16, 0, 16, 29)]))
    maps.append(dict(medium, id="ridges", title="断脊山道", color=(0.38, 0.47, 0.215), description="两道长岩脊和两处侧峰围成分叉谷口。外圈山道适合包抄，中央工坊则能连通两翼的支援。",
                     mountains=[(-5, -30, 10, 17), (-5, 13, 10, 17), (-28, -5, 8, 10), (20, -5, 8, 10)],
                     buildings=starts(42, [-23, 23]) + mirrored([42], [-5.5, 5.5]) + mirrored([27], [-27, 27])
                     + mirrored([27], [-9, 9], 2, 18) + mirrored([14], [-19.5, 19.5], 1, 24)
                     + mirrored([13], [-35, 35]) + [building(0, 0, 2, population=28)] + mirrored([12], [0], 0, 20)))
    large = dict(common, size=2, half=(76, 54), team=3)
    maps.append(dict(large, id="islands", title="群岛长滩", description="三座纵向岛屿与八座宽桥连接三条战线。两岸内凹水湾分开集结区，沿岛心转兵可迅速支援队友。",
                     water=[(-25, -76, 7, 152), (18, -76, 7, 152), (-18, -23, 36, 7), (-18, 16, 36, 7)]
                     + [(x, z, 4, 6) for x in (-29, 25) for z in (-13, 7)],
                     bridges=[(x, z - 5, 7, 10) for x in (-25, 18) for z in (-37, 0, 37)] + [(-4, z, 8, 7) for z in (-23, 16)],
                     buildings=starts(60, [-36, 0, 36]) + mirrored([40], [-36, 0, 36]) + mirrored([60, 40], [-18.5, 18.5])
                     + [building(x, z, 2 if x == 0 else 0, population=22) for z in (-36, 0, 36) for x in (-9, 0, 9)]
                     + mirrored([70], [-31, 9, 31], 2, 18) + mirrored([30], [-36, 0, 36], 1, 25)))
    maps.append(dict(large, id="highland", title="环湖高原", half=(76, 58), color=(0.35, 0.455, 0.195), description="中央石台扼守长桥，湖岸四处岩岬分出内侧捷径和外侧迂回线。三位队友分别推进，也能借中央快速换翼。",
                     water=[(-18, -26, 36, 52)], bridges=[(-20, -4.5, 40, 9), (-7, -7, 14, 14)],
                     mountains=[(x, z, 8, 10) for x in (-36, 28) for z in (-20, 10)],
                     buildings=starts(60, [-39, 0, 39]) + mirrored([40], [-39, 0, 39]) + mirrored([60, 39], [-19.5, 19.5])
                     + mirrored([26], [-39, 0, 39], 1, 25) + mirrored([52], [-44, -10.5, 10.5, 44], 2, 18)
                     + [building(0, z, 1 if z == 0 else 0, population=35 if z == 0 else 22) for z in (-41, 0, 41)]))
    # Wide, deliberately placed earth ramps are the only ways across cliff edges.
    maps.append(dict(common, id="terraces", title="叠翠台地", half=(44, 32),
                     description="四条宽土坡通向中央台地，坡顶炮塔控制近路。沿南北低地绕行，可以避开正面争坡并抢占两翼工坊。",
                     heights=[((-12, -12, 24, 24), 4.5, 4.5, 0),
                              ((-26, -6, 14, 12), 0, 4.5, 0), ((12, -6, 14, 12), 4.5, 0, 0),
                              ((-6, -24, 12, 12), 0, 4.5, 1), ((-6, 12, 12, 12), 4.5, 0, 1)],
                     buildings=starts(34, [0]) + mirrored([33], [-20, 20])
                     + mirrored([18], [-23, 23], 2, 20) + [building(0, 0, 1, population=36)]))
    maps.append(dict(medium, id="switchback", title="盘山双关", half=(54, 44), color=(0.37, 0.465, 0.215),
                     description="南北两座台地由二段土坡连接八米高的山脊要塞。可以沿坡逐层推进，也能走山脚与外沿山道换线包抄。",
                     heights=[((-18, -36, 36, 18), 4.5, 4.5, 0), ((-18, 18, 36, 18), 4.5, 4.5, 0),
                              ((-8, -6, 16, 12), 8, 8, 0), ((-6, -18, 12, 12), 4.5, 8, 1),
                              ((-6, 6, 12, 12), 8, 4.5, 1)]
                     + [((x, z, 16, 12), a, b, 0) for x, a, b in [(-34, 0, 4.5), (18, 4.5, 0)] for z in (-33, 21)],
                     buildings=starts(43, [-27, 27]) + mirrored([42], [-9, 9])
                     + mirrored([28], [0], 2, 20) + mirrored([10], [-27, 27], 0, 24)
                     + [building(0, 0, 1, population=42)]))
    maps.append(dict(large, id="crown", title="云冠盆地", half=(76, 58), color=(0.355, 0.455, 0.22),
                     description="环形高地围住林间盆地，六处外坡连接三条战线，两处内坡通向腹地。夺取坡顶哨塔，或借盆地工坊组织跨线支援。",
                     water=[(-12, -58, 24, 10), (-12, 48, 24, 10)],
                     heights=[((-36, -36, 72, 16), 5, 5, 0), ((-36, 20, 72, 16), 5, 5, 0),
                              ((-36, -20, 16, 40), 5, 5, 0), ((20, -20, 16, 40), 5, 5, 0),
                              ((-6, -20, 12, 12), 5, 0, 1), ((-6, 8, 12, 12), 0, 5, 1)]
                     + [((x, z, 16, 12), a, b, 0) for x, a, b in [(-52, 0, 5), (36, 5, 0)] for z in (-32, -6, 20)],
                     buildings=starts(64, [-30, 0, 30]) + mirrored([62], [-16, 16])
                     + mirrored([18], [-28, 28], 1, 28) + mirrored([28], [0], 0, 24)
                     + mirrored([12], [-11, 11], 0, 18) + [building(0, 0, 2, population=30)]))
    return maps


def inside(region, x, z, margin=0):
    rx, rz, w, h = region
    return rx - margin < x < rx + w + margin and rz - margin < z < rz + h + margin


def walkable(layout, x, z):
    if abs(x) > layout["half"][0] or abs(z) > layout["half"][1]:
        return False
    return any(inside(r, x, z) for r in layout["bridges"]) or not any(inside(r, x, z) for r in layout["water"] + layout["mountains"])


def scene_path(layout):
    return "res://scenes/block_war/map.tscn" if layout["id"] == "rift" else f'res://scenes/block_war/maps/{layout["id"]}.tscn'


def terrain_axes(layout):
    # Match the authored Land partition, including the outer woodland apron.
    # Water endpoints can extend farther than half_size + 24 (the rift map).
    hx, hz = layout["half"]
    xs = sorted({-hx - 24, hx + 24} | {r[0] + d for r in layout["water"] for d in (0, r[2])})
    zs = sorted({-hz - 24, hz + 24} | {r[1] + d for r in layout["water"] for d in (0, r[3])})
    return xs, zs


def write_definition(layout):
    items = layout["buildings"]
    positions = ", ".join(str(v) for x, z, *_ in items for v in (x, height_at(layout, x, z), z))
    heights = layout.get("heights", [])
    height_resources = ''
    height_property = ''
    if heights:
        height_resources = '[ext_resource type="Script" path="res://scripts/block_war/war_height_zone.gd" id="height_zone"]\n\n'
        for index, (region, start, end, axis) in enumerate(heights):
            height_resources += f'[sub_resource type="Resource" id="Height{index}"]\nscript = ExtResource("height_zone")\nregion = {vec(region, "Rect2")}\nstart_height = {float(start)}\nend_height = {float(end)}\naxis = {axis}\n\n'
        height_property = 'height_zones = Array[ExtResource("height_zone")]([' + ', '.join(f'SubResource("Height{i}")' for i in range(len(heights))) + '])\n'
    xs, zs = terrain_axes(layout)
    camera_bounds = (xs[0], zs[0], xs[-1] - xs[0], zs[-1] - zs[0])
    text = f'''[gd_resource type="Resource" script_class="WarMapDefinition" format=3]

[ext_resource type="Script" path="res://scripts/block_war/war_map_definition.gd" id="script"]

{height_resources}[resource]
script = ExtResource("script")
map_id = "{layout['id']}"
title = "{layout['title']}"
size_class = {layout['size']}
team_size = {layout['team']}
scene_path = "{scene_path(layout)}"
routes_path = "res://data/block_war/routes/{layout['id']}.res"
description = "{layout['description']}"
half_size = {vec(layout['half'], 'Vector2')}
camera_bounds = {vec(camera_bounds, 'Rect2')}
ground_color = {vec((*layout['color'], 1), 'Color')}
water_regions = {rects(layout['water'])}
mountain_regions = {rects(layout['mountains'])}
bridges = {rects(layout['bridges'])}
{height_property}building_positions = PackedVector3Array({positions})
building_kinds = PackedInt32Array({', '.join(str(b[2]) for b in items)})
building_factions = PackedInt32Array({', '.join(str(b[3]) for b in items)})
'''
    target = ROOT / f'data/block_war/maps/{layout["id"]}.tres'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def author(layout):
    items, (hx, hz) = layout["buildings"], layout["half"]
    paths = author_paths(layout)
    assert len(layout["bridges"]) <= 16
    externals = [
        '[ext_resource type="Script" path="res://scripts/block_war/war_map.gd" id="script"]',
        f'[ext_resource type="Resource" path="res://data/block_war/maps/{layout["id"]}.tres" id="definition"]',
        '[ext_resource type="PackedScene" path="res://scenes/block_war/building.tscn" id="building"]',
        f'[ext_resource type="Shader" path="{ENV}map_ground.gdshader" id="ground_shader"]',
        f'[ext_resource type="Texture2D" path="{ENV}meadow_noise.tres" id="noise"]',
    ]
    resources = [f'''[sub_resource type="ShaderMaterial" id="Ground"]
shader = ExtResource("ground_shader")
shader_parameter/meadow_noise = ExtResource("noise")
shader_parameter/half_size = {vec((hx, hz), 'Vector2')}
shader_parameter/meadow = {vec((*layout['color'], 1), 'Color')}
shader_parameter/site_count = {len(items)}
shader_parameter/sites = PackedVector2Array({', '.join(str(v) for b in [b[:2] for b in items] + [(0, 0)] * (64 - len(items)) for v in b)})
shader_parameter/path_count = {len(paths)}
shader_parameter/paths = PackedVector4Array({', '.join(str(v) for path in paths + [(0, 0, 0, 0)] * (64 - len(paths)) for v in path)})
shader_parameter/bridge_count = {len(layout['bridges'])}
shader_parameter/bridge_regions = PackedVector4Array({', '.join(str(v) for region in layout['bridges'] + [(0, 0, 0, 0)] * (16 - len(layout['bridges'])) for v in region)})''',
        '[sub_resource type="BoxMesh" id="Cube"]\nsize = Vector3(1, 1, 1)']
    water_paths = 'NodePath("Terrain/Water")' if layout["water"] else ''
    nodes = [f'[node name="WarMap" type="Node3D"]\nscript = ExtResource("script")\ndefinition = ExtResource("definition")\nwater_paths = Array[NodePath]([{water_paths}])']
    nodes += [f'[node name="{name}" type="Node3D" parent="."]' for name in ("Terrain", "Bridges", "Nature", "Buildings")]

    # Land ends at the conservative navigation boundary. Authored grass lips
    # extend into forbidden water, never exposing water beneath a valid route.
    xs, zs = terrain_axes(layout)
    for ix, (left, right) in enumerate(zip(xs, xs[1:])):
        for iz, (top, bottom) in enumerate(zip(zs, zs[1:])):
            x, z = (left + right) / 2, (top + bottom) / 2
            if not any(inside(r, x, z) for r in layout["water"]):
                nodes.append(f'[node name="Land{ix}_{iz}" type="MeshInstance3D" parent="Terrain"]\nlayers = 524289\nposition = {vec((x, -1.6, z))}\nscale = {vec((right - left, 3.2, bottom - top))}\nmesh = SubResource("Cube")\nmaterial_override = SubResource("Ground")')
    if layout["water"]:
        externals.append(f'[ext_resource type="Shader" path="{ENV}map_water.gdshader" id="water_shader"]')
        externals.extend([
            f'[ext_resource type="Texture2D" path="{ENV}water_noise.tres" id="water_noise"]',
            f'[ext_resource type="Texture2D" path="{ENV}water_normals.tres" id="water_normals"]',
            f'[ext_resource type="Material" path="{ENV}shore_rock.tres" id="shore_rock_material"]',
        ])
        resources.append('[sub_resource type="ShaderMaterial" id="Water"]\nshader = ExtResource("water_shader")\nshader_parameter/surface_noise = ExtResource("water_noise")\nshader_parameter/wave_normals = ExtResource("water_normals")')
        for layer, name in (("bank_grass", "ShoreGrass"), ("bank_stone", "ShoreRock"), ("water", "Water")):
            externals.append(f'[ext_resource type="ArrayMesh" path="{ENV}maps/{layout["id"]}_{layer}.res" id="shore_{layer}"]')
            material = {"water": 'SubResource("Water")', "bank_grass": 'SubResource("Ground")', "bank_stone": 'ExtResource("shore_rock_material")'}[layer]
            override = f'\nmaterial_override = {material}'
            receiver = '\nlayers = 524289' if layer != 'water' else ''
            nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="Terrain"]{receiver}\nmesh = ExtResource("shore_{layer}"){override}')
    if layout.get("heights"):
        externals.append(f'[ext_resource type="Material" path="{ENV}upland_cliff.tres" id="cliff_material"]')
        for layer, material in (("upland", 'SubResource("Ground")'), ("cliffs", 'ExtResource("cliff_material")')):
            externals.append(f'[ext_resource type="ArrayMesh" path="{ENV}maps/{layout["id"]}_{layer}.res" id="{layer}"]')
            nodes.append(f'[node name="{layer.title()}" type="MeshInstance3D" parent="Terrain"]\nlayers = 524289\nmesh = ExtResource("{layer}")\nmaterial_override = {material}')
    ext, sub, children = author_bridges(layout)
    externals.extend(ext)
    resources.extend(sub)
    nodes.extend(children)
    ext, sub, children = author_nature(layout, paths)
    externals.extend(ext)
    resources.extend(sub)
    nodes.extend(children)
    for i, (x, z, kind, faction, population) in enumerate(items):
        nodes.append(f'[node name="Building{i}" parent="Buildings" instance=ExtResource("building")]\nposition = {vec((x, height_at(layout, x, z), z))}\nbuilding_id = {i}\nfaction = {faction}\nkind = {kind}\npopulation = {float(population)}')
    return "\n\n".join([f"[gd_scene load_steps={len(externals) + len(resources) + 1} format=3]"] + externals + resources + nodes) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--definitions-only", action="store_true", help="Update bank inputs before baking changed terrain")
    parser.add_argument("--map", choices=tuple(layout["id"] for layout in layouts()),
                        help="Author one map without rewriting the other saved scenes")
    args = parser.parse_args()
    for layout in layouts():
        if args.map and layout["id"] != args.map:
            continue
        for x, z, *_ in layout["buildings"]:
            assert walkable(layout, x, z), (layout["id"], x, z)
            assert supported_footprint(layout, x, z, 4.5), (layout["id"], "building needs a level yard", x, z)
        write_definition(layout)
        if not args.definitions_only:
            target = ROOT / scene_path(layout).removeprefix("res://")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(author(layout), encoding="utf-8")
        print(f'{layout["id"]}: {layout["half"][0] * 2} x {layout["half"][1] * 2}, {layout["team"]}v{layout["team"]}, {len(layout["buildings"])} buildings')


if __name__ == "__main__":
    main()
