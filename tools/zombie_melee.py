"""Three tool-bearing monster sculpts, authored as independent rigid models.

Tools are attached at the same local point as the gripping palm. The attack
poses move that hierarchy, so the tool cannot separate from the hand.
"""
import math

import numpy as np
import trimesh as tm

from build_units import P, polygon
from unit_zombie import cut_block
from zombie_variant_common import base_variant


GRIP = (0, -.265, -.008)


def _colors():
    P.update({
        "zombie_apron": (125, 112, 83),
        "zombie_apron_dark": (93, 87, 66),
        "zombie_workleather": (101, 73, 48),
        "zombie_workleather_edge": (130, 98, 61),
        "zombie_shouldercloth": (138, 122, 86),
        "zombie_handle": (113, 87, 53),
        "zombie_handle_worn": (147, 118, 76),
    })


def _belt(s):
    # The band follows the broad clipped sections of the tunic.
    belt = cut_block([(-.156, .241, .183, .023), (-.090, .245, .185, .024)], caps=False)
    s.add("Body", belt, "zombie_workleather")
    s.b("Body", (.085, .068, .022), (.038, -.120, -.192), "darksteel", bevel=.005)
    s.b("Body", (.048, .041, .010), (.038, -.120, -.207), "zombie_workleather", bevel=.003)
    for x in (-.148, -.100):
        s.b("Body", (.014, .012, .009), (x, -.121, -.187), "zombie_apron_dark", bevel=0)


def _pouch(s, x, y=-.235, z=.050):
    side = 1 if x > 0 else -1
    s.b("Body", (.15, .20, .17), (x, y, z), "zombie_workleather", bevel=.020)
    s.b("Body", (.17, .073, .185), (x, y + .064, z -.003), "zombie_workleather_edge", bevel=.009)
    s.b("Body", (.022, .072, .016), (x, y + .021, z -.096), "zombie_apron_dark", bevel=.003)
    s.b("Body", (.034, .023, .016), (x, y + .004, z -.107), "darksteel", bevel=.003)
    s.b("Body", (.035, .135, .045), (x - side * .038, y + .12, z), "zombie_workleather", bevel=.004)


def _tool(s, name, top, bottom=-.26, radius=.029):
    tool = s.joint(name, GRIP, "ForearmRight")
    s.r(tool, (0, bottom, 0), (0, top, 0), radius, "zombie_handle", sections=8)
    s.r(tool, (0, -.088, 0), (0, .084, 0), radius + .006, "zombie_workleather", sections=8)
    for y in (-.078, .071):
        s.r(tool, (0, y, 0), (0, y + .012, 0), radius + .010,
            "zombie_handle_worn", sections=8)
    return tool


def _attack(s, tool, rest, poses, times, wrist, waist, length):
    s.monster_rest.update(rest)
    s.monster_rest[tool] = wrist[0]
    s.monster_attack_length = length
    for part, values in poses.items():
        assert values[0] == rest[part] and values[-1] == rest[part]
        s.monster_tracks.append((s.part_path(part) + ":rotation", values, times))
    s.monster_tracks.append((s.part_path(tool) + ":rotation", wrist, times))
    s.monster_tracks.append((s.part_path("Waist") + ":position", waist, times))


