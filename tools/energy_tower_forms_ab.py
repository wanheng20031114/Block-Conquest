"""Original offline energy-tower studies A and B, with independent Glow meshes.

Both forms stand on y=0, face +z and use the existing toy-kingdom palette.
The shared exporter owns the final asset paths, materials and scene assembly.
"""
from __future__ import annotations

import math

import numpy as np
import trimesh as tm

import war_geometry as env
import build_war_architecture as arch


env.C.update({
    "energy_aqua": (65, 190, 169),
    "energy_bright": (168, 239, 194),
})


def _octagonal(model, width, depth, bottom, top, material="stone", bevel=.17):
    outline = arch.octagon(width, depth, bevel)
    vertices = [(x, y, z) for y in (bottom, top) for x, z in outline]
    return model.add(tm.convex.convex_hull(np.asarray(vertices)), material)


def _glow(model, mesh, material="energy_aqua", pos=(0, 0, 0), rot=(0, 0, 0)):
    """Energy colors intentionally retain the shared palette's Stone default."""
    part = model.add(mesh, material, pos=pos, rot=rot)
    assert model.parts["Stone"][-1] is part
    model.parts["Stone"].pop()
    model.parts["Glow"].append(part)
    return part


def _crystal(model, radius, height, pos, lean=0.0):
    """A closed six-sided prism with an asymmetric pointed crown."""
    sides = 6
    vertices = []
    for y, r in ((0.0, .67 * radius), (.18 * height, radius), (.73 * height, .9 * radius)):
        vertices.extend((math.cos(i * math.tau / sides + math.pi / 6) * r,
                         y,
                         math.sin(i * math.tau / sides + math.pi / 6) * r)
                        for i in range(sides))
    vertices.append((radius * .11, height, -radius * .12))
    tip = len(vertices) - 1
    faces = []
    for row in range(2):
        for i in range(sides):
            a = row * sides + i
            b = row * sides + (i + 1) % sides
            faces.extend(((a, b, b + sides), (a, b + sides, a + sides)))
    faces.extend((2 * sides + i, 2 * sides + (i + 1) % sides, tip) for i in range(sides))
    faces.extend((0, i + 1, i) for i in range(1, sides - 1))
    crystal = tm.Trimesh(vertices, faces, process=False)
    crystal.fix_normals()
    part = _glow(model, crystal, pos=pos, rot=(0, 0, lean))
    # Flat facets carry a restrained two-color gradient, entirely as vertex color.
    part.unmerge_vertices()
    colors = []
    for normal in part.face_normals:
        highlight = normal[1] > .40 or (normal[0] < -.55 and normal[2] > .12)
        shade = .035 if normal[2] > .45 else -.025
        colors.extend([env.color("energy_bright" if highlight else "energy_aqua", shade)] * 3)
    part.visual.vertex_colors = np.asarray(colors, dtype=np.uint8)


def _steps(model, width=1.2, threshold_z=1.27):
    # The lowest stair rests on the same ground plane as the foundation.
    model.box((width + .16, .12, .46), (0, .06, threshold_z + .39), "stone", bevel=.045)
    model.box((width, .22, .40), (0, .11, threshold_z + .19), "stone_light", bevel=.045)


def _masonry_seams(model, radius, bottom, height, sides=12, rows=3):
    """Broad course joints on the flat faces of a polygonal round wall."""
    # Cylinder vertices are at integer angles; each seam sits on a face plane.
    apothem = radius * math.cos(math.pi / sides)
    face_width = 2 * radius * math.sin(math.pi / sides)
    for row in range(rows):
        y = bottom + (row + 1) * height / rows
        for index in range(sides):
            angle = (index + .5) * math.tau / sides
            x, z = math.sin(angle) * apothem, math.cos(angle) * apothem
            # Keep the front doorway clean, with its own pale arch surround.
            if z > apothem * .65 and abs(x) < .85:
                continue
            model.box((face_width - .035, .025, .017), (x, y, z),
                      "stone_joint", rot=(0, angle, 0))
            if (index + row) % 2 == 0:
                model.box((.023, height / rows - .025, .018),
                          (x, y - height / rows * .5, z), "stone_joint", rot=(0, angle, 0))


