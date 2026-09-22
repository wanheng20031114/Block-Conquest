"""Deterministic, chunky sculpted woodland for the war map.

Run with numpy, trimesh and shapely installed (the environment modeller's deps),
then run build_war_nature.gd in Godot to bake native ArrayMesh resources.  Shape,
branching, leaf laminae, colour gradients and smooth normals are authored here;
no geometry is generated during gameplay.  No source environment asset changes.
"""
from __future__ import annotations

import math
from collections import defaultdict
from pathlib import Path

import numpy as np
import trimesh as tm
import build_environment as env

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/block_war/nature"
OUT.mkdir(parents=True, exist_ok=True)
TAU = math.tau

PALETTE = {
    "bark": ((117, 70, 34), (179, 115, 55)),
    "birch": ((174, 176, 143), (237, 229, 188)),
    "scar": ((76, 80, 57), (118, 115, 80)),
    "oak": ((44, 103, 46), (111, 160, 58)),
    "birch_leaf": ((53, 112, 43), (132, 172, 60)),
    "pine": ((29, 74, 67), (74, 127, 81)),
    "hazel": ((49, 116, 49), (122, 167, 54)),
    "fern": ((46, 122, 68), (99, 166, 70)),
    "grass": ((65, 128, 48), (141, 183, 64)),
    "reed": ((85, 122, 45), (167, 177, 75)),
    "seed": ((110, 79, 43), (164, 126, 67)),
    "stone": ((99, 101, 89), (151, 151, 129)),
    "moss": ((53, 115, 57), (104, 149, 63)),
    "white": ((205, 218, 175), (255, 249, 215)),
    "gold": ((200, 141, 35), (255, 207, 67)),
    "blue": ((76, 102, 162), (163, 175, 235)),
}


def norm(v):
    v = np.asarray(v, dtype=float)
    return v / max(np.linalg.norm(v), 1e-8)


def paint(mesh, palette, shift=0.0):
    low, high = (np.asarray(c, dtype=float) for c in PALETTE[palette])
    verts = mesh.vertices
    y = (verts[:, 1] - verts[:, 1].min()) / max(np.ptp(verts[:, 1]), .01)
    # Broad painted light/shadow, never per-triangle random noise.
    sweep = .48 + .27 * np.sin(verts[:, 0] * 1.37 + verts[:, 2] * .91 + shift)
    light = np.clip(.19 + y * .68 + sweep * .13, 0, 1)
    rgb = low[None, :] + (high - low)[None, :] * light[:, None]
    mesh.visual.vertex_colors = np.column_stack((rgb, np.full(len(verts), 255))).astype(np.uint8)
    return mesh


class Nature:
    def __init__(self):
        self.parts = defaultdict(list)

    def add(self, mesh, palette, group="Foliage", shift=0.0, shade=1.0):
        mesh = mesh.copy()
        mesh.fix_normals(multibody=True)
        paint(mesh, palette, shift)
        if shade != 1.0:
            rgba = mesh.visual.vertex_colors.copy()
            rgba[:, :3] = np.clip(rgba[:, :3].astype(float) * shade, 0, 255).astype(np.uint8)
            mesh.visual.vertex_colors = rgba
        # Cache normal vectors before concatenation. Neighbouring triangles on
        # one sculpt share vertices and retain continuous curved lighting.
        mesh.vertex_normals
        self.parts[group].append(mesh)

    def save(self, name):
        scene = tm.Scene()
        triangles = 0
        for group, parts in self.parts.items():
            merged = tm.util.concatenate(parts)
            rgba = merged.visual.vertex_colors.copy()
            srgb = rgba[:, :3].astype(np.float32) / 255.0
            linear = np.where(srgb <= .04045, srgb / 12.92, ((srgb + .055) / 1.055) ** 2.4)
            rgba[:, :3] = np.round(linear * 255).astype(np.uint8)
            merged.visual.vertex_colors = rgba
            scene.add_geometry(merged, node_name=group, geom_name=group)
            triangles += len(merged.faces)

        def materials(tree):
            tree["materials"] = []
            for index, mesh in enumerate(tree["meshes"]):
                tree["materials"].append({"name": mesh["name"], "pbrMetallicRoughness": {
                    "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": .95},
                    "doubleSided": mesh["name"] in ("Foliage", "Petals", "Grass")})
                for primitive in mesh["primitives"]:
                    primitive["material"] = index

        blob = tm.exchange.gltf.export_glb(scene, include_normals=True, tree_postprocessor=materials)
        env.write_asset(OUT / (name + ".glb"), blob)
        groups = list(self.parts)
        lines = [f'[gd_scene load_steps={len(groups) * 2 + 1} format=3]', ""]
        for group in groups:
            lines.append(f'[ext_resource type="ArrayMesh" path="res://assets/models/block_war/nature/{name}_{group.lower()}.res" id="{group}_mesh"]')
            material = "leaves" if group == "Foliage" else "grass" if group in ("Grass", "Petals") else "bark" if group == "Wood" else "stone"
            lines.append(f'[ext_resource type="Material" path="res://assets/models/block_war/nature/{material}.tres" id="{group}_material"]')
        lines += ["", f'[node name="{name.title().replace("_", "")}" type="Node3D"]']
        for group in groups:
            lines += ["", f'[node name="{group}" type="MeshInstance3D" parent="."]',
                      f'mesh = ExtResource("{group}_mesh")', f'material_override = ExtResource("{group}_material")']
            if group in ("Grass", "Petals"):
                lines.append("cast_shadow = 0")
        env.write_asset(OUT / (name + ".tscn"), "\n".join(lines) + "\n")
        print(name, "triangles", triangles, "bounds", np.round(scene.bounds, 2).tolist())


