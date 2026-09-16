"""Author the hero's native UI scene. This runs offline, never in the game."""
from pathlib import Path
import re
from build_hero_theme import build_theme
import hero_ui_layout
build_theme()
ROOT=Path(__file__).resolve().parents[1]
lines=['[gd_scene format=3]',
'[ext_resource type="Script" path="res://scripts/hero/hero_interface.gd" id="script"]',
'[ext_resource type="Theme" path="res://assets/ui/hero/theme.tres" id="theme"]',
'[ext_resource type="StyleBox" path="res://assets/ui/hero/styles/panel.tres" id="paper"]',
'[ext_resource type="StyleBox" path="res://assets/ui/hero/styles/empty.tres" id="compact"]',
'[ext_resource type="PackedScene" path="res://assets/models/heroes/capsule.tscn" id="hero"]',
'[ext_resource type="PackedScene" path="res://assets/models/weapons/repeating_musket.tscn" id="weapon"]',
'[ext_resource type="PackedScene" path="res://scenes/hero/inventory_slot.tscn" id="item_slot"]',
'[ext_resource type="Texture2D" path="res://assets/ui/hero/backpack.png" id="bag_icon"]',
'[sub_resource type="Environment" id="studio"]\nbackground_mode = 0\nambient_light_source = 2\nambient_light_color = Color(1,.94,.85,1)\nambient_light_energy = .6',
'[sub_resource type="Environment" id="weapon_world"]\nbackground_mode = 0\nambient_light_source = 2\nambient_light_color = Color(1,.94,.85,1)\nambient_light_energy = .6',
'[sub_resource type="ViewportTexture" id="gun_texture"]\nviewport_path = NodePath("WeaponViewport")',
'[sub_resource type="StandardMaterial3D" id="flash_mat"]\nshading_mode = 0\nalbedo_color = Color(1,.81,.38,1)',
'[sub_resource type="SphereMesh" id="flash_mesh"]\nradius = .04\nheight = .08\nradial_segments = 6\nrings = 2\nmaterial = SubResource("flash_mat")']


def node(name,kind,parent=None,props='',unique=False):
    lines.append(f'[node name="{name}" type="{kind}"'+(f' parent="{parent}"' if parent is not None else '')+']\n'+('unique_name_in_owner = true\n' if unique else '')+props)


def label(name,parent,text,extra='',size=18):
    text=text.replace('\n',r'\n')
    node(name,'Label',parent,f'layout_mode = 2\ntext = "{text}"\ntheme_override_font_sizes/font_size = {size}\ntheme_override_constants/line_spacing = 2\n'+extra,True)


def button(name,parent,text,extra=''):
    size='' if 'custom_minimum_size' in extra else 'custom_minimum_size = Vector2(0,40)\n'
    layout='' if 'layout_mode =' in extra else 'layout_mode = 2\n'
    node(name,'Button',parent,layout+f'text = "{text}"\n'+size+extra,True)


