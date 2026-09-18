"""Fitted cloth crowns: adjacent colour bands share the same ring geometry."""
import math
import numpy as np
from build_units import tm


def crown(s, part, loops, colors):
    """One closed loft, split by vertex-paint material only after joining it."""
    count = len(loops[0])
    vertices = [point for loop in loops for point in loop]
    faces, face_colors = [], []
    for row, color in enumerate(colors):
        for i in range(count):
            j = (i + 1) % count
            a, b = row * count + i, row * count + j
            c, d = a + count, b + count
            faces.extend(((a, c, b), (b, c, d)))
            face_colors.extend((color, color))
    for row, color, bottom in [(0, colors[0], True), (len(loops) - 1, colors[-1], False)]:
        center = len(vertices)
        vertices.append(tuple(np.mean(loops[row], axis=0)))
        for i in range(count):
            tri = (center, row * count + i, row * count + (i + 1) % count)
            faces.append(tri[::-1] if bottom else tri)
            face_colors.append(color)
    mesh = tm.Trimesh(vertices=vertices, faces=faces, process=True)
    mesh.fix_normals()
    assert mesh.is_watertight
    # Surface boundaries keep identical coordinates; no second rim or dome
    # is laid over the first and no runtime nodes are needed for the hat.
    for color in dict.fromkeys(face_colors):
        indices = [i for i, value in enumerate(face_colors) if value == color]
        section = mesh.submesh([indices], append=True, repair=False)
        s.add(part, section, color)


def spearman_cap(s, part, advanced=False):
    rings = [
        (.100, .227, .239, .000, -.024),
        (.154, .235, .242, .005, -.020),
        (.195, .249, .238, .015, -.014),
        (.258, .214, .199, .029, -.002),
        (.308, .115, .104, .030, .000),
        (.324, .032, .030, .025, .000),
    ]
    loops = [[(cx + rx * math.cos(i * math.tau / 12), y,
               cz + rz * math.sin(i * math.tau / 12)) for i in range(12)]
             for y, rx, rz, cx, cz in rings]
    crown(s, part, loops, ["leather" if advanced else "leatherlight"] + ["blue"] * 4)
    if advanced:
        s.b(part, (.052, .041, .020), (.161, .134, -.189), "steel",
            rot=(0, -math.pi / 4, 0), bevel=.008)
        s.e(part, (.014, .014, .010), (.172, .134, -.200), "gold", sub=0)


def archer_cap(s, part, advanced=False):
    # A flatter forehead contour closes over the face opening. The rear and
    # sides overlap the existing cloth hood; eyes and eyebrows stay exposed.
    outline = [(0, -.287), (.13, -.281), (.223, -.245), (.270, -.12),
               (.276, .065), (.225, .20), (.10, .265), (0, .277),
               (-.10, .265), (-.225, .20), (-.276, .065), (-.270, -.12),
               (-.223, -.245), (-.13, -.281)]
    rings = [(.095, .96, .96, .000, .040), (.132, 1, 1, .000, .022),
             (.160, 1.015, 1.005, .000, .005), (.213, .98, .94, .000, 0),
             (.279, .70, .65, .014, 0), (.332, .20, .16, .015, 0)]
    # The brow edge must clear the existing face, which protrudes farther
    # forward than the side hood. Otherwise the forehead punctures this rim.
    loops = [[(x * sx, y, z * sz + cz - brow * max(0, (-z - .12) / .167))
              for x, z in outline] for y, sx, sz, cz, brow in rings]
    crown(s, part, loops, ["blue", "leather" if advanced else "blue", "blue", "blue", "blue"])
    if advanced:
        s.e(part, (.024, .022, .014), (-.197, .148, -.273), "gold", sub=0)
