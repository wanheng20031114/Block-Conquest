"""Offline sculpted woodland for the miniature kingdom battlefield.

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
    "bark": ((100, 60, 31), (192, 130, 67)),
    "birch": ((151, 142, 104), (239, 223, 173)),
    "scar": ((96, 82, 49), (145, 125, 81)),
    "oak": ((38, 98, 62), (108, 170, 82)),
    "oak_sun": ((57, 116, 59), (140, 184, 85)),
    "birch_leaf": ((79, 117, 47), (178, 187, 82)),
    "willow": ((44, 108, 65), (134, 166, 78)),
    "pine": ((35, 107, 79), (103, 170, 102)),
    "hazel": ((46, 118, 59), (145, 183, 64)),
    "fern": ((51, 123, 71), (137, 185, 90)),
    "grass": ((70, 135, 57), (174, 203, 91)),
    "reed": ((78, 127, 57), (163, 187, 82)),
    "seed": ((110, 68, 35), (185, 126, 64)),
    "stone": ((106, 121, 116), (170, 180, 164)),
    "stone_side": ((90, 109, 106), (144, 160, 144)),
    "moss": ((77, 127, 55), (157, 171, 88)),
    "white": ((223, 221, 178), (255, 254, 235)),
    "gold": ((216, 155, 28), (255, 220, 78)),
    "blue": ((96, 89, 180), (183, 170, 239)),
}


def norm(v):
    v = np.asarray(v, dtype=float)
    return v / max(np.linalg.norm(v), 1e-8)


def paint(mesh, palette, shift=0.0, color_height=None):
    low, high = (np.asarray(c, dtype=float) for c in PALETTE[palette])
    verts = mesh.vertices
    bottom, top = color_height if color_height is not None else (verts[:, 1].min(), verts[:, 1].max())
    y = np.clip((verts[:, 1] - bottom) / max(top - bottom, .01), 0, 1)
    # Broad painted light/shadow, never per-triangle random noise.
    sweep = .5 + .5 * np.sin(verts[:, 0] * .85 + verts[:, 2] * .6 + shift)
    light = np.clip(.13 + y * .76 + sweep * .11, 0, 1)
    rgb = low[None, :] + (high - low)[None, :] * light[:, None]
    mesh.visual.vertex_colors = np.column_stack((rgb, np.full(len(verts), 255))).astype(np.uint8)
    return mesh


class Nature:
    def __init__(self):
        self.parts = defaultdict(list)

    def add(self, mesh, palette, group="Foliage", shift=0.0, shade=1.0, color_height=None):
        mesh = mesh.copy()
        mesh.fix_normals(multibody=True)
        paint(mesh, palette, shift, color_height)
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
                    "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": .82},
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
            scallop = 1 + .055 * math.cos(5 * a + seed) * st ** 2 + .025 * math.sin(3 * a - seed * .7) * st
            shoulder = 1 + .035 * math.sin(phi * 3 + seed)
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


def leaf_pad(center, outward, length, width, depth, heading=0.0):
    """A closed, ridged leaf sculpt lying along the surface of a crown."""
    outward = norm(outward)
    down = norm(np.array([0., -1., 0.]) - outward * np.dot([0., -1., 0.], outward))
    if np.linalg.norm(down) < .1:
        down = np.array([1., 0., 0.])
    side = norm(np.cross(outward, down))
    along = down * math.cos(heading) + side * math.sin(heading)
    across = norm(np.cross(outward, along))
    vertices, faces = [], []
    rings, sections = 6, 8
    for i in range(rings + 1):
        t = (i + .002) / (rings + .004)
        width_at = math.sin(math.pi * t) ** .85 * width * .5
        # The tip turns slightly away from the cluster, making a leaf edge.
        mid = np.asarray(center) + along * (t - .5) * length + outward * (.055 * t * t)
        for j in range(sections):
            a = TAU * j / sections
            vertices.append(mid + across * math.cos(a) * width_at + outward * math.sin(a) * depth * math.sin(math.pi * t))
    for i in range(rings):
        for j in range(sections):
            a, b = i * sections + j, i * sections + (j + 1) % sections
            faces.extend(((a, b, a + sections), (b, b + sections, a + sections)))
    return tm.Trimesh(vertices, faces, process=True)


def foliage_mass(m, center, radii, seed, palette="oak", shade=1.0, detail=True):
    """Large crown structure plus overlapping, explicitly sculpted leaf plates.

    Leaf plates follow the surface downhill. Their ridges catch light in close
    views, and native LODs simplify them at the tactical camera distance.
    """
    m.add(crown(center, np.asarray(radii) * (.87 if detail else 1.0), seed, 24, 12), palette, shift=seed, shade=shade * .97)
    if not detail:
        return
    slender = palette == "willow"
    for row, (phi, count) in enumerate(((.32, 6), (.69, 11), (1.08, 15), (1.49, 15), (1.91, 11))):
        for j in range(count):
            a = j * TAU / count + seed * .61 + row * .37
            phi_at = phi + .045 * math.sin(j * 1.7 + seed)
            unit = np.array([math.sin(phi_at) * math.cos(a), math.cos(phi_at), math.sin(phi_at) * math.sin(a)])
            at = np.asarray(center) + np.asarray(radii) * unit * .93
            normal = norm(unit / np.asarray(radii))
            scale = min(radii[0], radii[2])
            pad = leaf_pad(at, normal, scale * (.99 if slender else .85),
                           scale * (.29 if slender else .47), scale * .06,
                           .29 * math.sin(a * 3 + seed))
            m.add(pad, palette, shift=seed + row * .14, shade=shade * (1.025 + .025 * math.sin(j * 2.1)),
                  color_height=(center[1] - radii[1], center[1] + radii[1]))


def roots(m, radius=.43, count=5):
    for i in range(count):
        a = i * TAU / count + .3
        reach = .71 + .08 * math.sin(i * 2.2)
        m.add(tube([(math.cos(a) * .13, .67, math.sin(a) * .13),
                    (math.cos(a + .13) * .32, .27, math.sin(a + .13) * .32),
                    (math.cos(a + .05) * reach * .7, .10, math.sin(a + .05) * reach * .7),
                    (math.cos(a - .14) * reach, .028, math.sin(a - .14) * reach)],
                   [radius * .61, radius * .42, radius * .21, .012], 12, 3), "bark", "Wood", a)


def oak_bark(m):
    # Raised ribbons run with the bend in the trunk, ending before the forks.
    for i in range(7):
        a = i * TAU / 7 + .18
        path = []
        for y, x, radius in ((.16, .02, .415), (.80, .13, .355), (1.40, .09, .317), (2.08, -.04, .286)):
            path.append((x + math.cos(a + y * .1) * radius, y, .06 + math.sin(a + y * .1) * radius))
        m.add(tube(path, [.026, .030, .022, .007], 6, 3), "bark", "Wood", i, .88)
    knot = tm.creation.torus(major_radius=.10, minor_radius=.026, major_sections=18, minor_sections=7)
    knot.apply_scale([1., 1.45, .65])
    knot.apply_translation([.18, 1.19, .368])
    m.add(knot, "bark", "Wood", 1.7, .84)


def canopy_oak():
    m = Nature()
    roots(m)
    m.add(tube([(0, 0, 0), (.16, 1.05, .02), (-.04, 2.08, .12), (.21, 3.15, .04), (.12, 4.75, -.10)],
               [.43, .34, .29, .18, .07], 14, 5, .055), "bark", "Wood")
    oak_bark(m)
    # Open forks show between the lower masses. The upper masses form a
    # single irregular crown, replacing the old horizontal canopy slabs.
    branches = [((-1.25, 3.15, .04), (-.71, 2.23, .04)),
                ((1.12, 3.61, .04), (.65, 2.61, .11)),
                ((.01, 3.33, 1.13), (.08, 2.42, .57)),
                ((-.46, 4.03, -.92), (-.11, 2.93, -.38))]
    for i, (tip, elbow) in enumerate(branches):
        m.add(tube([(.03, 1.53 + i * .18, .03), elbow, tip], [.23 - i * .025, .16, .055], 11, 4, .045), "bark", "Wood", i)
    clusters = [(-1.25, 3.29, .13, 1.17, .77, .99),
                (1.15, 3.66, -.12, 1.17, .83, 1.01),
                (-.12, 3.36, 1.07, 1.17, .74, .98),
                (-.54, 3.87, -.96, 1.10, .78, .93),
                (-1.03, 4.22, -.15, 1.16, .87, 1.04),
                (.72, 4.34, .73, 1.12, .91, 1.01),
                (.59, 4.49, -.72, 1.06, .91, .94),
                (-.07, 4.77, -.01, 1.32, .94, 1.12)]
    for i, (x, y, z, rx, ry, rz) in enumerate(clusters):
        foliage_mass(m, (x, y, z), (rx, ry, rz), i * 1.37,
                     "oak_sun" if i >= 6 else "oak", .96 if i < 3 else 1.0)
    return m


def silver_birch():
    m = Nature()
    for i, (x, z, lean, height) in enumerate([(-.14, -.04, -.30, 5.25), (.21, .08, .44, 4.37)]):
        m.add(tube([(x, .0, z), (x + lean * .27, 1.65, z),
                    (x + lean * .75, 3.30, z - .1), (x + lean, height, z)],
                   [.21, .17, .105, .026], 12, 4, .018), "birch", "Wood")
        for j in range(6):
            y = .42 + j * .48
            scar = crown((x + lean * y / height, y, z + .143 - y * .018), (.10, .027, .025), j, 12, 6)
            m.add(scar, "scar", "Wood")
        for j in range(3):
            a = j * 2.35 + i * 1.65
            y = 2.63 + j * .66 - i * .13
            cx, cz = x + lean * .7 + math.cos(a) * .70, z + math.sin(a) * .57
            m.add(tube([(x + lean * .5, y - .85, z), (cx * .72, y - .35, cz * .62), (cx, y + .19, cz)],
                       [.105, .065, .018], 9, 3), "birch", "Wood")
            foliage_mass(m, (cx, y + .42, cz), (.82, .73, .76), j + i * 3.1, "birch_leaf")
        foliage_mass(m, (x + lean, height - .36, z), (.88, .76, .79), i + 7, "birch_leaf")
    return m


def pine_bough(center, radius, height, angle, seed):
    """A tapered branch with broad, scalloped needle fans, open between boughs."""
    vertices, faces = [], []
    radial = np.array([math.cos(angle), 0., math.sin(angle)])
    across = np.array([-math.sin(angle), 0., math.cos(angle)])
    normal = norm([math.cos(angle) * height * .6, radius, math.sin(angle) * height * .6])
    sections, rings = 10, 12
    for i in range(rings + 1):
        t = (i + .005) / (rings + .010)
        mid = np.asarray(center) + radial * radius * t
        mid[1] += height * (1 - t) ** .91 + .12 * math.sin(math.pi * t)
        breadth = radius * .48 * math.sin(math.pi * t) ** .60 * (1 + .16 * math.sin(t * math.pi * 5 + seed))
        thickness = radius * .105 * math.sin(math.pi * t) ** .7
        for j in range(sections):
            a = TAU * j / sections
            vertices.append(mid + across * math.cos(a) * breadth + normal * math.sin(a) * thickness)
    for i in range(rings):
        for j in range(sections):
            a, b = i * sections + j, i * sections + (j + 1) % sections
            faces.extend(((a, b, a + sections), (b, b + sections, a + sections)))
    mesh = tm.Trimesh(vertices, faces, process=True)
    mesh.fix_normals()
    return mesh


def wind_pine():
    m = Nature()
    roots(m, .32)
    m.add(tube([(0, 0, 0), (.08, 1.1, .04), (-.1, 2.7, .08), (.08, 4.2, 0), (.18, 5.6, -.04)],
               [.33, .25, .18, .105, .035], 12, 4, .03), "bark", "Wood")
    for i, (cx, y, r, h) in enumerate([(-.10, 1.10, 1.77, 1.78), (.14, 2.28, 1.44, 1.65),
                                       (-.02, 3.36, 1.09, 1.44), (.16, 4.30, .71, 1.45)]):
        for j in range(7):
            a = j * TAU / 7 + i * .47
            reach = r * (1 + .065 * math.sin(j * 1.83 + i))
            m.add(pine_bough((cx, y, 0), reach, h, a, i * .5), "pine", shift=i + a,
                  shade=.96 + i * .025 + .035 * math.sin(a))
            outer = (cx + math.cos(a) * reach * .91, y + h * .10, math.sin(a) * reach * .91)
            m.add(tube([(cx, y + h * .57, 0), (outer[0] * .56, y + h * .33, outer[2] * .56), outer],
                       [.065, .036, .008], 7, 3), "bark", "Wood")
    foliage_mass(m, (.16, 5.22, 0), (.29, .56, .28), 17, "pine", detail=False)
    return m


def weeping_willow():
    m = Nature()
    roots(m, .44, 6)
    m.add(tube([(0, 0, 0), (-.18, 1.03, .05), (-.32, 2.13, .08), (-.02, 3.40, .11), (.22, 4.43, -.04)],
               [.44, .35, .29, .20, .045], 14, 5, .065), "bark", "Wood")
    for i in range(7):
        a = i * TAU / 7 + .24
        reach = 1.32 + .17 * math.sin(i * 1.74)
        cx, cz = math.cos(a) * reach, math.sin(a) * reach
        y = 3.40 + .36 * math.sin(i * 1.30)
        m.add(tube([(-.18, 1.70 + i * .10, .05), (cx * .53, y + .17, cz * .53),
                    (cx, y + .12, cz), (cx * 1.13, y - 1.43, cz * 1.13)],
                   [.17, .12, .055, .010], 10, 4, .03), "bark", "Wood", i)
        foliage_mass(m, (cx * .75, y + .26, cz * .75), (.85, .59, .79), i * 1.63, "willow")
        # Hanging sprays are actual slender twigs with alternating long leaves.
        # Leaving spaces between sprays makes the arched willow silhouette airy.
        for spray in range(3):
            sa = a + (spray - 1) * .22
            reach_at = reach * (1.0 + spray * .035)
            top = np.array([math.cos(sa) * reach_at, y + .14 - spray * .10, math.sin(sa) * reach_at])
            drop = 1.07 + .38 * (.5 + .5 * math.sin(i + spray * 1.8))
            bottom = top + [math.cos(sa) * .12, -drop, math.sin(sa) * .12]
            m.add(tube([top, (top + bottom) * .5 + [0, .06, 0], bottom], [.017, .013, .004], 6, 3), "bark", "Wood")
            for j in range(5):
                t = .13 + j * .17
                at = top * (1 - t) + bottom * t
                normal = [math.cos(sa), .16, math.sin(sa)]
                pad = leaf_pad(at, normal, .57, .14, .027, (-1 if j % 2 else 1) * .42)
                m.add(pad, "willow", shift=i * .8 + j * .2, shade=.99 + .035 * math.sin(j))
    foliage_mass(m, (.02, 4.12, -.05), (1.01, .65, .94), 12, "willow")
    return m


def hazel_thicket():
    m = Nature()
    clusters = [(-.52, .42, .05, .64, .42, .57), (.45, .50, -.12, .67, .48, .61),
                (.05, .61, .25, .64, .53, .61), (-.18, .61, -.31, .54, .44, .50)]
    for i, (x, y, z, rx, ry, rz) in enumerate(clusters):
        m.add(tube([(0, .015, 0), (x * .6, .3, z * .6), (x, y, z)], [.048, .030, .009], 8, 3), "bark", "Wood")
        foliage_mass(m, (x, y, z), (rx, ry, rz), i * 1.62, "hazel")
    return m


def split_stone(mesh, origin, normal, gap=.027):
    """Cut a convex rock into closed chunks with an actual recessed fracture."""
    normal = norm(normal)
    origin = np.asarray(origin)
    distances = (mesh.vertices - origin) @ normal
    intersections = []
    for left, right in mesh.edges_unique:
        if distances[left] * distances[right] < 0:
            t = distances[left] / (distances[left] - distances[right])
            intersections.append(mesh.vertices[left] * (1 - t) + mesh.vertices[right] * t)
    chunks = []
    for sign in (-1, 1):
        points = np.vstack((mesh.vertices[distances * sign >= 0], intersections))
        chunk = tm.convex.convex_hull(points)
        chunk.apply_translation(normal * gap * sign)
        chunks.append(chunk)
    return chunks


def rounded_stone(mesh, radius=.019):
    # A small geometric bevel preserves broad fracture planes. It is a
    # Minkowski sum with a coarse sphere, not a smoothed sphere silhouette.
    center = mesh.vertices.mean(axis=0)
    core = center + (mesh.vertices - center) * .974
    bevel = tm.creation.icosphere(subdivisions=1).vertices * radius
    return tm.convex.convex_hull((core[:, None, :] + bevel[None, :, :]).reshape(-1, 3))


def moss_relief(m, chunk, outline, seed):
    """Project a torn, thin moss sheet onto the rock's actual sloping faces."""
    from shapely.geometry import MultiPoint
    footprint = MultiPoint(chunk.vertices[:, [0, 2]]).convex_hull.buffer(-.025)
    patch = env.Polygon(outline).intersection(footprint)
    if patch.is_empty:
        return
    triangles = env.constrained_delaunay_triangles(patch)
    vertices, faces = [], []
    for tri in triangles.geoms:
        points = list(tri.exterior.coords)[:3]
        offset = len(vertices)
        vertices.extend((x, 0., z) for x, z in points)
        faces.append((offset, offset + 1, offset + 2))
    sheet = tm.Trimesh(vertices, faces, process=True)
    sheet = sheet.subdivide_to_size(max_edge=.12, max_iter=5)
    normals = chunk.face_normals
    top_faces = normals[:, 1] > .05
    planes = normals[top_faces]
    distances = np.einsum('ij,ij->i', planes, chunk.triangles_center[top_faces])
    v = sheet.vertices.copy()
    ceiling = (distances[None, :] - v[:, 0, None] * planes[None, :, 0] - v[:, 2, None] * planes[None, :, 2]) / planes[None, :, 1]
    v[:, 1] = ceiling.min(axis=1) + .014 + .004 * np.sin(v[:, 0] * 14 + v[:, 2] * 12 + seed)
    sheet.vertices = v
    m.add(sheet, "moss", "Stone", seed, .82, color_height=(.4, 1.1))


