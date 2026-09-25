"""Deliberate road spines, with short settlement approaches on dry ground."""
import math


def author_paths(layout):
    paths = []

    def line(*points):
        paths.extend((*a, *b) for a, b in zip(points, points[1:]))

    map_id = layout["id"]
    if map_id == "lake":
        line((-28, 0), (-30, -17), (-18, -20), (0, -19), (18, -20),
             (30, -17), (28, 0), (30, 23), (16, 25), (0, 25),
             (-16, 25), (-30, 23), (-28, 0))
    elif map_id == "rivers":
        for z in (-26, 0, 26):
            line((-49, z + 2), (-29, z), (29, z), (49, z + 2))
        for side in (-1, 1):
            line((side * 40, -29), (side * 41, -12), (side * 40, 12), (side * 40, 29))
        line((0, -32), (3, -16), (0, 0), (-3, 16), (0, 32))
    elif map_id == "ridges":
        for side in (-1, 1):
            line((side * 48, -26), (side * 31, -27), (side * 18, -38),
                 (0, -39))
            line((side * 48, 26), (side * 31, 29), (side * 18, 39), (0, 39))
            line((side * 34, -30), (side * 25, -12), (side * 22, 0),
                 (side * 25, 12), (side * 34, 30))
        line((-48, 2), (-24, 3), (0, 3), (24, 3), (48, 2))
    elif map_id == "islands":
        for z in (-42, 0, 42):
            line((-70, z + 2), (-34, z), (34, z), (70, z + 2))
        line((0, -42), (0, 0), (0, 42))
        for side in (-1, 1):
            line((side * 58, -44), (side * 57, -21), (side * 60, 0),
                 (side * 57, 21), (side * 58, 44))
    elif map_id == "highland":
        for side in (-1, 1):
            line((side * 68, -42), (side * 46, -41), (side * 28, -43), (0, -43))
            line((side * 68, 46), (side * 46, 47), (side * 28, 46), (0, 49))
            line((side * 52, -43), (side * 53, -24), (side * 48, 0),
                 (side * 53, 24), (side * 52, 46))
        line((-68, 2), (-35, 0), (35, 0), (68, 2))
    else:
        raise ValueError(f"No road plan for {map_id}")

    def clear(segment):
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
    assert all(clear(segment) for segment in paths), (map_id, "road crosses forbidden terrain")
    return paths
