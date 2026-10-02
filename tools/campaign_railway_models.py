"""Author the railway's editable, native Godot model scenes (offline only).

Shape reference: medieval-voxel-railway/src/props.js and train.js supplied by
the user. Stair roofs, inset plaster, exposed beams, square tree lobes, eight
sided locomotive boiler and coach proportions follow those models. Colours
are quieter: warm limestone, worn timber, grey green foliage and teal enamel.

Godot native references checked before authoring (2026-10-02):
https://docs.godotengine.org/en/stable/classes/class_multimeshinstance3d.html
https://docs.godotengine.org/en/stable/classes/class_cylindermesh.html
https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html
https://docs.godotengine.org/en/stable/classes/class_particleprocessmaterial.html

Station local rail centre is z=0, rails run along X, buildings face +Z.
Vehicles face -Z and y=0 is wheel contact. Vehicle placement offsets, measured
backwards from the locomotive centre, are 0, 1.51 and 2.94 metres.
Run: python tools/campaign_railway_models.py
"""
from collections import OrderedDict
from pathlib import Path
import math
import random

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "scenes/campaign/railway_models"
C = {
    "foundation": "a69f91", "stone": "c2bbae", "stone_dark": "9f978b",
    "plaster": "ede2c9", "timber": "705039", "timber_dark": "584331",
    "wood": "a47c51", "wood_light": "bf9965", "door": "825b3c",
    "glass": "637b87", "glow": "eed6a0", "metal": "464951",
    "gold": "c9aa68", "cream": "efe3c7", "teal": "4a8179",
    "teal_dark": "366e68", "red": "ad6552", "roof": "a36b54",
    "blue_roof": "637d8e", "leaf": "758967", "leaf_light": "87987a",
    "leaf_dark": "62795b", "pine": "4d7365", "pine_light": "658574",
    "bark": "7a5d44", "snow": "e5edeb", "coal": "34343a",
    "flower": "cba88f", "lavender": "a29bad", "ochre": "c4a56e",
}


def fmt(v):
    return f"{v:.6f}".rstrip("0").rstrip(".") if v else "0"


def vector(v):
    return "Vector3(" + ", ".join(fmt(n) for n in v) + ")"


def rgb(col):
    value = C.get(col, col)
    return tuple(int(value[k:k + 2], 16) / 255 for k in (0, 2, 4))


def linear(col, strength=1):
    return tuple((v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4) * strength for v in rgb(col))


def shade(col, amount):
    return "".join(f"{min(255, round(c * amount * 255)):02x}" for c in rgb(col))


def write(path, content):
    content = content.rstrip() + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_text(encoding="utf-8") != content:
        path.write_text(content, encoding="utf-8", newline="\n")


def product(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]


class Boxes:
    def __init__(self, scale=1, origin=(0, 0, 0), vehicle=False, seed=31):
        self.parts = []
        self.scale = scale
        self.origin = origin
        self.vehicle = vehicle
        self.rnd = random.Random(seed)

    def box(self, x, y, z, sx, sy, sz, col, ry=0, rz=0, rx=0, jitter=.025):
        cy, syaw, cz, szr, cx, sxr = math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz), math.cos(rx), math.sin(rx)
        basis = product(product([[cy, 0, syaw], [0, 1, 0], [-syaw, 0, cy]],
                                [[cz, -szr, 0], [szr, cz, 0], [0, 0, 1]]),
                        [[1, 0, 0], [0, cx, -sxr], [0, sxr, cx]])
        if self.vehicle:
            basis = product([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], basis)
            x, z = z, -x
        pos = [v * self.scale + d for v, d in zip((x, y, z), self.origin)]
        dim = [v * self.scale for v in (sx, sy, sz)]
        transform = [component for r in range(3) for component in
                     [*(basis[r][c] * dim[c] for c in range(3)), pos[r]]]
        self.parts.append((*transform, *linear(col, 1 + self.rnd.uniform(-jitter, jitter)), 1))

    def cube(self, x, y, z, sx, sy, sz, col, jitter=.025):
        self.box(x + sx / 2, y + sy / 2, z + sz / 2, sx, sy, sz, col, jitter=jitter)

    def resource(self, name):
        return (f'[sub_resource type="MultiMesh" id="{name}"]\ntransform_format = 1\n'
                'use_colors = true\n' + f'instance_count = {len(self.parts)}\nmesh = SubResource("Cube")\n'
                'buffer = PackedFloat32Array(' + ', '.join(fmt(n) for p in self.parts for n in p) + ')\n\n')