def build_zombie_pitchfork():
    s = base_variant("zombie_pitchfork")
    _colors()
    # An angular hanging apron sits over the shirt; its two side seams and
    # uneven bottom form a farmer's working silhouette without extra jewelry.
    apron = polygon([(-.173, .205), (.155, .205), (.191, -.334),
                     (.074, -.361), (-.005, -.336), (-.180, -.360)],
                    .025, pos=(0, 0, -.199))
    s.add("Body", apron, "zombie_apron")
    for x in (-.126, .111):
        s.b("Body", (.025, .111, .021), (x, .240, -.183),
            "zombie_workleather", rot=(.25, 0, 0), bevel=.003)
        s.b("Body", (.014, .017, .014), (x, .201, -.219), "darksteel", bevel=.002)
    s.b("Body", (.13, .105, .020), (.060, -.028, -.217), "zombie_apron_dark", bevel=.005)
    s.b("Body", (.138, .014, .013), (.060, .024, -.231), "zombie_thread", bevel=.002)
    for x in (-.146, .144):
        for y in (-.14, -.21, -.28):
            s.b("Body", (.014, .028, .012), (x, y, -.218), "zombie_thread", bevel=.002)
    s.b("Body", (.07, .03, .013), (-.071, -.247, -.219), "zombie_apron_dark", rot=(0, 0, -.18), bevel=.003)
    _belt(s)
    s.b("Body", (.394, .060, .019), (0, -.121, -.225), "zombie_workleather", bevel=.004)
    s.b("Body", (.083, .063, .019), (.038, -.121, -.241), "darksteel", bevel=.004)
    s.b("Body", (.049, .039, .008), (.038, -.121, -.254), "zombie_workleather", bevel=.002)

    tool = _tool(s, "Pitchfork", .925, -.51, .029)
    s.r(tool, (0, .805, 0), (0, .947, 0), .045, "darksteel", sections=8)
    s.b(tool, (.360, .055, .064), (0, .930, 0), "darksteel", bevel=.008)
    for x in (-.158, 0, .158):
        s.r(tool, (x, .938, 0), (x, 1.228, -.020), .024, "steel", sections=6)
        s.r(tool, (x, 1.222, -.020), (x, 1.337, -.042), .024,
            "edge", sections=6, r2=.002)
    # Exposed timber has one long pale wear mark, away from the gripping hand.
    s.r(tool, (.020, .264, -.019), (.020, .674, -.019), .006,
        "zombie_handle_worn", sections=5)
    rest = {"Waist": (.095, 0, -.025), "Head": (-.025, 0, .025),
            "ArmRight": (.46, -.05, .22), "ForearmRight": (.40, 0, 0),
            "ArmLeft": (.34, -.10, -.12), "ForearmLeft": (.34, 0, 0)}
    times = [0, .20, .31, .40, .54, .80, 1.05]
    poses = {
        "ArmRight": [rest["ArmRight"], (.34, -.08, .25), (.51, -.07, .25),
                     (1.38, -.04, .14), (1.46, -.04, .14), (.86, -.05, .20), rest["ArmRight"]],
        "ForearmRight": [rest["ForearmRight"], (.61, 0, 0), (.60, 0, 0),
                         (.12, 0, 0), (.08, 0, 0), (.31, 0, 0), rest["ForearmRight"]],
        "Waist": [rest["Waist"], (.08, -.065, -.025), (.07, -.09, -.025),
                  (.15, .05, -.025), (.17, .06, -.025), (.12, .02, -.025), rest["Waist"]],
    }
    wrist = [(-.98, 0, -.11), (-1.20, 0, -.11), (-1.77, 0, -.09),
             (-3.05, 0, -.09), (-3.12, 0, -.09), (-1.89, 0, -.10), (-.98, 0, -.11)]
    waist = [(0, 1.07, 0), (0, 1.07, .025), (0, 1.07, .035),
             (0, 1.045, -.080), (0, 1.04, -.10), (0, 1.06, -.030), (0, 1.07, 0)]
    _attack(s, tool, rest, poses, times, wrist, waist, 1.05)
    s.monster_socket = (tool, (0, 1.337, -.042))
    return s


def _notched_axe_blade():
    outline = np.asarray([(.017, .534), (.275, .475), (.416, .503),
                          (.399, .650), (.349, .676), (.408, .707),
                          (.432, .900), (.278, .882), (.017, .788)])
    # A fan around an interior point preserves the small V notch; a convex hull
    # would silently fill it back in and lose the damaged cutting edge.
    center = np.asarray((.190, .689))
    points = np.vstack((outline, center))
    count, vertices, faces = len(points), [], []
    for z in (-.045, .045):
        vertices.extend((x, y, z) for x, y in points)
    for a in range(len(outline)):
        b = (a + 1) % len(outline)
        faces += [(count - 1, a, b), (2 * count - 1, b + count, a + count),
                  (a, a + count, b + count), (a, b + count, b)]
    mesh = tm.Trimesh(vertices=vertices, faces=faces, process=False)
    mesh.fix_normals()
    assert mesh.is_volume
    return mesh


def _heavy_swing(s, tool, contact_time, rest, top_contact):
    times = [0, contact_time * .38, contact_time * .78, contact_time,
             contact_time + .13, contact_time + .40, contact_time + .70]
    wrist_rest = (-1.18, 0, -.08)
    poses = {
        "ArmRight": [rest["ArmRight"], (1.78, -.09, -.12), (2.68, -.08, -.25),
                     (1.29, -.04, .22), (.96, -.01, .19), (.45, -.06, .31), rest["ArmRight"]],
        "ForearmRight": [rest["ForearmRight"], (-.55, 0, 0), (-1.25, 0, 0),
                         (.10, 0, 0), (.18, 0, 0), (.53, 0, 0), rest["ForearmRight"]],
        "Waist": [rest["Waist"], (.04, -.10, -.025), (.025, -.13, -.025),
                  (.19, .10, -.025), (.23, .12, -.025), (.14, .02, -.025), rest["Waist"]],
    }
    wrist = [wrist_rest, (-.98, 0, -.08), (-.83, 0, -.08),
             (-2.80, 0, -.08), (-3.17, 0, -.08), (-1.78, 0, -.08), wrist_rest]
    waist = [(0, 1.07, 0), (0, 1.08, .016), (0, 1.10, .027),
             (0, 1.040, -.045), (0, 1.025, -.061), (0, 1.060, -.020), (0, 1.07, 0)]
    _attack(s, tool, rest, poses, times, wrist, waist, times[-1])
    s.monster_socket = (tool, top_contact)