def catmull(points, steps=5):
    points = np.asarray(points, dtype=float)
    extended = np.vstack((points[0], points, points[-1]))
    result = []
    for i in range(1, len(extended) - 2):
        a, b, c, d = extended[i - 1:i + 3]
        for t in np.linspace(0, 1, steps, endpoint=False):
            result.append(.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t))
    result.append(points[-1])
    return np.asarray(result)


def tube(points, radii, sections=9, steps=4, fluting=0.0):
    path = catmull(points, steps)
    radii = np.interp(np.linspace(0, len(radii) - 1, len(path)), np.arange(len(radii)), radii)
    vertices, faces = [], []
    for i, (p, radius) in enumerate(zip(path, radii)):
        direction = norm(path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)])
        ref = [1, 0, 0] if abs(direction[0]) < .8 else [0, 0, 1]
        side = norm(np.cross(direction, ref))
        front = norm(np.cross(direction, side))
        for j in range(sections):
            a = j * TAU / sections
            r = radius * (1 + fluting * math.sin(a * 5 + i * .13))
            vertices.append(p + (side * math.cos(a) + front * math.sin(a)) * r)
    for i in range(len(path) - 1):
        for j in range(sections):
            a = i * sections + j
            b = i * sections + (j + 1) % sections
            faces.extend(((a, b, b + sections), (a, b + sections, a + sections)))
    vertices.extend((path[0], path[-1]))
    for j in range(sections):
        faces.append((len(vertices) - 2, (j + 1) % sections, j))
        faces.append((len(vertices) - 1, (len(path) - 1) * sections + j, (len(path) - 1) * sections + (j + 1) % sections))
    return tm.Trimesh(vertices, faces, process=False)


def crown(center, radii, seed=0, segments=36, rings=18):
    """A continuous scalloped canopy with softly swept shoulders and ridges."""
    vertices, faces = [], []
    cx, cy, cz = center
    rx, ry, rz = radii
    for i in range(rings + 1):
        phi = math.pi * (i + .008) / (rings + .016)
        st, ct = math.sin(phi), math.cos(phi)
        for j in range(segments):
            a = j * TAU / segments
            scallop = 1 + .080 * math.cos(5 * a + seed) * st ** 2 + .038 * math.sin(9 * a - seed * .7) * st
            shoulder = 1 + .055 * math.sin(phi * 4 + seed)
            x = cx + rx * st * math.cos(a) * scallop * shoulder
            z = cz + rz * st * math.sin(a) * scallop * shoulder
            y = cy + ry * ct + .055 * ry * math.sin(a * 4 + seed) * st ** 2
            vertices.append((x, y, z))
    for i in range(rings):
        for j in range(segments):
            a, b = i * segments + j, i * segments + (j + 1) % segments
            faces.extend(((a, a + segments, b), (b, a + segments, b + segments)))
    mesh = tm.Trimesh(vertices, np.asarray(faces)[:, ::-1], process=False)
    mesh.merge_vertices(digits_vertex=6)
    return mesh