def moss_boulder():
    m = Nature()
    outline = [(-1.0, -.36), (-.65, -.70), (.25, -.75), (.91, -.23),
               (.86, .48), (.12, .78), (-.78, .59)]
    vertices = []
    for y, scale, dx in ((.025, .77, -.06), (.39, 1.0, 0.), (.70, .92, .06), (.99, .69, .02)):
        for j, (x, z) in enumerate(outline):
            vertices.append((x * scale + dx, y + x * .115 - z * .07 + .037 * math.sin(j * 1.7), z * scale))
    body = tm.convex.convex_hull(vertices)
    # Two oblique fractures make three unequal pieces within one natural
    # boulder. Their narrow gaps expose dark recessed stone, not white seams.
    left, right = split_stone(body, (-.22, .45, -.03), (.95, .19, .31))
    front, back = split_stone(right, (.35, .4, .02), (.21, -.28, .95), .019)
    core = body.copy()
    core.apply_scale([.91, .87, .91])
    m.add(core, "stone_side", "Stone", shade=.64)
    moss_outline = [(-.87, -.37), (-.65, -.50), (-.57, -.44), (-.41, -.55),
                    (-.31, -.44), (-.13, -.49), (-.09, -.34), (.02, -.30),
                    (-.08, -.19), (-.01, -.12), (-.20, -.04), (-.13, .07),
                    (-.29, .17), (-.38, .10), (-.48, .22), (-.55, .13),
                    (-.69, .16), (-.65, .02), (-.79, -.03), (-.73, -.16),
                    (-.87, -.23)]
    for i, chunk in enumerate((left, front, back)):
        chunk = rounded_stone(chunk)
        m.add(chunk, "stone" if i != 1 else "stone_side", "Stone", i * 1.8,
              1.0 if i == 0 else .94, color_height=(-.05, 1.05))
        moss_relief(m, chunk, moss_outline, i)
        moss_relief(m, chunk, [(-.25, .29), (-.09, .20), (.01, .24), (-.04, .30),
                              (.03, .35), (-.03, .40), (-.15, .34), (-.24, .40)], i + 3)
    return m


