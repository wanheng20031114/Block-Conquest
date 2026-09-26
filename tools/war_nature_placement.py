"""Offline rock seating against Godot's saved shore triangles.

Export the current meshes with tools/export_war_shore_support.gd first. This
cache is checked against its source meshes; it is never loaded by the game.
"""
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ShoreSupport:
    def __init__(self, map_id, waters):
        path = ROOT / ".local/war_shore_support.json"
        if not path.exists():
            raise RuntimeError("Run Godot --headless --path . --script tools/export_war_shore_support.gd first")
        source = json.loads(path.read_text(encoding="utf-8"))[map_id]
        mesh = ROOT / source["mesh"].removeprefix("res://")
        if hashlib.sha256(mesh.read_bytes()).hexdigest() != source["sha256"]:
            raise RuntimeError(f"{map_id}: bank geometry changed; re-run export_war_shore_support.gd")
        self.waters = waters
        self.cells = defaultdict(list)
        self.contour = []
        values = source["faces"]
        for i in range(0, len(values), 9):
            triangle = [tuple(values[j:j + 3]) for j in range(i, i + 9, 3)]
            (ax, ay, az), (bx, by, bz), (cx, cy, cz) = triangle
            determinant = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
            if abs(determinant) < 1e-8:
                continue
            for x in range(math.floor(min(ax, bx, cx) / 4), math.floor(max(ax, bx, cx) / 4) + 1):
                for z in range(math.floor(min(az, bz, cz) / 4), math.floor(max(az, bz, cz) / 4) + 1):
                    self.cells[x, z].append((triangle, determinant))
            # The upper lip at -8 cm is wide enough to read as an actual shore.
            # Its uphill gradient points from the water toward a supported seat.
            intersections = []
            for a, b in zip(triangle, triangle[1:] + triangle[:1]):
                if (a[1] < -.08) != (b[1] < -.08):
                    t = (-.08 - a[1]) / (b[1] - a[1])
                    intersections.append((a[0] + (b[0] - a[0]) * t, a[2] + (b[2] - a[2]) * t))
            if len(intersections) == 2:
                gx = ((ay - cy) * (bz - cz) - (by - cy) * (az - cz)) / determinant
                gz = ((ax - cx) * (by - cy) - (bx - cx) * (ay - cy)) / determinant
                length = math.hypot(gx, gz)
                self.contour.append((*intersections, (gx / length, gz / length)))

    def height(self, x, z):
        hits = []
        for triangle, determinant in self.cells[math.floor(x / 4), math.floor(z / 4)]:
            (ax, ay, az), (bx, by, bz), (cx, cy, cz) = triangle
            a = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / determinant
            b = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / determinant
            if a >= -1e-6 and b >= -1e-6 and a + b <= 1.000001:
                hits.append(a * ay + b * by + (1 - a - b) * cy)
        if hits:
            return max(hits)
        if not any(rx <= x <= rx + w and rz <= z <= rz + h for rx, rz, w, h in self.waters):
            return 0.0
        return None

    def seat(self, x, z, radius, height_scale, clear):
        """Return a level, shallowly buried dry-shore seat, or reject the site.

        Every footprint sample needs support. No fixed below-ground Y and no
        large rock balanced on the steep wall between the bank and the river.
        """
        candidates = []
        for a, b, uphill in self.contour:
            dx, dz = b[0] - a[0], b[1] - a[1]
            t = max(0., min(1., ((x - a[0]) * dx + (z - a[1]) * dz) / (dx * dx + dz * dz)))
            px, pz = a[0] + dx * t, a[1] + dz * t
            candidates.append((math.hypot(px - x, pz - z), px, pz, uphill))
        for _, px, pz, (nx, nz) in sorted(candidates)[:20]:
            for setback in (radius + .22, radius + .6):
                sx, sz = px + nx * setback, pz + nz * setback
                if not clear(sx, sz, radius):
                    continue
                heights = [self.height(sx, sz)] + [self.height(sx + math.cos(j * math.tau / 12) * radius,
                           sz + math.sin(j * math.tau / 12) * radius) for j in range(12)]
                if None in heights or max(heights) - min(heights) > .12:
                    continue
                return sx, min(heights) - .11 * height_scale, sz
        return None