def leaf(start, end, width, curl=.05, twist=0.0, lobes=0, segments=4):
    start, end = np.asarray(start, float), np.asarray(end, float)
    direction = end - start
    side = norm(np.cross(direction, [0, 1, .13]))
    up = norm(np.cross(side, direction))
    side, up = side * math.cos(twist) + up * math.sin(twist), up * math.cos(twist) - side * math.sin(twist)
    vertices, faces = [], []
    for i in range(segments + 1):
        t = i / segments
        mid = start + direction * t + up * curl * math.sin(t * math.pi)
        spread = math.sin(t * math.pi) ** .78 * width * .5 * (1 + lobes * .16 * math.sin(t * math.pi * 7))
        vertices.extend((mid - side * spread, mid + up * spread * .17, mid + side * spread))
    for i in range(segments):
        a = i * 3
        faces.extend(((a, a + 3, a + 1), (a + 1, a + 3, a + 4),
                      (a + 1, a + 4, a + 2), (a + 2, a + 4, a + 5)))
    return tm.Trimesh(vertices, faces, process=False)


def foliage_mass(m, center, radii, seed, palette="oak"):
    """Rounded, chamfer-like leaf masses: broad forms and clear colour planes."""
    mesh = crown(center, radii, seed, 24, 12)
    p = (mesh.vertices - np.asarray(center)) / np.asarray(radii)
    # Super-elliptic shoulders create broad faces with softly rounded corners.
    p[:, 0] = np.sign(p[:, 0]) * np.abs(p[:, 0]) ** .88
    p[:, 1] = np.sign(p[:, 1]) * np.abs(p[:, 1]) ** .74
    p[:, 2] = np.sign(p[:, 2]) * np.abs(p[:, 2]) ** .88
    mesh.vertices = p * np.asarray(radii) + np.asarray(center)
    m.add(mesh, palette, shift=seed, shade=.96 + .035 * math.sin(seed))


def roots(m, radius=.35, count=5):
    for i in range(count):
        a = i * TAU / count + .28
        m.add(tube([(math.cos(a) * .1, .5, math.sin(a) * .1),
                    (math.cos(a) * .4, .17, math.sin(a) * .4),
                    (math.cos(a) * .72, .045, math.sin(a) * .72)],
                   [radius * .58, radius * .4, .017], 8), "bark", "Wood", a)


def canopy_oak():
    m = Nature()
    roots(m)
    trunk = [(0, 0, 0), (.06, 1.2, .05), (-.08, 2.25, .13), (.14, 3.35, .05), (.38, 4.45, -.02)]
    m.add(tube(trunk, [.40, .31, .24, .17, .075], 12, 5, .10), "bark", "Wood")
    # Broad lower scaffold and a separate upper crown form a readable old oak.
    scaffold = [(-1.45, 3.82, .10, 1.43, .77, 1.22), (1.28, 4.15, -.13, 1.47, .84, 1.23),
                (-.03, 4.21, 1.02, 1.55, .85, 1.18), (-.19, 5.25, -.35, 1.70, 1.04, 1.48)]
    for i, (x, y, z, rx, ry, rz) in enumerate(scaffold):
        branch_start = (.03, 1.65 + i * .29, .05)
        m.add(tube([branch_start, (x * .38, y - 1.25, z * .35), (x * .78, y - .45, z * .72), (x, y, z)],
                   [.18 - i * .010, .14 - i * .008, .075, .024], 9), "bark", "Wood", i)
        foliage_mass(m, (x, y, z), (rx, ry, rz), i * 1.4)
    return m


def silver_birch():
    m = Nature()
    for tree, (sx, sz, lean, height) in enumerate([(-.20, -.05, -.45, 6.5), (.25, .09, .49, 5.65)]):
        points = [(sx, 0, sz), (sx + lean * .18, 1.65, sz + .04),
                  (sx + lean * .62, 3.45, sz - .12), (sx + lean, height, sz + .09)]
        m.add(tube(points, [.17, .13, .082, .018], 10, 5, .025), "birch", "Wood")
        for j in range(11):
            y = .35 + j * .39
            x = sx + lean * y / height
            a = j * 2.41
            radial = np.array([math.cos(a), 0, math.sin(a)])
            pos = np.array([x, y, sz]) + radial * (.153 - y * .014)
            m.add(leaf(pos - np.cross(radial, [0, 1, 0]) * .075, pos + np.cross(radial, [0, 1, 0]) * .10,
                       .034, .0), "scar", "Wood")
        for j in range(3):
            a = j * 2.24 + tree * 1.7
            y = 2.75 + j * 1.04
            reach = 1.10 - j * .12
            x, z = sx + lean * y / height + math.cos(a) * reach, sz + math.sin(a) * reach
            m.add(tube([(sx + lean * y / height, y - .65, sz),
                        (x * .62, y + .18, z * .62), (x, y + .08, z)], [.067, .041, .009], 7), "birch", "Wood")
            foliage_mass(m, (x, y + .47, z), (1.03 - j * .065, .83, .78), j + tree * 3, "birch_leaf")
        foliage_mass(m, (sx + lean, height - .25, sz + .05), (.83, .69, .69), tree + 11, "birch_leaf")
    return m