full='anchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\ngrow_horizontal = 2\ngrow_vertical = 2\n'
hero_ui_layout.resources(lines)
node('HeroInterface','CanvasLayer',props='layer = 20\nscript = ExtResource("script")')
node('WeaponViewport','SubViewport','.', 'transparent_bg = true\nsize = Vector2i(1280,720)\nmsaa_3d = 2\nown_world_3d = true\nrender_target_update_mode = 0',True)
node('Environment','WorldEnvironment','WeaponViewport','environment = SubResource("weapon_world")')
node('Light','DirectionalLight3D','WeaponViewport','rotation_degrees = Vector3(-40,-25,0)\nlight_color = Color(1,.91,.73,1)\nlight_energy = 1.3')
node('Camera','Camera3D','WeaponViewport','current = true\nfov = 65.0\nnear = .03\nfar = 6.0')
node('GunPivot','Node3D','WeaponViewport','position = Vector3(.32,-.29,-.54)\nscale = Vector3(.65,.65,.65)',True)
lines.append('[node name="Gun" parent="WeaponViewport/GunPivot" instance=ExtResource("weapon")]')
node('MuzzleFlash','MeshInstance3D','WeaponViewport/GunPivot','position = Vector3(0,.08,-.985)\nvisible = false\nmesh = SubResource("flash_mesh")',True)
hero_ui_layout.weapon_preview(node,lines)
node('Root','Control','.',full+'mouse_filter = 2\ntheme = ExtResource("theme")')
node('WeaponView','TextureRect','Root',full+'mouse_filter = 2\ntexture = SubResource("gun_texture")\nexpand_mode = 1\nstretch_mode = 5\nvisible = false',True)
node('Crosshair','Label','Root','anchor_left = .5\nanchor_top = .5\nanchor_right = .5\nanchor_bottom = .5\noffset_left = -15.0\noffset_top = -20.0\noffset_right = 15.0\noffset_bottom = 20.0\ntext = "+"\nhorizontal_alignment = 1\nvertical_alignment = 1\nmouse_filter = 2\ntheme_override_font_sizes/font_size = 28\ntheme_override_colors/font_color = Color(1,.98,.88,1)\ntheme_override_colors/font_shadow_color = Color(.12,.12,.10,1)\ntheme_override_constants/shadow_offset_x = 1\ntheme_override_constants/shadow_offset_y = 1\nvisible = false',True)
hero_ui_layout.hud(node,label,button,lines)
node('FPSHint','Label','Root','anchor_left = .5\nanchor_right = .5\noffset_left = -350.0\noffset_right = 350.0\noffset_top = 20.0\noffset_bottom = 58.0\ntext = "WASD 移动 · 左键开火 · R 换弹 · Space 跳跃 · F5 返回 · Esc 菜单"\nhorizontal_alignment = 1\nmouse_filter = 2\ntheme_override_font_sizes/font_size = 15\ntheme_override_colors/font_color = Color(1,.96,.85,1)\ntheme_override_colors/font_shadow_color = Color(.1,.1,.1,1)\ntheme_override_constants/shadow_offset_y = 1\nvisible = false',True)
node('Notice','Label','Root','anchor_left = .5\nanchor_top = .15\nanchor_right = .5\nanchor_bottom = .15\noffset_left = -450.0\noffset_right = 450.0\noffset_bottom = 50.0\nhorizontal_alignment = 1\nmouse_filter = 2\ntheme_override_colors/font_color = Color(1,.92,.67,1)\ntheme_override_colors/font_shadow_color = Color(.1,.1,.1,1)\ntheme_override_constants/shadow_offset_y = 2',True)
node('Creator','ColorRect','Root',full+'color = Color(.03,.04,.04,.24)\nvisible = false',True)
node('Center','CenterContainer','Root/Creator',full)
node('Panel','PanelContainer','Root/Creator/Center','custom_minimum_size = Vector2(970,625)\ntheme_override_styles/panel = ExtResource("paper")')
node('Layout','VBoxContainer','Root/Creator/Center/Panel','layout_mode = 2\ntheme_override_constants/separation = 12')
base='Root/Creator/Center/Panel/Layout'
label('CreatorTitle',base,'我的英雄',size=28)
label('CreatorSubtitle',base,'姓名、队伍与外观',size=16)
node('Body','HBoxContainer',base,'layout_mode = 2\ntheme_override_constants/separation = 25')
node('Preview','SubViewportContainer',base+'/Body','layout_mode = 2\ncustom_minimum_size = Vector2(450,430)\nsize_flags_horizontal = 3\nstretch = true',True)
node('Viewport','SubViewport',base+'/Body/Preview','size = Vector2i(450,430)\ntransparent_bg = true\nmsaa_3d = 2\nown_world_3d = true\nhandle_input_locally = false\nrender_target_update_mode = 0',True)
view=base+'/Body/Preview/Viewport'
node('World','WorldEnvironment',view,'environment = SubResource("studio")')
node('Light','DirectionalLight3D',view,'rotation_degrees = Vector3(-40,145,0)\nlight_color = Color(1,.93,.79,1)\nlight_energy = .8\nshadow_enabled = true')
node('Camera','Camera3D',view,'position = Vector3(4,2.7,-6)\nrotation_degrees = Vector3(-10,146.3,0)\nprojection = 1\nsize = 3.4\ncurrent = true')
node('PreviewPivot','Node3D',view,unique=True)
lines.append(f'[node name="Model" parent="{view}/PreviewPivot" instance=ExtResource("hero")]\nunique_name_in_owner = true')
node('Fields','TabContainer',base+'/Body','layout_mode = 2\ncustom_minimum_size = Vector2(385,430)\nsize_flags_horizontal = 3',True)
tabs=base+'/Body/Fields'
node('Identity','VBoxContainer',tabs,'layout_mode = 2\nmetadata/_tab_index = 0\ntheme_override_constants/separation = 7')
fields=tabs+'/Identity'
label('NameLabel',fields,'玩家名',size=16)
node('PlayerName','LineEdit',fields,'layout_mode = 2\nmax_length = 20\nplaceholder_text = "远行者"',True)
label('FactionLabel',fields,'所属队伍',size=16)
node('Faction','OptionButton',fields,'layout_mode = 2\ncustom_minimum_size = Vector2(0,38)',True)
node('TeamClothes','CheckBox',fields,'layout_mode = 2\ntext = "衣服使用阵营主色"\nbutton_pressed = true',True)
node('Colors','HBoxContainer',fields,'layout_mode = 2\ntheme_override_constants/separation = 12')
for title,key in [('衣服','Garment'),('脸部','Face'),('靴子','Boots')]:
    node(key+'Col','VBoxContainer',fields+'/Colors','layout_mode = 2\nsize_flags_horizontal = 3')
    label(key+'Label',fields+'/Colors/'+key+'Col',title,size=14)
    node(key,'ColorPickerButton',fields+'/Colors/'+key+'Col','layout_mode = 2\ncustom_minimum_size = Vector2(72,32)\nedit_alpha = false',True)