def build_zombie_axe():
    s = base_variant("zombie_axe")
    _colors()
    _belt(s)
    _pouch(s, -.277, -.245, .055)
    # A stitched shoulder cloth is merged into the sleeve so it follows the
    # shoulder rather than crossing the rotating upper-arm seam.
    shoulder = cut_block([(-.089, .121, .126, .018), (.044, .123, .131, .020),
                          (.094, .078, .093, .015)])
    s.add("ArmRight", shoulder, "zombie_shouldercloth")
    for x in (-.065, 0, .065):
        s.b("ArmRight", (.009, .032, .012), (x, -.060, -.129),
            "zombie_workleather", rot=(0, 0, -.14), bevel=.002)
    # Three dull front fastenings carry a narrow leather chest strap.
    s.b("Body", (.047, .33, .025), (.157, .099, -.181),
        "zombie_workleather", rot=(0, 0, -.16), bevel=.005)
    for y in (-.010, .095, .20):
        s.b("Body", (.042, .025, .012), (.157 + .16 * (y - .099), y, -.199),
            "zombie_workleather_edge", bevel=.002)

    tool = _tool(s, "WoodAxe", .810, -.278, .036)
    s.add(tool, _notched_axe_blade(), "darksteel")
    for z in (-.049, .049):
        s.add(tool, polygon([(.370, .515), (.413, .504), (.396, .645),
                             (.352, .670)], .007, pos=(0, 0, z)), "steel")
        s.add(tool, polygon([(.364, .714), (.405, .714), (.427, .891),
                             (.391, .884)], .007, pos=(0, 0, z)), "steel")
    s.b(tool, (.105, .184, .145), (-.010, .686, 0), "darksteel", bevel=.012)
    s.r(tool, (0, .555, 0), (0, .615, 0), .050, "zombie_workleather", sections=8)
    rest = {"Waist": (.095, 0, -.025), "Head": (-.025, 0, .025),
            "ArmRight": (.44, -.07, .28), "ForearmRight": (.53, 0, 0),
            "ArmLeft": (.30, -.07, -.16), "ForearmLeft": (.25, 0, 0)}
    _heavy_swing(s, tool, .50, rest, (.410, .710, 0))
    return s


def build_zombie_miner():
    s = base_variant("zombie_miner")
    _colors()
    _belt(s)
    _pouch(s, -.273, -.225, .085)
    # A worn leather working cap: low angular crown and a modest sewn peak.
    # Its shell covers the scalp and existing hair, rather than perching above.
    cap = cut_block([(.148, .282, .242, .043), (.232, .281, .238, .047),
                     (.385, .191, .178, .038)])
    cap.apply_translation((.016, 0, 0))
    s.add("Head", cap, "zombie_workleather")
    band = cut_block([(.147, .288, .247, .044), (.194, .290, .250, .045)], caps=False)
    band.apply_translation((.016, 0, 0))
    s.add("Head", band, "zombie_workleather_edge")
    s.add("Head", polygon([(-.274, -.03), (.274, -.03), (.248, -.132),
                            (-.239, -.153)], .028,
                           pos=(.016, .152, -.195), rot=(math.pi / 2, 0, 0)), "zombie_workleather")
    # A dull, riveted brow strip and crown seam remain deliberately non-luminous.
    s.b("Head", (.207, .029, .020), (.016, .174, -.259), "darksteel", bevel=.004)
    for x in (-.062, .094):
        s.b("Head", (.017, .014, .012), (x, .174, -.273), "steel", bevel=.002)
    s.b("Head", (.023, .025, .308), (.016, .382, .005), "zombie_workleather_edge", bevel=.006)
    # A compact blunt chisel tucked through the pouch loop, clear of the thigh.
    s.r("Body", (-.320, -.279, .090), (-.320, -.011, .090), .024, "darksteel", sections=6)
    s.b("Body", (.075, .035, .055), (-.320, .003, .090), "steel", bevel=.004)
    s.b("Body", (.046, .054, .027), (-.321, -.10, -.015), "zombie_workleather_edge", bevel=.004)

    tool = _tool(s, "Pickaxe", .850, -.295, .033)
    s.b(tool, (.134, .141, .113), (0, .750, 0), "darksteel", bevel=.010)
    # Two tapered, slightly drooping forged arms give a clear pick silhouette.
    for sign in (-1, 1):
        s.add(tool, polygon([(sign * .027, .811), (sign * .190, .788),
                             (sign * .328, .696), (sign * .387, .609),
                             (sign * .312, .652), (sign * .154, .699),
                             (sign * .028, .704)], .069), "darksteel")
        s.add(tool, polygon([(sign * .284, .698), (sign * .385, .611),
                             (sign * .313, .655)], .072), "steel")
    s.r(tool, (0, .594, 0), (0, .656, 0), .047, "zombie_workleather", sections=8)
    rest = {"Waist": (.095, 0, -.025), "Head": (-.025, 0, .025),
            "ArmRight": (.44, -.09, .36), "ForearmRight": (.53, 0, 0),
            "ArmLeft": (.34, -.07, -.14), "ForearmLeft": (.26, 0, 0)}
    _heavy_swing(s, tool, .55, rest, (.387, .609, 0))
    return s
