"""Offline geometry regressions for authored bridge scenes, without Godot.

The tests read the saved native mesh bounds and compose the emitted scene
transforms.  They check the resulting geometry against water/navigation regions,
rather than asserting particular node names, scales, or serialized offsets.
"""
from __future__ import annotations

from dataclasses import dataclass
import itertools
import math
from pathlib import Path
import re
import struct
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from block_war_bridge_authoring import author_bridges
from block_war_path_authoring import author_paths
from build_block_war_maps import layouts


@dataclass
class SceneNode:
    path: str
    parent: str
    position: tuple
    scale: tuple
    yaw: float
    mesh: Path | None


def vector_property(section, key, default):
    match = re.search(rf"^{key} = Vector3\(([^)]+)\)", section, re.M)
    return tuple(float(value) for value in match[1].split(",")) if match else default


def mesh_bounds(path):
    """Read the AABB Variant saved in an uncompressed Godot ArrayMesh resource."""
    data = path.read_bytes()
    if data[:4] != b"RSRC":
        raise ValueError(f"Expected an uncompressed native mesh: {path}")
    # A Dictionary's string key 'aabb' followed by Variant type 15 (AABB).
    # The different custom_aabb resource-property name is not a dictionary key.
    marker = b"\x05\x00\x00\x00aabb\x00\x0f\x00\x00\x00"
    matches = [match.end() for match in re.finditer(re.escape(marker), data)]
    if len(matches) != 1:
        raise ValueError(f"Expected one saved mesh surface AABB: {path}")
    values = struct.unpack_from("<6f", data, matches[0])
    return values[:3], tuple(values[axis] + values[axis + 3] for axis in range(3))


class AuthoredScene:
    def __init__(self, layout):
        self.layout = layout
        external, _, sections = author_bridges(layout)
        mesh_files = {}
        for section in external:
            attributes = dict(re.findall(r'(\w+)="([^"]*)"', section))
            mesh_files[attributes["id"]] = ROOT / attributes["path"].removeprefix("res://")
        self.nodes = {}
        self.bounds = {}
        for section in sections:
            attributes = dict(re.findall(r'(\w+)="([^"]*)"', section.splitlines()[0]))
            parent = attributes["parent"]
            path = f'{parent}/{attributes["name"]}'
            reference = re.search(r'mesh = ExtResource\("([^"]+)"\)', section)
            rotation = vector_property(section, "rotation", (0, 0, 0))
            if rotation[0] or rotation[2]:
                raise ValueError("Bridge geometry must not tilt the level road surface")
            self.nodes[path] = SceneNode(
                path, parent, vector_property(section, "position", (0, 0, 0)),
                vector_property(section, "scale", (1, 1, 1)), rotation[1],
                mesh_files[reference[1]] if reference else None,
            )
        for node in self.nodes.values():
            if node.mesh:
                minimum, maximum = mesh_bounds(node.mesh)
                corners = [self.to_world(node, corner) for corner in itertools.product(*zip(minimum, maximum))]
                self.bounds[node.path] = (
                    tuple(min(corner[axis] for corner in corners) for axis in range(3)),
                    tuple(max(corner[axis] for corner in corners) for axis in range(3)),
                )

    def to_world(self, node, point):
        while node:
            x, y, z = (point[axis] * node.scale[axis] for axis in range(3))
            c, s = math.cos(node.yaw), math.sin(node.yaw)
            point = (c * x + s * z + node.position[0], y + node.position[1],
                     -s * x + c * z + node.position[2])
            node = self.nodes.get(node.parent)
        return point

    def meshes(self, asset, subtree=None):
        return [node for node in self.nodes.values() if node.mesh and node.mesh.stem == asset
                and (subtree is None or node.path.startswith(subtree + "/"))]


def water_at(layout, point):
    x, z = point
    return any(rx < x < rx + width and rz < z < rz + depth for rx, rz, width, depth in layout["water"])


