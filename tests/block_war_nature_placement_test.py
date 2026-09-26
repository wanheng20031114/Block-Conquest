"""Independent geometry checks for saved nature scenes (modeller's Python).

Run export_war_shore_support.gd first. Uses actual glTF vertex footprints, not
the placement generator's radius constants, to catch rock/rock and rock/trunk
intersections. Shore samples also catch floating and almost fully buried rocks.
"""
import itertools
import math
from pathlib import Path
import re
import sys
import unittest

import numpy as np
import trimesh
from shapely.geometry import MultiPoint

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build_block_war_maps import layouts, scene_path
from war_nature_placement import ShoreSupport


def vector(block, key, default):
    match = re.search(rf"^{key} = Vector3\(([^)]+)\)", block, re.M)
    return np.array([float(v) for v in match[1].split(",")] if match else default)


def nature_nodes(layout):
    source = (ROOT / scene_path(layout).removeprefix("res://")).read_text(encoding="utf-8")
    result = []
    for block in re.split(r"(?=^\[node )", source, flags=re.M):
        if not block.startswith("[node ") or 'parent="Nature"' not in block:
            continue
        species = re.search(r'instance=ExtResource\("nature_([^"]+)"\)', block)
        if species is None:
            continue
        rotation = vector(block, "rotation", (0, 0, 0))
        rx = trimesh.transformations.rotation_matrix(rotation[0], (1, 0, 0))
        ry = trimesh.transformations.rotation_matrix(rotation[1], (0, 1, 0))
        rz = trimesh.transformations.rotation_matrix(rotation[2], (0, 0, 1))
        transform = ry @ rx @ rz
        transform[:3, :3] *= vector(block, "scale", (1, 1, 1))[None, :]
        transform[:3, 3] = vector(block, "position", (0, 0, 0))
        result.append((re.search('name="([^"]+)"', block)[1], species[1], transform, block))
    return result


class NaturePlacementTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.maps = layouts()
        cls.nodes = {layout["id"]: nature_nodes(layout) for layout in cls.maps}
        cls.models = {}
        for species in ("moss_boulder", "canopy_oak", "silver_birch", "wind_pine", "weeping_willow"):
            model = trimesh.load(ROOT / f"assets/models/block_war/nature/{species}.glb", force="scene")
            group = "Stone" if species == "moss_boulder" else "Wood"
            vertices = np.asarray(model.geometry[group].vertices)
            if group == "Wood":
                vertices = vertices[vertices[:, 1] < 1.2]
            cls.models[species] = vertices

    def geometry(self, node):
        _, species, transform, _ = node
        vertices = trimesh.transform_points(self.models[species], transform)
        return vertices, MultiPoint(vertices[:, [0, 2]]).convex_hull

    def test_no_rock_footprints_intersect_other_rocks_or_tree_trunks(self):
        for map_id, nodes in self.nodes.items():
            rocks = [(n, self.geometry(n)[1]) for n in nodes if n[1] == "moss_boulder"]
            trunks = [(n, self.geometry(n)[1]) for n in nodes if n[1] in self.models and n[1] != "moss_boulder"]
            pairs = itertools.chain(itertools.combinations(rocks, 2), itertools.product(rocks, trunks))
            for (a, pa), (b, pb) in pairs:
                with self.subTest(map=map_id, first=a[0], second=b[0]):
                    self.assertLess(pa.intersection(pb).area, .002)

    def test_shore_rocks_are_supported_and_keep_their_visible_volume(self):
        count = 0
        for layout in self.maps:
            if not layout["water"]:
                continue
            support = ShoreSupport(layout["id"], layout["water"])
            for node in self.nodes[layout["id"]]:
                if not ("BankStone" in node[0] or "RiverStone" in node[0]):
                    continue
                vertices, footprint = self.geometry(node)
                x, z = footprint.centroid.coords[0]
                base_y, top_y = vertices[:, 1].min(), vertices[:, 1].max()
                # Sample the actual projected perimeter, independently of the
                # circular ring used by the author. All edges must meet terrain.
                heights = [support.height(*footprint.exterior.interpolate(i / 24, normalized=True).coords[0]) for i in range(24)]
                with self.subTest(map=layout["id"], rock=node[0]):
                    self.assertNotIn(None, heights)
                    self.assertLessEqual(base_y, min(heights) + .04)
                    self.assertGreater(top_y - max(heights), (top_y - base_y) * .60)
                    self.assertLess(max(heights) - min(heights), .18)
                    for bx, bz, width, depth in layout["bridges"]:
                        dx = max(bx - x, 0, x - bx - width)
                        dz = max(bz - z, 0, z - bz - depth)
                        self.assertGreater(math.hypot(dx, dz), 4)
                count += 1
        self.assertGreater(count, 70, "Emptying every shoreline would hide the placement bug")

    def test_interior_trees_form_groups_instead_of_isolated_survivors(self):
        for layout in self.maps[1:]:
            trees = [n for n in self.nodes[layout["id"]] if "ClearingTree" in n[0]]
            points = [n[2][[0, 2], 3] for n in trees]
            with self.subTest(map=layout["id"]):
                self.assertGreater(len(points), 10)
                for i, point in enumerate(points):
                    distances = sorted(np.linalg.norm(point - other) for j, other in enumerate(points) if i != j)
                    self.assertLess(distances[1], 5.8, "Each interior tree needs at least two neighbours")


if __name__ == "__main__":
    unittest.main(verbosity=2)