class Model:
    def __init__(self, name, scale=1, origin=(0, 0, 0), vehicle=False):
        self.name, self.scale, self.origin, self.vehicle = name, scale, origin, vehicle
        self.groups = OrderedDict()
        self.resources, self.nodes = [], []

    def group(self, name):
        if name not in self.groups:
            self.groups[name] = Boxes(self.scale, self.origin, self.vehicle, 31 + len(self.groups))
        return self.groups[name]

    def cylinder(self, name, pos, radius, length, col, axis="x"):
        # Primitive dimensions/placement are transformed exactly as the boxes.
        x, y, z = pos
        if self.vehicle:
            x, z = z, -x
            axis = "z" if axis == "x" else "x" if axis == "z" else "y"
        p = [v * self.scale + d for v, d in zip((x, y, z), self.origin)]
        rotation = {"x": (0, 0, math.pi / 2), "y": (0, 0, 0), "z": (math.pi / 2, 0, 0)}[axis]
        rgba = ', '.join(fmt(v) for v in (*rgb(col), 1))
        self.resources.append(f'[sub_resource type="StandardMaterial3D" id="Mat_{name}"]\nalbedo_color = Color({rgba})\nroughness = 0.84\n\n'
                              f'[sub_resource type="CylinderMesh" id="Mesh_{name}"]\nmaterial = SubResource("Mat_{name}")\n'
                              f'top_radius = {fmt(radius * self.scale)}\nbottom_radius = {fmt(radius * self.scale)}\nheight = {fmt(length * self.scale)}\nradial_segments = 8\n\n')
        self.nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="."]\nposition = {vector(p)}\nrotation = {vector(rotation)}\nmesh = SubResource("Mesh_{name}")\n\n')

    def save(self):
        scene = ('[gd_scene format=3]\n\n[sub_resource type="BoxMesh" id="Cube"]\nsize = Vector3(1, 1, 1)\n\n'
                 '[sub_resource type="StandardMaterial3D" id="Matte"]\nvertex_color_use_as_albedo = true\nroughness = 0.9\n\n')
        scene += ''.join(b.resource(name) for name, b in self.groups.items())
        scene += ''.join(self.resources)
        scene += f'[node name="{self.name}" type="Node3D"]\n\n'
        for name in self.groups:
            scene += f'[node name="{name}" type="MultiMeshInstance3D" parent="."]\nmultimesh = SubResource("{name}")\nmaterial_override = SubResource("Matte")\n\n'
        scene += ''.join(self.nodes)
        write(OUT / f"{self.name}.tscn", scene)


def wall(b, side, x0, z0, w, d):
    along_x = side[1] == "z"
    sign = 1 if side[0] == "+" else -1
    length = w if along_x else d
    face = (z0 + d if sign > 0 else z0) if along_x else (x0 + w if sign > 0 else x0)
    start = x0 if along_x else z0

    def put(along, y, out, sa, sy, so, col, tilt=0):
        p = face + out * sign
        if along_x:
            b.box(start + along, y + sy / 2, p, sa, sy, so, col, rz=tilt)
        else:
            b.box(p, y + sy / 2, start + along, so, sy, sa, col, rx=tilt)
    return length, put


def window(put, along, y, shutter, flowers=False):
    put(along, y - .05, .018, .52, .56, .05, "timber")
    put(along, y, .05, .36, .44, .04, "glass")
    put(along, y, .077, .035, .44, .02, "cream")
    put(along, y + .2, .078, .36, .035, .02, "cream")
    if shutter:
        for side in (-1, 1):
            put(along + side * .29, y - .02, .055, .14, .48, .05, shutter)
            for k in range(4):
                put(along + side * .29, y + .055 + k * .095, .088, .13, .019, .018, shade(shutter, .77))
    if flowers:
        put(along, y - .17, .105, .54, .12, .18, "wood")
        for k in range(3):
            put(along + (k - 1) * .15, y - .06, .13, .10, .085, .10, ["flower", "cream", "lavender"][k])


