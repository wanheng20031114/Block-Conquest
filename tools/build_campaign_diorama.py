"""Author the campaign's original block-built miniature as native Godot scenes.

Run with Python's standard library. This is an OFFLINE modelling tool: the game
loads saved scenes, MultiMeshes, markers and a Curve3D, never constructs scenery.
Each grove, terrain stratum and landmark remains a named editable scene object.
"""
from pathlib import Path
from collections import defaultdict
import math
import random

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "scenes/campaign/models"
RNG = random.Random(70461)
COLORS = {
    "bark": "72523d", "bark_light": "967052", "leaf": "618945",
    "leaf_light": "82a957", "leaf_dark": "436b40", "pine": "356a59",
    "pine_light": "4c8270", "snow": "e4f0ef", "ice": "aacccd",
    "stone": "879696", "stone_light": "a5b1ac", "stone_dark": "677b80",
    "plaster": "eee0b9", "wood": "906849", "wood_light": "b38c5b",
    "wood_dark": "56493d", "roof": "b88642", "roof_light": "d2a75c",
    "slate": "4b7280", "slate_light": "678e98", "dark": "2f4950",
    "gold": "e3b65c", "blue": "568c98", "white": "eaf0d9",
    "grass": "8da966", "earth": "8d8262", "rock": "819492",
    "road": "cfc197", "flower": "e9d592", "water": "4e9fa6",
}


def write(path, content):
    content = content.rstrip() + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_text(encoding="utf-8") != content:
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(content, encoding="utf-8", newline="\n")
        temporary.replace(path)


def fmt(value):
    return f"{value:.5f}".rstrip("0").rstrip(".") if value else "0"


def vec(values):
    return "Vector3(" + ", ".join(map(fmt, values)) + ")"


def color(name, shift=0):
    value = COLORS.get(name, name)
    srgb = [max(0, min(1, int(value[i:i + 2], 16) / 255 + shift)) for i in (0, 2, 4)]
    # Instance colors are linear values, unlike color-picker hex values.
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in srgb)


class Blocks:
    def __init__(self):
        self.parts = []

    def box(self, size, pos, tint, angle=0, variation=0):
        # Godot's MultiMesh buffer is row-major 3x4 transform + RGBA.
        sx, sy, sz = size
        x, y, z = pos
        c, s = math.cos(angle), math.sin(angle)
        rgb = color(tint, variation)
        self.parts.append((c * sx, 0, s * sz, x, 0, sy, 0, y,
                           -s * sx, 0, c * sz, z, *rgb, 1))

    def res(self, name):
        return (f'[sub_resource type="MultiMesh" id="{name}"]\n'
                'transform_format = 1\nuse_colors = true\n'
                f'instance_count = {len(self.parts)}\nmesh = SubResource("Cube")\n'
                'buffer = PackedFloat32Array(' + ', '.join(fmt(n) for p in self.parts for n in p) + ')\n\n')


def model(name, groups, extra_resources="", extra_nodes="", extra_imports=""):
    text = '[gd_scene format=3]\n\n'
    text += '[ext_resource type="Shader" path="res://assets/campaign/block_foliage.gdshader" id="leaves"]\n\n'
    text += extra_imports
    text += '[sub_resource type="BoxMesh" id="Cube"]\nsize = Vector3(1, 1, 1)\n\n'
    text += '[sub_resource type="StandardMaterial3D" id="Matte"]\nvertex_color_use_as_albedo = true\nroughness = 0.88\n\n'
    text += '[sub_resource type="ShaderMaterial" id="Foliage"]\nshader = ExtResource("leaves")\n\n'
    for group, blocks in groups.items():
        text += blocks.res(group)
    text += extra_resources
    text += f'[node name="{name}" type="Node3D"]\n\n'
    for group in groups:
        mat = "Foliage" if group == "Crown" else "Matte"
        text += f'[node name="{group}" type="MultiMeshInstance3D" parent="."]\nmultimesh = SubResource("{group}")\nmaterial_override = SubResource("{mat}")\n\n'
    text += extra_nodes
    write(OUT / (name + ".tscn"), text)


