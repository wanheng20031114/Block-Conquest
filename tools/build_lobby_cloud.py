"""Sculpt a connected, closed 3D cloud for the lobby. Requires numpy.

Offline authoring only: Godot imports the OBJ as an ordinary ArrayMesh.
Broad lobes blend into one surface with a gently flattened underside;
there are no overlapping sphere meshes, billboard planes, or baked lighting.
"""
from pathlib import Path
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/models/lobby/cloud.obj"
LOBES = (
    ((0.0, -0.12, 0.0), (1.78, 0.36, 0.60)),
    ((-1.23, 0.0, 0.03), (0.68, 0.49, 0.60)),
    ((-0.42, 0.40, -0.08), (0.78, 0.76, 0.70)),
    ((0.92, 0.15, 0.12), (0.77, 0.61, 0.63)),
    ((0.30, 0.26, -0.34), (0.60, 0.54, 0.50)),
)


def smooth_min(a, b, width):
    h = np.clip(0.5 + 0.5 * (b - a) / width, 0.0, 1.0)
    return b * (1.0 - h) + a * h - width * h * (1.0 - h)


def field(points):
    p = points.copy()
    p[:, 1] += 0.018 * np.sin(p[:, 0] * 2.4 + p[:, 2] * 1.9)
    distance = np.full(len(p), 10.0)
    for center, radii in LOBES:
        q = p - center
        radii = np.asarray(radii)
        k0 = np.linalg.norm(q / radii, axis=1)
        k1 = np.linalg.norm(q / (radii * radii), axis=1)
        ellipsoid = k0 * (k0 - 1.0) / np.maximum(k1, 1e-8)
        distance = smooth_min(distance, ellipsoid, 0.22)
    floor = -0.49 + 0.035 * np.cos(p[:, 0] * 1.1) * np.cos(p[:, 2] * 1.4)
    return -smooth_min(-distance, p[:, 1] - floor, 0.16)


def build():
    # Closed latitude rings share seam and pole vertices. Implicit-surface
    # normals retain the broad sculpt at a modest 2,496 triangles.
    columns, rows = 48, 27
    directions = [(0.0, 1.0, 0.0)]
    for row in range(1, rows):
        phi = np.pi * row / rows
        for column in range(columns):
            theta = 2.0 * np.pi * column / columns
            directions.append((np.sin(phi) * np.cos(theta), np.cos(phi), np.sin(phi) * np.sin(theta)))
    directions.append((0.0, -1.0, 0.0))
    directions = np.asarray(directions)
    origin = np.asarray((0.0, 0.1, 0.0))
    low, high = np.zeros(len(directions)), np.full(len(directions), 3.0)
    for _ in range(28):
        radius = (low + high) * 0.5
        inside = field(origin + directions * radius[:, None]) < 0.0
        low = np.where(inside, radius, low)
        high = np.where(inside, high, radius)
    vertices = origin + directions * ((low + high) * 0.5)[:, None]
    normals = np.column_stack([
        field(vertices + axis * 0.002) - field(vertices - axis * 0.002)
        for axis in np.eye(3)
    ])
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    faces = []
    for column in range(columns):
        following = (column + 1) % columns
        faces.append((0, 1 + column, 1 + following))
        for row in range(rows - 2):
            a = 1 + row * columns + column
            b = 1 + row * columns + following
            c, d = a + columns, b + columns
            faces.extend(((a, c, b), (b, c, d)))
        a = 1 + (rows - 2) * columns + column
        b = 1 + (rows - 2) * columns + following
        faces.append((len(vertices) - 1, b, a))
    faces = np.asarray(faces)
    # OBJ uses outward counterclockwise faces; Godot's importer converts them.
    a, b, c = (vertices[faces[:, i]] for i in range(3))
    flip = np.sum(np.cross(b - a, c - a) * normals[faces].mean(axis=1), axis=1) < 0.0
    faces[flip] = faces[flip][:, (0, 2, 1)]
    edges = np.sort(np.concatenate([faces[:, (0, 1)], faces[:, (1, 2)], faces[:, (2, 0)]]), axis=1)
    assert np.all(np.unique(edges, axis=0, return_counts=True)[1] == 2), "Cloud must be watertight"
    assert np.max(np.abs(field(vertices))) < 1e-5, "Vertices must lie on the sculpted surface"
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as output:
        output.write("# Connected lobby cloud; authored by tools/build_lobby_cloud.py\no Cumulus\ns 1\n")
        for vertex in vertices:
            output.write("v %.6f %.6f %.6f\n" % tuple(vertex))
        for normal in normals:
            output.write("vn %.6f %.6f %.6f\n" % tuple(normal))
        for face in faces + 1:
            output.write("f " + " ".join(f"{i}//{i}" for i in face) + "\n")
    print(f"{OUTPUT.relative_to(ROOT)}: {len(vertices)} vertices, {len(faces)} triangles, closed surface")


if __name__ == "__main__":
    build()