label('HeroStats',fields,'生命 200     护甲 3 / 3     移速 4.2\n攻击 20 + 武器 20 = 40\n射程 20     弹匣 10 发     换弹 1.8 秒', 'autowrap_mode = 2',16)
node('Details','VBoxContainer',tabs,'layout_mode = 2\nmetadata/_tab_index = 1\ntheme_override_constants/separation = 8')
details=tabs+'/Details'
label('ExpressionLabel',details,'面部表情',size=16)
node('Expression','OptionButton',details,'layout_mode = 2\ncustom_minimum_size = Vector2(0,38)',True)
label('HeadwearLabel',details,'帽子',size=16)
node('Headwear','OptionButton',details,'layout_mode = 2\ncustom_minimum_size = Vector2(0,38)',True)
node('Accessories','GridContainer',details,'layout_mode = 2\ncolumns = 2\ntheme_override_constants/h_separation = 8\ntheme_override_constants/v_separation = 6')
for key,title in [('Backpack','小背包'),('Nose','圆鼻子'),('Glasses','圆框眼镜'),('Scarf','阵营围巾'),('Moustache','小胡子'),('Feather','帽边羽饰')]:
    node(key,'CheckBox',details+'/Accessories',f'layout_mode = 2\nsize_flags_horizontal = 3\ntext = "{title}"',True)
button('ResetAppearance',details,'还原默认外观')
label('PreviewHint',base,'拖动模型旋转 · 滚轮缩放 · 固定的阵营布章保留队伍辨识度',size=14)
node('Footer','HBoxContainer',base,'layout_mode = 2\nalignment = 2\ntheme_override_constants/separation = 16')
button('CancelCreator',base+'/Footer','返回')
button('ApplyCreator',base+'/Footer','创建英雄','custom_minimum_size = Vector2(190,44)')
node('Pause','ColorRect','Root',full+'color = Color(.03,.04,.04,.26)\nvisible = false',True)
node('Center','CenterContainer','Root/Pause',full)
node('Panel','PanelContainer','Root/Pause/Center','custom_minimum_size = Vector2(430,350)\ntheme_override_styles/panel = ExtResource("paper")')
node('Rows','VBoxContainer','Root/Pause/Center/Panel','layout_mode = 2\ntheme_override_constants/separation = 14')
pause='Root/Pause/Center/Panel/Rows'
label('PauseTitle',pause,'远行者 · 暂停',size=26)
button('Resume',pause,'继续第一人称')
button('ReturnRTS',pause,'返回 RTS 视角')
button('Settings',pause,'第一人称与游戏设置')
button('BackMenu',pause,'返回主菜单')
hero_ui_layout.inventory(node,label,button,lines)
(ROOT/'scenes/hero/hero_interface.tscn').write_text(re.sub(r'(?<![A-Za-z0-9_])\.(\d)',r'0.\1','\n\n'.join(lines)+'\n'),encoding='utf-8')