def pine_bough(center, radius, height, angle, width):
    """One thick, round-tipped drooping leaf in a pine's layered skirt."""
    vertices, faces = [], []
    segments, rings = 12, 9
    radial = np.array([math.cos(angle), 0, math.sin(angle)])
    side = np.array([-math.sin(angle), 0, math.cos(angle)])
    normal = norm([math.cos(angle) * height, radius, math.sin(angle) * height])
    for i in range(rings + 1):
        t = .5 - .5 * math.cos(math.pi * i / rings)
        at = np.asarray(center) + radial * (radius * t ** .90)
        at[1] += height * (1 - t) + .085 * math.sin(math.pi * t)
        half_width = width * .5 * math.sin(math.pi * t) ** .53
        depth = .105 * math.sin(math.pi * t) ** .64
        for j in range(segments):
            a = j * TAU / segments
            vertices.append(at + side * math.cos(a) * half_width + normal * math.sin(a) * depth)
    for i in range(rings):
        for j in range(segments):
            a, b = i * segments + j, i * segments + (j + 1) % segments
            faces.extend(((a, a + segments, b), (b, a + segments, b + segments)))
    mesh = tm.Trimesh(vertices, faces, process=True)
    mesh.update_faces(mesh.nondegenerate_faces())
    mesh.fix_normals()
    return mesh


def wind_pine():
    m = Nature()
    roots(m, .28, 5)
    m.add(tube([(0, 0, 0), (.10, 1.4, -.07), (.24, 3, -.09), (.12, 4.8, 0), (.35, 6.2, .06)],
               [.29, .23, .17, .10, .023], 11, 5, .04), "bark", "Wood")
    for i, (y, r, h) in enumerate([(1.24, 2.08, 2.30), (2.58, 1.75, 2.10), (3.82, 1.30, 1.86), (4.96, .82, 1.82)]):
        cx = .14 + .17 * math.sin(y * 1.7)
        for j in range(8):
            a = j * TAU / 8 + i * .49
            reach = r * (1 + .045 * math.sin(a * 3 + i))
            width = r * .59
            m.add(pine_bough((cx, y, 0), reach, h, a, width), "pine", shift=a, shade=.95 + .05 * math.sin(a))
    return m


def hazel_thicket():
    m = Nature()
    for i in range(4):
        a = i * 2.40
        c = (math.cos(a) * .48, .51 + .16 * (i % 3), math.sin(a) * .40)
        m.add(tube([(0, 0, 0), (c[0] * .58, .34, c[2] * .6), c], [.035, .024, .008], 7), "bark", "Wood")
        foliage_mass(m, c, (.60, .41, .53), i * 1.5, "hazel")
    return m


def moss_boulder():
    m = Nature()
    # A small asymmetrical, bevelled rock has broad readable faces instead of
    # granular fractures.  Its one consolidated mesh is also used on the bank.
    outline = [(-.85, -.64), (.15, -.82), (.87, -.52), (1.03, .21), (.35, .82), (-.74, .61), (-1.0, -.04)]
    vertices = []
    for y, scale in [(.04, .73), (.23, .96), (.79, 1.0), (1.07, .73)]:
        vertices.extend((x * scale + y * .15, y + x * .045, z * scale + y * .04) for x, z in outline)
    rock = tm.convex.convex_hull(np.asarray(vertices))
    m.add(rock, "stone", "Stone")
    stone_mesh = m.parts["Stone"][0]
    rgba = stone_mesh.visual.vertex_colors.copy()
    moss_rgb = np.array(PALETTE["moss"][1], dtype=float)
    v = stone_mesh.vertices
    weight = np.clip((v[:, 1] - .55) / .65, 0, 1) * np.clip((.5 - v[:, 0]) / 1.2, 0, 1) * .58
    rgba[:, :3] = (rgba[:, :3] * (1 - weight[:, None]) + moss_rgb * weight[:, None]).astype(np.uint8)
    stone_mesh.visual.vertex_colors = rgba
    return m