def frame(b, x0, y, z0, w, height, d, braces):
    for side in ("+z", "-z", "+x", "-x"):
        length, put = wall(b, side, x0, z0, w, d)
        n = max(1, round(length / 1.0))
        for k in range(n + 1):
            put(min(length - .06, max(.06, k / n * length)), y, .023, .12, height, .06, "timber")
        put(length / 2, y, .023, length, .08, .06, "timber")
        put(length / 2, y + height - .1, .023, length, .1, .06, "timber")
        if braces and n >= 2:
            seg = length / n
            length_beam = math.hypot(seg, height) * .92
            angle = math.pi / 2 - math.atan2(height, seg)
            for along, tilt in ((seg / 2, angle), (length - seg / 2, -angle)):
                put(along, y + height / 2 - length_beam / 2, .028, .09, length_beam, .045, "timber", tilt)


def roof(b, x0, z0, w, d, y, col, snow=False, axis="x", over=.22, step=.27, lh=.25):
    half = (d if axis == "x" else w) / 2 + over
    k = 0
    while half > .1:
        color = shade(col, .86) if k % 2 else col
        if axis == "x":
            b.cube(x0 - over, y, z0 + d / 2 - half, w + 2 * over, lh, 2 * half, color)
            if snow:
                b.cube(x0 - over, y + lh, z0 + d / 2 - half, w + 2 * over, .045, step * .86, "snow")
                b.cube(x0 - over, y + lh, z0 + d / 2 + half - step * .86, w + 2 * over, .045, step * .86, "snow")
        else:
            b.cube(x0 + w / 2 - half, y, z0 - over, 2 * half, lh, d + 2 * over, color)
        y += lh
        half -= step
        k += 1
    if axis == "x":
        b.cube(x0 - over - .05, y, z0 + d / 2 - .13, w + 2 * over + .1, .1, .26, "snow" if snow else shade(col, .75))
    else:
        b.cube(x0 + w / 2 - .13, y, z0 - over - .05, .26, .1, d + 2 * over + .1, shade(col, .75))
    return y + .1


def house_parts(m, x0, z0, w, d, floors=2, roof_col="roof", shutter="teal", snowy=False, base=0, chimney=True):
    stone, plaster, timber, windows, tiles = [m.group(n) for n in ("Stonework", "Plaster", "ExposedTimber", "WindowsAndShutters", "SteppedRoof")]
    stone.cube(x0 + .06, base, z0 + .06, w - .12, .3, d - .12, "foundation")
    y = base + .3
    ix, iz, iw, id_ = x0 + .16, z0 + .16, w - .32, d - .32
    plaster.cube(ix, y, iz, iw, 1.3, id_, "stone" if floors == 2 else "plaster")
    if floors == 1:
        frame(timber, ix, y, iz, iw, 1.3, id_, False)
    for side in ("+z", "-z", "+x", "-x"):
        length, put = wall(windows, side, ix, iz, iw, id_)
        door_pos = length / 2 if side == "+z" else -9
        if side == "+z":
            put(door_pos, y - .02, .02, .74, 1.04, .05, "timber_dark")
            put(door_pos, y, .05, .58, .94, .04, "door")
            put(door_pos + .18, y + .45, .08, .055, .055, .025, "gold")
            put(door_pos, base, .2, .9, .3, .36, "foundation")
        n = max(1, math.floor(length / 1.05))
        for k in range(n):
            along = (k + .5) / n * length
            if abs(along - door_pos) > .6:
                window(put, along, y + .55, shutter if floors == 1 else None, floors == 1)
        if floors == 2:
            _, stones = wall(stone, side, ix, iz, iw, id_)
            for k in range(max(2, round(length * 2))):
                stones(.22 + (k * .49) % (length - .4), y + .1 + (k % 3) * .3, .018, .28, .15, .055, "stone_dark")
    y += 1.3
    if floors == 2:
        timber.cube(x0 + .06, y, z0 + .06, w - .12, .12, d - .12, "timber")
        y += .12
        ux, uz, uw, ud = x0 + .08, z0 + .08, w - .16, d - .16
        plaster.cube(ux, y, uz, uw, 1.15, ud, "plaster")
        frame(timber, ux, y, uz, uw, 1.15, ud, True)
        for side in ("+z", "-z", "+x", "-x"):
            length, put = wall(windows, side, ux, uz, uw, ud)
            n = max(1, math.floor(length / 1.4))
            for k in range(n):
                window(put, (k + .5) / n * length, y + .45, shutter, True)
        y += 1.15
    timber.cube(x0 + .04, y, z0 + .04, w - .08, .1, d - .08, "timber")
    y += .1
    ridge = roof(tiles, x0, z0, w, d, y, roof_col, snowy)
    if chimney:
        cx, cz = x0 + w * .72, z0 + d / 2 + .35
        stone.box(cx, (y + ridge + .35) / 2, cz, .42, ridge + .35 - y, .42, "stone_dark")
        stone.box(cx, ridge + .41, cz, .54, .12, .54, "timber_dark")
    return ridge


