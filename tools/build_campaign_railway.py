"""Author the six-stop railway miniature as native, editable Godot scenes.

Offline geometry follows the supplied medieval-voxel-railway reference:
continuous cutaway strata, stepped mountains, timber railway and dense villages.
No scenery or train nodes are constructed by the game at runtime.
"""
from pathlib import Path
import math
import random

ROOT = Path(__file__).resolve().parents[1]
GRID = .5
GROUND = .15
RAIL_Y = .52
STATIONS = [(-18, 1.3), (-10.8, 1.3), (-3.6, 0), (3.6, 0), (10.8, 1.3), (18, 1.3)]
COLORS = {
    "grass": "7d8662", "forest": "74805e", "meadow": "89906d",
    "soil": "9a8a73", "earth": "877c6e", "stone": "79848a", "deep": "616b73",
    "rock": "8b999f", "snow": "dce4e5", "snow_side": "bac9cf",
    "sand": "b2ac92", "path": "b8af95", "ballast": "aaa494",
    "tie": "80664e", "timber": "947956", "timber_dark": "645546",
    "steel": "737e83", "rail_top": "c3c8c8", "water": "689297",
    "water_light": "86acaa", "wheat": "b2a278", "crop": "6e775c",
    "lavender": "8b8095", "window": "d6bb87",
}


def number(value):
    return f"{value:.5f}".rstrip("0").rstrip(".") if value else "0"


def vec(values):
    return "Vector3(" + ", ".join(map(number, values)) + ")"


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    content = text.rstrip() + "\n"
    if not path.exists() or path.read_text(encoding="utf-8") != content:
        path.write_text(content, encoding="utf-8", newline="\n")


def color(name, shift=0):
    value = COLORS.get(name, name)
    srgb = [max(0, min(1, int(value[i:i + 2], 16) / 255 + shift)) for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in srgb)


class Blocks:
    def __init__(self):
        self.parts = []

    def box(self, size, position, tint, yaw=0, shift=0):
        sx, sy, sz = size
        x, y, z = position
        c, s = math.cos(yaw), math.sin(yaw)
        self.parts.append((c*sx, 0, s*sz, x, 0, sy, 0, y, -s*sx, 0, c*sz, z, *color(tint, shift), 1))

    def resource(self, name):
        return (f'[sub_resource type="MultiMesh" id="{name}"]\n'
                'transform_format = 1\nuse_colors = true\n'
                f'instance_count = {len(self.parts)}\nmesh = SubResource("Cube")\n'
                'buffer = PackedFloat32Array(' + ', '.join(number(n) for part in self.parts for n in part) + ')\n\n')


def route_z(x):
    """Straight platforms joined by two shallow, smooth S bends."""
    for i in range(len(STATIONS) - 1):
        ax, az = STATIONS[i]
        bx, bz = STATIONS[i + 1]
        start, end = ax + 2.3, bx - 2.3
        if x < start:
            return az
        if x <= end:
            t = (x - start) / (end - start)
            return az + (bz - az) * (t*t*(3 - 2*t))
    return STATIONS[-1][1]


def river_x(z):
    return .12 + .52 * math.sin(z * .52)


def river(x, z):
    return abs(x - river_x(z)) < 1.04


def height(x, z):
    if river(x, z):
        return -.63
    if x > 7 and z < -3.0:
        peaks = [(13.4, -7.4, 4.8, .95), (19.1, -7.1, 6.5, 1.04), (22.1, -4.6, 4.1, 1.02)]
        h = max(v - math.hypot(x-px, (z-pz)*1.13)*s for px, pz, v, s in peaks)
        return max(GROUND, math.floor(max(0, h) / .45) * .45 + GROUND)
    if -7.5 < x < -1.6 and z < -4.1:
        return GROUND + (.35 if z < -6.1 else 0)
    return GROUND


def snow(x, z):
    return x > 12 + .65*math.sin(z*.6) or height(x, z) > 3.75


