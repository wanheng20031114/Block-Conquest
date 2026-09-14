"""Author editable Godot scenes for the first forest expedition.

This offline authoring tool writes complete native scenes. The game only
instances those scenes; it never builds individual model/UI pieces in code.
"""
from pathlib import Path
import math
import random

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "scenes/rogue"
OUT.mkdir(parents=True, exist_ok=True)

def write(path, text):
    dest = ROOT / path
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text, encoding="utf-8")

def scene():
    return ['[gd_scene format=3]\n']

def ext(s, kind, path, key):
    s.append(f'[ext_resource type="{kind}" path="res://{path}" id="{key}"]\n')

def sub(s, kind, key, props):
    s.append(f'[sub_resource type="{kind}" id="{key}"]\n{props}\n')

def node(s, name, kind="", parent=None, props="", instance=None):
    header = f'[node name="{name}"'
    if kind:
        header += f' type="{kind}"'
    if parent is not None:
        header += f' parent="{parent}"'
    if instance:
        header += f' instance=ExtResource("{instance}")'
    s.append(header + f']\n{props}\n')

def material(s, key, color, extra=""):
    sub(s, "StandardMaterial3D", key, f'albedo_color = Color({color})\nroughness = 0.9\n{extra}')

def box(s, key, size, mat):
    sub(s,"BoxMesh",key,f'size = Vector3({size})\nmaterial = SubResource("{mat}")')

def ui(s,name,kind,parent,props=""):
    node(s,name,kind,parent,"layout_mode = 2\n"+props)

FULL = 'layout_mode = 1\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\ngrow_horizontal = 2\ngrow_vertical = 2'

theme = ['[gd_resource type="Theme" format=3]\n']
for key,bg,border in [('Normal','0.07,0.125,0.115,0.97','0.25,0.34,0.28,0.8'),('Hover','0.15,0.235,0.19,1','0.84,0.66,0.32,1'),('Pressed','0.24,0.28,0.16,1','0.96,0.78,0.39,1'),('Disabled','0.07,0.10,0.09,0.8','0.16,0.21,0.18,0.7'),('Panel','0.035,0.073,0.064,0.97','0.36,0.43,0.28,0.8')]:
    sub(theme,'StyleBoxFlat',key,f'bg_color = Color({bg})\nborder_width_bottom = 1\nborder_color = Color({border})\ncontent_margin_left = 18.0\ncontent_margin_right = 18.0\ncontent_margin_top = 12.0\ncontent_margin_bottom = 12.0')
sub(theme,'StyleBoxFlat','Focus','bg_color = Color(0,0,0,0)\nborder_width_left = 2\nborder_width_top = 2\nborder_width_right = 2\nborder_width_bottom = 2\nborder_color = Color(0.96,0.78,0.39,1)')
sub(theme,'SystemFont','Font','font_names = PackedStringArray("Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC")')
theme.append('[resource]\ndefault_font = SubResource("Font")\ndefault_font_size = 18\nLabel/colors/font_color = Color(0.9,0.93,0.83,1)\nButton/colors/font_color = Color(0.91,0.94,0.85,1)\nButton/colors/font_hover_color = Color(1,0.94,0.72,1)\nButton/colors/font_disabled_color = Color(0.44,0.51,0.45,1)\nButton/styles/normal = SubResource("Normal")\nButton/styles/hover = SubResource("Hover")\nButton/styles/pressed = SubResource("Pressed")\nButton/styles/disabled = SubResource("Disabled")\nButton/styles/focus = SubResource("Focus")\nPanelContainer/styles/panel = SubResource("Panel")\nVBoxContainer/constants/separation = 12\nHBoxContainer/constants/separation = 14\n')
write('assets/ui/rogue_theme.tres','\n'.join(theme))