def houses():
    for name, col, shutter, snowy in (("HalfTimberHouse", "roof", "teal", False),
                                     ("HalfTimberHouseBlue", "blue_roof", "ochre", False),
                                     ("SnowHouse", "blue_roof", "teal", True)):
        m = Model(name, scale=.72)
        house_parts(m, -1.5, -1.25, 3, 2.5, roof_col=col, shutter=shutter, snowy=snowy)
        m.save()
    m = Model("Cottage", scale=.72)
    house_parts(m, -1.5, -1.25, 3, 2.5, floors=1, roof_col="ochre")
    m.save()


def lamp(b, x, z, g, sc=1):
    for y, sx, sy, sz, col in ((.08, .26, .16, .26, "metal"), (.8, .09, 1.5, .09, "metal"),
                              (1.62, .3, .06, .3, "metal"), (1.45, .22, .28, .22, "glow"),
                              (1.66, .12, .08, .12, "metal")):
        b.box(x, g + y * sc, z, sx * sc, sy * sc, sz * sc, col)


def crate(b, x, z, g, s=.32):
    b.box(x, g + s / 2, z, s, s, s, "wood_light")
    b.box(x, g + s / 2, z, s + .01, s * .16, s + .01, "wood")
    for dx in (-s * .36, s * .36):
        b.box(x + dx, g + s / 2, z, s * .1, s + .015, s + .015, "wood")


