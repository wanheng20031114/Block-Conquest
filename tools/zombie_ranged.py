"""Three equipped zombie studies, with saved, hand-fitted ranged attack clips.

Weapons remain separate rigid parts. All two-hand poses and bow-string lengths
are solved offline; the exported scene only plays native animation tracks.
"""
import math

import numpy as np
import trimesh as tm

from build_units import godot_euler, godot_rotation, lathe, polygon
from unit_zombie import cut_block, surface_line
from zombie_variant_common import base_variant


PALM = np.array((0, -.265, -.008))


def _arm_pose(s, side, target):
    """Exact two-bone solve for this zombie's existing elbow and palm pivots."""
    sign = -1 if side == "Left" else 1
    shoulder = np.asarray(s.joints["Arm" + side])
    upper = np.asarray(s.joints["Forearm" + side])
    direction = np.asarray(target) - shoulder
    distance = np.linalg.norm(direction)
    a, b = np.linalg.norm(upper), np.linalg.norm(PALM)
    assert abs(a - b) + .002 < distance < a + b - .002, (s.name, side, target, distance)
    direction /= distance
    along = (a * a - b * b + distance * distance) / (2 * distance)
    pole = np.array((sign * .75, -.50, .30))
    pole -= direction * np.dot(pole, direction)
    pole /= np.linalg.norm(pole)
    elbow = direction * along + pole * math.sqrt(a * a - along * along)
    basis = tm.geometry.align_vectors(upper, elbow)[:3, :3]
    lower = basis.T @ (direction * distance - elbow)
    fore = tm.geometry.align_vectors(PALM, lower)[:3, :3]
    return godot_euler(basis), godot_euler(fore)


def _hands(s, weapon, anchor, rotation, left, right):
    result = {s.part_path(weapon) + ":position": tuple(anchor),
              s.part_path(weapon) + ":rotation": tuple(rotation)}
    basis = godot_rotation(rotation)
    for side, grip in (("Left", left), ("Right", right)):
        upper, fore = _arm_pose(s, side, np.asarray(anchor) + basis @ np.asarray(grip))
        result[s.part_path("Arm" + side) + ":rotation"] = upper
        result[s.part_path("Forearm" + side) + ":rotation"] = fore
    return result


def _string_pose(s, part, endpoint):
    direction = np.asarray(endpoint) - np.asarray(s.joints[part])
    basis = tm.geometry.align_vectors((0, 1, 0), direction)[:3, :3]
    return {s.part_path(part) + ":rotation": godot_euler(basis),
            s.part_path(part) + ":scale": (1, float(np.linalg.norm(direction)), 1)}


def _save_pose(s, duration, callback, key_times):
    times = sorted(set([round(i * .02, 4) for i in range(round(duration / .02) + 1)] + key_times))
    poses = [callback(t) for t in times]
    rest = callback(0)
    s.monster_properties = {}
    for path, value in rest.items():
        part_path, prop = path.rsplit(":", 1)
        part = part_path.rsplit("/", 1)[-1]
        if prop == "rotation":
            s.monster_rest[part] = value
        else:
            s.monster_properties[path] = value
        s.monster_tracks.append((path, [pose[path] for pose in poses], times))
    s.monster_attack_length = duration
    # Authoring guard: every shot ends at exactly the saved carrying pose.
    for path, value in rest.items():
        assert np.allclose(value, poses[-1][path]), (s.name, path, value, poses[-1][path])
    return s


def _interp(time, times, values):
    values = np.asarray(values)
    if values.ndim == 1:
        return float(np.interp(time, times, values))
    return np.array([np.interp(time, times, values[:, i]) for i in range(values.shape[1])])


def _strap(s, back=False, width=.055, color="leather"):
    coat = s.parts["Body"]["PaintedMatte"][0]
    points = [(-.175, .255), (-.105, .095), (.01, -.04), (.165, -.235)]
    if back:
        points = [(-x, y) for x, y in points]
    surface_line(s, "Body", coat, points, width, color, offset=.013, side=1 if back else -1)


def _arrow(s, part, length=.77, feather=.15):
    s.r(part, (0, 0, 0), (0, 0, -length), .010, "woodlight", 6)
    s.r(part, (0, 0, -length + .025), (0, 0, -length - .080), .031, "darksteel", 4, r2=0)
    for sign in (-1, 1):
        s.b(part, (.048, .009, feather), (sign * .025, 0, -.07), "zombie_lining", bevel=.002)


