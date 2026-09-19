"""Opt-in monster study: a plain, unarmed zombie with saved rigid animations."""
import math

from build_units import P, OUT, Sculpture, anim_resource, vec


def build_zombie():
    P.update({
        "zombie_skin": (127, 157, 104),
        "zombie_shade": (108, 135, 88),
        "zombie_coat": (87, 99, 91),
        "zombie_coat_edge": (104, 114, 101),
        "zombie_pants": (94, 80, 67),
    })
    s = Sculpture("zombie")
    body = s.joint("Body", (0, 1.07, 0))
    head = s.joint("Head", (0, 1.71, -.035))
    s.b(body, (.54, .61, .37), (0, .045, 0), "zombie_coat", bevel=.037)
    # The trouser seat overlaps both thigh roots through the walking cycle.
    s.b(body, (.44, .16, .28), (0, -.26, 0), "zombie_pants", bevel=.020)
    s.b(body, (.24, .20, .23), (0, .38, -.02), "zombie_skin", bevel=.020)
    # Large stepped hems read as worn cloth; no tiny shreds or painted wounds.
    s.b(body, (.19, .13, .035), (-.15, -.278, -.17), "zombie_coat", bevel=.009)
    s.b(body, (.15, .09, .035), (.17, -.26, .17), "zombie_coat", bevel=.008)
    s.b(body, (.032, .45, .022), (.08, .055, -.183), "zombie_coat_edge", bevel=.003)
    s.b(body, (.15, .12, .025), (-.125, -.12, .185), "zombie_coat_edge", bevel=.007)

    # Flat facial features embed into the flat front face, instead of floating
    # in front of a faceted sphere. A small bevel retains the game's lighting.
    s.b(head, (.55, .59, .50), (0, .025, 0), "zombie_skin", bevel=.035)
    for sign in (-1, 1):
        s.b(head, (.074, .066, .012), (sign * .115, .05, -.253), "black", bevel=.003)
        s.b(head, (.072, .12, .085), (sign * .28, -.025, .02), "zombie_skin", bevel=.014)
    s.b(head, (.105, .026, .012), (.009, -.119, -.253), "zombie_shade", bevel=.002)
    s.b(head, (.064, .061, .045), (0, -.035, -.259), "zombie_skin", bevel=.009)

    for side, sign in (("Left", -1), ("Right", 1)):
        arm = s.joint("Arm" + side, (sign * .365, 1.355, 0))
        s.b(arm, (.225, .28, .225), (0, -.10, 0), "zombie_coat", bevel=.027)
        s.b(arm, (.175, .13, .175), (0, -.23, 0), "zombie_skin", bevel=.021)
        if side == "Left":
            # One narrow cloth band is the only team-colored surface.
            s.b(arm, (.239, .075, .239), (0, -.135, 0), "blue", bevel=.014)
        fore = s.joint("Forearm" + side, (0, -.275, 0), arm)
        s.b(fore, (.153, .245, .164), (0, -.095, 0), "zombie_skin", bevel=.020)
        s.b(fore, (.19, .17, .19), (0, -.266, -.012), "zombie_skin", bevel=.025)
        # A thumb and two shallow knuckle divisions keep the hands readable.
        s.b(fore, (.065, .105, .09), (-sign * .103, -.225, -.032), "zombie_skin", bevel=.018)
        for x in (-.028, .029):
            s.b(fore, (.008, .045, .010), (x, -.298, -.107), "zombie_shade", bevel=.001)
    for side, x in (("Left", -.16), ("Right", .16)):
        leg = s.joint("Leg" + side, (x, .74, 0))
        s.b(leg, (.202, .37, .215), (0, -.16, 0), "zombie_pants", bevel=.024)
        s.b(leg, (.076, .095, .023), (-.058, -.362, -.092), "zombie_pants", bevel=.006)
        s.b(leg, (.151, .30, .164), (0, -.444, .005), "zombie_skin", bevel=.021)
        s.b(leg, (.227, .16, .335), (0, -.65, -.061), "zombie_skin", bevel=.023)
        step = s.pivot("Step" + side, (x, .74, 0))
        s.reparent(leg, step)
    waist = s.pivot("Waist", (0, 1.07, 0))
    for part in (body, head, "ArmLeft", "ArmRight"):
        s.reparent(part, waist)
    return s


def resting_pose():
    return {"Waist": (.095, 0, -.025), "Head": (-.025, 0, .025),
            "ArmLeft": (.86, -.045, -.055), "ArmRight": (.72, .055, .07),
            "ForearmLeft": (.25, 0, 0), "ForearmRight": (.31, 0, 0)}