def oak(name, variant):
    wood, leaves = Blocks(), Blocks()
    wood.box((.32, 1.9, .34), (0, .95, 0), "bark")
    for dx, dz in [(-1, 0), (1, 0), (0, 1), (0, -1)]:
        wood.box((.19, .18, .55), (dz * .24, .09, dx * .24), "bark", math.pi / 2 if dz else 0)
        wood.box((.18, .9, .2), (dx * .43, 1.52, dz * .43), "bark_light")
        wood.box((.92 if dx else .2, .21, .92 if dz else .2), (dx * .27, 1.45, dz * .27), "bark")
    # Connected lobes, broad quiet planes and a few stepped edges, not confetti.
    lobes = [(-.52, 2.02, .18, 1.25), (.46, 2.08, -.16, 1.42),
             (0, 2.77, .02, 1.4), (-.35, 2.38, -.56, 1.08),
             (.40, 2.33, .55, 1.08), (-.67, 2.44, .48, .69)]
    for i, (x, y, z, w) in enumerate(lobes):
        y += variant * .09 * (i % 2)
        leaves.box((w, .86 if i != 2 else .70, w * .91), (x, y, z), "leaf" if i % 3 else "leaf_dark")
        leaves.box((w * .87, .12, w * .79), (x - .045, y + .47 if i != 2 else y + .40, z - .035), "leaf_light", variation=variant * .015)
        if i in (0, 1, 3):
            leaves.box((.32, .22, .37), (x - w * .37, y + .22, z + w * .43), "leaf_light")
    model(name, {"Trunk": wood, "Crown": leaves})


def pine(name, snow=False):
    wood, leaves, caps = Blocks(), Blocks(), Blocks()
    wood.box((.27, 3.55, .28), (0, 1.775, 0), "bark")
    for i, (y, w) in enumerate([(1.2, 2.2), (1.9, 1.8), (2.6, 1.36), (3.22, .87), (3.65, .40)]):
        def cross(target, width, height, at, tint):
            # Three adjacent prisms form a plus, with no overlapping top faces.
            target.box((width, height, width * .57), (0, at, 0), tint)
            for sign in (-1, 1):
                target.box((width * .57, height, width * .215), (0, at, sign * width * .3925), tint)
        cross(leaves, w, .42, y, "pine")
        cross(leaves, w * .81, .30, y + .31, "pine_light")
        if snow:
            cross(caps, w * .86, .13, y + .515, "snow")
        if i < 3:
            for sign in (-1, 1):
                leaves.box((.20, .21, .29), (sign * w * .45, y - .25, .13), "pine")
    groups = {"Trunk": wood, "Crown": leaves}
    if snow:
        groups["SnowCaps"] = caps
    model(name, groups)


def cottage(name, snowy=False):
    b = Blocks()
    b.box((2.0, .26, 1.7), (0, .13, 0), "stone_dark")
    b.box((1.80, 1.40, 1.52), (0, .93, 0), "plaster")
    for x in (-.88, .88):
        for z in (-.74, .74):
            b.box((.13, 1.44, .14), (x, .98, z), "wood_dark")
    for y in (.38, 1.53):
        b.box((1.92, .12, 1.64), (0, y, 0), "wood")
    for x in (-.57, .55):
        b.box((.34, .43, .035), (x, 1.03, .78), "dark")
        b.box((.29, .32, .045), (x, 1.02, .8), "gold")
        b.box((.055, .43, .05), (x, 1.03, .83), "wood_dark")
        b.box((.43, .09, .14), (x, .78, .82), "wood_light")
    b.box((.38, .86, .06), (0, .72, .81), "wood_dark")
    for x in (-.12, 0, .12):
        b.box((.06, .76, .04), (x, .72, .845), "wood")
    b.box((.06, .06, .05), (.1, .72, .88), "gold")
    for i in range(3):
        b.box((.70, .11, .30), (0, .06 + .095 * i, 1.37 - i * .23), "stone_light")
    for i in range(6):
        width = 2.14 - i * .31
        b.box((width, .19, 1.93), (0, 1.66 + i * .155, 0), "slate" if snowy else "roof")
        for z in range(6):
            for sign in (-1, 1):
                b.box((.20, .045, .28), (sign * (width / 2 - .08), 1.78 + i * .155, -.79 + z * .32), "snow" if snowy else "roof_light")
    b.box((.30, .16, 2.02), (0, 2.60, 0), "snow" if snowy else "wood_light")
    b.box((.30, .77, .32), (.48, 2.2, -.37), "stone_dark")
    for y in range(5):
        b.box((.32, .11, .34), (.48, 1.91 + y * .14, -.37), "stone_light")
    b.box((.40, .12, .41), (.48, 2.67, -.37), "snow" if snowy else "stone")
    model(name, {"House": b})