def crossing_axis(layout, bridge):
    """Infer direction from dry banks across the opening, not rectangle aspect."""
    x, z, width, depth = bridge
    left = (x - 0.5, z + depth / 2)
    right = (x + width + 0.5, z + depth / 2)
    top = (x + width / 2, z - 0.5)
    bottom = (x + width / 2, z + depth + 0.5)
    dry_x = not water_at(layout, left) and not water_at(layout, right)
    dry_z = not water_at(layout, top) and not water_at(layout, bottom)
    if dry_x == dry_z:
        raise ValueError(f"Ordinary bridge must connect exactly two opposite dry banks: {bridge}")
    return 0 if dry_x else 2


def overlap_area(first, second):
    return max(0, min(first[1][0], second[1][0]) - max(first[0][0], second[0][0])) * max(
        0, min(first[1][2], second[1][2]) - max(first[0][2], second[0][2]))


class BridgeAuthoringTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scenes = {layout["id"]: AuthoredScene(layout) for layout in layouts()}

    def ordinary_bridges(self):
        for scene in self.scenes.values():
            if scene.layout["id"] == "highland":
                continue  # The central platform joins two road spans, not two banks.
            for index, bridge in enumerate(scene.layout["bridges"]):
                yield scene, bridge, f"Bridges/Bridge{index}"

    def test_arches_span_the_water_instead_of_blocking_the_entrance(self):
        for scene, bridge, root in self.ordinary_bridges():
            with self.subTest(map=scene.layout["id"], bridge=root):
                axis = crossing_axis(scene.layout, bridge)
                arches = scene.meshes("stone_bridge_arch", root)
                self.assertTrue(arches, "A bridge needs its supporting masonry")
                for arch in arches:
                    origin = scene.to_world(arch, (0, 0, 0))
                    along = scene.to_world(arch, (1, 0, 0))
                    vector = tuple(along[i] - origin[i] for i in range(3))
                    self.assertGreater(abs(vector[axis]) / math.sqrt(sum(value * value for value in vector)), 0.999)

    def test_decks_reach_both_banks_and_cover_the_walkable_road(self):
        for scene, bridge, root in self.ordinary_bridges():
            with self.subTest(map=scene.layout["id"], bridge=root):
                axis = crossing_axis(scene.layout, bridge)
                road_axis = 2 if axis == 0 else 0
                x, z, width, depth = bridge
                opening = ((x, 0, z), (x + width, 0, z + depth))
                decks = scene.meshes("stone_bridge_deck", root)
                self.assertEqual(len(decks), 1)
                low, high = scene.bounds[decks[0].path]
                self.assertLessEqual(low[axis], opening[0][axis] - 0.5)
                self.assertGreaterEqual(high[axis], opening[1][axis] + 0.5)
                self.assertLessEqual(low[road_axis], opening[0][road_axis] + 1e-5)
                self.assertGreaterEqual(high[road_axis], opening[1][road_axis] - 1e-5)

    def test_surfaces_are_separated_from_land_and_paving_rest_on_deck(self):
        for scene in self.scenes.values():
            for deck in scene.meshes("stone_bridge_deck"):
                with self.subTest(map=scene.layout["id"], deck=deck.path):
                    deck_top = scene.bounds[deck.path][1][1]
                    self.assertLess(deck_top, -0.003, "Deck top must not fight with land at y=0")
                    paving = scene.meshes("stone_bridge_paving", deck.parent)
                    self.assertTrue(paving)
                    for stone in paving:
                        low, high = scene.bounds[stone.path]
                        self.assertGreater(high[1], 0.003, "Paving top needs real separation from ground")
                        self.assertLess(high[1], 0.05, "Road must remain level with y=0 army motion")
                        self.assertAlmostEqual(low[1], deck_top, places=5, msg="Paving must sit on its supporting deck")

    def test_highland_platform_has_no_overlapping_decks_or_paving(self):
        scene = self.scenes["highland"]
        for asset in ("stone_bridge_deck", "stone_bridge_paving"):
            for first, second in itertools.combinations(scene.meshes(asset), 2):
                with self.subTest(asset=asset, first=first.path, second=second.path):
                    self.assertLess(overlap_area(scene.bounds[first.path], scene.bounds[second.path]), 1e-4)
        # A missing platform would also avoid overlap, so verify the central
        # building actually has exactly one supporting surface under it.
        central_decks = [deck for deck in scene.meshes("stone_bridge_deck")
                         if scene.bounds[deck.path][0][0] < 0 < scene.bounds[deck.path][1][0]
                         and scene.bounds[deck.path][0][2] < 0 < scene.bounds[deck.path][1][2]]
        self.assertEqual(len(central_decks), 1)

    def test_ordinary_bridge_road_and_approaches_have_full_railing_clearance(self):
        for scene, bridge, root in self.ordinary_bridges():
            axis = crossing_axis(scene.layout, bridge)
            x, z, width, depth = bridge
            corridor = [[x + 0.001, 0, z + 0.001], [x + width - 0.001, 0, z + depth - 0.001]]
            # Include the approach beyond each bank, where the wingwalls stand.
            corridor[0][axis] -= 4
            corridor[1][axis] += 4
            raised_structure = [node for node in scene.nodes.values()
                                if node.path.startswith(root + "/") and node.mesh
                                and scene.bounds[node.path][1][1] > 0.05]
            self.assertTrue(raised_structure, "Bridge needs visible parapets, not merely a flat slab")
            for node in raised_structure:
                with self.subTest(map=scene.layout["id"], bridge=root, structure=node.path):
                    self.assertLess(overlap_area(scene.bounds[node.path], corridor), 1e-5,
                                    "Raised masonry intrudes into the authored army corridor")

    def test_highland_central_road_keeps_both_platform_entrances_open(self):
        scene = self.scenes["highland"]
        x, z, width, depth = scene.layout["bridges"][0]
        corridor = ((x - 2, 0, z + 0.001), (x + width + 2, 0, z + depth - 0.001))
        for node in scene.nodes.values():
            if node.mesh and scene.bounds[node.path][1][1] > 0.05:
                with self.subTest(structure=node.path):
                    self.assertLess(overlap_area(scene.bounds[node.path], corridor), 1e-5)