# Three physical resource symbols. No raster generation or alpha extraction.
for kind in ['coin','bread','boot']:
    s=scene()
    material(s,'Gold','0.95,0.65,0.17,1','metallic = 0.65')
    material(s,'Pale','1,0.88,0.55,1')
    material(s,'Crust','0.65,0.30,0.09,1')
    material(s,'Leather','0.33,0.18,0.08,1')
    material(s,'Sole','0.10,0.085,0.055,1')
    if kind=='coin':
        sub(s,'CylinderMesh','Coin','top_radius = 0.79\nbottom_radius = 0.79\nheight = 0.24\nradial_segments = 16\nmaterial = SubResource("Gold")')
        box(s,'Mark','0.12,0.82,0.08','Pale')
        node(s,'Coin','Node3D')
        node(s,'Disc','MeshInstance3D','.', 'rotation_degrees = Vector3(90,0,0)\nmesh = SubResource("Coin")')
        for i in [-1,0,1]:
            node(s,f'Mark{i+1}','MeshInstance3D','.',f'position = Vector3({i*.24},0,0.15)\nmesh = SubResource("Mark")')
    elif kind=='bread':
        box(s,'CrustBase','1.55,1.35,0.48','Crust')
        box(s,'BreadBase','1.29,1.18,0.49','Pale')
        sub(s,'SphereMesh','RoundCrust','radius = 0.57\nheight = 1.14\nradial_segments = 16\nrings = 8\nmaterial = SubResource("Crust")')
        sub(s,'SphereMesh','RoundBread','radius = 0.45\nheight = 0.9\nradial_segments = 16\nrings = 8\nmaterial = SubResource("Pale")')
        node(s,'Bread','Node3D',props='rotation_degrees = Vector3(0,-12,8)')
        node(s,'Crust','MeshInstance3D','.', 'mesh = SubResource("CrustBase")')
        node(s,'Crumb','MeshInstance3D','.', 'position = Vector3(0,0.02,0.02)\nmesh = SubResource("BreadBase")')
        for i,x in enumerate([-.35,.35]):
            node(s,f'Top{i}','MeshInstance3D','.',f'position = Vector3({x},0.62,0)\nscale = Vector3(1,0.75,0.45)\nmesh = SubResource("RoundCrust")')
            node(s,f'CrumbTop{i}','MeshInstance3D','.',f'position = Vector3({x},0.65,0.03)\nscale = Vector3(1,0.74,0.55)\nmesh = SubResource("RoundBread")')
    else:
        box(s,'Ankle','0.75,1.15,0.75','Leather')
        box(s,'Foot','0.9,0.5,1.55','Leather')
        box(s,'SoleMesh','0.98,0.18,1.65','Sole')
        box(s,'Lace','0.78,0.10,0.08','Pale')
        node(s,'Boot','Node3D',props='rotation_degrees = Vector3(0,-25,0)')
        node(s,'Ankle','MeshInstance3D','.', 'position = Vector3(0,0.34,-0.25)\nmesh = SubResource("Ankle")')
        node(s,'Foot','MeshInstance3D','.', 'position = Vector3(0,-0.35,0.12)\nmesh = SubResource("Foot")')
        node(s,'Sole','MeshInstance3D','.', 'position = Vector3(0,-0.64,0.12)\nmesh = SubResource("SoleMesh")')
        for i in range(3):
            node(s,f'Lace{i}','MeshInstance3D','.',f'position = Vector3(0,{i*.22},0.16)\nmesh = SubResource("Lace")')
    write(f'scenes/rogue/icon_{kind}.tscn','\n'.join(s))

s=scene()
ext(s,'Script','scripts/rogue/rogue_route_node.gd','script')
for k in ['defense_tower','house','cart','tent','campfire','royal_banner']:
    ext(s,'PackedScene',f'assets/models/environment/{k}.tscn',k)
