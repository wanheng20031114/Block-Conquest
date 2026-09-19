"""Opt-in monster study: a plain, unarmed zombie with saved rigid animations."""
import math
import numpy as np
import trimesh as tm

from build_units import P, OUT, Sculpture, anim_resource, vec, ellipsoid, lathe


def front_depth(surface, points):
    """Fit ink to the actual front-facing triangles, not an enclosing sphere."""
    triangles = surface.triangles
    a = triangles[:, 0]
    u, v = triangles[:, 1] - a, triangles[:, 2] - a
    determinant = u[:, 0] * v[:, 1] - u[:, 1] * v[:, 0]
    valid = abs(determinant) > 1e-10
    a, u, v, determinant = a[valid], u[valid], v[valid], determinant[valid]
    result = []
    for x, y in points:
        q = np.array((x, y)) - a[:, :2]
        b = (q[:, 0] * v[:, 1] - q[:, 1] * v[:, 0]) / determinant
        c = (u[:, 0] * q[:, 1] - u[:, 1] * q[:, 0]) / determinant
        inside = (b >= -1e-7) & (c >= -1e-7) & (b + c <= 1 + 1e-7)
        assert inside.any(), "Facial stroke must remain on the head"
        result.append(np.min((a[:, 2] + b * u[:, 2] + c * v[:, 2])[inside]))
    return np.asarray(result)


def face_line(s, part, surface, points, width):
    """A thin, closed ribbon embedded in the head; no floating face plate."""
    points = np.asarray(points)
    tangent = np.gradient(points, axis=0)
    normal = np.column_stack((-tangent[:, 1], tangent[:, 0]))
    normal /= np.linalg.norm(normal, axis=1)[:, None]
    xy = np.stack((points + normal * width / 2, points - normal * width / 2), axis=1).reshape(-1, 2)
    front = np.column_stack((xy, front_depth(surface, xy) - .004))
    back = front + (0, 0, .010)
    vertices = np.concatenate((front, back))
    count = len(front)
    faces = []
    for i in range(0, count - 2, 2):
        faces += [(i, i + 2, i + 1), (i + 1, i + 2, i + 3),
                  (i + count, i + count + 1, i + count + 2),
                  (i + count + 1, i + count + 3, i + count + 2)]
    perimeter = list(range(0, count, 2)) + list(range(count - 1, 0, -2))
    for a, b in zip(perimeter, perimeter[1:] + perimeter[:1]):
        faces += [(a, b, b + count), (a, b + count, a + count)]
    mesh = tm.Trimesh(vertices=vertices, faces=faces, process=False)
    mesh.fix_normals()
    assert mesh.is_watertight
    s.add(part, mesh, "zombie_ink")


def build_zombie():
    P.update({
        "zombie_skin": (127, 157, 104),
        "zombie_shade": (108, 135, 88),
        "zombie_coat": (87, 99, 91),
        "zombie_coat_edge": (104, 114, 101),
        "zombie_pants": (94, 80, 67),
        "zombie_ink": (49, 65, 43),
    })
    s = Sculpture("zombie")
    body = s.joint("Body", (0, 1.07, 0))
    head = s.joint("Head", (0, 1.71, -.035))
    coat = lathe([(-.285, .245), (-.21, .275), (.16, .295), (.29, .255), (.35, .16)], 12)
    # Shape the hem in the same closed surface, without detached cloth tabs.
    coat.vertices[:12, 1] += np.array([0, -.035, -.025, .012, -.014, -.04,
                                      -.014, 0, -.035, -.045, .012, -.02])
    coat.apply_scale((1, 1, .72))
    s.add(body, coat, "zombie_coat")
    # The trouser seat overlaps both thigh roots through the walking cycle.
    s.e(body, (.237, .113, .155), (0, -.235, 0), "zombie_pants")
    s.e(body, (.118, .12, .11), (0, .38, -.02), "zombie_skin")
    # Rounded cheeks and crown keep the silhouette simple without a box head.
    skin = ellipsoid((.30, .315, .26), (0, .025, 0), sub=2)
    s.add(head, skin, "zombie_skin")
    for sign in (-1, 1):
        # Two small smiling eyelids, drawn as curves rather than square pupils.
        points = [(sign * .114 + (t - .5) * .112, .047 + .034 * math.sin(math.pi * t))
                  for t in np.linspace(0, 1, 9)]
        face_line(s, head, skin, points, .016)
        s.e(head, (.048, .065, .045), (sign * .278, -.012, .015), "zombie_skin")
    mouth = [((t - .5) * .087, -.117 + .018 * (2 * t - 1) ** 2) for t in np.linspace(0, 1, 9)]
    face_line(s, head, skin, mouth, .011)
    nose_z = front_depth(skin, [(0, -.030)])[0]
    s.e(head, (.027, .031, .032), (0, -.030, nose_z + .009), "zombie_skin")

    for side, sign in (("Left", -1), ("Right", 1)):
        arm = s.joint("Arm" + side, (sign * .365, 1.355, 0))
        s.add(arm, lathe([(.08, .065), (.04, .105), (-.11, .12), (-.225, .09)], 12), "zombie_coat")
        s.e(arm, (.092, .082, .086), (0, -.23, 0), "zombie_skin")
        if side == "Left":
            # One narrow cloth band is the only team-colored surface.
            s.add(arm, lathe([(-.166, .111), (-.155, .119), (-.105, .128), (-.092, .124)], 12, caps=False), "blue")
        fore = s.joint("Forearm" + side, (0, -.275, 0), arm)
        s.add(fore, lathe([(.025, .060), (0, .072), (-.15, .078), (-.215, .072)], 10), "zombie_skin")
        s.e(fore, (.104, .104, .096), (0, -.26, -.012), "zombie_skin")
        s.e(fore, (.038, .054, .045), (-sign * .098, -.223, -.032), "zombie_skin")
    for side, x in (("Left", -.16), ("Right", .16)):
        leg = s.joint("Leg" + side, (x, .74, 0))
        pants = lathe([(-.36, .09), (-.285, .101), (0, .11), (.028, .088)], 10)
        pants.vertices[:10, 1] += np.array([0, -.022, -.03, .01, -.012,
                                           -.025, 0, -.015, -.032, -.012])
        s.add(leg, pants, "zombie_pants")
        s.e(leg, (.078, .172, .084), (0, -.44, .005), "zombie_skin")
        foot = lathe([(-.725, .084), (-.707, .105), (-.645, .114), (-.596, .09), (-.576, .06)], 12)
        foot.apply_scale((1, 1, 1.5))
        foot.apply_translation((0, 0, -.061))
        s.add(leg, foot, "zombie_skin")
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