def fern_patch():
    m = Nature()
    for i in range(7):
        a = i * 2.4
        length = .46 + .09 * math.sin(i * 1.7)
        end = (math.cos(a) * length, .16 + .05 * (i % 3), math.sin(a) * length)
        m.add(leaf((0, .02, 0), end, .25, .17, .1, segments=8), "fern", "Grass", i)
    return m


def grass_blade(start, height, angle, width, lean):
    start = np.asarray(start, float)
    return leaf(start, start + [math.cos(angle) * lean, height, math.sin(angle) * lean], width, .085, .18, segments=8)


def meadow_tuft():
    m = Nature()
    for i in range(7):
        a = i * 2.4
        r = .085 * math.sqrt(i / 7)
        h = .22 + .17 * (.5 + .5 * math.sin(i * 1.71))
        m.add(grass_blade((math.cos(a) * r, .01, math.sin(a) * r), h, a, .13, .14 + r), "grass", "Grass", i)
    return m


def reed_cluster():
    m = Nature()
    for i in range(3):
        a = i * 2.4
        x, z = math.cos(a) * .15, math.sin(a) * .15
        h = .58 + .17 * (i / 2)
        m.add(tube([(x, .01, z), (x + .03, h * .6, z), (x + .06, h, z)], [.021, .014, .008], 7, 3), "reed", "Grass")
        m.add(crown((x + .055, h - .05, z), (.052, .15, .052), i, 12, 8), "seed", "Grass")
        for side in (-1, 1):
            m.add(grass_blade((x, .018, z), h * .73, a + side * .7, .12, .25), "reed", "Grass", i)
    return m