def fern_patch():
    m = Nature()
    for i in range(5):
        a = i * 2.40
        length = .57 + .09 * math.sin(i * 1.7)
        start = np.array([0, .018, 0])
        end = np.array([math.cos(a) * length, .12 + .05 * (i % 3), math.sin(a) * length])
        path = catmull([start, end * np.array([.32, 0, .32]) + [0, .35, 0], end], 8)
        m.add(tube(path[::4], [.021] * len(path[::4]), 5, 2), "fern", "Grass")
        for j in (4, 8, 12):
            t = j / 16
            at = path[j]
            size = .22 * math.sin(t * math.pi) ** .8
            for side in (-1, 1):
                heading = a + side * 1.03
                tip = at + np.array([math.cos(heading) * size, -.012, math.sin(heading) * size])
                m.add(leaf(at, tip, size * .74, .034), "fern", "Grass")
    return m


def grass_blade(start, height, angle, width, lean):
    start = np.asarray(start, float)
    end = start + np.array([math.cos(angle) * lean, height, math.sin(angle) * lean])
    mesh = leaf(start, end, width, .08, twist=.25)
    return mesh


def meadow_tuft():
    m = Nature()
    for i in range(9):
        a = i * 2.4
        r = .13 * math.sqrt(i / 9)
        h = .27 + .24 * (.5 + .5 * math.sin(i * 1.71))
        m.add(grass_blade((math.cos(a) * r, .01, math.sin(a) * r), h, a, .15, .19 + r), "grass", "Grass")
    return m


def reed_cluster():
    m = Nature()
    for i in range(5):
        a = i * 2.4
        r = .20 * math.sqrt(i / 7)
        x, z = math.cos(a) * r, math.sin(a) * r
        h = .65 + .24 * (.5 + .5 * math.cos(i * 1.3))
        m.add(tube([(x, .01, z), (x + .05, h * .58, z), (x + .10, h, z + .02)], [.018, .011, .006], 5, 3), "reed", "Grass")
        for side in (-1, 1):
            m.add(grass_blade((x, .035, z), h * .79, a + side * .6, .075, .28), "reed", "Grass")
        m.add(crown((x + .094, h * .87, z + .02), (.044, .13, .044), i, 10, 8), "seed", "Grass")
    return m


def daisies():
    m = Nature()
    for i in range(3):
        a = i * 2.4
        x, z = math.cos(a) * .20, math.sin(a) * .20
        h = .25 + .10 * (.5 + .5 * math.cos(i * 1.7))
        m.add(tube([(x, .01, z), (x + .035, h, z)], [.01, .006], 5, 2), "grass", "Grass")
        for side in (-1, 1):
            m.add(leaf((x, .07, z), (x + side * .13, .12, z + .045), .07, .02), "grass", "Grass")
        for j in range(7):
            b = j * TAU / 7
            c = np.array([x + .035, h, z])
            m.add(leaf(c, c + np.array([math.cos(b) * .145, -.025, math.sin(b) * .145]), .084, .032), "white", "Petals")
        m.add(crown((x + .035, h + .013, z), (.047, .022, .047), i, 12, 6), "gold", "Petals")
    return m


def bluebell_shape(center, angle):
    verts, faces = [], []
    for i in range(6):
        t = i / 5
        r = .033 + .038 * t * t
        for j in range(16):
            a = j * TAU / 16
            flare = 1 + .14 * math.cos(a * 5) * t ** 4
            verts.append((center[0] + math.cos(a) * r * flare + math.cos(angle) * .045 * t,
                          center[1] - t * .095 + math.cos(a * 5) * .015 * t ** 4,
                          center[2] + math.sin(a) * r * flare + math.sin(angle) * .045 * t))
    for i in range(5):
        for j in range(16):
            a, b = i * 16 + j, i * 16 + (j + 1) % 16
            faces.extend(((a, a + 16, b), (b, a + 16, b + 16)))
    return tm.Trimesh(verts, faces, process=False)


def bluebells():
    m = Nature()
    for i in range(3):
        a = i * 2.4
        x, z = math.cos(a) * .19, math.sin(a) * .19
        h = .38 + .12 * (i % 2)
        m.add(tube([(x, 0, z), (x, h * .66, z), (x + .045, h, z + .02)], [.011, .009, .003], 5), "grass", "Grass")
        for j in range(2):
            c = (x + math.cos(a) * .025, h - j * .082, z + math.sin(a) * .025)
            m.add(bluebell_shape(c, a), "blue", "Petals")
        for j in (-1, 1):
            m.add(grass_blade((x, .01, z), h * .55, a + j * .5, .072, .15), "grass", "Grass")
    return m


if __name__ == "__main__":
    for builder in (canopy_oak, silver_birch, wind_pine, hazel_thicket, moss_boulder,
                    fern_patch, meadow_tuft, reed_cluster, daisies, bluebells):
        builder().save(builder.__name__)
