"""Author four review-only energy tower meshes and native Godot scenes.

Uses the same offline geometry and vertex palette as the existing architecture.
No candidate is registered in the playable building catalogue before selection.
"""
from pathlib import Path
import json
import numpy as np
import war_geometry as env
import build_war_architecture as architecture
from energy_tower_forms_ab import build_crystal, build_armillary
from energy_tower_forms_cd import build_coil, build_lantern

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "tests/energy_towers/models"
VARIANTS = [
    ("a_crystal", "A  晶簇炉塔", "高低晶簇 · 铜爪锻炉", build_crystal),
    ("b_armillary", "B  星环聚能塔", "交错铜环 · 悬浮能量核", build_armillary),
    ("c_coil", "C  线圈充能塔", "双柱线圈 · 石木工坊", build_coil),
    ("d_lantern", "D  符文灯塔", "四面灯室 · 青瓦尖顶", build_lantern),
]


def write(relative, text):
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    env.write_asset(path, text)


def model_scene(name, groups):
    text = '[gd_scene format=3]\n\n'
    text += '[ext_resource type="Shader" path="res://assets/models/block_war/architecture/surface.gdshader" id="surface"]\n'
    for group in groups:
        text += f'[ext_resource type="ArrayMesh" path="res://tests/energy_towers/models/{name}_{group.lower()}.res" id="{group}"]\n'
    for group in groups:
        if group == "Glow":
            text += '''
[sub_resource type="StandardMaterial3D" id="GlowMaterial"]
vertex_color_use_as_albedo = true
roughness = 0.4
emission_enabled = true
emission = Color(0.19, 0.63, 0.43, 1)
emission_energy_multiplier = 0.65
'''
        else:
            text += f'\n[sub_resource type="ShaderMaterial" id="{group}Material"]\nshader = ExtResource("surface")\n'
            text += f'shader_parameter/surface_roughness = {0.6 if group == "Metal" else 0.9}\n'
            if group == "Metal":
                text += 'shader_parameter/metalness = 0.28\n'
    text += f'\n[node name="{name}" type="Node3D"]\n'
    for group in groups:
        text += f'\n[node name="{group}" type="MeshInstance3D" parent="."]\nmesh = ExtResource("{group}")\nmaterial_override = SubResource("{group}Material")\n'
    write(f"tests/energy_towers/models/{name}.tscn", text)


def stage_scene():
    # Authored once as a reusable native scene; each viewport instances it.
    write("tests/energy_towers/stage.tscn", '''[gd_scene format=3]

[ext_resource type="Environment" path="res://assets/block_war/environment/woodland_daylight.tres" id="environment"]

[sub_resource type="StandardMaterial3D" id="GroundMaterial"]
albedo_color = Color(0.19, 0.27, 0.21, 1)
roughness = 1.0

[sub_resource type="PlaneMesh" id="GroundMesh"]
size = Vector2(200, 200)
material = SubResource("GroundMaterial")

[sub_resource type="StandardMaterial3D" id="RimMaterial"]
albedo_color = Color(0.38, 0.40, 0.31, 1)
roughness = 1.0

[sub_resource type="CylinderMesh" id="Rim"]
top_radius = 2.65
bottom_radius = 2.75
height = 0.20
radial_segments = 48
material = SubResource("RimMaterial")

[sub_resource type="StandardMaterial3D" id="GrassMaterial"]
albedo_color = Color(0.29, 0.39, 0.22, 1)
roughness = 1.0

[sub_resource type="CylinderMesh" id="Grass"]
top_radius = 2.59
bottom_radius = 2.65
height = 0.10
radial_segments = 48
material = SubResource("GrassMaterial")

[node name="Stage" type="Node3D"]

[node name="Environment" type="WorldEnvironment" parent="."]
environment = ExtResource("environment")

[node name="Sun" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-49, -38, 0)
light_color = Color(1, 0.965, 0.88, 1)
light_energy = 0.92
light_specular = 0.6
shadow_enabled = true
directional_shadow_max_distance = 80.0
shadow_bias = 0.035
shadow_normal_bias = 0.65
shadow_blur = 1.3
directional_shadow_mode = 0

[node name="Ground" type="MeshInstance3D" parent="."]
position = Vector3(0, -0.28, 0)
mesh = SubResource("GroundMesh")

[node name="Rim" type="MeshInstance3D" parent="."]
position = Vector3(0, -0.14, 0)
mesh = SubResource("Rim")

[node name="Grass" type="MeshInstance3D" parent="."]
position = Vector3(0, -0.01, 0)
mesh = SubResource("Grass")

[node name="Camera" type="Camera3D" parent="."]
position = Vector3(8, 10, 14)
projection = 1
size = 7.2
current = true
''')


