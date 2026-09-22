"""Dress the existing war map with deterministic, editable native Godot nodes.

Nature, bridge decks and bank props are authored as native editable nodes.
Buildings, navigation trunk positions, bridge anchors and gameplay values stay.
Bridge deck meshes and riverbank lips use tools/bake_war_map_details.gd resources.
Run with --plan to inspect counts without changing the scene.
"""
from __future__ import annotations

import argparse
from collections import Counter
import math
from pathlib import Path
import random
import re

ROOT = Path(__file__).resolve().parents[1]
MAP = ROOT / "scenes/block_war/map.tscn"
NATURE = "res://assets/models/block_war/nature/"
SPECIES = ("canopy_oak", "silver_birch", "wind_pine", "hazel_thicket", "moss_boulder", "fern_patch", "meadow_tuft", "reed_cluster", "daisies", "bluebells")
TREE_SPECIES = SPECIES[:3]
BATCH_MESHES = {name: name + "_combined" for name in ("fern_patch", "meadow_tuft", "daisies", "bluebells")}
MAP_DETAILS = ("bridge_plank", "bridge_beam", "bridge_rail", "bridge_low_rail", "bridge_post", "bridge_brace", "bank_lip", "bank_blocks")
SEED = 922031


def vector(values: tuple[float, ...]) -> str:
    return "Vector3(" + ", ".join(f"{v:.5f}".rstrip("0").rstrip(".") if v else "0" for v in values) + ")"


def attribute(block: str, name: str) -> str:
    found = re.search(rf'\b{name}="([^"]+)"', block.splitlines()[0])
    return found[1] if found else ""


def property_vector(block: str, name: str) -> tuple[float, float, float]:
    found = re.search(rf"^{name} = Vector3\(([^)]+)\)", block, re.M)
    return tuple(map(float, found[1].split(",")))


def riverbed(x: float) -> bool:
    return 9.0 < abs(x) < 15.0


def bridge_approach(x: float, z: float, margin: float = 0.0) -> bool:
    return abs(abs(x) - 12.0) < 7.0 + margin and abs(abs(z) - 14.0) < 4.1 + margin


def bank_jut(z: float, sign: float, river_x: float) -> float:
    wave = 1.03 + sign * 0.76 * math.sin(z * 0.17 + river_x * 0.19) + 0.18 * math.cos(z * 0.49)
    bridge = max(0.0, 1.0 - abs(abs(z) - 14.0) / 4.6)
    return wave * (1.0 - bridge * 0.94)