def build_zombie_archer():
    s = base_variant("zombie_archer")
    # A conspicuously tall patched quiver, carried on a fitted diagonal strap.
    _strap(s)
    _strap(s, True)
    quiver = cut_block([(-.27, .080, .067, .008), (.23, .105, .077, .010)])
    quiver.apply_translation((.12, .10, .255))
    s.add("Body", quiver, "leather")
    s.b("Body", (.223, .043, .168), (.12, .345, .255), "wooddark", bevel=.008)
    s.b("Body", (.080, .135, .018), (.145, .02, .342), "zombie_patch", bevel=.003)
    for x, y in ((.102, .048), (.165, -.008)):
        s.b("Body", (.009, .030, .012), (x, y, .353), "zombie_thread", bevel=0)
    for x, y, z in ((.056, .61, .236), (.116, .66, .267), (.183, .58, .254)):
        s.r("Body", (x, .25, z), (x + .024, y, z + .014), .010, "woodlight", 6)
        s.b("Body", (.062, .095, .008), (x + .021, y - .045, z + .014), "zombie_lining", bevel=.003)
    # A dark guard wraps the left forearm, away from the sole blue upper-arm band.
    bracer = cut_block([(-.182, .082, .086, .014), (-.060, .077, .088, .013)], caps=False)
    s.add("ForearmLeft", bracer, "leather")
    bow = s.joint("Bow", (-.08, .20, -.36), "Waist")
    points = [(0, -.51, .045), (0, -.37, -.055), (0, -.20, -.072),
              (0, 0, 0), (0, .20, -.072), (0, .37, -.055), (0, .51, .045)]
    for index, (a, b) in enumerate(zip(points, points[1:])):
        s.r(bow, a, b, .031 if index in (2, 3) else .024, "wood", 6)
    s.r(bow, (0, -.085, 0), (0, .085, 0), .039, "leatherlight", 8)
    for y in (-.057, -.019, .019, .057):
        s.b(bow, (.081, .012, .071), (0, y, 0), "zombie_thread", bevel=.003)
    for suffix, at in (("Top", points[-1]), ("Bottom", points[0])):
        part = s.joint("BowString" + suffix, at, bow)
        s.r(part, (0, 0, 0), (0, 1, 0), .006, "rope", 5)
    arrow = s.joint("Arrow", (0, .025, .22), bow)
    _arrow(s, arrow)
    times = [0, .20, .44, .45, .50, .73, 1.03, 1.37, 1.8]
    # Drawing, release, fetching from the quiver, seating and returning to guard.
    def pose(t):
        draw = _interp(t, times, [.22, .30, .32, .045, .045, .06, .06, .22, .22])
        rotation = (_interp(t, times, [-.10, .02, .02, .025, -.08, -.18, -.18, -.10, -.10]), 0, -.08)
        anchor = np.array((-.08, .20, -.36))
        # Release lets the string snap away; the hand stays behind the bow.
        right = np.array((0, .025, max(draw, .18)))
        # The nock hand first relaxes behind the string, then visibly draws again.
        right[1] += _interp(t, times, [0, 0, 0, 0, -.06, -.11, -.08, 0, 0])
        result = _hands(s, bow, anchor, rotation, (0, -.010, .005), right)
        for part in ("BowStringTop", "BowStringBottom"):
            result.update(_string_pose(s, part, (0, .025, draw)))
        result[s.part_path(arrow) + ":position"] = (0, .025, draw)
        result[s.part_path(arrow) + ":visible"] = not (.45 <= t < 1.03)
        return result
    s.monster_socket = (bow, (0, .025, -.58))
    return _save_pose(s, 1.8, pose, times)


