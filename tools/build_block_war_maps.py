"""Author five editable battlefields and a six-map Resource catalog.

All terrain, bridges, buildings and scenery are saved as native scene nodes.
The original rift scene is retained; no runtime node or image generation is used.
"""
from __future__ import annotations

from pathlib import Path
import re

from block_war_bridge_authoring import author_bridges
from block_war_nature_authoring import author_nature
from block_war_path_authoring import author_paths

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
    original = (ROOT / "scenes/block_war/map.tscn").read_text(encoding="utf-8")
    homes = []
    for record in re.findall(r'\[node name="Building\d+" parent="Buildings"[^\[]+', original):
        x, _, z = map(float, re.search(r"position = Vector3\(([^)]+)\)", record)[1].split(","))
        def number(key):
            return float(re.search(rf"^{key} = ([^\n]+)", record, re.M)[1])
        homes.append((x, z, int(number("kind")), int(number("faction")), number("population")))
    common = dict(size=0, half=(40, 28), team=1, water=[], mountains=[], bridges=[], color=(0.29, 0.405, 0.235))
    maps = [dict(common, id="rift", title="裂谷交汇", description="两道溪谷、四座石桥。保留原有的小型战场，争夺中央住宅与桥头炮塔。", buildings=homes,
                 water=[(-15, -68, 6, 136), (9, -68, 6, 136)], bridges=[(x, z - 3.2, 6, 6.4) for x in (-15, 9) for z in (-14, 14)])]
    maps.append(dict(common, id="lake", title="林湖回廊", half=(40, 30), description="湖泊隔开两军，南北两条林间回廊连接战场。绕行扩张与侧翼增援同样重要。",
                     water=[(-9, -12, 18, 24)], buildings=starts(30, [0]) + mirrored([30], [-20, 20]) + mirrored([18], [0], 2, 18)
                     + [building(0, z, population=20) for z in (-22, 22)] + mirrored([14], [-22, 22], 1, 22)))
    medium = dict(common, size=1, half=(60, 44), team=2)
    maps.append(dict(medium, id="rivers", title="双河平原", description="双河上的六座宽桥形成三条战线。两位队友分别扩张上下区域，在中央平原会合。",
                     water=[(-17, -68, 6, 136), (11, -68, 6, 136)], bridges=[(x, z - 4, 6, 8) for x in (-17, 11) for z in (-26, 0, 26)],
                     buildings=starts(48, [-26, 26]) + mirrored([48], [-6, 6]) + mirrored([28], [-30, 30])
                     + mirrored([28], [-7, 7], 1, 22) + mirrored([38], [-17, 17], 2, 18)
                     + [building(0, z, 1 if z == 0 else 0, population=30 if z == 0 else 20) for z in (-32, -16, 0, 16, 32)]))
    maps.append(dict(medium, id="ridges", title="断脊山道", color=(0.355, 0.405, 0.285), description="两段岩脊将战场分成中央谷口和两端山道。队友可以守住谷口，也可沿外围迂回。",
                     mountains=[(-6, -34, 12, 20), (-6, 14, 12, 20)],
                     buildings=starts(48, [-26, 26]) + mirrored([48], [-6, 6]) + mirrored([30], [-30, 30])
                     + mirrored([30], [-10, 10], 2, 18) + mirrored([16], [-22, 22], 1, 24)
                     + mirrored([14], [-39, 39]) + [building(0, 0, 2, population=28)] + mirrored([14], [0], 0, 20)))
    large = dict(common, size=2, half=(84, 60), team=3)
    maps.append(dict(large, id="islands", title="群岛长滩", description="三片中央岛屿、八座桥梁连接三条主战线。每位队友经营一翼，跨岛调兵支援薄弱方向。",
                     water=[(-28, -84, 8, 168), (20, -84, 8, 168), (-20, -25, 40, 8), (-20, 17, 40, 8)],
                     bridges=[(x, z - 5, 8, 10) for x in (-28, 20) for z in (-42, 0, 42)] + [(-4, z, 8, 8) for z in (-25, 17)],
                     buildings=starts(68, [-42, 0, 42]) + mirrored([46], [-42, 0, 42]) + mirrored([68, 46], [-21, 21])
                     + [building(x, z, 2 if x == 0 else 0, population=22) for z in (-42, 0, 42) for x in (-10, 0, 10)]
                     + mirrored([78], [-35, 10, 35], 2, 18) + mirrored([34], [-42, 0, 42], 1, 25)))
    maps.append(dict(large, id="highland", title="环湖高原", half=(84, 64), color=(0.34, 0.395, 0.255), description="宽阔湖面围绕中央石台，南北高原与中央长桥形成三条不同长度的通道。控制中央也要兼顾两翼。",
                     water=[(-20, -30, 40, 60)], bridges=[(-22, -4.5, 44, 9), (-8, -8, 16, 16)],
                     buildings=starts(68, [-44, 0, 44]) + mirrored([46], [-44, 0, 44]) + mirrored([68, 44], [-22, 22])
                     + mirrored([30], [-44, 0, 44], 1, 25) + mirrored([58], [-50, -12, 12, 50], 2, 18)
                     + [building(0, z, 1 if z == 0 else 0, population=35 if z == 0 else 22) for z in (-46, 0, 46)]))
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


