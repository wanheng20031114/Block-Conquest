"""Offline surface authoring for MOBA test1; no gameplay/map-layout regeneration.

Run this file, then Godot --headless --path . --script res://tools/bake_moba_ground.gd.
Simple block textures are ImageGen quadrants; this tool only authors geometry, vertex
material masks and persisted MultiMeshes. Paths, collisions and navigation stay
in test1_map.tscn. All decorative surfaces are shallow and non-colliding.
"""
from pathlib import Path
import json
import math
import random

from build_rogue_forest import Mesh, clamp, smooth

ROOT = Path(__file__).resolve().parents[1]
OUT = "assets/models/environment/moba"
FORTS = [(sign * x, z, w, d) for sign in (-1, 1) for x, z, w, d in
         [(87, 0, 5.5, 5.1), (61, 0, 7.0, 6.5), (37, 0, 5.6, 5.1),
          (15, -9, 3.5, 3.5), (15, 9, 3.5, 3.5)]]


def write(path, text):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


def lane_at(x):
    ax = abs(x)
    t = clamp((ax - 12) / 23)
    return 10 * t * t * (3 - 2 * t) * (1 - clamp((ax - 77) / 17))


def fort_distance(x, z, margin=0):
    # Rounded rectangle SDF: the dirt apron follows masonry, not an airbrushed disk.
    result = 1000
    for fx, fz, w, d in FORTS:
        dx, dz = abs(x - fx) - w - margin + .7, abs(z - fz) - d - margin + .7
        result = min(result, math.hypot(max(0, dx), max(0, dz)) + min(0, max(dx, dz)) - .7)
    return result


def road_distance(x, z):
    lane = abs(abs(z) - lane_at(x)) - 2.45
    verge = .08 * math.sin(abs(x) * .33 + z * .21)
    return min(lane, fort_distance(x, z, .65)) + verge


def mesh_data(mesh, material):
    return {"vertices": mesh.v, "normals": mesh.n, "colors": mesh.c,
            "uv": mesh.uv, "material": f"res://{OUT}/{material}.tres"}