def zombie_clips(s):
    path = lambda part, prop: s.part_path(part) + ":" + prop
    rest = resting_pose()
    idle, walk, strike = [], [], []
    for part, pose in rest.items():
        idle.append((path(part, "rotation"), [pose, pose]))
    idle += [("Rig:position", [(0, 0, 0), (0, .009, 0), (0, 0, 0)]),
             (path("Waist", "position"), [s.joints["Waist"]] * 2)]
    for side in ("Left", "Right"):
        idle.append((path("Leg" + side, "rotation"), [(0, 0, 0)] * 2))
        idle.append((path("Step" + side, "position"), [s.joints["Step" + side]] * 2))

    # A planted foot travels backward; the lifted foot returns forward (-Z).
    # Correct each rigid leg's support height from its actual exported vertices.
    cycle = 1.08
    times = [cycle * i / 24 for i in range(25)]
    for side, phase in (("Left", 0), ("Right", .5)):
        part = "Leg" + side
        pieces = [mesh for category in s.parts[part].values() for mesh in category]
        vertices = [vertex for mesh in pieces for vertex in mesh.vertices]
        rotations, positions = [], []
        for i in range(25):
            u = (i / 24 + phase) % 1
            if u < .62:
                angle = .27 - .54 * u / .62
                lift = 0
            else:
                swing = (u - .62) / .38
                angle = -.27 + .54 * swing
                lift = .075 * math.sin(math.pi * swing)
            lowest = min(v[1] * math.cos(angle) - v[2] * math.sin(angle) for v in vertices)
            rotations.append((angle, 0, 0))
            positions.append((s.joints["Step" + side][0], .01 - lowest + lift, 0))
        walk += [(path(part, "rotation"), rotations, times),
                 (path("Step" + side, "position"), positions, times)]
    for part, pose in rest.items():
        amplitude = .055 if part.startswith("Arm") else .025 if part == "Waist" else .013
        walk.append((path(part, "rotation"),
                     [(pose[0] + amplitude * math.sin(i * math.tau / 24), pose[1], pose[2]) for i in range(25)], times))
    walk.append(("Rig:position", [(0, 0, 0)] * 2))
    walk.append((path("Waist", "position"), [s.joints["Waist"]] * 2))

    # A short, heavy open-hand shove. Contact is at 0.30s; no weapon or projectile.
    times = [0, .14, .23, .30, .39, .58, .82]
    poses = {
        "Waist": [rest["Waist"], (.07, -.06, -.025), (.06, -.11, -.025),
                  (.16, .09, -.025), (.17, .11, -.025), (.12, .03, -.025), rest["Waist"]],
        "Head": [rest["Head"], (-.02, .05, .025), (-.02, .08, .025),
                 (-.045, -.03, .025), (-.045, -.03, .025), rest["Head"], rest["Head"]],
        "ArmRight": [rest["ArmRight"], (.39, .1, .15), (.52, .1, .17),
                     (1.49, -.1, .055), (1.55, -.1, .04), (1.01, .03, .06), rest["ArmRight"]],
        "ForearmRight": [rest["ForearmRight"], (.62, 0, 0), (.75, 0, 0),
                         (.08, 0, 0), (.045, 0, 0), (.20, 0, 0), rest["ForearmRight"]],
        "ArmLeft": [rest["ArmLeft"]] * 7,
        "ForearmLeft": [rest["ForearmLeft"]] * 7,
    }
    for part, values in poses.items():
        strike.append((path(part, "rotation"), values, times))
    strike.append((path("Waist", "position"),
                   [(0, 1.07, 0), (0, 1.07, .025), (0, 1.07, .035),
                    (0, 1.045, -.10), (0, 1.04, -.12), (0, 1.06, -.04), (0, 1.07, 0)], times))
    return idle, walk, strike


def write_zombie_scene(s):
    parts = list(s.parts)
    idle, walk, strike = zombie_clips(s)
    lines = ['[gd_scene format=3]',
             '[ext_resource type="Script" path="res://scripts/unit_visual.gd" id="script"]']
    for part in parts:
        lines.append(f'[ext_resource type="ArrayMesh" path="res://assets/models/units/zombie/{part}.res" id="{part}"]')
    lines += [anim_resource("idle", 2.8, idle, True), anim_resource("walk", 1.08, walk, True),
              anim_resource("strike", .82, strike),
              '[sub_resource type="AnimationLibrary" id="locomotion"]\n_data = {&"idle": SubResource("Animation_idle"), &"walk": SubResource("Animation_walk")}',
              '[sub_resource type="AnimationLibrary" id="attack"]\n_data = {&"strike": SubResource("Animation_strike")}',
              '[node name="Zombie" type="Node3D"]\nscript = ExtResource("script")\nkind = "zombie"\nprojectile_socket = NodePath("Rig/Action/Waist/ArmRight/ForearmRight/HandContact")\nmetadata/faction = &"monsters"\nmetadata/prototype = true',
              '[node name="Rig" type="Node3D" parent="."]',
              '[node name="Action" type="Node3D" parent="Rig"]']
    emitted = set()
    rest = resting_pose()

    def emit(part):
        if part in emitted:
            return
        parent_part = s.parents[part]
        if parent_part:
            emit(parent_part)
        parent = s.part_path(parent_part) if parent_part else "Rig/Action"
        kind = "Node3D" if part in s.pivots else "MeshInstance3D"
        properties = f'position = {vec(s.joints[part])}'
        if part in rest:
            properties += f'\nrotation = {vec(rest[part])}'
        if part in s.parts:
            properties += f'\nmesh = ExtResource("{part}")'
        lines.append(f'[node name="{part}" type="{kind}" parent="{parent}"]\n{properties}')
        emitted.add(part)

    for part in parts:
        emit(part)
    lines += [f'[node name="HandContact" type="Marker3D" parent="{s.part_path("ForearmRight")}"]\nposition = Vector3(0, -0.345, -0.012)',
              '[node name="Locomotion" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("locomotion")}\nautoplay = "idle"',
              '[node name="Attack" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("attack")}',
              '[node name="VisibilityNotifier" type="VisibleOnScreenNotifier3D" parent="."]\naabb = AABB(-0.8, -0.05, -1.1, 1.6, 2.3, 1.7)',
              '[connection signal="screen_entered" from="VisibilityNotifier" to="." method="_on_screen_entered"]',
              '[connection signal="screen_exited" from="VisibilityNotifier" to="." method="_on_screen_exited"]']
    (OUT / "zombie.tscn").write_text("\n\n".join(lines) + "\n", encoding="utf-8")
