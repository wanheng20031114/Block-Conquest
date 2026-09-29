"""Deliberate road spines, with short settlement approaches on dry ground."""
import math
from block_war_height_authoring import surface_segment_clear


def author_paths(layout):
    paths = []

    def line(*points):
        paths.extend((*a, *b) for a, b in zip(points, points[1:]))

    map_id = layout["id"]
    if map_id == "rift":
        for z in (-12, 12):
            line((-28, z), (0, z), (28, z))
        for side in (-1, 1):
            line((side * 26, -20), (side * 26, 0), (side * 26, 20))
        line((0, -19), (0, 0), (0, 20))
    elif map_id == "lake":
        line((-26, 0), (-26, -16), (-14, -17), (0, -17), (14, -17),
             (26, -16), (26, 0), (26, 21), (12, 23), (0, 23),
             (-12, 23), (-26, 21), (-26, 0))
    elif map_id == "rivers":
        for z in (-23, 0, 23):
            line((-43, z + 2), (-25, z), (25, z), (43, z + 2))
        for side in (-1, 1):
            line((side * 35, -26), (side * 36, -12), (side * 35, 12), (side * 35, 26))
        line((0, -29), (2, -16), (0, 0), (-2, 16), (0, 29))
    elif map_id == "ridges":
        for side in (-1, 1):
            line((side * 42, -23), (side * 27, -24), (side * 16, -34), (0, -35))
            line((side * 42, 23), (side * 27, 26), (side * 16, 36), (0, 37))
            line((side * 29, -27), (side * 17, -10), (side * 12, 3),
                 (side * 17, 10), (side * 29, 27))
            for direction in (-1, 1):
                line((side * 42, direction * 2), (side * 34, direction * 9),
                     (side * 17, direction * 9), (side * 12, direction * 3), (0, direction * 3))
    elif map_id == "islands":
        for z in (-37, 0, 37):
            line((-62, z + 2), (-30, z), (30, z), (62, z + 2))
        line((0, -37), (0, 0), (0, 37))
        for side in (-1, 1):
            line((side * 51, -39), (side * 50, -18.5), (side * 52, 0),
                 (side * 50, 18.5), (side * 51, 39))
    elif map_id == "highland":
        for side in (-1, 1):
            line((side * 60, -37), (side * 40, -36), (side * 24, -38), (0, -38))
            line((side * 60, 41), (side * 40, 42), (side * 24, 42), (0, 44))
            line((side * 46, -38), (side * 47, -21), (side * 43, 0),
                 (side * 47, 21), (side * 46, 41))
        line((-60, 2), (-38, 0), (38, 0), (60, 2))
    elif map_id == "terraces":
        line((-35, 0), (0, 0), (35, 0))
        line((0, -27), (0, 0), (0, 27))
        for z in (-26, 26):
            line((-33, z), (0, z), (33, z))
        for side in (-1, 1):
            line((side * 33, -26), (side * 33, 0), (side * 33, 26))
    elif map_id == "switchback":
        for z in (-27, 27):
            line((-44, z), (-10, z), (10, z), (44, z))
        line((0, -30), (0, -18), (0, 0), (0, 18), (0, 30))
        for side in (-1, 1):
            line((side * 43, -40), (side * 43, 0), (side * 43, 40))
            line((side * 43, 0), (side * 28, 0))
        for z in (-40, 40):
            line((-43, z), (0, z), (43, z))
    elif map_id == "crown":
        for z in (-26, 0, 26):
            line((-65, z), (-28, z))
            line((28, z), (65, z))
        for side in (-1, 1):
            line((side * 62, -33), (side * 62, 0), (side * 62, 33))
            line((side * 28, -28), (side * 28, 0), (side * 28, 28))
        for z in (-28, 28):
            line((-28, z), (0, z), (28, z))
        line((0, -28), (0, 0), (0, 28))
        for side in (-1, 1):
            line((side * 12, -13), (side * 12, 0), (side * 12, 14))
            line((0, 0), (side * 12, 0))
    else:
        raise ValueError(f"No road plan for {map_id}")

    def clear(segment):
        if not surface_segment_clear(layout, segment):
            return False
        x1, z1, x2, z2 = segment
        steps = max(1, math.ceil(math.hypot(x2 - x1, z2 - z1) * 2))
        for i in range(steps + 1):
            x, z = x1 + (x2 - x1) * i / steps, z1 + (z2 - z1) * i / steps
            def inside(r):
                return r[0] < x < r[0] + r[2] and r[1] < z < r[1] + r[3]
            if any(inside(r) for r in layout["bridges"]):
                continue
            if any(inside(r) for r in layout["water"] + layout["mountains"]):
                return False
        return True

    # Attach each front courtyard to the nearest visible spine, without
    # recursively growing branches or drawing a web between every building.
    spines = list(paths)
    for x, z, *_ in layout["buildings"]:
        door = (x, z + 2.5)
        options = []
        for x1, z1, x2, z2 in spines:
            dx, dz = x2 - x1, z2 - z1
            t = max(0, min(1, ((door[0] - x1) * dx + (door[1] - z1) * dz) / (dx * dx + dz * dz)))
            target = (x1 + t * dx, z1 + t * dz)
            segment = (*door, *target)
            if clear(segment):
                options.append((math.dist(door, target), segment))
        assert options, (map_id, "isolated courtyard", door)
        length, segment = min(options)
        if length > 1.0:
            paths.append(segment)
    assert len(paths) <= 64, (map_id, len(paths))
    blocked = [segment for segment in paths if not clear(segment)]
    assert not blocked, (map_id, "road crosses forbidden terrain", blocked)
    return paths