def build_zombie_musketeer():
    s = base_variant("zombie_musketeer")
    # Low battered soldier cap and a powder bandolier, both deliberately neutral.
    cap = cut_block([(.210, .248, .216, .031), (.285, .225, .204, .035),
                     (.363, .145, .152, .025)])
    # Follow the base head's slight sideways shear instead of clipping its rim.
    cap.vertices[:, 0] += (cap.vertices[:, 1] + .245) * .045
    s.add("Head", cap, "zombie_coat_dark")
    s.b("Head", (.400, .028, .14), (0, .213, -.201), "leather", bevel=.010)
    _strap(s, width=.069, color="leatherlight")
    _strap(s, True)
    for x, y in ((-.136, .179), (-.077, .082), (.005, -.022), (.099, -.131)):
        s.r("Body", (x, y, -.222), (x + .008, y - .079, -.224), .023, "wood", 6)
        s.r("Body", (x, y + .006, -.223), (x, y - .014, -.223), .026, "darksteel", 6)
    s.b("Body", (.21, .25, .145), (.259, -.205, .026), "leather", bevel=.018)
    s.b("Body", (.222, .065, .163), (.258, -.091, .017), "leatherlight", bevel=.009)
    s.b("Body", (.032, .072, .019), (.268, -.128, -.067), "steel", bevel=.004)
    gun = s.joint("Musket", (.20, .24, -.23), "Waist")
    s.b(gun, (.112, .096, .69), (0, -.010, -.16), "wood", bevel=.016)
    stock = polygon([(-.01, .019), (.30, -.010), (.34, -.145), (.28, -.186), (.034, -.10)],
                    .122, rot=(0, -math.pi / 2, 0))
    # Cast-off at the wrist seats the butt against the outer right shoulder,
    # rather than driving a straight stock through the centre of the chest.
    stock.vertices[:, 0] += np.clip(stock.vertices[:, 2] / .15, 0, 1) * .15
    s.add(gun, stock, "wooddark")
    # A real recessed bore and narrow iron binding rings, never a solid end cap.
    s.add(gun, lathe([(-.79, .043), (-.70, .045), (.10, .058)], 10,
                     pos=(0, .070, 0), rot=(math.pi / 2, 0, 0), caps=False), "darksteel")
    s.add(gun, lathe([(-.792, .044), (-.792, .027), (-.71, .027)], 10,
                     pos=(0, .070, 0), rot=(math.pi / 2, 0, 0), caps=False), "steel")
    s.r(gun, (0, .070, -.709), (0, .070, -.704), .028, "black", 10)
    for z in (-.54, -.22, .065):
        s.r(gun, (0, .070, z - .013), (0, .070, z + .013), .061, "steel", 10)
    s.b(gun, (.125, .12, .025), (.15, -.077, .310), "darksteel", bevel=.007)
    s.b(gun, (.07, .052, .095), (.055, .03, .025), "steel", bevel=.008)
    s.r(gun, (0, -.06, .04), (0, -.14, .05), .011, "darksteel", 6)
    s.r(gun, (0, -.14, .05), (0, -.14, .14), .011, "darksteel", 6)
    s.r(gun, (0, -.14, .14), (0, -.07, .14), .011, "darksteel", 6)
    hammer = s.joint("Hammer", (.074, .071, .077), gun)
    s.r(hammer, (0, 0, 0), (0, .075, -.020), .016, "steel", 6)
    s.b(hammer, (.033, .032, .051), (0, .075, -.037), "black", bevel=.005)
    rod = s.joint("Ramrod", (.0, .07, -.84), gun)
    s.r(rod, (0, 0, 0), (0, 0, .40), .008, "steel", 6)
    s.r(rod, (0, 0, -.012), (0, 0, .025), .015, "woodlight", 6)
    times = [0, .35, .64, .65, .73, .98, 1.23, 1.65, 1.92, 2.16, 2.43, 2.76, 3.0]
    anchors = [( .20, .24, -.23), (.20, .33, -.23), (.20, .33, -.23),
               (.20, .33, -.23), (.20, .33, -.17), (.11, .15, -.23),
               (.08, -.30, -.14), (.08, -.30, -.14), (.08, -.30, -.14),
               (.08, -.30, -.14), (.08, -.30, -.14), (.12, .18, -.23), (.20, .24, -.23)]
    pitches = [-.16, 0, 0, -.01, .075, .40, 1.35, 1.35, 1.35, 1.35, 1.35, .32, -.16]
    def pose(t):
        anchor = _interp(t, times, anchors)
        rotation = (_interp(t, times, pitches), 0, 0)
        right = np.array((.115, -.10, .115))
        # On reload the right hand approaches the raised muzzle and pumps the rod.
        reload = _interp(t, times, [0, 0, 0, 0, 0, 0, .80, 1, 1, 1, .65, 0, 0])
        load_z = _interp(t, times, [-.86] * 7 + [-.93, -.82, -.93, -.86, -.86, -.86])
        support = (rotation[0] + .16) / 1.51
        # Lift the butt inward while rotating it down for muzzle loading.
        arc = math.sin(support * math.pi)
        anchor += np.array((0, .025 * arc, .067 * arc))
        left = (1 - support) * np.array((-.125, -.075, -.020)) + support * np.array((-.070, -.025, -.40))
        right = (1 - reload) * right + reload * np.array((.045, .07, load_z))
        result = _hands(s, gun, anchor, rotation, left, right)
        result[s.part_path(hammer) + ":rotation"] = (_interp(t, times, [-.65, -.65, -.65, .20, .20, .20, .20, .20, -.65, -.65, -.65, -.65, -.65]), 0, 0)
        result[s.part_path(rod) + ":visible"] = 1.23 <= t < 2.43
        result[s.part_path(rod) + ":position"] = (0, .07, load_z - .03)
        return result
    s.monster_socket = (gun, (0, .07, -.794))
    return _save_pose(s, 3.0, pose, times)