def build_crystal() -> env.Model:
    """A: a pale octagonal furnace cradling one high and two low green crystals."""
    model = env.Model()
    _octagonal(model, 3.02, 2.72, 0, .20, "stone")
    _octagonal(model, 2.87, 2.56, .18, .39, "stone_light")
    _octagonal(model, 2.48, 2.24, .35, 1.72, "plaster")
    _octagonal(model, 2.62, 2.37, .39, .55, "stone")
    _octagonal(model, 2.80, 2.53, 1.57, 1.81, "stone_light")
    _octagonal(model, 2.66, 2.40, 1.80, 1.95, "gold_dark")
    _octagonal(model, 2.47, 2.21, 1.93, 2.045, "gold")
    model.cylinder(.94, .035, (0, 2.06, -.10), "dark", sections=12)
    model.ring(.89, 1.035, .12, (0, 2.085, -.10), "gold_light", sections=12)

    # Thick corner blocks and inset seams make the little kiln read as masonry.
    for side in (-1, 1):
        for z in (-.77, .77):
            model.box((.25, 1.10, .24), (side * 1.08, 1.035, z), "stone", bevel=.055)
            model.box((.32, .17, .30), (side * 1.08, 1.49, z), "stone_light", bevel=.035)
        flank = env.Model()
        arch.wall_joints(flank, 1.45, (0, .55, 0), .99)
        arch.window(flank, 0, 1.035, .015, .30, .48)
        model.absorb(flank, (side * 1.245, 0, -.09), side * math.pi / 2)
    back = env.Model()
    arch.wall_joints(back, 1.63, (0, .57, 0), .98)
    model.absorb(back, (0, 0, -1.13), math.pi)
    arch.royal_gate(model, 0, .23, 1.115, width=.72, height=1.07)
    _steps(model, 1.12, 1.20)
    # A copper keystone joins the practical doorway to the magical furnace above.
    model.box((.24, .22, .12), (0, 1.50, 1.195), "gold_light", bevel=.025)

    _crystal(model, .50, 2.95, (0, 2.035, -.14), lean=math.radians(-3))
    _crystal(model, .31, 1.92, (-.70, 2.035, .10), lean=math.radians(17))
    _crystal(model, .34, 1.72, (.72, 2.035, .05), lean=math.radians(-19))

    # Four bent copper claws clasp the crystal shoulders, with cast rounded feet.
    for angle in (math.radians(35), math.radians(145), math.radians(215), math.radians(325)):
        direction = np.array((math.sin(angle), 0, math.cos(angle)))
        foot = direction * .98 + np.array((0, 2.035, -.10))
        elbow = direction * .88 + np.array((0, 2.40, -.10))
        tip = direction * .56 + np.array((0, 2.62, -.10))
        model.beam(foot, elbow, .155, "gold_dark")
        model.beam(elbow, tip, .14, "gold")
        model.add(tm.creation.icosphere(subdivisions=1, radius=.115), "gold_light", pos=foot)
        model.add(tm.creation.icosphere(subdivisions=1, radius=.088), "gold_light", pos=tip)
    return model


def _ring_ticks(model, center, radius, rotation, count=12):
    """Raised brass divisions on the sky ring resemble a village observatory."""
    pose = env.transform(center, rotation)
    for index in range(count):
        angle = index * math.tau / count
        local = np.array((math.cos(angle) * radius, 0, math.sin(angle) * radius))
        position = tm.transform_points([local], pose)[0]
        model.add(tm.creation.icosphere(subdivisions=1, radius=.063), "gold_light", pos=position)


def build_armillary() -> env.Model:
    """B: a squat round stone tower carrying two inclined brass celestial rings."""
    model = env.Model()
    model.cylinder(1.47, .19, (0, .095, 0), "stone", sections=16)
    model.cylinder(1.39, .21, (0, .265, 0), "stone_light", sections=16)
    model.cylinder(1.235, 1.34, (0, 1.005, 0), "plaster", sections=16)
    model.ring(1.15, 1.285, .19, (0, .45, 0), "stone", sections=16)
    model.cylinder(1.38, .22, (0, 1.66, 0), "stone_light", sections=16)
    model.cylinder(1.31, .10, (0, 1.815, 0), "gold_dark", sections=16)
    model.cylinder(1.20, .11, (0, 1.915, 0), "gold", sections=16)
    _masonry_seams(model, 1.244, .48, .93, sides=16, rows=3)
    arch.royal_gate(model, 0, .23, 1.20, width=.72, height=1.02)
    _steps(model, 1.10, 1.28)

    # Narrow arched side niches keep the circular base recognizably architectural.
    for side in (-1, 1):
        niche = env.Model()
        arch.window(niche, 0, 1.05, 0, .29, .48)
        model.absorb(niche, (side * 1.225, 0, -.04), side * math.pi / 2)
    for angle in (math.pi * .28, math.pi * .72, math.pi * 1.28, math.pi * 1.72):
        x, z = 1.10 * math.sin(angle), 1.10 * math.cos(angle)
        model.box((.20, .95, .19), (x, 1.00, z), "stone", rot=(0, angle, 0), bevel=.03)

    # The turned wooden pedestal and brass yoke are handcrafted supports, not machinery.
    arch.turned(model, [(1.94, .47), (2.00, .47), (2.09, .31),
                       (2.28, .24), (2.38, .37), (2.45, .37)], "wood", sections=12)
    model.ring(.26, .35, .09, (0, 2.11, 0), "gold_light", sections=12)
    model.ring(.30, .40, .11, (0, 2.40, 0), "gold", sections=12)
    center = (0, 3.00, 0)
    model.cylinder(.085, 1.79, (0, 3.10, 0), "gold_dark", sections=10)
    for y in (2.26, 3.99):
        model.add(tm.creation.icosphere(subdivisions=1, radius=.12), "gold_light", pos=(0, y, 0))

    rotations = ((math.radians(66), math.radians(13), math.radians(18)),
                 (math.radians(-62), math.radians(-22), math.radians(-24)))
    for index, rotation in enumerate(rotations):
        inner, outer = (1.14, 1.29) if index == 0 else (1.25, 1.40)
        model.ring(inner, outer, .105, center, "gold" if index == 0 else "gold_dark",
                   sections=32, rot=rotation)
        _ring_ticks(model, center, (inner + outer) * .5, rotation)

    globe = tm.creation.icosphere(subdivisions=2, radius=.61)
    glow = _glow(model, globe, pos=center)
    glow.unmerge_vertices()
    colors = []
    for normal in glow.face_normals:
        bright = normal[1] > .38 and normal[2] > -.48
        colors.extend([env.color("energy_bright" if bright else "energy_aqua")] * 3)
    glow.visual.vertex_colors = np.asarray(colors, dtype=np.uint8)
    # A low cradle catches the floating globe without covering its clear silhouette.
    model.ring(.30, .43, .08, (0, 2.46, 0), "gold_light", sections=12)
    return model