def station(name="Station", snowy=False):
    m = Model(name, origin=(0, 0, -.25))
    platform, planks, furnishings = [m.group(n) for n in ("StonePlatform", "PlatformDeck", "Furnishings")]
    platform.cube(-2.3, 0, -1.85, 4.6, .22, 1.5, "stone")
    for k in range(24):
        planks.cube(-2.3 + k * 4.6 / 24 + .008, .22, -1.83, 4.6 / 24 - .015, .035, 1.28, "wood" if k % 2 else "wood_light")
    planks.cube(-2.3, .22, -.55, 4.6, .055, .2, "cream")
    for k in range(12):
        platform.cube(-2.28 + k * .38, .035, -.36, .35, .13, .04, "foundation")
    platform.cube(-2.58, 0, -.98, .3, .12, .65, "stone")
    # Reference station house reduced uniformly, preserving its stepped roof.
    building = Model("unused", scale=.64, origin=(-.38, .05, -2.87))
    house_parts(building, -1.8, -1.2, 3.6, 2.4, floors=1, roof_col="blue_roof" if snowy else "roof", snowy=snowy, chimney=False)
    for group, blocks in building.groups.items():
        m.groups[group] = blocks
    # Station nameboard surround, with a small clock above its entrance.
    furnishings.box(-.38, 1.07, -1.941, .92, .22, .052, "timber_dark")
    furnishings.box(-.38, 1.07, -1.909, .84, .155, .026, "teal_dark")
    for x in (-.76, 0):
        furnishings.box(x, 1.07, -1.891, .018, .105, .018, "gold")
    furnishings.box(-.38, 1.31, -1.916, .275, .275, .075, "timber_dark")
    furnishings.box(-.38, 1.31, -1.866, .223, .223, .028, "cream")
    furnishings.box(-.38, 1.35, -1.846, .018, .084, .016, "metal")
    furnishings.box(-.34, 1.31, -1.845, .084, .018, .016, "metal")
    # A timber waiting shelter, open toward the track.
    shelter = m.group("WaitingShelter")
    for x in (1.03, 2.05):
        for z in (-1.56, -.78):
            shelter.box(x, .83, z, .065, 1.17, .065, "timber")
    shelter.box(1.54, 1.36, -.78, 1.2, .09, .085, "timber")
    roof(shelter, .99, -1.63, 1.1, .91, 1.4, "blue_roof", snowy, over=.1, step=.14, lh=.10)
    for x in (-1.65, 1.54):
        furnishings.box(x, .45, -1.38, .66, .055, .24, "wood")
        furnishings.box(x, .59, -1.49, .66, .2, .045, "wood")
        for dx in (-.25, .25):
            furnishings.box(x + dx, .35, -1.38, .05, .2, .2, "metal")
    for x in (-2.13, .6):
        lamp(furnishings, x, -.63, .255, .68)
    for x in (-1.12, .43):
        furnishings.box(x, .37, -1.96, .33, .2, .29, "wood")
        furnishings.box(x, .49, -1.96, .29, .065, .25, "leaf_dark")
        for j in range(3):
            furnishings.box(x - .09 + j * .09, .54 + (j % 2) * .025, -1.94, .066, .072, .06, ["flower", "cream", "lavender"][j])
    crate(furnishings, 2.09, -1.12, .255, .25)
    crate(furnishings, 1.97, -1.53, .255, .29)
    if snowy:
        caps = m.group("SnowCaps")
        for x, z, width in ((-1.83, -1.73, .63), (-.03, -.85, .42), (.64, -1.28, .41)):
            caps.box(x, .276, z, width, .036, .27, "snow")
    m.save()


def trees():
    for name, leaf in (("Oak", "leaf"), ("OakLight", "leaf_light")):
        m = Model(name)
        trunk, crown = m.group("Trunk"), m.group("SquareCrown")
        trunk.box(0, .425, 0, .24, .85, .24, "bark")
        s, y = 1.15, .85
        crown.box(0, y + s * .45, 0, s, s * .9, s, leaf)
        crown.box(.045, y + s * .9 + s * .66 * .3, -.025, s * .66, s * .66 * .62, s * .66, shade(leaf, 1.08))
        for side, z in ((-1, .12), (1, -.14)):
            crown.box(side * s * .42, y + s * .3 + .09, z, s * .46, s * .46 * .8, s * .46, shade(leaf, .93))
        m.save()
    for name, snowy in (("Pine", False), ("SnowPine", True)):
        m = Model(name)
        m.group("Trunk").box(0, .225, 0, .2, .45, .2, "bark")
        crown = m.group("SteppedCrown")
        y = .4
        for k, s in enumerate((1.25, .98, .72, .46, .22)):
            h = .3 if k == 4 else .42
            crown.box(0, y + h / 2, 0, s, h, s, "pine_light" if k % 2 else "pine")
            if snowy:
                m.group("SnowCaps").box(0, y + h + .03, 0, s - .1, .07, s - .1, "snow")
            y += h
        m.save()


def water_tower():
    m = Model("WaterTower", scale=.65)
    b = m.group("TimberFrame")
    for x in (-.55, .55):
        for z in (-.55, .55):
            b.box(x, 1, z, .14, 2, .14, "timber_dark")
    for z in (-.55, .55):
        b.box(0, 1, z, 1.6, .09, .09, "timber", rz=.8)
        b.box(0, 1, z, 1.6, .09, .09, "timber", rz=-.8)
    tank = m.group("WaterTank")
    tank.box(0, 2.6, 0, 1.5, 1.2, 1.5, "wood")
    for hy in (2.2, 2.6, 3):
        tank.box(0, hy, 0, 1.54, .07, 1.54, "metal")
    for k in range(6):
        for sign in (-1, 1):
            tank.box(-.625 + k * .25, 2.6, sign * .753, .016, 1.1, .012, "timber")
            tank.box(sign * .753, 2.6, -.625 + k * .25, .012, 1.1, .016, "timber")
    y, half, k = 3.2, .85, 0
    while half > .08:
        tank.cube(-half, y, -half, half * 2, .22, half * 2, "teal" if k % 2 else "teal_dark")
        y += .22
        half -= .2
        k += 1
    tank.box(0, 2.3, .95, .14, .14, .6, "metal")
    tank.box(0, 2.05, 1.2, .12, .4, .12, "metal")
    m.save()