material(s,'Earth','0.39,0.43,0.25,1')
material(s,'Ring','0.94,0.74,0.35,1','shading_mode = 0\nemission_enabled = true\nemission = Color(0.6,0.35,0.08,1)')
material(s,'Red','0.9,0.24,0.12,1','shading_mode = 0')
sub(s,'CylinderMesh','Base','top_radius = 1.65\nbottom_radius = 1.9\nheight = 0.4\nradial_segments = 12\nmaterial = SubResource("Earth")')
sub(s,'TorusMesh','RingMesh','inner_radius = 1.75\nouter_radius = 2.05\nrings = 24\nring_segments = 8\nmaterial = SubResource("Ring")')
sub(s,'CylinderShape3D','Pick','radius = 2.4\nheight = 5.0')
sub(s,'SystemFont','Font','font_names = PackedStringArray("Microsoft YaHei UI", "Microsoft YaHei")')
node(s,'RouteNode','Node3D',props='script = ExtResource("script")')
node(s,'Base','MeshInstance3D','.', 'mesh = SubResource("Base")')
node(s,'Ring','MeshInstance3D','.', 'visible = false\nposition = Vector3(0,0.26,0)\nmesh = SubResource("RingMesh")')
node(s,'Content','Node3D','.')
for name,asset,scale in [('Battle','defense_tower',.43),('Shop','house',.48),('Event','cart',.55),('Camp','tent',.60),('Road','royal_banner',.45)]:
    node(s,name,'','Content',f'visible = false\nscale = Vector3({scale},{scale},{scale})',asset)
node(s,'Label','Label3D','.', 'position = Vector3(0,0.55,2.8)\nbillboard = 1\nno_depth_test = true\nfont = SubResource("Font")\nfont_size = 46\npixel_size = 0.019\noutline_size = 10\nmodulate = Color(0.94,0.96,0.84,1)\ntext = "林间小径"')
node(s,'Flag','Label3D','.', 'position = Vector3(0,4.3,0)\nbillboard = 1\nno_depth_test = true\nfont = SubResource("Font")\nfont_size = 66\npixel_size = 0.018\noutline_size = 12\ntext = ""')
node(s,'Pick','Area3D','.', 'collision_layer = 1\ncollision_mask = 0\ninput_ray_pickable = true\nmonitoring = false\nmonitorable = false')
node(s,'Shape','CollisionShape3D','Pick','position = Vector3(0,1.8,0)\nshape = SubResource("Pick")')
write('scenes/rogue/route_node.tscn','\n'.join(s))

# A quiet miniature of the actual outpost is used in its operation briefing.
s=scene()
for k in ['defense_tower','barracks','tree_pine','headquarters']:
    ext(s,'PackedScene',f'assets/models/environment/{k}.tscn',k)
material(s,'Ground','0.25,0.34,0.20,1')
material(s,'Road','0.51,0.45,0.30,1')
box(s,'GroundMesh','112,1,64','Ground')
box(s,'RoadMesh','106,0.05,7','Road')
node(s,'Preview','Node3D')
node(s,'Ground','MeshInstance3D','.', 'position = Vector3(0,-0.65,0)\nmesh = SubResource("GroundMesh")')
node(s,'Road','MeshInstance3D','.', 'mesh = SubResource("RoadMesh")')
node(s,'Outpost','Node3D','.')
for i,(x,z) in enumerate([(-8,-15),(-8,15),(15,0),(36,-16),(36,16)]):
    node(s,f'Tower{i}','','Outpost',f'position = Vector3({x},0,{z})', 'defense_tower')
for i,(x,z) in enumerate([(9,-20),(9,20),(42,0)]):
    node(s,f'Barracks{i}','','Outpost',f'position = Vector3({x},0,{z})', 'barracks')
node(s,'Siege','Node3D','.', 'visible = false')
node(s,'HQ','','Siege','', 'headquarters')
for i in range(24):
    x=-52+i*4.5
    z=(-28 if i%2 else 28)
    node(s,f'Tree{i}','','.',f'position = Vector3({x},0,{z})\nscale = Vector3(1.2,1.2,1.2)', 'tree_pine')
write('scenes/rogue/route_preview.tscn','\n'.join(s))