def tower(name, snow=False, timber=False):
    b = Blocks()
    b.box((2.08, .28, 1.9), (0, .14, 0), "stone_dark")
    if timber:
        for x in (-.65, .65):
            for z in (-.58, .58):
                b.box((.22, 2.2, .22), (x, 1.31, z), "wood_dark")
        for y in (.48, 1.72, 2.42):
            b.box((1.82, .16, 1.65), (0, y, 0), "wood_light")
        for i in range(9):
            b.box((.50, .07, .09), (0, .4 + i * .22, .87), "wood_light")
        for x in (-.26, .26):
            b.box((.07, 2.0, .09), (x, 1.2, .87), "wood")
        b.box((1.50, .74, 1.34), (0, 2.0, 0), "wood")
        for x in (-.5, 0, .5):
            b.box((.21, .28, .06), (x, 2.1, .70), "dark")
    else:
        b.box((1.60, 2.55, 1.46), (0, 1.5, 0), "stone")
        for row in range(7):
            for j in range(3):
                x = -.55 + j * .53
                b.box((.50, .31, .06), (x, .42 + row * .34, .757), "stone_light", variation=-.018 * ((row + j) % 3))
        for x in (-.81, .81):
            b.box((.20, 2.68, 1.64), (x, 1.49, 0), "stone_light")
        for z in (-.84, .84):
            b.box((1.96, .20, .17), (0, 2.84, z), "stone_light")
        for x in (-.72, 0, .72):
            for z in (-.80, .80):
                b.box((.37, .43, .33), (x, 3.10, z), "stone_light")
                if snow:
                    b.box((.44, .12, .39), (x - .03, 3.38, z), "snow")
        b.box((.22, .72, .05), (0, 2.1, .82), "dark")
        b.box((.15, .40, .06), (0, 2.0, .85), "gold")
    if timber:
        for i in range(5):
            b.box((2.02 - i * .32, .17, 1.92 - i * .22), (0, 2.59 + i * .16, 0), "slate")
    model(name, {"Structure": b})


def bridge():
    b = Blocks()
    # Local origin is the walking surface; pilings reach the river bed.
    for z in (-.69, .69):
        b.box((7.0, .24, .18), (0, -.23, z), "wood_dark")
    for i in range(27):
        x = -3.38 + i * .26
        b.box((.24, .16, 1.72), (x, -.04, 0), "wood_light", variation=.014 * (i % 3))
    for x in (-3.3, -2.2, -1.1, 0, 1.1, 2.2, 3.3):
        for z in (-.88, .88):
            b.box((.15, 1.05, .15), (x, .41, z), "wood_dark")
            b.box((.23, .09, .23), (x, .975, z), "wood_light")
    for z in (-.89, .89):
        b.box((6.9, .12, .12), (0, .82, z), "wood_light")
        b.box((6.9, .085, .10), (0, .36, z), "wood")
    for x in (-1.85, 1.65):
        for z in (-.67, .67):
            b.box((.30, 1.48, .33), (x, -.74, z), "wood_dark")
            b.box((.40, .17, .41), (x, -.35, z), "stone_dark")
    model("bridge", {"Timber": b})


def fort():
    b = Blocks()
    b.box((5.4, .25, 4.5), (0, .125, 0), "stone_dark")
    for z in (-1.85, 1.85):
        if z < 0:
            b.box((4.8, 1.65, .45), (0, 1.03, z), "stone")
        else:
            for x in (-1.67, 1.67):
                b.box((1.7, 1.65, .45), (x, 1.03, z), "stone")
            b.box((1.45, .53, .54), (0, 1.68, z), "stone_light")
        for j in range(11):
            x = -2.3 + j * .46
            b.box((.31, .36, .50), (x, 2.01, z), "stone_light")
            b.box((.38, .10, .55), (x, 2.24, z), "snow")
    for x in (-2.35, 2.35):
        b.box((.45, 1.65, 3.8), (x, 1.03, 0), "stone")
        for z in range(9):
            b.box((.53, .34, .29), (x, 2.03, -1.82 + z * .45), "snow")
    for row in range(4):
        for j in range(9):
            x = -2.08 + j * .51
            if abs(x) > .77:
                b.box((.48, .27, .055), (x, .50 + row * .32, 2.10), "stone_light", variation=-.03 * (j % 2))
    for i in range(4):
        b.box((1.38, .13, .38), (0, .065 + i * .07, 3.05 - i * .28), "stone_light")
    # Recessed courtyard, high central keep and its six stepped roof courses.
    b.box((4.30, .10, 3.24), (0, .30, 0), "ice")
    b.box((2.12, 3.2, 1.98), (.16, 1.95, -.35), "stone_light")
    for x in (-.95, 1.24):
        b.box((.23, 3.28, 2.14), (x, 1.98, -.35), "stone")
    for x in (-.43, .62):
        for y in (1.49, 2.55):
            b.box((.25, .60, .06), (x, y, .67), "dark")
            b.box((.15, .38, .07), (x, y - .06, .71), "gold")
    for i in range(6):
        w = 2.65 - i * .35
        b.box((w, .19, 2.51 - i * .32), (.16, 3.67 + i * .20, -.35), "slate")
        b.box((w * .94, .09, (2.51 - i * .32) * .94), (.12, 3.82 + i * .20, -.40), "snow")
    model("summit_fort", {"Citadel": b}, extra_imports='[ext_resource type="PackedScene" path="res://scenes/campaign/models/snow_tower.tscn" id="tower"]\n\n', extra_nodes='''[node name="WestTower" parent="." instance=ExtResource("tower")]
position = Vector3(-2.23, 0.12, -1.55)
scale = Vector3(0.73, 0.9, 0.73)

[node name="EastTower" parent="." instance=ExtResource("tower")]
position = Vector3(2.23, 0.12, -1.55)
scale = Vector3(0.73, 0.9, 0.73)
''')