def build_zombie_crossbowman():
    s = base_variant("zombie_crossbowman")
    # Short leather apron and a hip bolt box separate it from the archer's kit.
    s.add("Body", polygon([(-.20, .13), (.19, .13), (.17, -.32), (.06, -.38),
                           (-.18, -.34)], .035, pos=(0, 0, -.188)), "leather")
    s.b("Body", (.452, .062, .040), (0, .115, -.205), "leatherlight", bevel=.006)
    for x in (-.142, .139):
        s.b("Body", (.031, .047, .018), (x, .119, -.235), "steel", bevel=.004)
    s.b("Body", (.172, .27, .16), (.278, -.208, .07), "wooddark", bevel=.013)
    s.b("Body", (.181, .033, .171), (.278, -.069, .07), "leatherlight", bevel=.006)
    for x, z in ((.244, .03), (.297, .081), (.263, .119)):
        s.r("Body", (x, -.10, z), (x, .078, z), .011, "woodlight", 6)
        s.b("Body", (.056, .057, .009), (x, .050, z), "zombie_lining", bevel=.002)
    # A single repaired leather shoulder cape, not armor over the face.
    s.b("ArmRight", (.249, .050, .255), (.007, .055, .008), "leather", rot=(0, 0, -.12), bevel=.010)
    bow = s.joint("Crossbow", (0, .20, -.30), "Waist")
    s.b(bow, (.116, .091, .56), (0, 0, -.10), "wood", bevel=.012)
    s.b(bow, (.144, .105, .18), (0, -.020, .142), "wooddark", bevel=.018)
    s.b(bow, (.08, .145, .065), (0, -.093, .095), "wooddark", rot=(.12, 0, 0), bevel=.009)
    for x in (-.037, .037):
        s.b(bow, (.012, .020, .405), (x, .052, -.13), "woodlight", bevel=.002)
    s.b(bow, (.134, .029, .092), (0, .055, .066), "darksteel", bevel=.006)
    for sign in (-1, 1):
        points = [(0, .019, -.29), (sign * .17, .025, -.34),
                  (sign * .30, .027, -.34), (sign * .38, .03, -.285)]
        for a, b in zip(points, points[1:]):
            s.r(bow, a, b, .028, "darksteel", 6)
        s.b(bow, (.045, .103, .114), (sign * .067, .018, -.294), "leatherlight", bevel=.006)
        part = s.joint("CrossbowString" + ("Left" if sign < 0 else "Right"), points[-1], bow)
        s.r(part, (0, 0, 0), (0, 1, 0), .006, "rope", 5)
    for a, b in [((-.058, -.01, -.33), (-.066, -.03, -.44)),
                 ((.058, -.01, -.33), (.066, -.03, -.44)),
                 ((-.066, -.03, -.44), (.066, -.03, -.44))]:
        s.r(bow, a, b, .012, "steel", 6)
    bolt = s.joint("Bolt", (0, .069, .048), bow)
    _arrow(s, bolt, .46, .085)
    times = [0, .20, .34, .35, .42, .61, .81, 1.02, 1.20, 1.39, 1.6]
    def pose(t):
        draw = _interp(t, times, [.048, .048, .048, -.285, -.285, -.285, -.17, .048, .048, .048, .048])
        rotation = (_interp(t, times, [-.12, 0, 0, -.01, .03, -.30, -.30, -.30, -.20, -.12, -.12]), 0, 0)
        pull = _interp(t, times, [0, 0, 0, 0, 0, 1, 1, 1, .75, 0, 0])
        anchor = (0, .20, -.30 + .20 * pull)
        right = (1 - pull) * np.array((.03, -.085, .10)) + pull * np.array((.025, .064, draw + .055))
        result = _hands(s, bow, anchor, rotation, (-.065, -.055, -.045), right)
        for part in ("CrossbowStringLeft", "CrossbowStringRight"):
            result.update(_string_pose(s, part, (0, .047, draw)))
        result[s.part_path(bolt) + ":visible"] = not (.35 <= t < 1.20)
        return result
    s.monster_socket = (bow, (0, .069, -.493))
    return _save_pose(s, 1.6, pose, times)
