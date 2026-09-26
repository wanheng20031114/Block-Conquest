"""Author the woodland battlefield as editable native Godot scene nodes.

Preserves the thirteen gameplay buildings; groups 46 navigation trunks into groves.
The running game loads saved meshes and never generates environment nodes.
Run tools/bake_war_map_details.gd first; --plan only prints scene counts.
"""
from __future__ import annotations

import argparse
from collections import Counter
import math
from pathlib import Path
import random
import re
from war_nature_placement import ShoreSupport

ROOT = Path(__file__).resolve().parents[1]
MAP = ROOT / "scenes/block_war/map.tscn"
NATURE = "res://assets/models/block_war/nature/"
ENVIRONMENT = "res://assets/block_war/environment/"
SPECIES = ("canopy_oak", "silver_birch", "wind_pine", "weeping_willow", "hazel_thicket", "moss_boulder", "fern_patch", "meadow_tuft", "reed_cluster", "daisies", "bluebells")
DETAILS = ("fieldstone_block", "stone_bridge_deck", "stone_bridge_coping", "stone_bridge_pier", "stone_bridge_arch", "stone_bridge_paving", "meadow_bank_grass", "meadow_bank_stone")
BATCHED = ("fern_patch", "meadow_tuft", "daisies", "bluebells")


def vector(values: tuple[float, ...]) -> str:
    return "Vector3(" + ", ".join(f"{v:.6f}".rstrip("0").rstrip(".") if v else "0" for v in values) + ")"


def attribute(block: str, name: str) -> str:
    found = re.search(rf'\b{name}="([^"]+)"', block.splitlines()[0])
    return found[1] if found else ""


def position(block: str) -> tuple[float, float, float]:
    return tuple(map(float, re.search(r"^position = Vector3\(([^)]+)\)", block, re.M)[1].split(",")))