def flag():
    b = Blocks()
    b.box((.075, 2.2, .075), (0, 1.1, 0), "wood_dark")
    b.box((.15, .15, .15), (0, 2.22, 0), "gold")
    resources = '''[sub_resource type="PlaneMesh" id="Cloth"]
size = Vector2(0.88, 0.54)
orientation = 2
subdivide_width = 10
subdivide_depth = 3

[sub_resource type="ShaderMaterial" id="FlagMaterial"]
shader = ExtResource("flag_shader")

'''
    nodes = '''[node name="Banner" type="MeshInstance3D" parent="."]
position = Vector3(0.43, 1.84, 0)
mesh = SubResource("Cloth")
material_override = SubResource("FlagMaterial")
'''
    model("flag", {"Pole": b}, extra_resources=resources, extra_nodes=nodes,
          extra_imports='[ext_resource type="Shader" path="res://assets/campaign/banner.gdshader" id="flag_shader"]\n\n')


# A single shared terrain definition is used for model placement and the road.
def river_x(z):
    return -3.2 + 1.3 * math.sin(z * .29)


def in_river(x, z):
    return abs(x - river_x(z)) < (1.40 + .2 * math.cos(z * .6))


def inside(x, z):
    return (abs(x / 28.0) ** 4 + abs((z + .2) / 12.4) ** 4 < 1.0
            and abs(z) < 11.5 + .75 * math.sin(x * .31))


def terrain_height(x, z):
    # Spatial scales are deliberate: calm meadow shelves, then rugged peaks.
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
    # Authored level pads at the gate, winter hamlet and final citadel.
    for px, pz, rx, rz, target in [(-14, -5.3, 3, 1.8, 1.6), (5, -3.8, 2.9, 2.8, 2.4), (13, 2.5, 3.0, 2.6, 3.6), (21, -3.7, 4.1, 4.1, 6.4)]:
        if abs(x - px) < rx and abs(z - pz) < rz:
            h = target
    # A broad approach makes the summit reachable on real stone stairs.
    if 14 < x < 18.1 and -.8 < z < 2.8:
        h = max(h, 3.6 + (x - 14) * .70)
    return round(h / .4) * .4


HEIGHTS = {(x, z): terrain_height(x + .5, z + .5)
           for x in range(-28, 28) for z in range(-12, 12) if inside(x + .5, z + .5)}


def ground(x, z):
    return HEIGHTS[(math.floor(x), math.floor(z))]


ROUTE_XZ = [(-23, 5), (-21, 4.8), (-19.2, 3.5), (-18.5, 1.3),
            (-17, -1), (-14, -2.6), (-12.5, -3), (-10, -2), (-8, .1),
            (-7, 2.5), (-6, 2.5), (-3, 2.5), (.3, 2.5), (2, 1.2),
            (3, -1), (5, -2.5), (7.5, -1.2), (8.8, 1), (10, 3.8),
            (13, 4), (15, 3.2), (16, 1), (17, .4), (18, -.7),
            (20, -.7), (21, -1.2)]
STOP_INDICES = [0, 6, 11, 15, 19, 25]


def path_height(x, z):
    return 1.22 if -6.5 < x < .55 and abs(z - 2.5) < .4 else ground(x, z) + .14