def build():
    rng = random.Random(61026)
    groups = {name: Blocks() for name in ["DeepStratum", "StoneStratum", "EarthStratum", "Surface", "Mountain", "River", "RiverGlints", "VillagePaths", "TrackBallast", "Sleepers", "Rails", "Bridge", "Fields", "Fences", "Details"]}
    # Broad, uninterrupted horizontal strata keep the miniature a single world.
    for name, bottom, top, tint in [("DeepStratum", -2.4, -1.85, "deep"), ("StoneStratum", -1.85, -1.07, "stone"), ("EarthStratum", -1.07, -.48, "earth")]:
        groups[name].box((47, top-bottom, 18), (0, (top+bottom)/2, 0), tint)
        # Small visible edge courses, quiet enough not to become noisy tiles.
        for row in range(2):
            y = bottom + (top-bottom)*(row+.5)/2
            for n in range(47):
                x = -23 + n + (.22 if row else 0)
                width = min(1, 23.5-x+.5)
                if width <= 0:
                    continue
                for z in (-9.006, 9.006):
                    groups[name].box((width-.012, (top-bottom)/2-.012, .028), (x, y, z), tint, shift=rng.uniform(-.018, .018))
    for ix in range(94):
        x = -23.25 + ix*GRID
        for iz in range(36):
            z = -8.75 + iz*GRID
            h = height(x, z)
            bank = abs(x-river_x(z)) < 1.58
            snowy = snow(x, z)
            tint = "sand" if bank else "snow" if snowy else "forest" if -8<x<7 else "meadow" if x < -13 else "grass"
            if h > GROUND + .1:
                # The top cap owns the last 12 cm; overlapping side faces cause
                # depth fighting along every snow terrace in close-up views.
                groups["Mountain"].box((GRID, h-GROUND-.12, GRID), (x, (h-.12+GROUND)/2, z), "snow_side" if snowy else "rock", shift=rng.uniform(-.018, .018))
            soil_top = min(h-.12, .03)
            if soil_top > -.48:
                groups["Surface"].box((GRID, soil_top+.48, GRID), (x, (soil_top-.48)/2, z), "soil", shift=rng.uniform(-.012, .012))
            target = groups["Mountain"] if h > GROUND+.1 else groups["Surface"]
            target.box((GRID, .12, GRID), (x, h-.06, z), tint, shift=rng.uniform(-.012, .012))
            if river(x, z):
                groups["River"].box((GRID, .07, GRID), (x, -.285, z), "water", shift=rng.uniform(-.01, .01))
                if iz % 5 == 0 and ix % 2 == 0:
                    groups["RiverGlints"].box((.25, .008, .025), (x+.04, -.245, z), "water_light")
    # A village lane runs behind the six stations; side lanes meet station steps.
    for x in [-22.75+i*.5 for i in range(92)]:
        if not river(x, -3.25) and height(x, -3.25) <= GROUND:
            groups["VillagePaths"].box((.5, .024, .65), (x, .164, -3.25), "path", shift=rng.uniform(-.012, .012))
    for sx, sz in STATIONS:
        for k in range(8):
            z = -3.2 + k*.45
            groups["VillagePaths"].box((.65, .024, .46), (sx+2.0, .165, z), "path")
    # Ballast, repeated sleepers and two steel rail profiles share the exact curve.
    samples = [(round(-23+i*.05, 5), RAIL_Y, route_z(-23+i*.05)) for i in range(921)]
    for i in range(230):
        x = -23+(i+.5)*.2
        z = route_z(x)
        a, b = (x-.1, route_z(x-.1)), (x+.1, route_z(x+.1))
        yaw = -math.atan2(b[1]-a[1], b[0]-a[0])
        length = math.dist(a, b)+.025
        on_bridge = abs(x) < 1.8
        if not on_bridge:
            groups["TrackBallast"].box((length+.04, .15, 1.26), (x, .235, z), "ballast", yaw, rng.uniform(-.014, .014))
            for sign in (-1, 1):
                groups["TrackBallast"].box((length, .06, .16), (x, .18, z+sign*.66), "ballast", yaw, -.035)
        else:
            groups["Bridge"].box((length, .15, 1.62), (x, .235, z), "timber", yaw, -.025 if i%2 else .025)
        for side in (-.325, .325):
            nx, nz = math.sin(yaw)*side, math.cos(yaw)*side
            groups["Rails"].box((length, .07, .115), (x+nx, .43, z+nz), "steel", yaw)
            groups["Rails"].box((length, .055, .07), (x+nx, RAIL_Y-.0275, z+nz), "rail_top", yaw)
    for i in range(117):
        x = -22.9+i*.392
        z = route_z(x)
        yaw = -math.atan2(route_z(x+.02)-route_z(x-.02), .04)
        groups["Sleepers"].box((.18, .095, 1.1), (x, .3525, z), "tie", yaw, .018 if i%3 else -.018)
        if i % 2 == 0 and abs(x) > 1.8:
            for side in (-.53, .51):
                groups["Details"].box((.11, .045, .08), (x+.08, .299, z+side), "stone", yaw)
    # Timber crossing, lower crossbeams and parapets like the reference trestle.
    for z in (-.77, .77):
        groups["Bridge"].box((3.75, .18, .16), (0, .10, z), "timber_dark")
        groups["Bridge"].box((3.82, .08, .09), (0, .89, z), "timber")
        for x in (-1.7, -.8, .2, 1.2, 1.75):
            groups["Bridge"].box((.12, .76, .12), (x, .5, z), "timber_dark")
            groups["Bridge"].box((.18, .79, .18), (x, -.20, z*.79), "timber_dark")
    for x in (-1.65, 1.65):
        groups["Bridge"].box((.52, .5, 1.72), (x, -.12, 0), "stone")
    # Cultivated fields and split-rail fences give the village scale and density.
    for field_x in (-18.5, -11.5):
        groups["Fields"].box((4.9, .04, 2.4), (field_x, .174, 6.8), "soil")
        for row in range(5):
            z = 5.85+row*.46
            for col in range(17):
                x = field_x-2.3+col*.28
                h = .11 + .045*(col%3)
                groups["Fields"].box((.19, h, .15), (x, .20+h/2, z), "wheat" if field_x < -15 else "lavender", shift=rng.uniform(-.025, .025))
        for z in (5.42, 8.18):
            groups["Fences"].box((5.3, .07, .07), (field_x, .67, z), "timber")
            for n in range(6):
                groups["Fences"].box((.09, .67, .09), (field_x-2.5+n, .48, z), "timber_dark")
    # Railway buffer stops sit beyond both end stations, leaving room for all cars.
    for x in (-22.9, 22.5):
        for z in (1.0, 1.6):
            groups["Details"].box((.18, .35, .16), (x, .60, z), "timber_dark")
        groups["Details"].box((.18, .14, 1.05), (x, .78, 1.3), "timber")

    assets = ["Station", "SnowStation", "Oak", "OakLight", "Pine", "SnowPine", "HalfTimberHouse", "HalfTimberHouseBlue", "Cottage", "SnowHouse", "WaterTower", "Windmill", "Locomotive", "Tender", "Coach"]
    scene = '[gd_scene format=3]\n\n'
    for asset in assets:
        scene += f'[ext_resource type="PackedScene" path="res://scenes/campaign/railway_models/{asset}.tscn" id="{asset}"]\n'
    scene += '[ext_resource type="Curve3D" path="res://data/campaign/journey_3d.tres" id="journey"]\n\n'
    scene += '[sub_resource type="BoxMesh" id="Cube"]\nsize = Vector3(1, 1, 1)\n\n'
    scene += '[sub_resource type="StandardMaterial3D" id="Matte"]\nvertex_color_use_as_albedo = true\nroughness = 0.93\n\n'
    scene += '[sub_resource type="StandardMaterial3D" id="Water"]\nvertex_color_use_as_albedo = true\nroughness = 0.30\nmetallic = 0.15\n\n'
    for name, blocks in groups.items():
        scene += blocks.resource(name)
    # One restrained lift reveals the entire authored world; no per-block tracks.
    scene += '[sub_resource type="Animation" id="Unfold"]\nresource_name = "unfold"\nlength = 2.0\n'
    scene += 'tracks/0/type = "position_3d"\ntracks/0/path = NodePath(".")\ntracks/0/keys = PackedFloat32Array(0, 1, 0, -1.1, 0, 1.65, 1, 0, 0, 0, 2, 1, 0, 0, 0)\n\n'
    scene += '[sub_resource type="AnimationLibrary" id="EntranceLibrary"]\n_data = {&"unfold": SubResource("Unfold")}\n\n'
    scene += '[node name="Landscape" type="Node3D"]\n\n[node name="Terrain" type="Node3D" parent="."]\n\n'
    for name in groups:
        material = "Water" if name in ("River", "RiverGlints") else "Matte"
        scene += f'[node name="{name}" type="MultiMeshInstance3D" parent="Terrain"]\nmultimesh = SubResource("{name}")\nmaterial_override = SubResource("{material}")\n\n'
    scene += '[node name="Stations" type="Node3D" parent="."]\n\n'
    for i, (x, z) in enumerate(STATIONS):
        asset = "SnowStation" if snow(x,z) else "Station"
        scene += f'[node name="Station{i+1:02}" parent="Stations" instance=ExtResource("{asset}")]\nposition = {vec((x,GROUND,z))}\n\n'
    scene += '[node name="Villages" type="Node3D" parent="."]\n\n'
    occupied = []

    def place(name, asset, x, z, scale=1, yaw=0, parent="Villages"):
        nonlocal scene
        y = height(x, z)
        scene += f'[node name="{name}" parent="{parent}" instance=ExtResource("{asset}")]\nposition = {vec((x,y,z))}\n'
        if scale != 1:
            scene += f'scale = {vec((scale,scale,scale))}\n'
        if yaw:
            scene += f'rotation_degrees = {vec((0,yaw,0))}\n'
        scene += '\n'

    houses = [(-21,-6.8,.87,0),(-18.3,-6.2,1,0),(-15.2,-6.9,.82,-90),(-12.8,-5.6,.95,0),(-10.1,-7.1,.83,0),(-8.2,-4.6,.76,90),
              (-21.2,-3.4,.76,90),(-15.3,-3.7,.70,-90),(-13.8,3.8,.70,0),(-20.7,4.4,.82,90),
              (-5.8,-4.8,.83,0),(-2.9,-6.6,.74,0),(3.3,-5.8,.82,0),(6.3,-4.7,.86,0),
              (8.4,-2.7,.70,90),(12.3,-2.7,.68,-90),(15.4,-3.0,.72,0),(18.8,-3.0,.80,0),(21.6,-1.1,.72,-90),
              (19.7,5.7,.83,180),(15.8,5.3,.70,180),(10.9,6.3,.76,0),(6.6,5.6,.74,0)]
    for i, (x,z,s,yaw) in enumerate(houses):
        # A low cottage keeps the parked train visible over the foreground roof.
        asset = "Cottage" if i == 9 else "SnowHouse" if snow(x,z) else "HalfTimberHouseBlue" if i%3 == 0 else "HalfTimberHouse"
        place(f'House{i+1:02}', asset, x,z,s,yaw)
        occupied.append((x,z,1.25*s))
    place('FarmWindmill', 'Windmill', -22, 6.9, .88)
    place('StationWaterTower', 'WaterTower', -15.1, -.35, .88)
    occupied.extend([(-22,6.9,1.25), (-15.1,-.35,.8)])
    scene += '[node name="Groves" type="Node3D" parent="."]\n\n'
    tree_count = 0
    for center_x, center_z, columns, rows in [(-21.4,-8.0,3,1),(-17,-8.0,4,1),(-8,-7,3,3),(-4.7,-7.5,3,2),(3.8,-7.4,4,2),(6.2,-2.6,2,2),(-6.0,5.4,4,3),(3.5,5.7,3,3),(8.8,7.6,4,1),(14.1,6.8,4,2),(21.2,6.6,2,2),(21.8,-3.5,2,2),(12.0,-5.4,3,2)]:
        for row in range(rows):
            for col in range(columns):
                x = center_x+(col-(columns-1)/2)*1.15+rng.uniform(-.22,.22)
                z = center_z+(row-(rows-1)/2)*1.16+rng.uniform(-.22,.22)
                if abs(x)>22.5 or abs(z)>8.5 or river(x,z):
                    continue
                if any(math.hypot(x-hx,z-hz)<r+.68 for hx,hz,r in occupied):
                    continue
                if any(abs(x-sx)<2.8 and sz-3.8<z<sz+1.8 for sx,sz in STATIONS):
                    continue
                tree_count += 1
                asset = "SnowPine" if snow(x,z) else "Pine" if x>1 else "OakLight" if tree_count%4==0 else "Oak"
                place(f'Tree{tree_count:03}', asset,x,z,rng.uniform(.80,1.07),rng.choice([0,90,180,270]),"Groves")
    scene += '[node name="StageAnchors" type="Node3D" parent="."]\n\n'
    for i,(x,z) in enumerate(STATIONS):
        scene += f'[node name="Stage{i+1:02}" type="Marker3D" parent="StageAnchors"]\nposition = {vec((x,RAIL_Y,z))}\n\n'
    scene += '[node name="Journey" type="Path3D" parent="."]\ncurve = ExtResource("journey")\n\n'
    for node, model, progress in [("Train","Locomotive",5),("Tender","Tender",3.49),("Coach","Coach",2.06)]:
        scene += f'[node name="{node}" type="PathFollow3D" parent="Journey"]\nprogress = {number(progress)}\nrotation_mode = 1\nloop = false\ncubic_interp = false\n\n'
        scene += f'[node name="Model" parent="Journey/{node}" instance=ExtResource("{model}")]\n\n'
    scene += '[node name="Entrance" type="AnimationPlayer" parent="."]\nlibraries = {&"": SubResource("EntranceLibrary")}\n'
    write(ROOT/"scenes/campaign/campaign_landscape.tscn", scene)
    points = [n for x,y,z in samples for n in (0,0,0,0,0,0,x,y,z)]
    curve = '[gd_resource type="Curve3D" format=3]\n\n[resource]\nbake_interval = 0.05\n_data = {\n"points": PackedVector3Array(' + ', '.join(map(number,points)) + '),\n"tilts": PackedFloat32Array(' + ', '.join('0' for _ in samples) + f')\n}}\npoint_count = {len(samples)}\n'
    write(ROOT/"data/campaign/journey_3d.tres", curve)
    print(f'Authored 6 stations, {len(houses)} houses, {tree_count} trees, {sum(len(b.parts) for b in groups.values())} terrain/railway blocks and {len(samples)} route points.')


if __name__ == "__main__":
    build()