def windmill():
    m = Model("Windmill", scale=.57)
    b = m.group("MillTower")
    b.box(0, .25, 0, 2.8, .5, 2.8, "foundation")
    y = .5
    for width in (2.5, 2.3, 2.1, 1.9, 1.7):
        b.box(0, y + .45, 0, width, .9, width, "plaster")
        b.box(0, y + .04, 0, width + .04, .08, width + .04, "timber")
        y += .9
    b.box(0, 1, 1.24, .64, 1, .08, "door")
    b.box(0, 2.625, 1.09, .4, .45, .06, "glass")
    half, k = 1.15, 0
    while half > .1:
        b.cube(-half, y, -half, half * 2, .26, half * 2, "timber" if k % 2 else "wood")
        y += .26
        half -= .2
        k += 1
    sails = m.group("TimberAndLinenSails")
    sails.box(0, 4.3, 1.1, .3, .3, .5, "timber_dark")
    for i in range(4):
        a, length = i * math.pi / 2, 2.5
        ca, sa = math.cos(a), math.sin(a)
        sails.box(ca * length / 2, 4.3 + sa * length / 2, 1.38,
                  .12 if i % 2 else length, length if i % 2 else .12, .1, "timber")
        sails.box(ca * length * .58 - sa * .28, 4.3 + sa * length * .58 + ca * .28, 1.4,
                  .46 if i % 2 else 1.6, 1.6 if i % 2 else .46, .04, "cream")
        for j in range(4):
            t = .3 + j * .17
            sails.box(ca * length * t - sa * .28, 4.3 + sa * length * t + ca * .28, 1.43,
                      .48 if i % 2 else .05, .05 if i % 2 else .48, .03, "timber")
    m.save()


def chimney_smoke(m):
    m.resources.append('''[sub_resource type="Gradient" id="SmokeFade"]
offsets = PackedFloat32Array(0, 0.3, 1)
colors = PackedColorArray(0.87, 0.89, 0.87, 0.45, 0.91, 0.92, 0.89, 0.55, 0.91, 0.92, 0.89, 0)

[sub_resource type="GradientTexture1D" id="SmokeRamp"]
gradient = SubResource("SmokeFade")

[sub_resource type="ParticleProcessMaterial" id="SmokeMotion"]
direction = Vector3(0.12, 1, 0.16)
spread = 9.0
initial_velocity_min = 0.28
initial_velocity_max = 0.42
gravity = Vector3(0.025, 0.025, 0.018)
scale_min = 0.1
scale_max = 0.18
color_ramp = SubResource("SmokeRamp")

[sub_resource type="StandardMaterial3D" id="SmokeMaterial"]
transparency = 1
vertex_color_use_as_albedo = true
roughness = 1.0

[sub_resource type="BoxMesh" id="SmokeCube"]
material = SubResource("SmokeMaterial")
size = Vector3(1, 1, 1)

''')
    m.nodes.append('''[node name="ChimneySteam" type="GPUParticles3D" parent="."]
position = Vector3(0, 1.1008, -0.6272)
cast_shadow = 0
amount = 8
lifetime = 2.8
preprocess = 2.8
randomness = 0.2
local_coords = true
visibility_aabb = AABB(-0.7, -0.1, -0.7, 1.4, 2.2, 1.4)
process_material = SubResource("SmokeMotion")
draw_pass_1 = SubResource("SmokeCube")

''')