def interpolate_route():
    result = []
    for i in range(len(ROUTE_XZ) - 1):
        a, b = ROUTE_XZ[max(0, i - 1)], ROUTE_XZ[i]
        c, d = ROUTE_XZ[i + 1], ROUTE_XZ[min(len(ROUTE_XZ) - 1, i + 2)]
        count = max(4, math.ceil(math.dist(b, c) / .17))
        for step in range(count):
            t = step / count
            p = tuple(.5 * ((2*b[k]) + (-a[k]+c[k])*t + (2*a[k]-5*b[k]+4*c[k]-d[k])*t*t + (-a[k]+3*b[k]-3*c[k]+d[k])*t*t*t) for k in (0, 1))
            result.append(p)
    result.append(ROUTE_XZ[-1])
    return result


def build_world():
    route = interpolate_route()
    # The least raised grade envelope stays above the terrain without vertical
    # jumps. Quantized risers turn it into a continuous, supported stone stair.
    elevations = [path_height(x, z) for x, z in route]
    for traversal in (range(1, len(route)), range(len(route) - 2, -1, -1)):
        forward = traversal.step > 0
        for i in traversal:
            neighbor = i - 1 if forward else i + 1
            elevations[i] = max(elevations[i], elevations[neighbor] - .64 * math.dist(route[i], route[neighbor]))
    elevations = [math.ceil((y - 1e-7) / .14) * .14 for y in elevations]
    for i, (x, z) in enumerate(route):
        if -6.5 < x < .55 and abs(z - 2.5) < .4:
            elevations[i] = 1.22
    assert max(abs(a - b) for a, b in zip(elevations, elevations[1:])) < .29
    groups = defaultdict(Blocks)
    for (ix, iz), h in HEIGHTS.items():
        x, z = ix + .5, iz + .5
        river = in_river(x, z)
        section = "West" if x < -5 else "Valley" if x < 7 else "Alpine"
        top = -.28 if river else h - .16
        variation = .012 * math.sin(x * .49) * math.cos(z * .37)
        groups[section + "Bedrock"].box((1, top + 2.5, 1), (x, (top - 2.5) / 2, z), "stone_dark" if x > 0 else "earth", variation=variation)
        if river:
            groups["River"].box((1, .08, 1), (x, .035, z), "water")
            continue
        snow = x > 10 + 1.2 * math.sin(z * .45) or h > 5.2
        rocky = h > 4.7 or (x > 1 and z < -5)
        tint = "snow" if snow else "grass"
        if not snow and rocky:
            tint = "stone"
        # Only exposed cliffs receive separate strata; no lawn checkerboard.
        exposed = any(HEIGHTS.get((ix + dx, iz + dz), -3) < h - .3 or in_river(x + dx, z + dz) for dx, dz in [(1, 0), (-1, 0), (0, 1), (0, -1)])
        if exposed:
            groups[section + "Strata"].box((1.005, .25, 1.005), (x, h - .38, z), "ice" if snow else "stone" if rocky else "bark_light", variation=variation)
        groups[section + "Surface"].box((1, .20 if snow else .16, 1), (x, h - .08, z), tint, variation=variation)
        if exposed and x > 1:
            below = HEIGHTS.get((ix, iz + 1), -2.5)
            fissure = math.sin(ix * 2.31 + iz * 5.17)
            if h - below > .65 and fissure > -.25:
                relief = min(h - below - .24, .72 + .65 * abs(fissure))
                groups["CliffRelief"].box((.46 + .28 * abs(fissure), relief, .12), (x - .11 * fissure, h - .27 - relief / 2, z + .49), "stone", variation=.016 * math.sin(ix))
    for x, z in [(4.5, -8.5), (11.5, -9.5), (18.5, -10.5), (25.5, -7.5)]:
        y = ground(x, z)
        groups["PeakCrests"].box((.95, 1.15, .95), (x, y + .46, z), "stone")
        groups["PeakCrests"].box((1, .18, .99), (x - .025, y + 1.10, z - .02), "snow")
        groups["PeakCrests"].box((.58, .42, .61), (x - .11, y + 1.32, z - .06), "stone_light")
        groups["PeakCrests"].box((.62, .10, .65), (x - .12, y + 1.58, z - .08), "snow")
    # Walking surface is small warm flagstones that follow all terraces.
    for i, ((x, z), (nx, nz)) in enumerate(zip(route, route[1:])):
        if -6.45 < x < .48 and abs(z - 2.5) < .4:
            continue
        y, ny = elevations[i], elevations[i + 1]
        length = math.dist((x, z), (nx, nz))
        level = max(y, ny)
        tangent_x, tangent_z = (nx - x) / length, (nz - z) / length
        footprint = [(px + sign * tangent_z * .35, pz - sign * tangent_x * .35)
                     for px, pz in [(x, z), (nx, nz)] for sign in (-1, 1)]
        base = min(ground(px, pz) for px, pz in footprint) - .04
        groups["TrailSupports"].box((.62, level - base - .07, length), ((x + nx) / 2, (level + base) / 2 - .035, (z + nz) / 2), "stone", math.atan2(nx - x, nz - z))
        groups["Trail"].box((.68 + .02 * math.sin(i * .39), .09, length), ((x + nx) / 2, level - .035, (z + nz) / 2), "road", math.atan2(nx - x, nz - z), variation=.006 * (i % 3))
    # Sparse reeds, flowers and fallen logs; the broad meadow remains quiet.
    for i in range(230):
        x, z = RNG.uniform(-26, 25), RNG.uniform(-10.5, 10)
        if not inside(x, z) or (math.floor(x), math.floor(z)) not in HEIGHTS or in_river(x, z):
            continue
        if min(math.dist((x, z), p) for p in route) < .8:
            continue
        y = ground(x, z)
        if x < 8 and y < 3.5:
            for j in range(3):
                dx, dz = RNG.uniform(-.25, .25), RNG.uniform(-.2, .2)
                groups["MeadowDetails"].box((.035, .16 + j * .04, .06), (x + dx, y + .09, z + dz), "leaf_dark")
                if i % 3 == 0:
                    groups["MeadowDetails"].box((.12, .065, .12), (x + dx, y + .20, z + dz), "flower")
        elif x > 9 and i % 3 == 0:
            groups["SnowDetails"].box((.55, .15, .43), (x, y + .025, z), "ice")
            groups["SnowDetails"].box((.51, .08, .39), (x - .03, y + .13, z), "snow")
    # Readable ledge rocks are grounded, with the path and buildings excluded.
    rocks = []
    for i in range(48):
        x, z = RNG.uniform(-25, 25), RNG.uniform(-10.5, 10.3)
        if (math.floor(x), math.floor(z)) not in HEIGHTS or in_river(x, z) or min(math.dist((x, z), p) for p in route) < 1.4:
            continue
        if any(abs(x - px) < 3 and abs(z - pz) < 2.5 for px, pz in [(-23, 1), (-13, -5), (5, -4), (13, 1), (21, -4)]):
            continue
        y = ground(x, z)
        w = RNG.uniform(.5, 1.35)
        groups["LedgeRocks"].box((w, w * .54, w * .8), (x, y + w * .20, z), "stone", variation=RNG.uniform(-.04, .02))
        groups["LedgeRocks"].box((w * .71, .16, w * .64), (x - .07, y + w * .47, z - .04), "snow" if x > 9 else "stone_light")
        groups["LedgeRocks"].box((w * .36, w * .27, w * .40), (x + w * .46, y + w * .09, z + w * .13), "stone_dark")
        rocks.append((x, z, w))
    # A tiny cultivated field and fence provide human scale at the western camp.
    for row in range(5):
        z = 7.4 + row * .38
        groups["VillageGarden"].box((2.6, .08, .16), (-23, ground(-23, z) + .04, z), "earth")
        for j in range(13):
            groups["VillageGarden"].box((.08, .24, .12), (-24.2 + j * .20, ground(-23, z) + .18, z), "roof_light")
    for x in [-25, -24, -23, -22, -21]:
        y = ground(x, 9.4)
        groups["VillageGarden"].box((.12, .70, .12), (x, y + .34, 9.4), "wood")
    groups["VillageGarden"].box((4.1, .09, .09), (-23, ground(-23, 9.4) + .5, 9.4), "wood_light")
    # Frontier palisade and alpine gate frame, each kept clear of the route.
    for x in [-17.6, -17.2, -16.8, -16.4, -11.4, -11, -10.6, -10.2]:
        y = ground(x, -5)
        groups["FrontierDetails"].box((.30, 1.1, .27), (x, y + .53, -5), "wood")
        groups["FrontierDetails"].box((.19, .14, .19), (x, y + 1.13, -5), "wood_light")
    for x in (3.7, 6.45):
        y = ground(x, -2.8)
        for step in range(6):
            groups["PassGate"].box((.56, .30, .69), (x, y + .16 + step * .32, -2.8), "stone_light" if step % 2 else "stone")
    groups["PassGate"].box((3.45, .35, .83), (5.08, 4.58, -2.8), "wood_dark")
    groups["PassGate"].box((3.6, .12, .90), (5.08, 4.82, -2.8), "stone_light")
    # Small bank shelves and stepping foam marks sit above water, below grass.
    for iz in range(-11, 12):
        river_cells = [x for (x, z) in HEIGHTS if z == iz and in_river(x + .5, z + .5)]
        if not river_cells:
            continue
        for x in (min(river_cells) + .08, max(river_cells) + .90):
            if iz % 2 == 0:
                groups["RiverEdges"].box((.12, .035, .58), (x, .10, iz + .5), "ice")
    # Trim the bedrock behind the river mouth into an actual falling-water lip.
    for ix, iz in HEIGHTS:
        if in_river(ix + .5, iz + .5) and iz > 8 and (ix, iz + 1) not in HEIGHTS:
            groups["Falls"].box((1, 2.55, .08), (ix + .5, -1.20, iz + .96), "water")
            groups["FallsFoam"].box((1, .09, .38), (ix + .5, -2.48, iz + 1.08), "ice")

    text = '[gd_scene format=3]\n\n'
    models = ['oak_a', 'oak_b', 'pine', 'snow_pine', 'cottage', 'winter_cottage', 'timber_tower', 'snow_tower', 'bridge', 'summit_fort', 'flag']
    for m in models:
        text += f'[ext_resource type="PackedScene" path="res://scenes/campaign/models/{m}.tscn" id="{m}"]\n'
    text += '[ext_resource type="Shader" path="res://assets/campaign/river.gdshader" id="water_shader"]\n'
    text += '[ext_resource type="Shader" path="res://assets/campaign/waterfall.gdshader" id="fall_shader"]\n'
    text += '[ext_resource type="Curve3D" path="res://data/campaign/journey_3d.tres" id="journey"]\n\n'
    text += '[sub_resource type="BoxMesh" id="Cube"]\nsize = Vector3(1, 1, 1)\n\n'
    text += '[sub_resource type="StandardMaterial3D" id="Matte"]\nvertex_color_use_as_albedo = true\nroughness = 0.92\n\n'
    text += '[sub_resource type="ShaderMaterial" id="Water"]\nshader = ExtResource("water_shader")\n\n'
    text += '[sub_resource type="ShaderMaterial" id="FallingWater"]\nshader = ExtResource("fall_shader")\n\n'
    for group, blocks in groups.items():
        text += blocks.res(group)
    text += '[node name="Landscape" type="Node3D"]\n\n'
    text += '[node name="Terrain" type="Node3D" parent="."]\n\n'
    for group in groups:
        mat = "Water" if group == "River" else "FallingWater" if group == "Falls" else "Matte"
        text += f'[node name="{group}" type="MultiMeshInstance3D" parent="Terrain"]\nmultimesh = SubResource("{group}")\nmaterial_override = SubResource("{mat}")\n\n'

    text += '[node name="Landmarks" type="Node3D" parent="."]\n\n'
    def place(name, asset, x, z, scale=1, angle=0, y=None, parent="Landmarks"):
        nonlocal text
        if y is None:
            y = ground(x, z) + .04
        text += f'[node name="{name}" parent="{parent}" instance=ExtResource("{asset}")]\nposition = {vec((x, y, z))}\nrotation = {vec((0, angle, 0))}\nscale = {vec((scale, scale, scale))}\n\n'

    place("CampLodge", "cottage", -23.4, 1.8, 1.0, -.12)
    place("CampBarn", "cottage", -20.7, 1.1, .86, .20)
    place("CampCabin", "cottage", -25.2, 3.7, .74, -.18)
    place("WoodlandWatch", "timber_tower", -12.6, -5.2, 1.05)
    place("WatchLodge", "cottage", -15.2, -4.9, .75, .17)
    place("Crossing", "bridge", -3, 2.5, y=1.22)
    place("PassWatch", "snow_tower", 5.1, -4.6, .86)
    place("WinterLodge", "winter_cottage", 12.7, 1.0, 1.0, -.12)
    place("WinterCabin", "winter_cottage", 15.1, 1.9, .77, .19)
    place("SnowCrown", "summit_fort", 21, -4.2, .92, y=6.46)
    for i, (x, z) in enumerate([(-21.1, 3.6), (-11.3, -4.2), (-6.45, 1.35), (6.3, -3.4), (11.6, 2.6), (21.15, -4.52)]):
        place(f"Banner{i+1}", "flag", x, z, .7, y=11.15 if i == 5 else None)

    text += '[node name="Groves" type="Node3D" parent="."]\n\n'
    occupied = []
    grove_centers = [(-24, -5, 4.0, 2.9, 22), (-17.5, -7.5, 4.6, 2.4, 25),
                     (-18, 6.5, 3.1, 2.6, 19), (-8, -7.2, 2.8, 3.0, 15),
                     (-8, 7.2, 3.4, 2.2, 19), (2.4, -7.5, 2.6, 2.7, 12),
                     (3, 6.7, 3.3, 2.6, 17), (9.0, -5.8, 2.4, 2.4, 13),
                     (13, 8, 3.4, 1.8, 18), (22.9, 3.5, 2.7, 2.6, 16),
                     (17, -7, 2.4, 2, 10)]
    landmarks = [(-23.4, 1.8, 1.65), (-20.7, 1.1, 1.45), (-25.2, 3.7, 1.5),
                 (-12.6, -5.2, 1.65), (-15.2, -4.9, 1.4), (5.1, -4.6, 1.7),
                 (12.7, 1, 1.8), (15.1, 1.9, 1.6), (21, -4.2, 4.2)]
    tree_count = 0
    for g, (cx, cz, rx, rz, count) in enumerate(grove_centers):
        group = f"Groves/Grove{g+1:02}"
        text += f'[node name="Grove{g+1:02}" type="Node3D" parent="Groves"]\n\n'
        for attempt in range(count * 15):
            if sum(1 for p in occupied if p[3] == g) >= count:
                break
            angle, r = RNG.uniform(0, 2*math.pi), math.sqrt(RNG.random())
            x, z = cx + rx*r*math.cos(angle), cz + rz*r*math.sin(angle)
            if (math.floor(x), math.floor(z)) not in HEIGHTS or not inside(x, z) or in_river(x, z):
                continue
            scale = RNG.uniform(.60, 1.0)
            radius = scale * .83
            if min(math.dist((x, z), p) for p in route) < radius + .60:
                continue
            if any(math.dist((x, z), (px, pz)) < radius + rad for px, pz, rad in landmarks):
                continue
            if any(math.dist((x, z), (px, pz)) < radius + pr for px, pz, pr, _ in occupied):
                continue
            if any(math.dist((x, z), (px, pz)) < radius + w * .55 for px, pz, w in rocks):
                continue
            if any(math.dist((x, z), (px, pz)) < radius + .8 for px, pz in [(4.5, -8.5), (11.5, -9.5), (18.5, -10.5), (25.5, -7.5)]):
                continue
            # Avoid hanging tree roots over a terrace or a river bank.
            y = ground(x, z)
            foot_cells = [(math.floor(x + dx), math.floor(z + dz)) for dx, dz in [(-.38, 0), (.38, 0), (0, -.38), (0, .38)]]
            if any(HEIGHTS.get(cell, -100) != y or in_river(cell[0]+.5, cell[1]+.5) for cell in foot_cells):
                continue
            asset = "snow_pine" if x > 9 or y > 5.2 else "pine" if x > -5 or RNG.random() < .16 else RNG.choice(["oak_a", "oak_b"])
            place(f"Tree{tree_count:03}", asset, x, z, scale, RNG.uniform(-.22, .22), parent=group)
            tree_count += 1
            occupied.append((x, z, radius, g))

    text += '[node name="StageAnchors" type="Node3D" parent="."]\n\n'
    for i, index in enumerate(STOP_INDICES):
        x, z = ROUTE_XZ[index]
        sample = min(range(len(route)), key=lambda n: math.dist(route[n], (x, z)))
        assert math.dist(route[sample], (x, z)) < 1e-5
        text += f'[node name="Stage{i+1:02}" type="Marker3D" parent="StageAnchors"]\nposition = {vec((x, elevations[sample] + .09, z))}\n\n'
    text += '[node name="Journey" type="Path3D" parent="."]\ncurve = ExtResource("journey")\n'
    write(ROOT / "scenes/campaign/campaign_landscape.tscn", text)
    curve = []
    for (x, z), y in zip(route, elevations):
        curve.extend([0, 0, 0, 0, 0, 0, x, y + .09, z])
    write(ROOT / "data/campaign/journey_3d.tres", '[gd_resource type="Curve3D" format=3]\n\n[resource]\nbake_interval = 0.10\n_data = {\n"points": PackedVector3Array(' + ', '.join(map(fmt, curve)) + '),\n"tilts": PackedFloat32Array(' + ', '.join('0' for _ in route) + f')\n}}\npoint_count = {len(route)}\n')
    print(f"Authored {tree_count} trees in {len(grove_centers)} groves; {sum(len(b.parts) for b in groups.values())} terrain/detail blocks; {len(route)} 3D route points.")


if __name__ == "__main__":
    oak("oak_a", 0)
    oak("oak_b", 1)
    pine("pine")
    pine("snow_pine", True)
    cottage("cottage")
    cottage("winter_cottage", True)
    tower("timber_tower", timber=True)
    tower("snow_tower", snow=True)
    bridge()
    fort()
    flag()
    build_world()
