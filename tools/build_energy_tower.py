"""Bake the selected armillary energy tower as reusable architectural assets.

The scene owns the ring pivots and core pulse. Geometry is authored offline,
with separate Heraldry and Glow meshes for per-instance faction colors.
"""
from __future__ import annotations

import math

import numpy as np
import trimesh as tm

import war_geometry as env
import build_war_architecture as arch


env.C.update({
    "energy_heraldry": (128, 131, 135),
    "energy_facet": (132, 132, 132),
    "energy_highlight": (163, 163, 163),
})


def _move_part(model, part, source, target):
    assert model.parts[source][-1] is part
    model.parts[source].pop()
    if not model.parts[source]:
        del model.parts[source]
    model.parts[target].append(part)


def _masonry_seams(model):
    sides, rows = 16, 3
    radius, bottom, height = 1.244, .48, .93
    apothem = radius * math.cos(math.pi / sides)
    face_width = 2 * radius * math.sin(math.pi / sides)
    for row in range(rows):
        y = bottom + (row + 1) * height / rows
        for index in range(sides):
            angle = (index + .5) * math.tau / sides
            x, z = math.sin(angle) * apothem, math.cos(angle) * apothem
            if z > apothem * .65 and abs(x) < .85:
                continue
            model.box((face_width - .035, .025, .017), (x, y, z),
                      "stone_joint", rot=(0, angle, 0))
            if (index + row) % 2 == 0:
                model.box((.023, height / rows - .025, .018),
                          (x, y - height / rows * .5, z), "stone_joint", rot=(0, angle, 0))


def build_base():
    model = env.Model()
    model.cylinder(1.47, .19, (0, .095, 0), "stone", sections=16)
    model.cylinder(1.39, .21, (0, .265, 0), "stone_light", sections=16)
    model.cylinder(1.235, 1.34, (0, 1.005, 0), "plaster", sections=16)
    model.ring(1.15, 1.285, .19, (0, .45, 0), "stone", sections=16)
    # The 0.279 m faction band remains legible at the normal game camera.
    heraldry = model.cylinder(1.38, .34, (0, 1.60, 0), "energy_heraldry", sections=16)
    _move_part(model, heraldry, "Stone", "Heraldry")
    model.cylinder(1.31, .10, (0, 1.815, 0), "gold_dark", sections=16)
    model.cylinder(1.20, .11, (0, 1.915, 0), "gold", sections=16)
    _masonry_seams(model)
    arch.royal_gate(model, 0, .23, 1.20, width=.72, height=1.02)
    model.box((1.26, .12, .46), (0, .06, 1.67), "stone", bevel=.045)
    model.box((1.10, .22, .40), (0, .11, 1.47), "stone_light", bevel=.045)
    for side in (-1, 1):
        niche = env.Model()
        arch.window(niche, 0, 1.05, 0, .29, .48)
        model.absorb(niche, (side * 1.225, 0, -.04), side * math.pi / 2)
    for angle in (math.pi * .28, math.pi * .72, math.pi * 1.28, math.pi * 1.72):
        x, z = 1.10 * math.sin(angle), 1.10 * math.cos(angle)
        model.box((.20, .95, .19), (x, 1.00, z), "stone", rot=(0, angle, 0), bevel=.03)
    arch.turned(model, [(1.94, .47), (2.00, .47), (2.09, .31),
                       (2.28, .24), (2.38, .37), (2.45, .37)], "wood", sections=12)
    model.ring(.26, .35, .09, (0, 2.11, 0), "gold_light", sections=12)
    model.ring(.30, .40, .11, (0, 2.40, 0), "gold", sections=12)
    model.cylinder(.085, 1.79, (0, 3.10, 0), "gold_dark", sections=10)
    for y in (2.26, 3.99):
        model.add(tm.creation.icosphere(subdivisions=1, radius=.12), "gold_light", pos=(0, y, 0))
    model.ring(.30, .43, .08, (0, 2.46, 0), "gold_light", sections=12)
    return model


def build_ring(inner, outer, degrees, material):
    model = env.Model()
    rotation = tuple(math.radians(angle) for angle in degrees)
    model.ring(inner, outer, .105, (0, 0, 0), material, sections=32, rot=rotation)
    pose = env.transform(rot=rotation)
    for index in range(12):
        angle = index * math.tau / 12
        radius = (inner + outer) * .5
        position = tm.transform_points([(math.cos(angle) * radius, 0, math.sin(angle) * radius)], pose)[0]
        model.add(tm.creation.icosphere(subdivisions=1, radius=.063), "gold_light", pos=position)
    return model


def build_core():
    model = env.Model()
    glow = model.add(tm.creation.icosphere(subdivisions=2, radius=.61), "energy_facet")
    _move_part(model, glow, "Stone", "Glow")
    glow.unmerge_vertices()
    colors = []
    for normal in glow.face_normals:
        bright = normal[1] > .38 and normal[2] > -.48
        colors.extend([env.color("energy_highlight" if bright else "energy_facet")] * 3)
    glow.visual.vertex_colors = np.asarray(colors, dtype=np.uint8)
    return model


def main():
    models = {
        "energy_tower": build_base(),
        "energy_tower_core": build_core(),
        "energy_tower_ring_a": build_ring(1.14, 1.29, (66, 13, 18), "gold"),
        "energy_tower_ring_b": build_ring(1.25, 1.40, (-62, -22, -24), "gold_dark"),
    }
    for name, model in models.items():
        for parts in model.parts.values():
            for part in parts:
                part.apply_scale(arch.BODY_SCALE)
        print(name, model.save(name, wrapper=False))


if __name__ == "__main__":
    main()