def write_definition(layout):
    items = layout["buildings"]
    positions = ", ".join(str(v) for x, z, *_ in items for v in (x, 0, z))
    text = f'''[gd_resource type="Resource" script_class="WarMapDefinition" format=3]

[ext_resource type="Script" path="res://scripts/block_war/war_map_definition.gd" id="script"]

[resource]
script = ExtResource("script")
map_id = "{layout['id']}"
title = "{layout['title']}"
size_class = {layout['size']}
team_size = {layout['team']}
scene_path = "{scene_path(layout)}"
routes_path = "res://data/block_war/routes/{layout['id']}.res"
description = "{layout['description']}"
half_size = {vec(layout['half'], 'Vector2')}
ground_color = {vec((*layout['color'], 1), 'Color')}
water_regions = {rects(layout['water'])}
mountain_regions = {rects(layout['mountains'])}
bridges = {rects(layout['bridges'])}
building_positions = PackedVector3Array({positions})
building_kinds = PackedInt32Array({', '.join(str(b[2]) for b in items)})
building_factions = PackedInt32Array({', '.join(str(b[3]) for b in items)})
'''
    target = ROOT / f'data/block_war/maps/{layout["id"]}.tres'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def author(layout):
    items, (hx, hz) = layout["buildings"], layout["half"]
    paths = author_paths(layout)
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
shader_parameter/paths = PackedVector4Array({', '.join(str(v) for path in paths + [(0, 0, 0, 0)] * (64 - len(paths)) for v in path)})''',
        '[sub_resource type="BoxMesh" id="Cube"]\nsize = Vector3(1, 1, 1)']
    water_paths = 'NodePath("Terrain/Water")' if layout["water"] else ''
    nodes = [f'[node name="WarMap" type="Node3D"]\nscript = ExtResource("script")\ndefinition = ExtResource("definition")\nwater_paths = Array[NodePath]([{water_paths}])']
    nodes += [f'[node name="{name}" type="Node3D" parent="."]' for name in ("Terrain", "Bridges", "Nature", "Buildings")]

    # Land ends at the conservative navigation boundary. Authored grass lips
    # extend into forbidden water, never exposing water beneath a valid route.
    xs = sorted({-hx - 24, hx + 24} | {r[0] + d for r in layout["water"] for d in (0, r[2])})
    zs = sorted({-hz - 24, hz + 24} | {r[1] + d for r in layout["water"] for d in (0, r[3])})
    for ix, (left, right) in enumerate(zip(xs, xs[1:])):
        for iz, (top, bottom) in enumerate(zip(zs, zs[1:])):
            x, z = (left + right) / 2, (top + bottom) / 2
            if not any(inside(r, x, z) for r in layout["water"]):
                nodes.append(f'[node name="Land{ix}_{iz}" type="MeshInstance3D" parent="Terrain"]\nposition = {vec((x, -1.6, z))}\nscale = {vec((right - left, 3.2, bottom - top))}\nmesh = SubResource("Cube")\nmaterial_override = SubResource("Ground")')
    if layout["water"]:
        externals.append(f'[ext_resource type="Shader" path="{ENV}map_water.gdshader" id="water_shader"]')
        resources.append('[sub_resource type="ShaderMaterial" id="Water"]\nshader = ExtResource("water_shader")\nshader_parameter/surface_noise = ExtResource("noise")')
        resources.append('[sub_resource type="StandardMaterial3D" id="BankStone"]\nalbedo_color = Color(1, 1, 1, 1)\nvertex_color_use_as_albedo = true\nvertex_color_is_srgb = true\nroughness = 0.93')
        for layer, name in (("bank_grass", "ShoreGrass"), ("bank_stone", "ShoreRock"), ("water", "Water")):
            externals.append(f'[ext_resource type="ArrayMesh" path="{ENV}maps/{layout["id"]}_{layer}.res" id="shore_{layer}"]')
            material = {"water": "Water", "bank_grass": "Ground", "bank_stone": "BankStone"}[layer]
            override = f'\nmaterial_override = SubResource("{material}")'
            nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="Terrain"]\nmesh = ExtResource("shore_{layer}"){override}')
    ext, sub, children = author_bridges(layout)
    externals.extend(ext)
    resources.extend(sub)
    nodes.extend(children)
    ext, sub, children = author_nature(layout, paths)
    externals.extend(ext)
    resources.extend(sub)
    nodes.extend(children)
    for i, (x, z, kind, faction, population) in enumerate(items):
        nodes.append(f'[node name="Building{i}" parent="Buildings" instance=ExtResource("building")]\nposition = {vec((x, 0, z))}\nbuilding_id = {i}\nfaction = {faction}\nkind = {kind}\npopulation = {float(population)}')
    return "\n\n".join([f"[gd_scene load_steps={len(externals) + len(resources) + 1} format=3]"] + externals + resources + nodes) + "\n"


def main():
    for layout in layouts():
        for x, z, *_ in layout["buildings"]:
            assert walkable(layout, x, z), (layout["id"], x, z)
        write_definition(layout)
        if layout["id"] != "rift":
            target = ROOT / scene_path(layout).removeprefix("res://")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(author(layout), encoding="utf-8")
        print(f'{layout["id"]}: {layout["half"][0] * 2} x {layout["half"][1] * 2}, {layout["team"]}v{layout["team"]}, {len(layout["buildings"])} buildings')


if __name__ == "__main__":
    main()
