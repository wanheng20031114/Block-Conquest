"""Opt-in monster rigs: shared shuffle, authored equipment and native clips."""
from build_units import OUT, anim_resource, vec
from unit_zombie import build_zombie, resting_pose, zombie_clips

VARIANTS = ("zombie_archer", "zombie_musketeer", "zombie_crossbowman",
            "zombie_pitchfork", "zombie_axe", "zombie_miner", "zombie_bell", "zombie_door")


def base_variant(kind):
    assert kind in VARIANTS
    s = build_zombie()
    s.name = s.kind = kind
    s.monster_rest = dict(resting_pose())
    s.monster_tracks = []
    s.monster_properties = {}
    s.monster_attack_length = 1.0
    s.monster_socket = ("ForearmRight", (0, -.345, -.012))
    s.monster_extra_clips = {}
    return s


def variant_clips(s):
    idle, walk, _ = zombie_clips(s)
    defaults = {s.part_path(part) + ":rotation": value for part, value in s.monster_rest.items()}
    defaults.update(s.monster_properties)
    # Reset every authored attack property, including bolt visibility and recoil,
    # when an attack is cancelled or a different animation starts.
    for tracks in [s.monster_tracks] + [value[1] for value in s.monster_extra_clips.values()]:
        for path, values, *_ in tracks:
            defaults.setdefault(path, values[0])
    for clip in (idle, walk):
        paths = set()
        for index, track in enumerate(clip):
            path = track[0]
            paths.add(path)
            if path in defaults:
                clip[index] = (path, [defaults[path]] * 2)
        for path, value in defaults.items():
            if path not in paths:
                clip.append((path, [value] * 2))
    return idle, walk, s.monster_tracks


def write_variant_scene(s):
    parts = list(s.parts)
    idle, walk, strike = variant_clips(s)
    socket_part, socket_pos = s.monster_socket
    socket_path = s.part_path(socket_part) + "/ReleasePoint"
    lines = ['[gd_scene format=3]',
             '[ext_resource type="Script" path="res://scripts/unit_visual.gd" id="script"]']
    for part in parts:
        lines.append(f'[ext_resource type="ArrayMesh" path="res://assets/models/units/{s.kind}/{part}.res" id="{part}"]')
    lines += [anim_resource("idle", 2.8, idle, True), anim_resource("walk", 1.08, walk, True),
              anim_resource("strike", s.monster_attack_length, strike)]
    for name, (length, tracks) in s.monster_extra_clips.items():
        lines.append(anim_resource(name, length, tracks))
    attack_entries = ', '.join(f'&"{name}": SubResource("Animation_{name}")' for name in ["strike"] + list(s.monster_extra_clips))
    lines += ['[sub_resource type="AnimationLibrary" id="locomotion"]\n_data = {&"idle": SubResource("Animation_idle"), &"walk": SubResource("Animation_walk")}',
              '[sub_resource type="AnimationLibrary" id="attack"]\n_data = {' + attack_entries + '}',
              f'[node name="{s.kind}" type="Node3D"]\nscript = ExtResource("script")\nkind = "{s.kind}"\nprojectile_socket = NodePath("{socket_path}")\nmetadata/faction = &"monsters"\nmetadata/prototype = true',
              '[node name="Rig" type="Node3D" parent="."]',
              '[node name="Action" type="Node3D" parent="Rig"]']
    emitted = set()

    def emit(part):
        if part in emitted:
            return
        parent_part = s.parents[part]
        if parent_part:
            emit(parent_part)
        parent = s.part_path(parent_part) if parent_part else "Rig/Action"
        node_type = "Node3D" if part in s.pivots else "MeshInstance3D"
        position = s.monster_properties.get(s.part_path(part) + ":position", s.joints[part])
        properties = f'position = {vec(position)}'
        if part in s.monster_rest:
            properties += f'\nrotation = {vec(s.monster_rest[part])}'
        if part in s.parts:
            properties += f'\nmesh = ExtResource("{part}")'
        for path, value in s.monster_properties.items():
            if path.rsplit(":", 1)[0] == s.part_path(part):
                prop = path.rsplit(":", 1)[1]
                if prop == "position":
                    continue
                value_text = str(value).lower() if isinstance(value, bool) else vec(value)
                properties += f'\n{prop} = {value_text}'
        lines.append(f'[node name="{part}" type="{node_type}" parent="{parent}"]\n{properties}')
        emitted.add(part)

    for part in parts:
        emit(part)
    lines += [f'[node name="ReleasePoint" type="Marker3D" parent="{s.part_path(socket_part)}"]\nposition = {vec(socket_pos)}',
              '[node name="Locomotion" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("locomotion")}\nautoplay = "idle"',
              '[node name="Attack" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("attack")}',
              '[node name="VisibilityNotifier" type="VisibleOnScreenNotifier3D" parent="."]\naabb = AABB(-1.2, -0.1, -1.8, 2.4, 3.1, 2.7)',
              '[connection signal="screen_entered" from="VisibilityNotifier" to="." method="_on_screen_entered"]',
              '[connection signal="screen_exited" from="VisibilityNotifier" to="." method="_on_screen_exited"]']
    (OUT / f"{s.kind}.tscn").write_text("\n\n".join(lines) + "\n", encoding="utf-8")