def author(source: str) -> tuple[str, dict[str, int]]:
    rng = random.Random(SEED)
    blocks = re.split(r"(?=^\[(?:gd_scene|ext_resource|sub_resource|node|editable)\b)", source, flags=re.M)
    blocks = [block.strip() for block in blocks if block.strip()]
    trees = []
    buildings = []
    retained = []
    for block in blocks:
        if block.startswith("[gd_scene"):
            continue
        if block.startswith("[node"):
            parent = attribute(block, "parent")
            name = attribute(block, "name")
            if parent == "Buildings":
                buildings.append(property_vector(block, "position"))
            if name.startswith("WayfindingTree"):
                position = property_vector(block, "position")
                scale = property_vector(block, "scale")
                radius = float(re.search(r"metadata/route_radius = ([\d.]+)", block)[1]) * scale[0]
                trees.append((name, position, radius))
            if parent == "Nature" or parent.startswith("Nature/"):
                continue
            if parent == "Cliffs" and name.startswith(("BankRock", "BankFern", "DressedBank", "CartoonBank")):
                continue
            if parent.startswith("Bridges/Bridge"):
                if name.startswith("Deck"):
                    continue
                timber = next((mesh for prefix, mesh in (("MainBeam", "bridge_beam"), ("Handrail", "bridge_rail"), ("LowRail", "bridge_low_rail"), ("PostBinding", ""), ("Post", "bridge_post"), ("Brace", "bridge_brace")) if name.startswith(prefix)), "")
                if timber:
                    block = re.sub(r'^mesh = .*$', f'mesh = ExtResource("detail_{timber}")', block, flags=re.M)
        if block.startswith("[sub_resource") and attribute(block, "id").startswith("Dress"):
            continue
        if block.startswith("[sub_resource") and attribute(block, "id") == "CartoonBankStone":
            continue
        if block.startswith("[ext_resource") and attribute(block, "id").startswith(("nature_", "detail_")):
            continue
        retained.append(block)
    assert len(trees) == 46, f"Expected all 46 original navigation trunks, got {len(trees)}"
    assert len(buildings) == 13, "Do not regenerate a scene without its thirteen building nodes"

    nodes: list[str] = []
    counts: Counter[str] = Counter()
    tree_positions: list[tuple[float, float, float]] = []
    low_positions: list[tuple[float, float]] = []
    batches: dict[tuple[str, int, int], list[tuple[float, ...]]] = {}

    def clear_of_building(x: float, z: float, radius: float = 3.65) -> bool:
        return all((x - bx) ** 2 + (z - bz) ** 2 > radius * radius for bx, _, bz in buildings)

    def instance(name: str, species: str, x: float, y: float, z: float, scale: float, *, radius: float = 0.0, parent: str = "Nature", rotation: float | None = None) -> None:
        yaw = rng.uniform(0, math.tau) if rotation is None else rotation
        counts[species] += 1
        if species in BATCH_MESHES:
            cell = (species, math.floor(x / 16), math.floor(z / 16))
            batches.setdefault(cell, []).append((x, y, z, scale, yaw))
            low_positions.append((x, z))
            return
        properties = [f"position = {vector((x, y, z))}", f"rotation = {vector((0, yaw, 0))}", f"scale = {vector((scale, scale, scale))}"]
        if radius:
            properties.append(f"metadata/route_radius = {radius / round(scale, 5):.8f}")
        nodes.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("nature_{species}")]\n' + "\n".join(properties))
        if species in TREE_SPECIES:
            tree_positions.append((x, z, scale))
        else:
            low_positions.append((x, z))

    # Keep the proven interior trunks, changing their silhouettes by grove.
    for index, (name, position, radius) in enumerate(trees):
        x, _, z = position
        species = "silver_birch" if (x > 0 and z < -8) or (x < 0 and z > 10) else "canopy_oak"
        if index % 7 == 0 or abs(x) < 8:
            species = "wind_pine"
        scale = 0.69 + 0.14 * (0.5 + 0.5 * math.sin(x * 0.45 + z * 0.73))
        instance(name, species, x, 0.0, z, scale, radius=radius)

    # Elliptical groves, with gaps and uneven margins instead of a border grid.
    groves = [
        (-47, -23, 10, 10, 11, "wind_pine"), (-46, 2, 10, 13, 14, "canopy_oak"),
        (-48, 27, 12, 12, 12, "silver_birch"), (47, -26, 11, 11, 12, "silver_birch"),
        (48, 1, 12, 12, 14, "canopy_oak"), (47, 27, 10, 11, 11, "wind_pine"),
        (-28, -38, 14, 11, 14, "canopy_oak"), (0, -39, 6, 12, 8, "wind_pine"),
        (28, -39, 15, 12, 13, "silver_birch"), (-27, 40, 14, 12, 13, "silver_birch"),
        (0, 40, 6, 12, 7, "canopy_oak"), (29, 40, 14, 11, 13, "canopy_oak"),
        (-65, -9, 11, 23, 9, "wind_pine"), (66, 12, 12, 24, 9, "wind_pine"),
    ]
    for grove_index, (cx, cz, rx, rz, wanted, dominant) in enumerate(groves):
        accepted = 0
        for attempt in range(wanted * 70):
            if accepted == wanted:
                break
            x = cx + rng.gauss(0, rx * 0.53)
            z = cz + rng.gauss(0, rz * 0.53)
            if abs(x) < 42.5 and abs(z) < 31.5:
                continue
            if 7.7 < abs(x) < 16.3 or abs(x) > 82 or abs(z) > 62:
                continue
            if any((x - tx) ** 2 + (z - tz) ** 2 < (2.3 + 0.9 * ts) ** 2 for tx, tz, ts in tree_positions):
                continue
            species = dominant if rng.random() < 0.72 else rng.choice(TREE_SPECIES)
            scale = rng.uniform(0.85, 1.22)
            instance(f"GroveTree{grove_index}_{accepted}", species, x, 0, z, scale, radius=0.65 * scale)
            accepted += 1

    # Clusters at roots cover the seam between trunk, exposed soil and grass.
    for index, (x, z, tree_scale) in enumerate(tree_positions):
        if abs(x) > 58 or abs(z) > 43:
            continue
        count = 2 if index < 46 else 1
        for slot in range(count):
            angle = rng.uniform(0, math.tau)
            reach = rng.uniform(0.65, 1.8) * tree_scale
            px, pz = x + math.cos(angle) * reach, z + math.sin(angle) * reach
            if riverbed(px) or not clear_of_building(px, pz) or bridge_approach(px, pz):
                continue
            species = "fern_patch" if slot == 0 else "meadow_tuft"
            if slot == 1 and index % 3 == 0:
                species = "hazel_thicket"
            instance(f"RootGarden{index}_{slot}", species, px, -0.025, pz, rng.uniform(0.7, 1.0))

    # Small meadow islands sit between paths. Central combat space stays sparse.
    meadow_centers = [(-34, -10, 2.5), (-34, 11, 2.6), (-22, 22, 2.7), (-22, -23, 2.1), (-20, 6, 2.2), (34, 12, 2.6), (34, -10, 2.3), (23, -24, 2.8), (23, 22, 2.4), (20, -6, 1.8), (-5, -7, 1.6), (5, 8, 1.6), (5, -24, 1.5), (-5, 24, 1.6)]
    for cluster, (cx, cz, radius) in enumerate(meadow_centers):
        for sample in range(7):
            angle = rng.uniform(0, math.tau)
            distance = radius * math.sqrt(rng.random())
            x, z = cx + math.cos(angle) * distance, cz + math.sin(angle) * distance
            if riverbed(x) or bridge_approach(x, z) or not clear_of_building(x, z, 3.9):
                continue
            species = rng.choices(["meadow_tuft", "daisies", "bluebells", "fern_patch"], [0.66, 0.14, 0.11, 0.09])[0]
            instance(f"Meadow{cluster}_{sample}", species, x, -0.015, z, rng.uniform(0.62, 0.9))

    # Rock groups share a geological seam; never sprinkle equal pebbles in rows.
    for river_index, river_x in enumerate((-12.0, 12.0)):
        for side, sign in enumerate((1.0, -1.0)):
            edge = river_x - 3.0 if sign == 1.0 else river_x + 3.0
            for cluster, center_z in enumerate([-26, -4.5, 5.5, 26]):
                center_z += rng.uniform(-1.4, 1.4)
                for rock in range(2 if cluster % 2 else 3):
                    z = center_z + rng.uniform(-1.5, 1.5)
                    x = edge + sign * (bank_jut(z, sign, river_x) + rng.uniform(-0.06, 0.38))
                    size = rng.uniform(0.72, 0.94) if rock else rng.uniform(1.0, 1.18)
                    instance(f"DressedBankRock{river_index}_{side}_{cluster}_{rock}", "moss_boulder", x, -0.55 - size * 0.4, z, size, parent="Cliffs")
                for plant in range(3):
                    z = center_z + rng.uniform(-2.0, 2.0)
                    x = edge - sign * rng.uniform(0.1, 0.9)
                    if bridge_approach(x, z) or not clear_of_building(x, z):
                        continue
                    species = rng.choice(["fern_patch", "meadow_tuft", "bluebells"])
                    instance(f"BankGarden{river_index}_{side}_{cluster}_{plant}", species, x, 0.01, z, rng.uniform(0.65, 0.9))
                water_x = edge + sign * (bank_jut(center_z, sign, river_x) + 0.44)
                instance(f"WaterReeds{river_index}_{side}_{cluster}", "reed_cluster", water_x, -2.9, center_z, rng.uniform(0.58, 0.91))

    # Low boulders and flowers soften the timber-to-earth bridge joints without
    # moving rails or the six-file walking surface.
    for bridge_index, (bridge_x, bridge_z) in enumerate([(-12, -14), (-12, 14), (12, -14), (12, 14)]):
        for sign_x in (-1, 1):
            for sign_z in (-1, 1):
                x, z = bridge_x + sign_x * 4.9, bridge_z + sign_z * 3.8
                instance(f"BridgeFootStone{bridge_index}_{sign_x}_{sign_z}", "moss_boulder", x, -0.32, z, 0.36)
                instance(f"BridgeFootGrass{bridge_index}_{sign_x}_{sign_z}", "meadow_tuft", x + sign_x * 0.45, -0.02, z + sign_z * 0.12, 0.58)

    # Remove obsolete external references, while preserving every resource used
    # by the untouched scene blocks (including concurrent material changes).
    body = "\n\n".join(block for block in retained if not block.startswith("[ext_resource"))
    referenced = set(re.findall(r'ExtResource\("([^"]+)"\)', body))
    retained = [block for block in retained if not block.startswith("[ext_resource") or attribute(block, "id") in referenced]
    externals = [block for block in retained if block.startswith("[ext_resource")]
    resources = [block for block in retained if block.startswith("[sub_resource")]
    original_nodes = [block for block in retained if not block.startswith(("[ext_resource", "[sub_resource"))]
    for species in SPECIES:
        if species in BATCH_MESHES:
            continue
        externals.append(f'[ext_resource type="PackedScene" path="{NATURE}{species}.tscn" id="nature_{species}"]')
    externals.append(f'[ext_resource type="Material" path="{NATURE}grass.tres" id="nature_grass_material"]')
    for species, mesh in BATCH_MESHES.items():
        externals.append(f'[ext_resource type="ArrayMesh" path="{NATURE}{mesh}.res" id="nature_mesh_{species}"]')
    for mesh in MAP_DETAILS:
        externals.append(f'[ext_resource type="ArrayMesh" path="res://assets/block_war/environment/{mesh}.res" id="detail_{mesh}"]')
    resources.append('[sub_resource type="StandardMaterial3D" id="CartoonBankStone"]\nvertex_color_use_as_albedo = true\nvertex_color_is_srgb = true\nroughness = 0.88')
    nodes.append('[node name="CartoonBankLip" type="MeshInstance3D" parent="Cliffs"]\nmesh = ExtResource("detail_bank_lip")\nmaterial_override = SubResource("CartoonBankStone")')
    nodes.append('[node name="CartoonBankBlocks" type="MeshInstance3D" parent="Cliffs"]\nmesh = ExtResource("detail_bank_blocks")\nmaterial_override = SubResource("CartoonBankStone")')
    for bridge in range(4):
        for plank in range(9):
            x = (plank - 4) * 0.985
            material = "PlankLight" if (plank + bridge) % 4 == 1 else "Plank"
            nodes.append(f'[node name="Deck{plank}" type="MeshInstance3D" parent="Bridges/Bridge{bridge}"]\nposition = {vector((x, -0.135, 0))}\nmesh = ExtResource("detail_bridge_plank")\nmaterial_override = SubResource("{material}")')
            for side in (-1, 1):
                nodes.append(f'[node name="DeckNail{plank}_{side}" type="MeshInstance3D" parent="Bridges/Bridge{bridge}"]\nposition = {vector((x, 0.04, side * 2.76))}\nscale = Vector3(1.6, 1.4, 1.6)\nmesh = SubResource("Mesh_6")\nmaterial_override = SubResource("Iron")')
    for (species, cell_x, cell_z), transforms in sorted(batches.items()):
        identifier = f"Dress_{species}_{cell_x}_{cell_z}".replace("-", "n")
        buffer = []
        for x, y, z, scale, yaw in transforms:
            c, s = math.cos(yaw) * scale, math.sin(yaw) * scale
            buffer.extend([c, 0, s, x, 0, scale, 0, y, -s, 0, c, z])
        serialized = ", ".join(f"{value:.5f}" for value in buffer)
        resources.append(f'[sub_resource type="MultiMesh" id="{identifier}"]\ntransform_format = 1\ninstance_count = {len(transforms)}\nmesh = ExtResource("nature_mesh_{species}")\ncustom_aabb = AABB({cell_x * 16 - 2}, -1, {cell_z * 16 - 2}, 20, 4, 20)\nbuffer = PackedFloat32Array({serialized})')
        nodes.append(f'[node name="{identifier}" type="MultiMeshInstance3D" parent="Nature"]\nmultimesh = SubResource("{identifier}")\nmaterial_override = ExtResource("nature_grass_material")\ncast_shadow = 0')

    color_updates = {"CliffUpper": "Color(0.49, 0.465, 0.395, 1)", "CliffLower": "Color(0.37, 0.385, 0.34, 1)", "Wood": "Color(0.30, 0.205, 0.125, 1)", "Plank": "Color(0.49, 0.345, 0.21, 1)", "PlankLight": "Color(0.57, 0.415, 0.26, 1)"}
    resources = [re.sub(r"albedo_color = Color\([^\n]+", f"albedo_color = {color_updates[attribute(block, 'id')]}", block) if attribute(block, "id") in color_updates else block for block in resources]
    header = f"[gd_scene load_steps={len(externals) + len(resources) + 1} format=3]"
    return "\n\n".join([header] + externals + resources + original_nodes + nodes) + "\n", dict(counts)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", action="store_true", help="Show authored counts without writing the scene")
    args = parser.parse_args()
    output, counts = author(MAP.read_text(encoding="utf-8"))
    print("Native forest dressing:", counts, "total", sum(counts.values()))
    if not args.plan:
        required = [species + ".tscn" for species in SPECIES if species not in BATCH_MESHES] + [mesh + ".res" for mesh in BATCH_MESHES.values()]
        missing = [asset for asset in required if not (ROOT / (NATURE + asset).removeprefix("res://")).exists()]
        if missing:
            raise SystemExit("Nature scenes must be authored before applying the layout: " + ", ".join(missing))
        missing = [mesh for mesh in MAP_DETAILS if not (ROOT / "assets/block_war/environment" / (mesh + ".res")).exists()]
        if missing:
            raise SystemExit("Run tools/bake_war_map_details.gd before applying the layout: " + ", ".join(missing))
        MAP.write_text(output, encoding="utf-8", newline="\n")
        print("Updated", MAP.relative_to(ROOT))


if __name__ == "__main__":
    main()
