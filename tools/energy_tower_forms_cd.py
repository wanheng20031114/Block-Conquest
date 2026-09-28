"""Original coil workshop and rune lantern concepts, built as offline geometry.

Both models stand on y=0 with their entrance facing +z.  The builders only
return Model objects; the concept-gallery pipeline owns exporting and import.
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


def _glow(m, mesh, material="energy_aqua", pos=(0, 0, 0), scale=(1, 1, 1)):
    """Keep emissive geometry separate without changing the shared exporter."""
    part = m.add(mesh, material, pos=pos, scale=scale)
    m.parts["Glow"].append(m.parts["Stone"].pop())
    return part


def _gem(m, center, radius, height, sides=8):
    """A broad cut crystal with a pale upper facet, all opaque geometry."""
    x, y, z = center
    angles = np.arange(sides) * math.tau / sides + math.pi / 8
    waist = [(x + radius * math.cos(a), y - height * .12,
              z + radius * math.sin(a)) for a in angles]
    shoulder = [(x + radius * .76 * math.cos(a), y + height * .24,
                 z + radius * .76 * math.sin(a)) for a in angles]
    lower = tm.convex.convex_hull(np.asarray(waist + shoulder + [(x, y-height*.5, z)]))
    upper = tm.convex.convex_hull(np.asarray(shoulder + [(x, y+height*.5, z)]))
    _glow(m, lower)
    _glow(m, upper, "energy_bright")


def _steps(m, entrance_z, width=1.12):
    for index, (height, depth) in enumerate(((.10, .34), (.19, .29), (.29, .28))):
        z = entrance_z + .66 - index * .24
        m.box((width - index*.04, height, depth), (0, height/2, z),
              "stone_light", bevel=.035)


def _rivet(m, pos, radius=.045, direction="z"):
    rotation = (math.pi/2, 0, 0) if direction == "z" else (0, 0, math.pi/2)
    m.cylinder(radius, .055, pos, "gold_light", sections=8, rot=rotation)


def _helix(m, center, radius=.47, height=1.36, turns=3.6, tube=.073):
    """A continuous, solid copper winding; no texture or floating ring stack."""
    cx, cy, cz = center
    segments, cross_section = 100, 8
    vertices = []
    for index in range(segments + 1):
        t = index / segments
        angle = t * math.tau * turns
        radial = np.asarray((math.cos(angle), 0, math.sin(angle)))
        tangent = np.asarray((-radius*math.sin(angle), height/(math.tau*turns),
                              radius*math.cos(angle)))
        tangent /= np.linalg.norm(tangent)
        side = np.cross(tangent, radial)
        center_point = np.asarray((cx+radius*math.cos(angle), cy+height*(t-.5),
                                   cz+radius*math.sin(angle)))
        for ring_index in range(cross_section):
            phi = ring_index * math.tau / cross_section
            vertices.append(center_point + tube * (math.cos(phi)*radial + math.sin(phi)*side))
    faces = []
    for row in range(segments):
        for side in range(cross_section):
            a = row*cross_section+side
            b = row*cross_section+(side+1) % cross_section
            faces.extend(((a, b, b+cross_section), (a, b+cross_section, a+cross_section)))
    for index in range(1, cross_section-1):
        faces.append((0, index+1, index))
        last = segments*cross_section
        faces.append((last, last+index, last+index+1))
    mesh = tm.Trimesh(vertices, faces, process=False)
    mesh.fix_normals()
    m.add(mesh, "gold")


def build_coil() -> env.Model:
    """C: a squat village workshop carrying two hand-wound copper coils."""
    m = env.Model()
    m.box((3.26, .24, 2.62), (0, .12, -.10), "mortar", bevel=.09)
    m.box((3.12, .18, 2.48), (0, .32, -.10), "stone_light", bevel=.07)
    m.box((2.82, 1.33, 2.20), (0, 1.04, -.10), "plaster", bevel=.13)
    m.box((2.99, .17, 2.36), (0, 1.62, -.10), "wood_dark", bevel=.045)
    m.box((3.24, .21, 2.59), (0, 1.79, -.10), "wood_light", bevel=.07)
    m.box((3.35, .12, 2.70), (0, 1.94, -.10), "stone_light", bevel=.04)
    # Broad timber piers and slanted joinery make the base an inhabited craft
    # workshop rather than a metal power cabinet.
    for x in (-1.31, 1.31):
        for z in (-1.10, .91):
            m.box((.18, 1.24, .18), (x, 1.02, z), "wood", bevel=.025)
            m.box((.23, .13, .23), (x, 1.47, z), "gold_dark", bevel=.022)
        m.beam((x, 1.05, 1.00), (x-math.copysign(.37, x), 1.55, 1.00), .13, "wood_light")
    arch.royal_gate(m, 0, .29, 1.005, .81, 1.18)
    _steps(m, 1.0, 1.12)
    for side in (-1, 1):
        wall = env.Model()
        arch.wall_joints(wall, 1.78, (0, .43, 0), .96)
        arch.window(wall, 0, 1.04, .018, .43, .62)
        m.absorb(wall, (side*1.42, 0, -.13), side*math.pi/2)
    for x in (-1.01, -.53, 0, .53, 1.01):
        m.box((.44, .05, 2.40), (x, 1.86, -.10), "wood", bevel=.013)

    # Ceramic cores have stepped porcelain skirts beneath the actual helix.
    # Neither coil has a needle/spire silhouette: paired mushroom terminals
    # remain legible from the normal strategy-game camera.
    for x in (-.99, .99):
        m.cylinder(.53, .17, (x, 2.04, -.17), "gold_dark", sections=12)
        m.cylinder(.36, .21, (x, 2.20, -.17), "stone_light", sections=12)
        arch.turned(m, [(2.22, .19), (2.31, .28), (2.40, .21),
                       (3.64, .21), (3.73, .28), (3.82, .24),
                       (3.94, .24)], "stone_light", (x, 0, -.17), 12)
        for y in (2.34, 2.66, 3.00, 3.34, 3.68):
            m.cone(.29, .235, .105, (x, y, -.17), "plaster", sections=12)
        _helix(m, (x, 3.02, -.17))
        m.ring(.205, .29, .13, (x, 3.89, -.17), "gold_dark", sections=12)
        arch.turned(m, [(3.92, .12), (3.99, .31), (4.04, .43),
                       (4.14, .47), (4.25, .38), (4.32, .17),
                       (4.33, .0)], "gold", (x, 0, -.17), 16)
        m.ring(.43, .475, .045, (x, 4.12, -.17), "gold_light", sections=16)
        m.beam((x, 2.28, .20), (x*.40, 2.60, .25), .10, "gold_dark")
        m.beam((x*.40, 2.60, .25), (x*.26, 2.79, .25), .075, "gold")
        for z in (-.56, .23):
            _rivet(m, (x, 2.03, z))

    # A little exposed reliquary, held between the coils by two copper arms.
    m.cylinder(.42, .14, (0, 2.13, .33), "gold_dark", sections=8)
    m.cone(.36, .22, .35, (0, 2.35, .33), "gold", sections=8)
    _gem(m, (0, 2.98, .33), .40, 1.18)
    m.ring(.445, .485, .065, (0, 2.81, .33), "gold", sections=12)
    for x in (-.43, .43):
        m.beam((x, 2.79, .33), (x*.62, 2.35, .33), .064, "gold_light")
    # Small front plaque and the workshop's two folded tools are geometry.
    m.box((.58, .28, .075), (.93, 1.10, 1.055), "wood_dark", bevel=.04)
    for x0, x1 in ((.76, 1.05), (1.05, .76)):
        m.beam((x0, 1.03, 1.12), (x1, 1.19, 1.12), .044, "gold_light")
    return m


def _lantern_roof(m):
    """Four pitched tile faces and a pointed cap, with actual course gaps."""
    lower, upper = 4.17, 4.91
    radii = (1.21, .91, .55, .10)
    heights = (lower, 4.40, 4.66, upper)
    for side in range(4):
        angle = side*math.pi/2
        for row in range(3):
            radius0, radius1 = radii[row:row+2]
            y0, y1 = heights[row:row+2]
            number = (5, 4, 3)[row]
            for index in range(number):
                a = -1 + 2*index/number + .013
                b = -1 + 2*(index+1)/number - .013
                vertices = []
                for thickness in (0, .070):
                    vertices.extend(((a*radius0, y0+thickness, radius0),
                                     (b*radius0, y0+thickness, radius0),
                                     (b*radius1, y1+thickness, radius1),
                                     (a*radius1, y1+thickness, radius1)))
                mesh = tm.convex.convex_hull(np.asarray(vertices))
                m.add(mesh, "slate_light" if (index+row)%3 == 0 else "slate", rot=(0, angle, 0))
        # Fine gold corner seams emphasize the four-sided lantern silhouette.
        m.beam((math.sin(angle+math.pi/4)*1.64, 4.22,
                math.cos(angle+math.pi/4)*1.64),
               (math.sin(angle+math.pi/4)*.15, 4.97,
                math.cos(angle+math.pi/4)*.15), .048, "gold")
    m.box((2.43, .13, 2.43), (0, 4.13, 0), "wood_dark", bevel=.055)
    m.box((2.48, .065, 2.48), (0, 4.18, 0), "gold_dark", bevel=.03)
    m.cone(.16, .07, .15, (0, 5.02, 0), "gold", sections=8)
    m.add(tm.creation.icosphere(subdivisions=1, radius=.085), "gold_light", (0, 5.105, 0))


def build_lantern() -> env.Model:
    """D: a high rune lamp with four timber supports and one tiled lantern."""
    m = env.Model()
    m.box((2.43, .24, 2.35), (0, .12, 0), "mortar", bevel=.08)
    m.box((2.21, .17, 2.16), (0, .30, 0), "stone_light", bevel=.075)
    # The high masonry pedestal is deliberately narrower than the lamp room.
    m.add(tm.convex.convex_hull(np.asarray([
        (x*r, y, z*r) for y, r in ((.37, .89), (2.67, .72))
        for x, z in ((-1,-1), (1,-1), (1,1), (-1,1))
    ])), "stone")
    for y, r in ((.49, .93), (1.56, .83), (2.53, .78)):
        m.box((r*2, .12, r*2), (0, y, 0), "stone_light", bevel=.033)
    arch.royal_gate(m, 0, .31, .886, .72, 1.25)
    _steps(m, .92, 1.08)
    for angle in (math.pi/2, math.pi, math.pi*1.5):
        side = env.Model()
        arch.wall_joints(side, 1.22, (0, .58, 0), 1.67)
        arch.window(side, 0, 1.81, .013, .30, .62)
        m.absorb(side, (math.sin(angle)*.785, 0, math.cos(angle)*.785), angle)
    # Four visibly grounded posts extend into the frame.  Their paired braces
    # carry the broad lantern floor; copper collars read as joinery, not wires.
    for x in (-.95, .95):
        for z in (-.95, .95):
            m.box((.37, .31, .37), (x, .31, z), "stone_light", bevel=.045)
            m.box((.17, 2.60, .17), (x, 1.72, z), "wood", bevel=.026)
            for y in (.61, 1.48, 2.37, 2.80):
                m.box((.21, .11, .21), (x, y, z), "gold_dark", bevel=.018)
            m.beam((x, 2.12, z), (x*.67, 2.77, z), .14, "wood_light")
            m.beam((x, 2.12, z), (x, 2.77, z*.67), .14, "wood_light")
    m.box((2.29, .18, 2.29), (0, 2.76, 0), "wood_dark", bevel=.08)
    m.box((2.36, .10, 2.36), (0, 2.86, 0), "gold", bevel=.045)
    m.box((2.04, .12, 2.04), (0, 2.96, 0), "stone_light", bevel=.04)

    # Four open faces reveal one luminous cut-stone heart.  No opaque glass
    # planes obscure the core at the three-quarter gameplay camera angle.
    for x in (-.92, .92):
        for z in (-.92, .92):
            m.box((.13, 1.14, .13), (x, 3.55, z), "gold", bevel=.02)
            m.box((.22, .12, .22), (x, 3.02, z), "gold_light", bevel=.025)
            m.box((.20, .13, .20), (x, 4.065, z), "gold_light", bevel=.022)
    for y in (3.09, 3.93):
        for side in range(4):
            frame = env.Model()
            frame.box((1.86, .070, .08), (0, y, .925), "gold_light", bevel=.016)
            m.absorb(frame, rot=side*math.pi/2)
    m.cone(.54, .35, .20, (0, 3.10, 0), "gold_dark", sections=8)
    _gem(m, (0, 3.56, 0), .64, 1.20)
    m.cone(.28, .45, .12, (0, 4.08, 0), "gold", sections=8)

    # Each face has a small hollow diamond rune, leaving most of the core
    # visible.  These are thin inlaid bars, not a second glowing lamp.
    for side in range(4):
        glyph = env.Model()
        points = ((0,3.80,.948), (.23,3.57,.948), (0,3.34,.948), (-.23,3.57,.948))
        for start, end in zip(points, points[1:]+points[:1]):
            glyph.beam(start, end, .042, "gold_light")
        m.absorb(glyph, rot=side*math.pi/2)
    _lantern_roof(m)
    return m
