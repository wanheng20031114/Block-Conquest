"""Author complete, static stone bridges using the original battlefield meshes.

The returned TSCN sections are consumed by the offline map authoring tool.  All
walkable geometry remains close to y=0; no runtime nodes or depth-bias materials
are needed.  The central highland platform is authored as a disjoint union, so
its deck and paving never cover another bridge surface.
"""
from __future__ import annotations

import math


ENVIRONMENT = "res://assets/block_war/environment/"
MESH_NAMES = (
    "stone_bridge_deck",
    "stone_bridge_paving",
    "stone_bridge_arch",
    "stone_bridge_coping",
    "stone_bridge_pier",
    "fieldstone_block",
)


def _vector(values):
    return "Vector3(" + ", ".join(f"{value:.6f}".rstrip("0").rstrip(".") if value else "0" for value in values) + ")"


def _crosses_horizontally(bridge, waters):
    """Cross the river's narrow dimension, regardless of bridge road width."""
    x, z, width, depth = bridge
    crossing = [
        water for water in waters
        if x < water[0] + water[2] and x + width > water[0]
        and z < water[1] + water[3] and z + depth > water[1]
    ]
    # Every authored ordinary bridge crosses a water region.  Invalid data is an
    # authoring error, rather than a reason to silently guess a road direction.
    assert crossing, f"Bridge has no water crossing: {bridge}"
    water = min(crossing, key=lambda region: min(region[2], region[3]))
    return water[3] > water[2]


