"""Save the miniature's choreography as editable Godot Animation tracks."""

LENGTH = 2.55


def number(value):
    return f"{value:.5f}".rstrip("0").rstrip(".") if value else "0"


def author_intro(items):
    text = '[sub_resource type="Animation" id="Unfold"]\nresource_name = "unfold"\nlength = 2.55\n'
    track = 0

    def value(path, times, values, discrete=False):
        nonlocal track, text
        text += f'tracks/{track}/type = "value"\ntracks/{track}/path = NodePath("{path}")\n'
        text += f'tracks/{track}/keys = {{"times": PackedFloat32Array(' + ', '.join(map(number, times)) + '), "transitions": PackedFloat32Array(' + ', '.join('1' for _ in times) + '), "update": ' + ('1' if discrete else '0') + ', "values": [' + ', '.join(values) + ']}\n'
        track += 1

    def transform(path, kind, keys):
        nonlocal track, text
        text += f'tracks/{track}/type = "{kind}_3d"\ntracks/{track}/path = NodePath("{path}")\n'
        text += f'tracks/{track}/keys = PackedFloat32Array(' + ', '.join(number(n) for t, v in keys for n in (t, 1, *v)) + ')\n'
        track += 1

    for material_node in ("WestBedrock", "River", "Falls"):
        value(f"Terrain/{material_node}:material_override:shader_parameter/build_time", [0, 1.6, LENGTH], ["0.0", "1.6", "1.6"])
    for i, (path, position, scale, kind, phase_x) in enumerate(items):
        x, y, z = position
        west_to_east = (phase_x + 28) / 56
        if kind == "tree":
            delay = 1.02 + .45*west_to_east + .07*(z+12)/24
            value(path + ":visible", [0, delay], ["false", "true"], True)
            transform(path, "scale", [(0, (scale, .003, scale)), (delay, (scale, .003, scale)),
                                       (delay+.23, (scale, scale*1.045, scale)), (delay+.36, (scale, scale, scale)), (LENGTH, (scale, scale, scale))])
        else:
            delay = 1.02 + .45*west_to_east + .032*(i % 3)
            value(path + ":visible", [0, delay], ["false", "true"], True)
            # Accelerating descent, short cushioned contact, one small rebound.
            transform(path, "position", [(0, (x, y+12, z)), (delay, (x, y+12, z)),
                                           (delay+.17, (x, y+9.1, z)), (delay+.32, (x, y+4.9, z)),
                                           (delay+.44, (x, y+.04, z)), (delay+.48, (x, y, z)),
                                           (delay+.54, (x, y+.10, z)), (delay+.64, (x, y, z)), (LENGTH, (x, y, z))])
            transform(path, "scale", [(0, (scale, scale, scale)), (delay+.44, (scale, scale, scale)),
                                       (delay+.48, (scale*1.018, scale*.957, scale*1.018)),
                                       (delay+.56, (scale, scale*1.012, scale)), (delay+.66, (scale, scale, scale)), (LENGTH, (scale, scale, scale))])
    text += '\n[sub_resource type="AnimationLibrary" id="EntranceLibrary"]\n_data = {&"unfold": SubResource("Unfold")}\n\n'
    node = '[node name="Entrance" type="AnimationPlayer" parent="."]\nlibraries = {&"": SubResource("EntranceLibrary")}\n'
    return text, node