def flower_bed(palette):
    m = Nature()
    for i in range(3):
        a = i * 2.4
        x, z = math.cos(a) * .21, math.sin(a) * .21
        h = .22 + .08 * (.5 + .5 * math.cos(i * 1.7))
        m.add(tube([(x, .01, z), (x + .025, h, z)], [.014, .009], 7, 2), "grass", "Grass")
        for side in (-1, 1):
            m.add(leaf((x, .04, z), (x + side * .19, .10, z + .075), .115, .055, segments=6), "grass", "Grass")
        for j in range(5):
            angle = j * TAU / 5 + i * .42
            petal = crown((0, 0, 0), (.074, .026, .125), j, 12, 6)
            petal.apply_transform(tm.transformations.rotation_matrix(angle, [0, 1, 0]))
            petal.apply_translation([x + .025 + math.sin(angle) * .094, h, z + math.cos(angle) * .094])
            m.add(petal, palette, "Petals", i)
        m.add(crown((x + .025, h + .021, z), (.059, .035, .059), i, 12, 6), "gold", "Petals")
    return m


def daisies():
    return flower_bed("white")


def bluebells():
    return flower_bed("blue")


if __name__ == "__main__":
    for builder in (canopy_oak, silver_birch, wind_pine, weeping_willow, hazel_thicket, moss_boulder,
                    fern_patch, meadow_tuft, reed_cluster, daisies, bluebells):
        builder().save(builder.__name__)
