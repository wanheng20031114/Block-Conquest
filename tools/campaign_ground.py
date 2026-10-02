"""Offline quarter-unit terrain grading and embedded campaign road survey.

The road is cut INTO the terrain. A shared fine heightfield describes the
actual earth under every paving stone; there is no elevated ribbon or viaduct.
"""
from collections import defaultdict
import math

GRID = .25
BRIDGE_WALK_Y = 1.02
ROUTE_XZ = [(-23, 5), (-21, 4.8), (-19.2, 3.5), (-18.5, 1.3),
            (-17, -1), (-14, -2.6), (-12.5, -3), (-10, -2), (-8, .1),
            (-7, 2.5), (-6, 2.5), (-3, 2.5), (.3, 2.5), (2, 1.2),
            (3, -1), (5, -2.5), (7.5, -1.2), (8.8, 1), (10, 3.8),
            (13, 4), (15, 3.2), (16, 1), (17, .4), (18, -.7),
            (20, -.7), (21, -1.2)]
ROUTE_Y = [.8, .8, .8, .8, .8, 1.2, 1.4, 1.2, .8, .9,
           1.02, 1.02, 1.02, 1.2, 1.6, 2.4, 2.4, 2.8, 3.2,
           3.6, 3.9, 4.4, 5.1, 5.8, 6.4, 6.4]
STOP_INDICES = [0, 6, 11, 15, 19, 25]


def river_x(z):
    return -3.2 + 1.3 * math.sin(z * .29)


def in_river(x, z):
    return abs(x - river_x(z)) < 1.40 + .2 * math.cos(z * .6)


def on_bridge(x, z):
    return -6.5 < x < .5 and abs(z - 2.5) < .91


def inside(x, z):
    return (abs(x / 28.0) ** 4 + abs((z + .2) / 12.4) ** 4 < 1.0
            and abs(z) < 11.5 + .75 * math.sin(x * .31))


def cell_key(x, z):
    return math.floor(x / GRID), math.floor(z / GRID)


def base_height(x, z):
    base = .8 if x < -1 else .8 + min(3.15, max(0, x) * .19)
    hill = max(0, 1 - ((x + 17) / 9) ** 2 - ((z + 7.5) / 5) ** 2) * 1.8
    hill = max(hill, max(0, 1 - ((x + 13) / 6) ** 2 - ((z - 7.8) / 3.7) ** 2) * 1.1)
    peaks = 0
    for px, pz, height, radius in [(4, -8, 6.0, 4.8), (11, -9, 8, 5.6),
                                  (18, -10, 8.8, 5.1), (25, -7, 7.2, 4.4),
                                  (23, 7.5, 3.5, 4), (6, 8, 2.4, 3.4)]:
        distance = max(abs(x - px) * .87, abs(z - pz)) + min(abs(x - px), abs(z - pz)) * .20
        peaks = max(peaks, height * max(0, 1 - distance / radius))
    h = base + max(hill, peaks)
    for px, pz, rx, rz, target in [(-14, -5.3, 3, 1.8, 1.6), (5, -3.8, 2.9, 2.8, 2.4), (13, 2.5, 3.0, 2.6, 3.6), (21, -3.7, 4.1, 4.1, 6.4)]:
        if abs(x - px) < rx and abs(z - pz) < rz:
            return target
    return round(h / (.25 if x > 2 else .4)) * (.25 if x > 2 else .4)


def interpolate_route():
    result = []
    for i in range(len(ROUTE_XZ) - 1):
        a, b = ROUTE_XZ[max(0, i - 1)], ROUTE_XZ[i]
        c, d = ROUTE_XZ[i + 1], ROUTE_XZ[min(len(ROUTE_XZ) - 1, i + 2)]
        count = max(4, math.ceil(math.dist(b, c) / .11))
        for step in range(count):
            t = step / count
            p = tuple(.5 * ((2*b[k]) + (-a[k]+c[k])*t + (2*a[k]-5*b[k]+4*c[k]-d[k])*t*t + (-a[k]+3*b[k]-3*c[k]+d[k])*t*t*t) for k in (0, 1))
            result.append((*p, ROUTE_Y[i] * (1-t) + ROUTE_Y[i+1] * t))
    result.append((*ROUTE_XZ[-1], ROUTE_Y[-1]))
    return result


SURVEY = interpolate_route()
BUCKETS = defaultdict(list)
for index, (a, b) in enumerate(zip(SURVEY, SURVEY[1:])):
    for bx in range(math.floor(min(a[0], b[0]) / 2) - 1, math.floor(max(a[0], b[0]) / 2) + 2):
        for bz in range(math.floor(min(a[1], b[1]) / 2) - 1, math.floor(max(a[1], b[1]) / 2) + 2):
            BUCKETS[(bx, bz)].append(index)


def survey_at(x, z):
    nearest, elevation = math.inf, 0.0
    for index in BUCKETS.get((math.floor(x / 2), math.floor(z / 2)), ()):
        ax, az, ay = SURVEY[index]
        bx, bz, by = SURVEY[index + 1]
        dx, dz = bx - ax, bz - az
        t = min(1, max(0, ((x-ax)*dx + (z-az)*dz) / (dx*dx + dz*dz)))
        distance = (x-ax-t*dx)**2 + (z-az-t*dz)**2
        if distance < nearest:
            nearest = distance
            elevation = ay * (1-t) + by * t
    return math.sqrt(nearest), elevation


HEIGHTS = {}
for ix in range(-112, 112):
    for iz in range(-48, 48):
        x, z = (ix + .5) * GRID, (iz + .5) * GRID
        if not inside(x, z):
            continue
        h = base_height(x, z)
        distance, grade = survey_at(x, z)
        if distance < 1.25 and not in_river(x, z):
            blend = min(1, max(0, (distance - .52) / .73))
            blend = blend * blend * (3 - 2 * blend)
            h = round((grade * (1-blend) + h * blend) / .1) * .1
        HEIGHTS[(ix, iz)] = h


def ground(x, z):
    return HEIGHTS[cell_key(x, z)]


def ground_edge(x, z):
    """Only the explicitly authored island boundary extends to the display floor."""
    return HEIGHTS.get(cell_key(x, z), -2.5)


def path_height(x, z):
    return BRIDGE_WALK_Y if on_bridge(x, z) else ground(x, z) + .008


def terrain_tiles():
    """Join quiet coplanar quarter cells; keep small blocks at ridges and roads."""
    consumed = set()
    for key in HEIGHTS:
        if key in consumed:
            continue
        ix, iz = key
        width = GRID
        h = HEIGHTS[key]
        neighbors = [(ix+dx, iz+dz) for dx in (0, 1) for dz in (0, 1)]
        if ix % 2 == 0 and iz % 2 == 0 and all(k in HEIGHTS and HEIGHTS[k] == h for k in neighbors):
            waters = {in_river((k[0]+.5)*GRID, (k[1]+.5)*GRID) for k in neighbors}
            if len(waters) == 1 and survey_at((ix+1)*GRID, (iz+1)*GRID)[0] > 1.35:
                width = GRID * 2
                consumed.update(neighbors)
        consumed.add(key)
        yield ix * GRID + width/2, iz * GRID + width/2, width, h