def inside_region(region, point):
    x, z, width, depth = region
    return x + 1e-7 < point[0] < x + width - 1e-7 and z + 1e-7 < point[1] < z + depth - 1e-7


def terrain_allows(layout, point):
    if abs(point[0]) > layout["half"][0] + 1e-7 or abs(point[1]) > layout["half"][1] + 1e-7:
        return False
    if any(region[0] - 1e-7 <= point[0] <= region[0] + region[2] + 1e-7
           and region[1] - 1e-7 <= point[1] <= region[1] + region[3] + 1e-7
           for region in layout["bridges"]):
        return True
    return not any(inside_region(region, point) for region in layout["water"] + layout["mountains"])


def segment_samples(segment, regions):
    """Sample the entire road plus every terrain-boundary interval.

    Boundary intervals catch narrow forbidden crossings that could fall between
    regular samples, independently of the author's half-metre clearance grid.
    """
    ax, az, bx, bz = segment
    steps = max(1, math.ceil(math.hypot(bx - ax, bz - az) / 0.125))
    parameters = {index / steps for index in range(steps + 1)}
    boundaries = {0.0, 1.0}
    for x, z, width, depth in regions:
        for start, difference, limits in ((ax, bx - ax, (x, x + width)), (az, bz - az, (z, z + depth))):
            if abs(difference) > 1e-9:
                boundaries.update((edge - start) / difference for edge in limits if 0 < (edge - start) / difference < 1)
    ordered = sorted(boundaries)
    parameters.update(boundaries)
    parameters.update((low + high) / 2 for low, high in zip(ordered, ordered[1:]))
    return [(ax + (bx - ax) * t, az + (bz - az) * t) for t in sorted(parameters)]


def distance_to_road(point, paths):
    distances = []
    for ax, az, bx, bz in paths:
        dx, dz = bx - ax, bz - az
        projection = ((point[0] - ax) * dx + (point[1] - az) * dz) / (dx * dx + dz * dz)
        if 0 <= projection <= 1:
            # Perpendicular distance to the infinite line, only when its foot
            # falls on this segment; otherwise use the closer endpoint.
            distances.append(abs(dx * (az - point[1]) - (ax - point[0]) * dz) / math.hypot(dx, dz))
        else:
            distances.append(min(math.dist(point, (ax, az)), math.dist(point, (bx, bz))))
    return min(distances)