def ground_mesh():
    m = Mesh("ground")
    for z in range(-28, 28):
        for x in range(-100, 100):
            m.tri((x, -.025, z), (x + 1, -.025, z), (x + 1, -.025, z + 1), (1, 1, 1))
            m.tri((x, -.025, z), (x + 1, -.025, z + 1), (x, -.025, z + 1), (1, 1, 1))
    for i in range(len(m.v) // 3):
        x, _, z = m.v[i * 3:i * 3 + 3]
        road = clamp(.5 - road_distance(x, z) / 6)
        forest = smooth(15, 24, abs(z))
        m.c[i * 4:i * 4 + 4] = [round(road, 5), round(forest, 5), 0, 1]
    return m


def octagon(w, d, corner):
    return [(-w + corner, -d), (w - corner, -d), (w, -d + corner),
            (w, d - corner), (w - corner, d), (-w + corner, d),
            (-w, d - corner), (-w, -d + corner)]


def slab():
    """Eight clipped corners and a bevel; top at most 3.5 cm above the play plane."""
    m = Mesh("inset_stone")
    low = octagon(.48, .32, .10)
    high = octagon(.455, .295, .09)
    for i in range(8):
        j = (i + 1) % 8
        a, b = high[i], high[j]
        c, d = low[i], low[j]
        m.tri((.07, .035, -.03), (a[0], .03, a[1]), (b[0], .03, b[1]),
              (.61, .63, .57))
        m.tri((a[0], .03, a[1]), (c[0], -.015, c[1]), (d[0], -.015, d[1]), (.54, .56, .50))
        m.tri((a[0], .03, a[1]), (d[0], -.015, d[1]), (b[0], .03, b[1]), (.54, .56, .50))
    return m


def courtyard():
    m = Mesh("courtyards")
    for x, z, w, d in FORTS:
        ring = octagon(w, d, .8)
        for i in range(8):
            a, b = ring[i], ring[(i + 1) % 8]
            m.tri((x, -.009, z), (x + a[0], -.009, z + a[1]),
                  (x + b[0], -.009, z + b[1]), (1, 1, 1))
    # World-scale stone tiles; separate material so grass never tints the masonry.
    m.uv = [v * 6 / 2.8 for v in m.uv]
    return m


def transform(x, z, sx, sz, angle=0, y=0, sy=1):
    c, s = math.cos(angle), math.sin(angle)
    return (c * sx, 0, s * sz, x, 0, sy, 0, y, -s * sx, 0, c * sz, z)


def build():
    rng = random.Random(731911)
    meshes = {"ground": mesh_data(ground_mesh(), "ground_material"),
              "inset_stone": mesh_data(slab(), "stone_material"),
              "courtyards": mesh_data(courtyard(), "paving_material")}
    write(".local/moba-ground/meshes.json", json.dumps(meshes, separators=(",", ":")))
    batches = {}

    def add(asset, x, z, sx=1, sz=None, angle=0, y=0):
        sector = min(7, max(0, int((x + 100) / 25)))
        key = (sector, asset)
        values = list(transform(x, z, sx, sx if sz is None else sz, angle, y,
                                .67 * sx if asset == "grass" else sx if asset != "inset_stone" else 1))
        tint = rng.uniform(.96, 1.0)
        values.extend((tint, tint, tint, 1))
        batches.setdefault(key, []).extend(values)

    # A small dressed-stone rim seats each structure into its courtyard. The
    # height is purely visual; it must not introduce stairs or collision seams.
    for x, z, w, d in FORTS:
        ring = octagon(w, d, .8)
        for i, a in enumerate(ring):
            b = ring[(i + 1) % 8]
            length = math.dist(a, b)
            count = max(1, round(length / 1.35))
            angle = -math.atan2(b[1] - a[1], b[0] - a[0])
            for j in range(count):
                t = (j + .5) / count
                add("inset_stone", x + a[0] + (b[0] - a[0]) * t,
                    z + a[1] + (b[1] - a[1]) * t, length / count / .98, .66, angle)

    # A few larger stepping-stone groups leave most of the lane as calm, plain soil.
    for sign in (-1, 1):
        for lane_sign in (-1, 1):
            for i in range(13, 66):
                x = i * 1.35
                z = lane_sign * lane_at(x)
                if x < 20 or i % 16 not in (4, 5, 6): continue
                tangent = (lane_at(x + .1) - lane_at(x - .1)) / .2 * lane_sign
                for row in (-.5, .5):
                    px = sign * (x + (.30 if row > 0 else 0))
                    pz = z + row * .85
                    if fort_distance(px, pz, .3) < 0: continue
                    add("inset_stone", px, pz, 1.25, 1.12,
                        -math.atan(tangent * sign) + rng.uniform(-.035, .035), -.015)

    # A small regular crossing is readable as a single shape from the RTS camera.
    for ix in range(-2, 3):
        for iz in range(-1, 2):
            if abs(ix) == 2 and iz == 1: continue
            x, z = ix * 1.35 + (.35 if iz % 2 else 0), iz * .85
            add("inset_stone", x, z, 1.28, 1.12, 0, -.017)

    # Tufts grow in clusters just outside the traveled surface, never as evenly
    # scattered confetti through the soldiers' central fighting corridor.
    for _ in range(155):
        x = rng.uniform(-97, 97)
        z = rng.choice((-1, 1)) * (lane_at(x) + rng.choice((-1, 1)) * rng.uniform(2.75, 4.8))
        if road_distance(x, z) < .25 or fort_distance(x, z, .5) < 0: continue
        size = rng.uniform(.45, .83)
        add("grass", x, z, size, angle=rng.random() * math.tau)
        if rng.random() < .18:
            add("grass", x + rng.uniform(-.4, .4), z + rng.uniform(-.3, .3), size * .7,
                angle=rng.random() * math.tau)
    for _ in range(80):
        x, z = rng.uniform(-98, 98), rng.choice((-1, 1)) * rng.uniform(16, 27)
        add("grass", x, z, rng.uniform(.55, .8), angle=rng.random() * math.tau)

    resources = []
    for asset in sorted({key[1] for key in batches}):
        directory = OUT if asset == "inset_stone" else "assets/models/environment/rogue_forest"
        resources.append(f'[ext_resource type="ArrayMesh" path="res://{directory}/{asset}.res" id="{asset}"]')
    resources.append(f'[ext_resource type="ArrayMesh" path="res://{OUT}/courtyards.res" id="courts"]')
    nodes = ['[node name="GroundDetails" type="Node3D"]',
             '[node name="Courtyards" type="MeshInstance3D" parent="."]\nmesh = ExtResource("courts")\ncast_shadow = 0']
    for (sector, asset), values in sorted(batches.items()):
        name = f"{asset}_{sector}"
        resources.append(f'[sub_resource type="MultiMesh" id="{name}"]\ntransform_format = 1\nuse_colors = true\ninstance_count = {len(values) // 16}\nmesh = ExtResource("{asset}")\nbuffer = PackedFloat32Array('
                         + ','.join(f'{v:.5f}' for v in values) + ')')
        nodes.append(f'[node name="{name}" type="MultiMeshInstance3D" parent="."]\nmultimesh = SubResource("{name}")\ncast_shadow = 0')
    write("scenes/moba/ground_details.tscn", '[gd_scene format=3]\n' + '\n'.join(resources + nodes))
    print("MOBA_GROUND", len(meshes), "meshes,", len(batches), "spatial batches,",
          sum(len(v) // 16 for v in batches.values()), "static details")


if __name__ == "__main__":
    build()