# Authored military miniatures give the two opening choices an actual visual.
strategy_models = [['archer','cannon','archer'],['shield_guard','swordsman','spearman'],['archer','archer','archer']]
pack_models = [['shield_guard','swordsman','spearman','archer','catapult','priest'],['shield_guard','spearman','archer','archer','cannon','engineer'],['knight','light_cavalry','swordsman','archer','catapult','spearman']]
for index in range(3):
    p=scene()
    for kind in sorted(set(strategy_models[index]+pack_models[index])):
        ext(p,'PackedScene',f'assets/models/units/{kind}.tscn',kind)
    material(p,'Earth','0.23,0.32,0.19,1')
    sub(p,'CylinderMesh','Stage','top_radius = 5.5\nbottom_radius = 5.8\nheight = 0.35\nradial_segments = 12\nmaterial = SubResource("Earth")')
    node(p,'Models','Node3D')
    node(p,'Stage','MeshInstance3D','.', 'position = Vector3(0,-0.3,0)\nmesh = SubResource("Stage")')
    for group,units in [('Strategy',strategy_models[index]),('Pack',pack_models[index])]:
        node(p,group,'Node3D','.',f'visible = {"true" if group=="Strategy" else "false"}')
        for unit_index,kind in enumerate(units):
            x=(unit_index%3-1)*3.0
            z=(unit_index//3)*3-1.0
            node(p,f'Unit{unit_index}','',group,f'position = Vector3({x},0,{z})\nrotation_degrees = Vector3(0,-22,0)',kind)
    write(f'scenes/rogue/setup_models_{index}.tscn','\n'.join(p))

s=scene()
ext(s,'Script','scripts/rogue/rogue_map.gd','script')
ext(s,'Theme','assets/ui/rogue_theme.tres','theme')
ext(s,'PackedScene','scenes/rogue/route_node.tscn','route_node')
ext(s,'PackedScene','scenes/rogue/route_preview.tscn','preview')
ext(s,'PackedScene','scenes/rogue/army_panel.tscn','army')
for index in range(3):
    ext(s,'PackedScene',f'scenes/rogue/setup_models_{index}.tscn',f'setup{index}')
for k in ['tree_pine','tree_oak','rock_medium','campfire']:
    ext(s,'PackedScene',f'assets/models/environment/{k}.tscn',k)
for k in ['coin','bread','boot']:
    ext(s,'PackedScene',f'scenes/rogue/icon_{k}.tscn',k)
material(s,'Ground','0.15,0.25,0.16,1')
material(s,'Path','0.48,0.45,0.28,1')
box(s,'GroundMesh','100,1.5,72','Ground')
box(s,'HorizontalPath','9,0.10,0.55','Path')
box(s,'VerticalPath','0.55,0.10,10','Path')
sub(s,'Environment','World','background_mode = 1\nbackground_color = Color(0.06,0.12,0.10,1)\nambient_light_source = 3\nambient_light_color = Color(0.63,0.78,0.65,1)\nambient_light_energy = 0.65\ntonemap_mode = 2\nssao_enabled = true\nssao_radius = 2.0\nssao_intensity = 1.6\nglow_enabled = true\nglow_intensity = 0.35\nfog_enabled = true\nfog_light_color = Color(0.12,0.24,0.19,1)\nfog_density = 0.002')
sub(s,'Environment','IconEnvironment','background_mode = 0\nambient_light_source = 3\nambient_light_color = Color(1,0.92,0.8,1)\nambient_light_energy = 0.7')
sub(s,'Shader','Shade','code = "shader_type canvas_item;\nvoid fragment(){float rim=smoothstep(0.2,0.75,length((UV-vec2(0.5,0.46))*vec2(1.1,1.0)));COLOR=vec4(0.025,0.055,0.043,rim*0.6);}"')
sub(s,'ShaderMaterial','ShadeMaterial','shader = SubResource("Shade")')
for key,color in [('ChoiceNormal','0.055,0.105,0.084,0.95'),('ChoiceHover','0.15,0.22,0.14,0.98')]:
    sub(s,'StyleBoxFlat',key,f'bg_color = Color({color})\ncontent_margin_top = 190.0\ncontent_margin_bottom = 20.0\ncontent_margin_left = 10.0\ncontent_margin_right = 10.0\nborder_width_bottom = 2\nborder_color = Color(0.62,0.52,0.28,1)')
node(s,'ForestExpedition','Node3D',props='script = ExtResource("script")')
node(s,'WorldEnvironment','WorldEnvironment','.', 'environment = SubResource("World")')
node(s,'Sun','DirectionalLight3D','.', 'rotation_degrees = Vector3(-60,-28,0)\nlight_color = Color(1,0.89,0.65,1)\nlight_energy = 1.3\nshadow_enabled = true\ndirectional_shadow_max_distance = 130.0')
node(s,'CameraRig','Node3D','.', 'position = Vector3(0,0,0)')
node(s,'Camera3D','Camera3D','CameraRig', 'position = Vector3(0,54,31.2)\nrotation_degrees = Vector3(-60,0,0)\nprojection = 1\nsize = 65.0\ncurrent = true\nfar = 180.0')
node(s,'Ground','MeshInstance3D','.', 'position = Vector3(0,-1.0,0)\nmesh = SubResource("GroundMesh")')
node(s,'Routes','Node3D','.')
coords=[(1,0),(2,0),(3,0),(4,0),(5,0),(6,0),(7,0),(1,1),(2,1),(3,1),(4,1),(5,1),(7,1),(0,2),(1,2),(3,2),(4,2),(5,2),(6,2),(0,3),(1,3),(2,3),(3,3),(4,3),(5,3),(6,3),(7,3),(0,4),(1,4),(2,4),(3,4),(4,4),(5,4),(6,4)]
edges=[(0,1),(0,7),(1,8),(2,3),(2,9),(3,4),(4,5),(5,6),(6,12),(7,8),(7,14),(8,9),(9,10),(9,15),(10,11),(10,16),(11,17),(13,14),(13,19),(15,16),(15,22),(16,17),(17,18),(19,27),(20,21),(21,22),(22,23),(22,30),(23,24),(24,25),(25,26),(25,33),(28,29),(29,30),(30,31),(31,32),(32,33)]
for i,(a,b) in enumerate(edges):
    xa,za=coords[a];xb,zb=coords[b]
    node(s,f'Path{i}','MeshInstance3D','Routes',f'position = Vector3({((xa+xb)/2-3.5)*9},-0.17,{((za+zb)/2-2)*10})\nmesh = SubResource("{"HorizontalPath" if za==zb else "VerticalPath"}")')
node(s,'Nodes','Node3D','.')
for i,(x,z) in enumerate(coords):
    node(s,f'Node{i}','','Nodes',f'position = Vector3({(x-3.5)*9},0,{(z-2)*10})\nnode_id = {i}', 'route_node')
node(s,'Forest','Node3D','.')
rng=random.Random(734)
for i in range(180):
    x=rng.uniform(-46,46);z=rng.uniform(-32,32)
    if any(abs(x-(cx-3.5)*9)<3.4 and abs(z-(cz-2)*10)<4.4 for cx,cz in coords):
        continue
    scale=rng.uniform(.65,1.15)
    node(s,f'Tree{i}','','Forest',f'position = Vector3({x:.3f},-0.22,{z:.3f})\nrotation_degrees = Vector3(0,{rng.uniform(0,360):.2f},0)\nscale = Vector3({scale:.3f},{scale:.3f},{scale:.3f})', 'tree_pine' if i%3 else 'tree_oak')
node(s,'Canvas','CanvasLayer','.')
node(s,'UI','Control','Canvas',FULL+'\nmouse_filter = 2\ntheme = ExtResource("theme")')
node(s,'Vignette','ColorRect','Canvas/UI',FULL+'\nmouse_filter = 2\nmaterial = SubResource("ShadeMaterial")')
node(s,'Top','HBoxContainer','Canvas/UI','layout_mode = 0\nanchor_right = 1.0\noffset_left = 32.0\noffset_top = 24.0\noffset_right = -32.0\noffset_bottom = 115.0\nmouse_filter = 2')
ui(s,'TitleBlock','VBoxContainer','Canvas/UI/Top','size_flags_horizontal = 3\nmouse_filter = 2\ntheme_override_constants/separation = 4')
ui(s,'Title','Label','Canvas/UI/Top/TitleBlock','text = "林海远征"\ntheme_override_font_sizes/font_size = 32')
ui(s,'Journey','Label','Canvas/UI/Top/TitleBlock','text = "单人肉鸽 · 第一层"\ntheme_override_colors/font_color = Color(0.72,0.81,0.66,1)')
ui(s,'XP','ProgressBar','Canvas/UI/Top/TitleBlock','custom_minimum_size = Vector2(190,5)\nsize_flags_horizontal = 0\nshow_percentage = false')
for name,icon in [('Gold','coin'),('Bread','bread'),('Action','boot')]:
    ui(s,name,'HBoxContainer','Canvas/UI/Top','custom_minimum_size = Vector2(136,65)\nalignment = 2')
    ui(s,'Icon','SubViewportContainer',f'Canvas/UI/Top/{name}','custom_minimum_size = Vector2(64,64)\nmouse_filter = 2\nstretch = true')
    node(s,'Viewport','SubViewport',f'Canvas/UI/Top/{name}/Icon','transparent_bg = true\nhandle_input_locally = false\nsize = Vector2i(64,64)\nrender_target_update_mode = 1\nown_world_3d = true')
    node(s,'Environment','WorldEnvironment',f'Canvas/UI/Top/{name}/Icon/Viewport','environment = SubResource("IconEnvironment")')
    node(s,'Model','',f'Canvas/UI/Top/{name}/Icon/Viewport','',icon)
    node(s,'Light','DirectionalLight3D',f'Canvas/UI/Top/{name}/Icon/Viewport','rotation_degrees = Vector3(-35,-30,0)\nlight_energy = 1.7')
    node(s,'Camera','Camera3D',f'Canvas/UI/Top/{name}/Icon/Viewport','position = Vector3(0,1.3,5)\nrotation_degrees = Vector3(-14,0,0)\nprojection = 1\nsize = 2.7\ncurrent = true')
    ui(s,'Value','Label',f'Canvas/UI/Top/{name}','text = "—"\ntheme_override_font_sizes/font_size = 28')
node(s,'Rail','VBoxContainer','Canvas/UI','layout_mode = 0\nanchor_top = 0.33\noffset_left = 24.0\noffset_top = 0.0\noffset_right = 154.0\noffset_bottom = 340.0')
for name,label in [('Army','编 队'),('Recruit','招 募'),('Load','读取存档'),('Pause','暂停菜单'),('Menu','返回大厅')]:
    ui(s,name,'Button','Canvas/UI/Rail',f'custom_minimum_size = Vector2(125,54)\ntext = "{label}"')
node(s,'Bottom','PanelContainer','Canvas/UI','layout_mode = 0\nanchor_top = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_left = 190.0\noffset_top = -104.0\noffset_right = -28.0\noffset_bottom = -24.0')
ui(s,'Content','HBoxContainer','Canvas/UI/Bottom')
ui(s,'Label','Label','Canvas/UI/Bottom/Content','text = "收 藏 品"\ntheme_override_colors/font_color = Color(0.86,0.70,0.40,1)')
ui(s,'Scroll','ScrollContainer','Canvas/UI/Bottom/Content','size_flags_horizontal = 3\nvertical_scroll_mode = 0')
ui(s,'Relics','HBoxContainer','Canvas/UI/Bottom/Content/Scroll')
for i in range(8):
    ui(s,f'Relic{i}','Button','Canvas/UI/Bottom/Content/Scroll/Relics',f'visible = false\ntext = "收藏品"\ncustom_minimum_size = Vector2(120,46)')
ui(s,'Empty','Label','Canvas/UI/Bottom/Content/Scroll/Relics','text = "尚未获得收藏品 · 在林海中寻找军团的机遇"\ntheme_override_font_sizes/font_size = 16')
node(s,'Hint','Label','Canvas/UI','layout_mode = 0\nanchor_top = 1.0\noffset_left = 194.0\noffset_top = -137.0\noffset_right = 1100.0\noffset_bottom = -110.0\ntext = "点击节点查看详情 · 中键拖动地图 · 滚轮缩放"\nmouse_filter = 2\ntheme_override_font_sizes/font_size = 16')
node(s,'Preview','PanelContainer','Canvas/UI','visible = false\nlayout_mode = 0\nanchor_left = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_left = -425.0\noffset_top = 132.0\noffset_right = -28.0\noffset_bottom = -158.0\ngrow_horizontal = 0')
ui(s,'Scroll','ScrollContainer','Canvas/UI/Preview','horizontal_scroll_mode = 0')
ui(s,'Content','VBoxContainer','Canvas/UI/Preview/Scroll','size_flags_horizontal = 3\ntheme_override_constants/separation = 12')
P='Canvas/UI/Preview/Scroll/Content'
ui(s,'Kind','Label',P,'text = "作战 / 难度 1"\ntheme_override_colors/font_color = Color(0.88,0.72,0.42,1)\ntheme_override_font_sizes/font_size = 16')
ui(s,'Name','Label',P,'text = "前哨站"\ntheme_override_font_sizes/font_size = 32')
ui(s,'MapView','SubViewportContainer',P,'custom_minimum_size = Vector2(0,160)\nstretch = true\nmouse_filter = 2')
node(s,'Viewport','SubViewport',P+'/MapView','size = Vector2i(352,160)\nrender_target_update_mode = 2\nown_world_3d = true\nhandle_input_locally = false')
node(s,'Environment','WorldEnvironment',P+'/MapView/Viewport','environment = SubResource("World")')
node(s,'Model','',P+'/MapView/Viewport','', 'preview')
node(s,'Camera','Camera3D',P+'/MapView/Viewport','position = Vector3(0,80,46)\nrotation_degrees = Vector3(-60,0,0)\nprojection = 1\nsize = 76\ncurrent = true')
node(s,'Light','DirectionalLight3D',P+'/MapView/Viewport','rotation_degrees = Vector3(-55,-30,0)\nlight_energy = 1.5\nshadow_enabled = true')
ui(s,'Detail','Label',P,'text = "摧毁所有敌方建筑与部队。"\nautowrap_mode = 2\ncustom_minimum_size = Vector2(290,0)\ntheme_override_font_sizes/font_size = 17')
ui(s,'Options','VBoxContainer',P,'theme_override_constants/separation = 8')
for i in range(6):
    ui(s,f'Option{i}','Button',P+'/Options','visible = false\ncustom_minimum_size = Vector2(0,58)\ntext = "选项"\nalignment = 0\ntheme_override_font_sizes/font_size = 16')
ui(s,'Primary','Button',P,'text = "进入节点  ·  行动力 −1"\ncustom_minimum_size = Vector2(0,52)')
ui(s,'Secondary','Button',P,'text = "关闭预览"')
node(s,'Setup','ColorRect','Canvas/UI',FULL+'\ncolor = Color(0.018,0.045,0.035,0.87)\nvisible = false')
node(s,'Margin','MarginContainer','Canvas/UI/Setup',FULL+'\noffset_left = 100.0\noffset_top = 80.0\noffset_right = -100.0\noffset_bottom = -60.0')
ui(s,'Content','VBoxContainer','Canvas/UI/Setup/Margin','theme_override_constants/separation = 20')
P='Canvas/UI/Setup/Margin/Content'
ui(s,'Eyebrow','Label',P,'text = "林 海 远 征  /  第一层"\ntheme_override_colors/font_color = Color(0.87,0.72,0.43,1)')
ui(s,'Title','Label',P,'text = "选择你的战略"\ntheme_override_font_sizes/font_size = 44')
ui(s,'Description','Label',P,'text = "先决定军团的优势，再选择初始部队。"\nautowrap_mode = 2')
ui(s,'Choices','HBoxContainer',P,'size_flags_vertical = 3\ntheme_override_constants/separation = 22')
for i in range(3):
    ui(s,f'Choice{i}','Button',P+'/Choices',f'custom_minimum_size = Vector2(270,330)\nsize_flags_horizontal = 3\ntext = "战略 {i+1}"\ntheme_override_font_sizes/font_size = 21\ntheme_override_styles/normal = SubResource("ChoiceNormal")\ntheme_override_styles/hover = SubResource("ChoiceHover")\ntheme_override_styles/pressed = SubResource("ChoiceHover")')
    choice=P+f'/Choices/Choice{i}'
    node(s,'Illustration','SubViewportContainer',choice,'layout_mode = 0\nanchor_right = 1.0\noffset_left = 12.0\noffset_top = 10.0\noffset_right = -12.0\noffset_bottom = 210.0\nstretch = true\nmouse_filter = 2')
    node(s,'Viewport','SubViewport',choice+'/Illustration','transparent_bg = true\nown_world_3d = true\nsize = Vector2i(400,200)\nrender_target_update_mode = 2\nhandle_input_locally = false')
    node(s,'Environment','WorldEnvironment',choice+'/Illustration/Viewport','environment = SubResource("IconEnvironment")')
    node(s,'Models','',choice+'/Illustration/Viewport','',f'setup{i}')
    node(s,'Sun','DirectionalLight3D',choice+'/Illustration/Viewport','rotation_degrees = Vector3(-45,-28,0)\nlight_energy = 1.5\nshadow_enabled = true')
    node(s,'Camera','Camera3D',choice+'/Illustration/Viewport','position = Vector3(0,9,13)\nrotation_degrees = Vector3(-30,0,0)\nprojection = 1\nsize = 9.8\ncurrent = true')
ui(s,'Footnote','Label',P,'text = "初始人口 20  /  军队在战斗之间恢复  /  作战失败结束本局"\nautowrap_mode = 2\ntheme_override_font_sizes/font_size = 17')
ui(s,'Actions','HBoxContainer',P)
for name,label in [('Back','返回大厅'),('Continue','继续上次远征')]:
    ui(s,name,'Button',P+'/Actions',f'text = "{label}"\ncustom_minimum_size = Vector2(230,52)')
node(s,'Alert','ColorRect','Canvas/UI',FULL+'\nmouse_filter = 2\nvisible = false\ncolor = Color(0.7,0.11,0.04,0.32)')
node(s,'AlertTitle','Label','Canvas/UI/Alert','layout_mode = 0\nanchor_left = 0.5\nanchor_right = 0.5\nanchor_top = 0.35\nanchor_bottom = 0.35\noffset_left = -400.0\noffset_right = 400.0\noffset_bottom = 100.0\ntext = "⚠  敌 军 围 剿"\nhorizontal_alignment = 1\ntheme_override_font_sizes/font_size = 52\ntheme_override_colors/font_color = Color(1,0.75,0.46,1)')
node(s,'ArmyPanel','','Canvas/UI','visible = false', 'army')
node(s,'PauseMenu','ColorRect','Canvas/UI',FULL+'\nvisible = false\ncolor = Color(0.015,0.04,0.03,0.78)')
node(s,'Panel','PanelContainer','Canvas/UI/PauseMenu','layout_mode = 0\nanchor_left = 0.5\nanchor_top = 0.5\nanchor_right = 0.5\nanchor_bottom = 0.5\noffset_left = -240.0\noffset_top = -210.0\noffset_right = 240.0\noffset_bottom = 210.0')
ui(s,'Content','VBoxContainer','Canvas/UI/PauseMenu/Panel')
ui(s,'Title','Label','Canvas/UI/PauseMenu/Panel/Content','text = "远征暂歇"\ntheme_override_font_sizes/font_size = 30')
ui(s,'Detail','Label','Canvas/UI/PauseMenu/Panel/Content','text = "离开完整节点时自动保存。\n节点内部退出将回到最近检查点。"\ntheme_override_font_sizes/font_size = 16')
for name,label in [('Resume','继续探索'),('Settings','游戏设置'),('Load','读取节点存档'),('Menu','返回大厅'),('Quit','退出游戏')]:
    ui(s,name,'Button','Canvas/UI/PauseMenu/Panel/Content',f'text = "{label}"\ncustom_minimum_size = Vector2(0,45)')
node(s,'ReplaceRun','ConfirmationDialog','Canvas/UI','title = "开始新远征"\ndialog_text = "开始新局将替换最近的节点存档。"\nok_button_text = "开始新局"\ncancel_button_text = "取消"')
node(s,'LoadConfirm','ConfirmationDialog','Canvas/UI','title = "读取节点存档"\ndialog_text = "恢复最近完整节点的存档，当前节点内的进度将被放弃。"\nok_button_text = "读取存档"\ncancel_button_text = "取消"')
node(s,'Notice','AcceptDialog','Canvas/UI','title = "林海远征"\nok_button_text = "知道了"')
write('scenes/rogue/rogue_map.tscn','\n'.join(s))

if __name__ == '__main__':
    print('Authored forest presentation scenes and native resource icons.')