def bridge_union_span(bridge, bridges, axis):
    """Find the joined deck span along a center ray, including plaza extensions."""
    cross_axis = 1 - axis
    center = bridge[cross_axis] + bridge[cross_axis + 2] / 2
    low, high = bridge[axis], bridge[axis] + bridge[axis + 2]
    candidates = [region for region in bridges if region[cross_axis] < center < region[cross_axis] + region[cross_axis + 2]]
    for _ in candidates:
        previous = (low, high)
        for region in candidates:
            start, end = region[axis], region[axis] + region[axis + 2]
            if start <= high and end >= low:
                low, high = min(low, start), max(high, end)
        if previous == (low, high):
            break
    return low, high


class RoadAuthoringTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.maps = [(layout, author_paths(layout)) for layout in layouts() if layout["id"] != "rift"]

    def test_all_five_road_plans_fit_the_shader_and_have_valid_segments(self):
        self.assertEqual(len(self.maps), 5)
        for layout, paths in self.maps:
            with self.subTest(map=layout["id"]):
                self.assertGreater(len(paths), 0)
                self.assertLessEqual(len(paths), 64, "Ground shader has a fixed 64-segment uniform array")
                for segment in paths:
                    self.assertEqual(len(segment), 4)
                    self.assertTrue(all(math.isfinite(value) for value in segment))
                    self.assertGreater(math.dist(segment[:2], segment[2:]), 0.01)

    def test_full_road_lengths_avoid_unbridged_water_and_mountain_interiors(self):
        for layout, paths in self.maps:
            regions = layout["water"] + layout["mountains"] + layout["bridges"]
            for index, segment in enumerate(paths):
                with self.subTest(map=layout["id"], road=index):
                    for point in segment_samples(segment, regions):
                        self.assertTrue(terrain_allows(layout, point), f"Road {segment} enters forbidden terrain at {point}")

    def test_every_bridge_centerline_and_both_approaches_have_a_road(self):
        for layout, paths in self.maps:
            for bridge in layout["bridges"]:
                x, z, width, depth = bridge
                low_x, high_x = bridge_union_span(bridge, layout["bridges"], 0)
                low_z, high_z = bridge_union_span(bridge, layout["bridges"], 1)
                horizontal_access = terrain_allows(layout, (low_x - 0.5, z + depth / 2)) and terrain_allows(layout, (high_x + 0.5, z + depth / 2))
                vertical_access = terrain_allows(layout, (x + width / 2, low_z - 0.5)) and terrain_allows(layout, (x + width / 2, high_z + 0.5))
                with self.subTest(map=layout["id"], bridge=bridge):
                    self.assertNotEqual(horizontal_access, vertical_access, "Bridge needs one clear crossing axis")
                    centerline = (x - 1, z + depth / 2, x + width + 1, z + depth / 2) if horizontal_access else (
                        x + width / 2, z - 1, x + width / 2, z + depth + 1)
                    for point in segment_samples(centerline, []):
                        self.assertLessEqual(distance_to_road(point, paths), 1.0, f"Bridge road stops before its approach at {point}")

    def test_every_actual_building_door_connects_to_the_road_or_front_courtyard(self):
        # Use the native Door marker, not the road generator's chosen attachment
        # point, so changing building art cannot silently strand its entrance.
        building = (ROOT / "scenes/block_war/building.tscn").read_text(encoding="utf-8")
        door_section = re.search(r'\[node name="Door"[^\[]+', building)[0]
        door = vector_property(door_section, "position", (0, 0, 0))
        for layout, paths in self.maps:
            for x, z, *_ in layout["buildings"]:
                actual_door = (x + door[0], z + door[2])
                with self.subTest(map=layout["id"], doorway=actual_door):
                    self.assertTrue(terrain_allows(layout, actual_door))
                    self.assertLessEqual(distance_to_road(actual_door, paths), 1.5,
                                         "Front courtyard cannot connect an entrance over 1.5m from the road")


if __name__ == "__main__":
    unittest.main(verbosity=2)