def author(source: str) -> tuple[str, dict[str, int]]:
    blocks = [block.strip() for block in re.split(r"(?=^\[node\b)", source, flags=re.M)]
    buildings = [block for block in blocks if block.startswith("[node") and attribute(block, "parent") == "Buildings"]
    trees = [block for block in blocks if block.startswith("[node") and attribute(block, "name").startswith("WayfindingTree")]
    assert len(buildings) == 13, "All 13 gameplay building records must be retained"
    assert len(trees) == 46, "All 46 navigation trunks must be retained"
    rng = random.Random(922094)
    counts: Counter[str] = Counter()
    waters = [(-15, -68, 6, 136), (9, -68, 6, 136)]
    support = ShoreSupport("rift", waters)
    tree_sites = []
    rock_sites = []
    externals = [
        '[ext_resource type="Script" path="res://scripts/block_war/war_map.gd" id="script"]',
        '[ext_resource type="PackedScene" path="res://scenes/block_war/building.tscn" id="building"]',
        f'[ext_resource type="Shader" path="{ENVIRONMENT}river.gdshader" id="water_shader"]',
        f'[ext_resource type="Material" path="{ENVIRONMENT}meadow_ground.tres" id="meadow_ground"]',
        f'[ext_resource type="Texture2D" path="{ENVIRONMENT}water_noise.tres" id="water_noise"]',
        f'[ext_resource type="Texture2D" path="{ENVIRONMENT}water_normals.tres" id="water_normals"]',
        f'[ext_resource type="Material" path="{ENVIRONMENT}shore_rock.tres" id="shore_rock_material"]',
    ]
    externals += [f'[ext_resource type="PackedScene" path="{NATURE}{name}.tscn" id="nature_{name}"]' for name in SPECIES if name not in BATCHED]
    externals += [f'[ext_resource type="ArrayMesh" path="{NATURE}{name}_combined.res" id="plant_mesh_{name}"]' for name in BATCHED]
    externals.append(f'[ext_resource type="Material" path="{NATURE}grass.tres" id="plant_material"]')
    externals += [f'[ext_resource type="ArrayMesh" path="{ENVIRONMENT}{name}.res" id="detail_{name}"]' for name in DETAILS]
    resources = ['[sub_resource type="ShaderMaterial" id="River"]\nshader = ExtResource("water_shader")\nshader_parameter/surface_noise = ExtResource("water_noise")\nshader_parameter/wave_normals = ExtResource("water_normals")']
    palettes = {"Limestone": (0.59, 0.585, 0.535), "LightStone": (0.67, 0.65, 0.595), "MossStone": (0.41, 0.44, 0.36), "Recess": (0.38, 0.395, 0.35)}
    for name, rgb in palettes.items():
        resources.append(f'[sub_resource type="StandardMaterial3D" id="{name}"]\nalbedo_color = Color({", ".join(map(str, rgb))}, 1)\nroughness = 0.89')
    resources.append('[sub_resource type="StandardMaterial3D" id="PaintedStone"]\nalbedo_color = Color(0.84, 0.86, 0.94, 1)\nvertex_color_use_as_albedo = true\nvertex_color_is_srgb = true\nroughness = 0.90')
    for name, size in (("OuterLand", (85, 3.2, 136)), ("CentralLand", (18, 3.2, 136)), ("Water", (6.06, 0.045, 136))):
        resources.append(f'[sub_resource type="BoxMesh" id="{name}"]\nsize = {vector(size)}')
    nodes = ['[node name="WarMap" type="Node3D"]\nscript = ExtResource("script")']
    nodes += [f'[node name="{name}" type="Node3D" parent="."]' for name in ("Terrain", "Cliffs", "Bridges", "Roads", "Nature", "Buildings")]
    batches: dict[tuple[str, int, int], list[tuple[float, ...]]] = {}

    def mesh(name: str, parent: str, asset: str, pos=(0, 0, 0), scale=(1, 1, 1), material="Limestone", rotation=(0, 0, 0)) -> None:
        material_ref = f'ExtResource("{material}")' if material in ("meadow_ground", "shore_rock_material") else f'SubResource("{material}")'
        mesh_ref = f'SubResource("{asset}")' if asset in ("OuterLand", "CentralLand", "Water") else f'ExtResource("detail_{asset}")'
        nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]\nposition = {vector(pos)}\nrotation = {vector(rotation)}\nscale = {vector(scale)}\nmesh = {mesh_ref}\nmaterial_override = {material_ref}')
        counts["environment_mesh"] += 1

    def plant(name: str, species: str, x: float, y: float, z: float, size: float, yaw: float | None = None, proportions=(1, 1, 1), radius=0.0) -> None:
        yaw = rng.uniform(0, math.tau) if yaw is None else yaw
        scale = tuple(size * component for component in proportions)
        counts[species] += 1
        if species in BATCHED:
            cell = (species, math.floor(x / 32), math.floor(z / 32))
            batches.setdefault(cell, []).append((x, y, z, *scale, yaw))
            return
        nodes.append(f'[node name="{name}" parent="Nature" instance=ExtResource("nature_{species}")]\nposition = {vector((x, y, z))}\nrotation = {vector((0, yaw, 0))}\nscale = {vector(scale)}')
        if radius > 0:
            nodes[-1] += f'\nmetadata/route_radius = {radius / scale[0]:.6f}'
        if species in ("canopy_oak", "silver_birch", "wind_pine", "weeping_willow"):
            tree_sites.append((x, z, .72 * size))

    # Walkable surfaces stay at y=0. Slopes occupy only excluded river channels.
    for name, x, asset in (("WestLand", -57.5, "OuterLand"), ("HeartLand", 0, "CentralLand"), ("EastLand", 57.5, "OuterLand")):
        mesh(name, "Terrain", asset, (x, -1.6, 0), material="meadow_ground")
    for index, x in enumerate((-12, 12)):
        mesh(f"River{index}", "Terrain", "Water", (x, -1.42, 0), material="River")
    mesh("SculptedGrassLips", "Cliffs", "meadow_bank_grass", material="meadow_ground")
    mesh("WarmStoneSlopes", "Cliffs", "meadow_bank_stone", material="shore_rock_material")
    nodes.extend(buildings)

    # Copings begin beyond z +/-3.2: the full 6.4m army corridor stays free.
    for index, (x, z) in enumerate(((-12, -14), (-12, 14), (12, -14), (12, 14))):
        parent = f"Bridges/Bridge{index}"
        nodes.append(f'[node name="Bridge{index}" type="Node3D" parent="Bridges"]\nposition = {vector((x, 0, z))}')
        mesh("StoneDeck", parent, "stone_bridge_deck", (0, -0.145, 0), material="Recess")
        mesh("DressedPaving", parent, "stone_bridge_paving", (0, -0.016, 0), material="PaintedStone")
        for side in (-1, 1):
            mesh(f"OpenArch{side}", parent, "stone_bridge_arch", (0, 0, side * 3.65), material="PaintedStone")
            mesh(f"LowCoping{side}", parent, "stone_bridge_coping", (0, 0.13, side * 3.55), material="LightStone")
            for end in (-1, 1):
                mesh(f"Abutment{side}_{end}", parent, "stone_bridge_pier", (end * 4.04, -1, side * 3.67))
                mesh(f"Capstone{side}_{end}", parent, "fieldstone_block", (end * 4.04, 0.25, side * 3.67), (1.12, 0.40, 0.88), "LightStone")
                mesh(f"Wingwall{side}_{end}", parent, "fieldstone_block", (end * 5.05, -0.32, side * 3.83), (1.70, 1.02, 0.62), "MossStone", (0, side * end * 0.23, 0))
                plant(f"BridgeheadGrass{index}_{side}_{end}", "meadow_tuft", x + end * 5.45, -0.015, z + side * 4.18, 0.72)
        counts["stone_bridge"] += 1

    # Deliberate groves replace the old single-file perimeter fence. Two small
    # inner landmarks remain; full bridge corridors and settlement yards stay open.
    authored_trunks = []
    for sign in (-1, 1):
        for cx, cz in ((37.3, -23.5), (38.5, -.8), (37.8, 21.2)):
            for dx, dz, size in ((0, 0, 1.02), (1.9, 1.1, .87), (-.1, 2.6, .63)):
                authored_trunks.append((sign * (cx + dx), cz + dz, size))
        for cz in (-28.2, 28.2):
            for dx, dz, size in ((-2.1, 0, .98), (.5, -1, 1.04), (2.7, .5, .81), (.9, 1.8, .59)):
                authored_trunks.append((sign * (24.7 + dx), cz + dz, size))
        for cz in (-29, 29):
            for dx, dz, size in ((0, 0, .91), (.9, 2.0, .63)):
                authored_trunks.append((sign * (4.6 + dx), cz + dz, size))
    authored_trunks += [(-35, -8, .84), (35, 8, .84), (-5, -5, .76), (5, 5, .76)]
    assert len(authored_trunks) == len(trees)
    for index, (x, z, size) in enumerate(authored_trunks):
        species = ("canopy_oak", "canopy_oak", "silver_birch", "wind_pine")[index % 4]
        plant(f"WayfindingTree{index}", species, x, 0, z, size, radius=.72 * size)
        counts["navigation_tree"] += 1
        if index % 3 == 0:
            plant(f"TrunkFern{index}", "fern_patch", x + 0.55, -0.015, z + 0.30, 0.60)
        if index % 2 == 0:
            plant(f"TrunkGrass{index}", "meadow_tuft", x - 0.48, -0.015, z + 0.4, 0.62)
        if index % 5 == 1:
            plant(f"TrunkFlowers{index}", "bluebells", x - 0.65, 0, z + 0.60, 0.60)

    # Uneven forest groups frame the clearing without adding navigation trunks.
    groves = [(-46, -23, 6), (-46, 1, 7), (-46, 24, 6), (46, -25, 6), (47, 0, 7), (46, 25, 6),
              (-29, -36, 6), (0, -37, 4), (29, -36, 6), (-29, 37, 5), (0, 37, 3), (29, 37, 5)]
    for grove, (cx, cz, count) in enumerate(groves):
        for index in range(count):
            angle = index * 2.39996 + grove * 0.48
            spread = 0.3 + 1.65 * math.sqrt(index)
            x, z = cx + math.cos(angle) * spread, cz + math.sin(angle) * spread * 0.76
            if abs(x) < 41.5 and abs(z) < 31.0 or 7.7 < abs(x) < 16.7:
                continue
            if any(math.hypot(x - tx, z - tz) < tr + .9 for tx, tz, tr in tree_sites):
                continue
            species = ("canopy_oak", "silver_birch", "canopy_oak", "wind_pine")[(grove + index) % 4]
            size = rng.uniform(0.49, 0.63) if index % 4 == 2 else rng.uniform(0.78, 1.08)
            plant(f"FramingTree{grove}_{index}", species, x, 0, z, size)
            if index % 2 == 0:
                plant(f"ForestUnderstory{grove}_{index}", "hazel_thicket", x - 1.1, 0, z + 0.4, rng.uniform(0.64, 0.98))
            if index % 3 == 0:
                plant(f"ForestFloor{grove}_{index}", "fern_patch", x + 0.82, -0.015, z + 0.54, rng.uniform(0.65, 0.86))
            if index % 4 == 0:
                plant(f"ForestGrass{grove}_{index}", "meadow_tuft", x - 0.75, -0.015, z - 0.32, rng.uniform(0.65, 0.85))
    for index, (x, z) in enumerate(((-18.5, -31), (18.8, -32), (-5.4, 31.5), (5.8, -33), (-19, 32), (19.5, 32))):
        plant(f"WatersideWillow{index}", "weeping_willow", x, 0, z, rng.uniform(0.74, 0.88))

    def rock_clear(x, z, radius):
        return (all(math.hypot(x - position(b)[0], z - position(b)[2]) > radius + 4.8 for b in buildings)
                and not any(abs(x - bx) < radius + 6.3 and abs(z - bz) < radius + 7.0
                            for bx in (-12, 12) for bz in (-14, 14))
                and all(math.hypot(x - tx, z - tz) > radius + tr + .3 for tx, tz, tr in tree_sites)
                and all(math.hypot(x - rx, z - rz) > radius + rr + .18 for rx, rz, rr in rock_sites))

    # Project every river group onto the sculpted grass lip and test its entire
    # footprint. Avoid the previous fixed Y that left rocks hanging on a wall.
    for river in (-12, 12):
        for side in (-1, 1):
            sites = (-31.5, -4.8, 27.5) if side * river > 0 else (-24.5, 4.5, 34.0)
            for index, z in enumerate(sites):
                z += rng.uniform(-1.5, 1.5)
                x = river - side * 3.0
                size = rng.uniform(.77, 1.08)
                for part, (along, factor) in enumerate(((0, 1), (1.9, .41))):
                    radius = size * factor * 1.16
                    seat = support.seat(x, z + along, radius, size * factor * .9, rock_clear)
                    if seat is None:
                        continue
                    bx, by, bz = seat
                    plant(f"RiverStone{river}_{side}_{index}_{part}", "moss_boulder", bx, by, bz,
                          size * factor, proportions=(1.08, .9, .88), radius=radius)
                    rock_sites.append((bx, bz, radius))
                    if part == 0:
                        plant(f"RiverReeds{river}_{side}_{index}", "reed_cluster", bx - side * (radius + .25), 0, bz + .2, .74)
    for group, (x, z) in enumerate(((-41, -29), (-43, 11), (-21, 31), (6, -31), (39, -29), (42, 13), (22, 31), (-3, 32))):
        size = rng.uniform(.86, 1.2)
        for part, (dx, dz, factor) in enumerate(((0, 0, 1), (size * 1.35 + .85, .35, .42))):
            radius = size * factor * 1.22
            if not rock_clear(x + dx, z + dz, radius):
                continue
            plant(f"ClearingRock{group}_{part}", "moss_boulder", x + dx, -.11 * size * factor * .92,
                  z + dz, size * factor, proportions=(1.15, .92, .78), radius=radius)
            rock_sites.append((x + dx, z + dz, radius))
        plant(f"RockGrass{group}", "meadow_tuft", x + 0.72, -0.015, z + 0.9, 0.78)
        for index in range(3):
            plant(f"ClearingFlowers{group}_{index}", "daisies" if group % 2 == 0 else "bluebells", x + 0.70 * index - 1.1, 0, z + 1.1, rng.uniform(0.70, 0.95))
    for (species, cell_x, cell_z), transforms in sorted(batches.items()):
        identifier = f"Groundcover_{species}_{cell_x}_{cell_z}".replace("-", "n")
        buffer = []
        for x, y, z, sx, sy, sz, yaw in transforms:
            cosine, sine = math.cos(yaw), math.sin(yaw)
            buffer.extend((cosine * sx, 0, sine * sz, x, 0, sy, 0, y, -sine * sx, 0, cosine * sz, z))
        serialized = ", ".join(f"{value:.6f}" for value in buffer)
        resources.append(f'[sub_resource type="MultiMesh" id="{identifier}"]\ntransform_format = 1\ninstance_count = {len(transforms)}\nmesh = ExtResource("plant_mesh_{species}")\ncustom_aabb = AABB({cell_x * 32 - 2}, -1, {cell_z * 32 - 2}, 36, 4, 36)\nbuffer = PackedFloat32Array({serialized})')
        nodes.append(f'[node name="{identifier}" type="MultiMeshInstance3D" parent="Nature"]\nmultimesh = SubResource("{identifier}")\nmaterial_override = ExtResource("plant_material")\ncast_shadow = 0')
    counts["groundcover_batches"] = len(batches)
    counts["authored_nodes"] = len(nodes)
    header = f"[gd_scene load_steps={1 + len(externals) + len(resources)} format=3]"
    return "\n\n".join([header] + externals + resources + nodes) + "\n", dict(counts)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", action="store_true", help="Show counts without writing the scene")
    args = parser.parse_args()
    output, counts = author(MAP.read_text(encoding="utf-8"))
    print("Authored woodland battlefield:", counts)
    if not args.plan:
        for name in DETAILS:
            assert (ROOT / "assets/block_war/environment" / f"{name}.res").exists(), f"Bake {name} with tools/bake_war_map_details.gd first"
        temporary = MAP.with_suffix(".tscn.tmp")
        temporary.write_text(output, encoding="utf-8", newline="\n")
        temporary.replace(MAP)
        print("Updated", MAP.relative_to(ROOT))


if __name__ == "__main__":
    main()