def board_scene():
    text = '''[gd_scene format=3]

[ext_resource type="Font" path="res://assets/ui/medieval/fonts/body.tres" id="font"]
[ext_resource type="PackedScene" path="res://tests/energy_towers/stage.tscn" id="stage"]
'''
    for name, _, _, _ in VARIANTS:
        text += f'[ext_resource type="PackedScene" path="res://tests/energy_towers/models/{name}.tscn" id="{name}"]\n'
    text += '''
[sub_resource type="Theme" id="Theme"]
default_font = ExtResource("font")
default_font_size = 24

[sub_resource type="StyleBoxFlat" id="Card"]
bg_color = Color(0.13, 0.20, 0.16, 1)
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.43, 0.49, 0.36, 1)
corner_radius_top_left = 10
corner_radius_top_right = 10
corner_radius_bottom_left = 10
corner_radius_bottom_right = 10

[node name="EnergyTowerReview" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
theme = SubResource("Theme")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 0
offset_right = 1920.0
offset_bottom = 1280.0
color = Color(0.075, 0.12, 0.10, 1)
mouse_filter = 2

[node name="Title" type="Label" parent="."]
offset_left = 48.0
offset_top = 23.0
offset_right = 1800.0
offset_bottom = 76.0
theme_override_colors/font_color = Color(0.94, 0.91, 0.79, 1)
theme_override_font_sizes/font_size = 40
text = "能源塔 · 四种造型方案"

[node name="Subtitle" type="Label" parent="."]
offset_left = 51.0
offset_top = 85.0
offset_right = 1860.0
offset_bottom = 116.0
theme_override_colors/font_color = Color(0.69, 0.77, 0.65, 1)
theme_override_font_sizes/font_size = 20
text = "同一建筑的四种外观 · 仅由铁匠铺改造 · 不可升级"

[node name="Footer" type="Label" parent="."]
offset_left = 48.0
offset_top = 1227.0
offset_right = 1872.0
offset_bottom = 1270.0
theme_override_colors/font_color = Color(0.72, 0.77, 0.65, 1)
theme_override_font_sizes/font_size = 18
text = "统一比例、视角与光照  /  Godot 实机模型截图"
horizontal_alignment = 2
'''
    for i, (name, title, subtitle, _) in enumerate(VARIANTS):
        x, y = 48 + (i % 2) * 924, 142 + (i // 2) * 540
        key = name[0].upper()
        text += f'''
[node name="{key}" type="Panel" parent="."]
offset_left = {float(x)}
offset_top = {float(y)}
offset_right = {float(x + 900)}
offset_bottom = {float(y + 520)}
theme_override_styles/panel = SubResource("Card")

[node name="Title" type="Label" parent="{key}"]
offset_left = 22.0
offset_top = 12.0
offset_right = 475.0
offset_bottom = 51.0
theme_override_colors/font_color = Color(0.95, 0.91, 0.76, 1)
theme_override_font_sizes/font_size = 26
text = "{title}"

[node name="Detail" type="Label" parent="{key}"]
offset_left = 480.0
offset_top = 18.0
offset_right = 876.0
offset_bottom = 49.0
theme_override_colors/font_color = Color(0.71, 0.79, 0.66, 1)
theme_override_font_sizes/font_size = 18
text = "{subtitle}"
horizontal_alignment = 2

[node name="View" type="SubViewportContainer" parent="{key}"]
offset_left = 10.0
offset_top = 66.0
offset_right = 890.0
offset_bottom = 510.0
stretch = true
mouse_filter = 2

[node name="Viewport" type="SubViewport" parent="{key}/View"]
size = Vector2i(880, 444)
own_world_3d = true
msaa_3d = 2
render_target_update_mode = 4

[node name="Stage" parent="{key}/View/Viewport" instance=ExtResource("stage")]

[node name="Model" parent="{key}/View/Viewport" instance=ExtResource("{name}")]
'''
    write("tests/energy_towers/review.tscn", text)


def main():
    FOLDER.mkdir(parents=True, exist_ok=True)
    env.OUT = FOLDER
    manifest = {}
    for index, (name, title, _, build) in enumerate(VARIANTS):
        env.RNG = np.random.default_rng(93101 + index)
        model = build()
        for parts in model.parts.values():
            for part in parts:
                part.apply_scale(architecture.BODY_SCALE)
        manifest[name] = {"title": title, **model.save(name, wrapper=False)}
        model_scene(name, list(model.parts))
    stage_scene()
    board_scene()
    write("tests/energy_towers/models/manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