def author_bridges(layout):
    """Return (external resources, subresources, nodes) for an existing Bridges root."""
    if not layout["bridges"]:
        return [], [], []

    externals = [
        f'[ext_resource type="ArrayMesh" path="{ENVIRONMENT}{name}.res" id="bridge_mesh_{name}"]'
        for name in MESH_NAMES
    ]
    resources = []
    for name, color in {
        "Limestone": (0.59, 0.585, 0.535),
        "LightStone": (0.67, 0.65, 0.595),
        "MossStone": (0.41, 0.44, 0.36),
        "Recess": (0.38, 0.395, 0.35),
    }.items():
        resources.append(
            f'[sub_resource type="StandardMaterial3D" id="bridge_{name}"]\n'
            f'albedo_color = Color({", ".join(str(value) for value in color)}, 1)\nroughness = 0.89'
        )
    resources.append(
        '[sub_resource type="StandardMaterial3D" id="bridge_PaintedStone"]\n'
        'albedo_color = Color(0.84, 0.86, 0.94, 1)\n'
        'vertex_color_use_as_albedo = true\nvertex_color_is_srgb = true\nroughness = 0.9'
    )
    nodes = []

    def group(name, parent, position=(0, 0, 0), rotation=0.0):
        nodes.append(
            f'[node name="{name}" type="Node3D" parent="{parent}"]\n'
            f'position = {_vector(position)}\nrotation = {_vector((0, rotation, 0))}'
        )
        return f"{parent}/{name}"

    def mesh(name, parent, asset, position=(0, 0, 0), scale=(1, 1, 1), material="Limestone", rotation=0.0):
        nodes.append(
            f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]\n'
            f'position = {_vector(position)}\nrotation = {_vector((0, rotation, 0))}\n'
            f'scale = {_vector(scale)}\nmesh = ExtResource("bridge_mesh_{asset}")\n'
            f'material_override = SubResource("bridge_{material}")'
        )

    def surface(parent, length, width):
        # The native deck is 0.28m thick.  Its top is -0.02, never coincident
        # with land y=0.  Paving bounds are [-0.029, 0.021]: offset +0.009
        # puts its bottom directly on the deck and its top at +0.03.
        mesh("StoneDeck", parent, "stone_bridge_deck", (0, -0.16, 0),
             (length / 8.8, 1, width / 6.4), "Recess")
        columns = max(1, math.ceil(length / 8.8))
        rows = max(1, round(width / 6.4))
        for column in range(columns):
            for row in range(rows):
                mesh(
                    f"DressedPaving{column}_{row}", parent, "stone_bridge_paving",
                    ((column + 0.5) * length / columns - length / 2, 0.009,
                     (row + 0.5) * width / rows - width / 2),
                    (length / columns / 8.8, 1, width / rows / 6.4), "PaintedStone",
                )

    def side_structure(parent, length, width):
        bays = max(1, math.ceil(length / 8.8))
        bay_length = length / bays
        for side in (-1, 1):
            # Keep all masonry beyond the full, navigable road width.
            mesh(f"LowCoping{side}", parent, "stone_bridge_coping", (0, 0.13, side * (width / 2 + 0.35)),
                 (length / 8.8, 1, 1), "LightStone")
            for bay in range(bays):
                along = (bay + 0.5) * bay_length - length / 2
                mesh(f"OpenArch{side}_{bay}", parent, "stone_bridge_arch", (along, 0, side * (width / 2 + 0.45)),
                     (bay_length / 8.8, 1, 1), "PaintedStone")
            for support in range(1, bays):
                along = support * bay_length - length / 2
                mesh(f"WaterPier{side}_{support}", parent, "stone_bridge_pier", (along, -1, side * (width / 2 + 0.47)))

    def bridgehead(parent, length, width, end):
        for side in (-1, 1):
            along = end * (length / 2 - 0.36)
            edge = side * (width / 2 + 0.47)
            mesh(f"Abutment{side}_{end}", parent, "stone_bridge_pier", (along, -1, edge))
            mesh(f"Capstone{side}_{end}", parent, "fieldstone_block", (along, 0.25, edge),
                 (1.12, 0.4, 0.88), "LightStone")
            mesh(f"Wingwall{side}_{end}", parent, "fieldstone_block", (end * (length / 2 + 0.65), -0.32, side * (width / 2 + 0.63)),
                 (1.7, 1.02, 0.62), "MossStone", side * end * 0.23)

    if layout["id"] == "highland":
        # Treat the platform as land-shaped masonry, not a second overlapping
        # bridge.  West/east road surfaces meet its edges exactly at x=+/-8.
        long_bridge, platform = layout["bridges"]
        left, top, length, width = long_bridge
        px, pz, pw, ph = platform
        assert left < px < px + pw < left + length
        assert pz < top and pz + ph > top + width
        bridge_root = group("Bridge0", "Bridges")
        for name, start, end, bank_end in (
            ("WestSpan", left, px, -1),
            ("EastSpan", px + pw, left + length, 1),
        ):
            span = group(name, bridge_root, ((start + end) / 2, 0, top + width / 2))
            surface(span, end - start, width)
            side_structure(span, end - start, width)
            bridgehead(span, end - start, width, bank_end)

        center = group("Bridge1", "Bridges", (px + pw / 2, 0, pz + ph / 2))
        surface(center, pw, ph)
        side_structure(center, pw, ph)
        # Partial west/east parapets frame the central plaza.  The 10.24m gap
        # leaves both 9m bridge approaches entirely open.  Returns end before
        # the north/south copings so their flat top faces never overlap.
        mouth_half_width = width / 2 + 0.62
        outside_half_depth = ph / 2 + 0.10
        return_length = outside_half_depth - mouth_half_width
        for side in (-1, 1):
            for end in (-1, 1):
                mesh(f"PlazaReturn{side}_{end}", center, "stone_bridge_coping",
                     (end * (pw / 2 + 0.35), 0.13, side * (mouth_half_width + return_length / 2)),
                     (return_length / 8.8, 1, 1), "LightStone", math.pi / 2)
                # These supports are below the raised parapet, so the plaza
                # corners retain a clear silhouette without caps on the road.
                mesh(f"PlazaPier{side}_{end}", center, "stone_bridge_pier",
                     (end * (pw / 2 - 0.36), -1, side * (ph / 2 + 0.47)))
        return externals, resources, nodes

    for index, bridge in enumerate(layout["bridges"]):
        x, z, width, depth = bridge
        horizontal = _crosses_horizontally(bridge, layout["water"])
        channel_span, road_width = (width, depth) if horizontal else (depth, width)
        # The original bridge reaches 1.4m onto each bank.  Preserve that
        # architectural proportion instead of squeezing it into the river.
        length = channel_span + 2.8
        parent = group(f"Bridge{index}", "Bridges", (x + width / 2, 0, z + depth / 2),
                       0.0 if horizontal else math.pi / 2)
        surface(parent, length, road_width)
        side_structure(parent, length, road_width)
        for end in (-1, 1):
            bridgehead(parent, length, road_width, end)

    return externals, resources, nodes