def chassis(m, length, wheel_x, radius):
    b = m.group("Chassis")
    b.box(0, .36, 0, length - .1, .14, .92, "metal")
    for sd in (-1, 1):
        b.box(sd * (length / 2 + .06), .36, 0, .16, .08, .1, "metal")
        b.box(sd * (length / 2 - .04), .36, 0, .08, .18, 1.04, "red")
    for i, x in enumerate(wheel_x):
        for j, z in enumerate((-.5, .5)):
            m.cylinder(f"Wheel{i}_{j}", (x, radius, z), radius, .1, "metal", axis="z")
            b.box(x, radius, z * 1.03, radius * .9, radius * .25, .13, "red", jitter=0)


def vehicles():
    m = Model("Locomotive", scale=.64, vehicle=True)
    chassis(m, 2.6, (-.75, .05, .85), .24)
    b = m.group("CabAndFittings")
    for p in ((1.42, .22, 0, .18, .16, 1, "gold"), (1.52, .12, 0, .12, .1, .78, "gold"),
              (-.72, .96, 0, .95, 1, 1.06, "teal_dark"), (-.72, .6, 0, .97, .08, 1.08, "gold"),
              (-.72, 1.52, 0, 1.18, .1, 1.26, "cream"), (-.72, 1.61, 0, .92, .08, 1, shade("cream", .9)),
              (.98, 1.3, 0, .24, .44, .24, "metal"), (.98, 1.56, 0, .36, .12, .36, "metal"),
              (.3, 1.27, 0, .3, .2, .3, "gold"), (.3, 1.39, 0, .18, .06, .18, "gold"),
              (1.25, 1.08, 0, .12, .18, .22, "glow"), (1.22, 1.08, 0, .1, .24, .28, "metal")):
        b.box(*p)
    for sd in (-1, 1):
        b.box(-.72, 1.15, sd * .535, .5, .34, .02, "glass", jitter=0)
        b.box(-.72, 1.15, sd * .55, .58, .04, .02, "cream", jitter=0)
        b.box(-.24, 1.2, sd * .26, .02, .26, .26, "glass", jitter=0)
        b.box(.4, .5, sd * .5, 1.6, .05, .14, "metal")
        b.box(.25, .25, sd * .56, 1.5, .04, .06, "stone")
    m.cylinder("Boiler", (.42, .86, 0), .38, 1.5, "teal_dark")
    m.cylinder("Smokebox", (1.12, .86, 0), .39, .24, "metal")
    for i, x in enumerate((0, .62)):
        m.cylinder(f"BoilerBand{i}", (x, .86, 0), .395, .06, "gold")
    chimney_smoke(m)
    m.save()

    m = Model("Tender", scale=.64, vehicle=True)
    chassis(m, 1.7, (-.45, .45), .2)
    b = m.group("CoalBunker")
    for p in ((0, .72, 0, 1.55, .58, 1, "teal_dark"), (0, .62, 0, 1.57, .07, 1.02, "gold"),
              (0, 1.03, 0, 1.6, .06, 1.05, "cream")):
        b.box(*p)
    for i in range(4):
        for j in range(3):
            b.box(-.55 + i * .37, 1.06 + ((i + j) % 2) * .06, -.3 + j * .3, .3, .14, .26, "coal", jitter=.09)
    m.save()

    m = Model("Coach", scale=.64, vehicle=True)
    chassis(m, 2.4, (-.75, .75), .2)
    b = m.group("PassengerCabin")
    for p in ((0, .62, 0, 2.3, .36, 1, "red"), (0, 1.08, 0, 2.3, .58, 1, "cream"),
              (0, .82, 0, 2.32, .05, 1.02, "gold"), (0, 1.42, 0, 2.46, .1, 1.14, "teal_dark"),
              (0, 1.52, 0, 2.3, .1, .86, shade("teal_dark", .88)), (0, 1.6, 0, 2.1, .06, .5, "teal_dark")):
        b.box(*p)
    for sd in (-1, 1):
        for k in range(4):
            b.box(-.78 + k * .52, 1.1, sd * .505, .32, .28, .02, "glass", jitter=0)
    m.save()


def author_models():
    houses()
    station()
    station("SnowStation", snowy=True)
    trees()
    water_tower()
    windmill()
    vehicles()
    print(f"Authored 15 reference-style native railway models in {OUT}")


if __name__ == "__main__":
    author_models()
