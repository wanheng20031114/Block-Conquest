"""Scene authoring helpers for the hero's equipment, backpack and combat HUD."""

FULL = 'anchor_right = 1.0\nanchor_bottom = 1.0\ngrow_horizontal = 2\ngrow_vertical = 2\n'
IGNORE = 'mouse_filter = 2\n'
BOLD = 'theme_override_fonts/font = ExtResource("bold")\n'
NUMBERS = 'theme_override_fonts/font = ExtResource("numbers")\n'
MUTED = 'theme_override_colors/font_color = Color(.66,.76,.84,1)\n'


def resources(lines):
    # Insert before the existing subresources, preserving native file ordering.
    index = next(i for i, s in enumerate(lines) if s.startswith('[sub_resource'))
    extra = []
    for name in ['weapon','header','glass_frame','chip','keycap','health_track','health_fill']:
        extra.append(f'[ext_resource type="StyleBox" path="res://assets/ui/hero/styles/{name}.tres" id="{name}_style"]')
    for name in ['bold','numbers']:
        extra.append(f'[ext_resource type="Font" path="res://assets/ui/hero/font_{name}.tres" id="{name}"]')
    for name in ['health_heart','speed_boot']:
        extra.append(f'[ext_resource type="Texture2D" path="res://assets/ui/hero/{name}.png" id="{name}"]')
    extra.append('[ext_resource type="Shader" path="res://assets/ui/hero/glass.gdshader" id="glass_shader"]')
    lines[index:index] = extra
    lines.append('[sub_resource type="ViewportTexture" id="weapon_icon"]\nviewport_path = NodePath("WeaponIconViewport")')
    for name,w,h in [('bag',460,710),('detail',330,544),('shortcuts',492,145)]:
        lines.append(f'[sub_resource type="ShaderMaterial" id="glass_{name}"]\nshader = ExtResource("glass_shader")\nshader_parameter/panel_size = Vector2({w},{h})')


def weapon_preview(node, lines):
    node('WeaponIconViewport','SubViewport','.', 'transparent_bg = true\nsize = Vector2i(512,256)\nmsaa_3d = 2\nown_world_3d = true\nrender_target_update_mode = 1',True)
    path='WeaponIconViewport'
    node('World','WorldEnvironment',path,'environment = SubResource("studio")')
    node('Key','DirectionalLight3D',path,'rotation_degrees = Vector3(-35,-35,0)\nlight_color = Color(1,.94,.84,1)\nlight_energy = 1.5')
    node('Fill','DirectionalLight3D',path,'rotation_degrees = Vector3(20,145,0)\nlight_color = Color(.64,.83,1,1)\nlight_energy = .6')
    node('Camera','Camera3D',path,'position = Vector3(3,1.35,1.6)\nrotation_degrees = Vector3(-20,62,0)\nprojection = 1\nsize = .95\ncurrent = true')
    lines.append('[node name="Musket" parent="WeaponIconViewport" instance=ExtResource("weapon")]\nrotation_degrees = Vector3(0,0,-12)')


def layout_helpers(node, label):
    def art(name, parent, resource, props='', unique=False):
        node(name,'TextureRect',parent,IGNORE+'expand_mode = 1\nstretch_mode = 5\ntexture_filter = 2\ntexture = '+resource+'\n'+props,unique)
    def keycap(name,parent,text,props=''):
        label(name,parent,text,IGNORE+NUMBERS+'horizontal_alignment = 1\nvertical_alignment = 1\ntheme_override_colors/font_color = Color(.11,.17,.21,1)\ntheme_override_constants/shadow_offset_y = 0\ntheme_override_styles/normal = ExtResource("keycap_style")\n'+props,16)
    def glass(name,parent,material,props):
        node(name,'Control',parent,props,True)
        path=parent+'/'+name
        node('Shadow','Panel',path,FULL+IGNORE+'theme_override_styles/panel = ExtResource("glass_frame_style")')
        node('Glass','ColorRect',path,FULL+IGNORE+f'material = SubResource("glass_{material}")')
        node('Margin','MarginContainer',path,FULL+'theme_override_constants/margin_left = 16\ntheme_override_constants/margin_right = 16\ntheme_override_constants/margin_top = 16\ntheme_override_constants/margin_bottom = 16')
        node('Rows','VBoxContainer',path+'/Margin','layout_mode = 2\ntheme_override_constants/separation = 12')
        return path+'/Margin/Rows'
    return art,keycap,glass


def hud(node,label,button,lines):
    art,keycap,_=layout_helpers(node,label)
    node('HudLayout','Control','Root',IGNORE+'offset_right = 1600.0\noffset_bottom = 900.0',True)
    node('Dock','Control','Root/HudLayout','anchor_top = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_top = -205.0\noffset_bottom = -35.0\nmouse_filter = 2\nvisible = false',True)
    base='Root/HudLayout/Dock'
    node('Rows','Control',base,FULL+IGNORE)
    node('Actions','HBoxContainer',base+'/Rows','anchor_left = .5\nanchor_right = .5\noffset_left = -40.0\noffset_right = 500.0\noffset_bottom = 38.0\ntheme_override_constants/separation = 10')
    for name,title in [('Control','操控英雄 F5'),('Reload','换弹 R'),('Edit','编辑形象'),('Run','开始交战')]:
        button(name,base+'/Rows/Actions',title,'theme_override_font_sizes/font_size = 15')
    node('Vitals','Control',base+'/Rows','offset_left = 48.0\noffset_right = 318.0\noffset_top = 75.0\noffset_bottom = 157.0\nmouse_filter = 2',True)
    vitals=base+'/Rows/Vitals'
    label('HeroName',vitals,'远行者',BOLD+IGNORE+'offset_top = 0.0\noffset_right = 260.0',20)
    node('HealthMeter','ProgressBar',vitals,'offset_left = 0.0\noffset_top = 35.0\noffset_right = 260.0\noffset_bottom = 65.0\nmax_value = 200\nvalue = 200\nshow_percentage = false\ntheme_override_styles/background = ExtResource("health_track_style")\ntheme_override_styles/fill = ExtResource("health_fill_style")\nmouse_filter = 2',True)
    art('Heart',vitals,'ExtResource("health_heart")','offset_left = -11.0\noffset_right = 29.0\noffset_top = 30.0\noffset_bottom = 70.0')
    label('Health',vitals,'200 / 200',NUMBERS+IGNORE+'offset_left = 27.0\noffset_right = 245.0\noffset_top = 35.0\noffset_bottom = 65.0\nhorizontal_alignment = 1\nvertical_alignment = 1',20)
    label('Armor',vitals,'护甲  3 / 3',MUTED+IGNORE+'offset_top = 68.0\noffset_right = 260.0',13)
    node('Boost','Control',base+'/Rows','offset_left = 342.0\noffset_right = 414.0\noffset_top = 87.0\noffset_bottom = 159.0\nvisible = false\nmouse_filter = 2',True)
    art('Boot',base+'/Rows/Boost','ExtResource("speed_boot")','offset_right = 56.0\noffset_bottom = 50.0')
    label('BoostTime',base+'/Rows/Boost','+20% · 10s',NUMBERS+'offset_top = 49.0\noffset_right = 76.0\ntheme_override_colors/font_color = Color(.59,.9,1,1)',14)
    node('Loadout','HBoxContainer',base+'/Rows','anchor_left = .5\nanchor_right = .5\noffset_left = -238.0\noffset_right = 490.0\noffset_top = 65.0\noffset_bottom = 146.0\nalignment = 1\ntheme_override_constants/separation = 22',True)
    row=base+'/Rows/Loadout'
    button('WeaponCard',row,'','custom_minimum_size = Vector2(132,82)\ntheme_override_styles/normal = ExtResource("weapon_style")\ntheme_override_styles/hover = ExtResource("weapon_style")\ntheme_override_styles/focus = ExtResource("weapon_style")\ntooltip_text = "连发火枪 · R 换弹"\nmetadata/ui_motion_hover_scale = 1.0')
    art('WeaponArt',row+'/WeaponCard','SubResource("weapon_icon")',FULL+'offset_left = 3.0\noffset_right = -3.0\noffset_top = -3.0\noffset_bottom = -13.0')
    label('WeaponTitle',row+'/WeaponCard','连发火枪',IGNORE+BOLD+'anchor_top = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_top = -23.0\nhorizontal_alignment = 1',13)
    label('Ammo',row+'/WeaponCard','10 / 10',NUMBERS+IGNORE+'anchor_left = .5\nanchor_right = .5\noffset_left = -44.0\noffset_right = 44.0\noffset_top = -27.0\noffset_bottom = -1.0\nhorizontal_alignment = 1\ntheme_override_styles/normal = ExtResource("chip_style")',20)
    node('ReloadMeter','ProgressBar',row+'/WeaponCard','anchor_top = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_left = 8.0\noffset_right = -8.0\noffset_top = -4.0\nmax_value = 1.0\nshow_percentage = false\nmouse_filter = 2\nvisible = false',True)
    keycap('WeaponKey',row+'/WeaponCard','R','anchor_left = .5\nanchor_right = .5\nanchor_top = 1.0\nanchor_bottom = 1.0\noffset_left = -12.0\noffset_right = 12.0\noffset_top = 6.0\noffset_bottom = 29.0')
    node('Hotbar','HBoxContainer',row,'layout_mode = 2\ntheme_override_constants/separation = 10',True)
    for i in range(5):
        lines.append(f'[node name="Slot{i}" parent="{row}/Hotbar" instance=ExtResource("item_slot")]\nlayout_mode = 2\ncustom_minimum_size = Vector2(78,82)\nslot_index = {i}\nis_shortcut = true')
    button('InventoryButton',row,'','custom_minimum_size = Vector2(78,82)\ntooltip_text = "背包 I"\nmetadata/ui_motion_hover_scale = 1.0')
    art('Icon',row+'/InventoryButton','ExtResource("bag_icon")',FULL+'offset_left = 6.0\noffset_right = -6.0\noffset_bottom = -18.0')
    label('InventoryLabel',row+'/InventoryButton','背包',IGNORE+BOLD+'anchor_top = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_top = -22.0\nhorizontal_alignment = 1',13)
    keycap('InventoryKey',row+'/InventoryButton','I','anchor_left = .5\nanchor_right = .5\nanchor_top = 1.0\nanchor_bottom = 1.0\noffset_left = -12.0\noffset_right = 12.0\noffset_top = 6.0\noffset_bottom = 29.0')


def inventory(node,label,button,lines):
    art,keycap,glass=layout_helpers(node,label)
    node('Inventory','ColorRect','Root',FULL+'color = Color(.025,.045,.085,.08)\nvisible = false',True)
    node('BackdropCopy','BackBufferCopy','Root/Inventory','copy_mode = 2')
    node('InventoryLayout','Control','Root/Inventory',IGNORE+'offset_right = 1600.0\noffset_bottom = 900.0',True)
    root='Root/Inventory/InventoryLayout'
    label('BagHeroName',root,'远行者',BOLD+'offset_left = 38.0\noffset_top = 44.0\noffset_right = 492.0',27)
    label('BagContext',root,'随身装备',MUTED+'offset_left = 38.0\noffset_top = 80.0',14)
    bag=glass('Left',root,'bag','offset_left = 32.0\noffset_right = 492.0\noffset_top = 108.0\noffset_bottom = 818.0')
    node('EquipmentHeader','PanelContainer',bag,'layout_mode = 2\ntheme_type_variation = &"HeroHeader"')
    label('EquipmentTitle',bag+'/EquipmentHeader','装备',BOLD,size=17)
    node('Equipment','HBoxContainer',bag,'layout_mode = 2\ntheme_override_constants/separation = 12')
    equip=bag+'/Equipment'
    button('EquippedWeapon',equip,'','custom_minimum_size = Vector2(184,98)\ntheme_override_styles/normal = ExtResource("weapon_style")\nmetadata/ui_motion_hover_scale = 1.0')
    art('Musket',equip+'/EquippedWeapon','SubResource("weapon_icon")',FULL+'offset_top = -8.0\noffset_bottom = -14.0')
    label('EquippedLabel',equip+'/EquippedWeapon','连发火枪',BOLD+IGNORE+'anchor_top = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_top = -25.0\nhorizontal_alignment = 1',14)
    node('BagEquipment','Panel',equip,'layout_mode = 2\ncustom_minimum_size = Vector2(86,98)\ntheme_override_styles/panel = ExtResource("header_style")')
    art('Bag',equip+'/BagEquipment','ExtResource("bag_icon")',FULL+'offset_bottom = -20.0')
    label('BagEquipmentTitle',equip+'/BagEquipment','随行背包',IGNORE+'anchor_top = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_top = -23.0\nhorizontal_alignment = 1',12)
    node('HeroSummary','VBoxContainer',equip,'layout_mode = 2\nsize_flags_horizontal = 3\nalignment = 1\ntheme_override_constants/separation = 7')
    label('BagArmor',equip+'/HeroSummary','护甲 3 / 3',NUMBERS,size=15)
    label('BagSpeed',equip+'/HeroSummary','移速 4.2',NUMBERS,size=15)
    label('BagHealth',equip+'/HeroSummary','200 / 200',NUMBERS+MUTED,size=15)
    node('BagHeading','PanelContainer',bag,'layout_mode = 2\ntheme_type_variation = &"HeroHeader"')
    node('Row','HBoxContainer',bag+'/BagHeading','layout_mode = 2')
    label('BagCapacity',bag+'/BagHeading/Row','背包  2 / 24',BOLD+'size_flags_horizontal = 3',18)
    button('SortInventory',bag+'/BagHeading/Row','整理','custom_minimum_size = Vector2(82,30)\ntheme_type_variation = &"HeroPrimary"\ntheme_override_font_sizes/font_size = 14')
    node('BagGrid','GridContainer',bag,'layout_mode = 2\ncolumns = 5\ntheme_override_constants/h_separation = 8\ntheme_override_constants/v_separation = 8',True)
    for i in range(24):
        lines.append(f'[node name="Slot{i}" parent="{bag}/BagGrid" instance=ExtResource("item_slot")]\nlayout_mode = 2\ncustom_minimum_size = Vector2(78,78)\nslot_index = {i}')
    label('BagHelp',bag,'拖动物品整理 · 拖入下方快捷位',MUTED+'size_flags_vertical = 3\nvertical_alignment = 2',13)
    detail=glass('Right',root,'detail','anchor_left = 1.0\nanchor_right = 1.0\noffset_left = -362.0\noffset_right = -32.0\noffset_top = 178.0\noffset_bottom = 722.0')
    node('DetailHeader','PanelContainer',detail,'layout_mode = 2\ntheme_type_variation = &"HeroHeader"')
    node('Row','HBoxContainer',detail+'/DetailHeader','layout_mode = 2')
    label('ItemKind',detail+'/DetailHeader/Row','恢复用品',MUTED+'size_flags_horizontal = 3',14)
    label('ItemStock',detail+'/DetailHeader/Row','持有 3',NUMBERS,size=14)
    art('ItemArt',detail,'ExtResource("health_heart")','layout_mode = 2\ncustom_minimum_size = Vector2(0,160)',True)
    label('ItemName',detail,'恢复药剂',BOLD,size=27)
    label('ItemDescription',detail,'恢复生命。','autowrap_mode = 2\ncustom_minimum_size = Vector2(0,50)\nsize_flags_vertical = 3',16)
    node('DetailStats','PanelContainer',detail,'layout_mode = 2\ntheme_override_styles/panel = ExtResource("header_style")')
    node('Rows','VBoxContainer',detail+'/DetailStats','layout_mode = 2\ntheme_override_constants/separation = 5')
    label('ItemEffect',detail+'/DetailStats/Rows','恢复 60 生命',BOLD,size=17)
    label('ItemCooldown',detail+'/DetailStats/Rows','冷却 10 秒',MUTED,size=14)
    button('UseItem',detail,'使用药剂','custom_minimum_size = Vector2(0,42)\ntheme_type_variation = &"HeroPrimary"')
    label('ItemFootnote',detail,'拖入快捷位，可在战斗中使用。',MUTED+'horizontal_alignment = 1',12)
    shortcut=glass('Shortcuts',root,'shortcuts','anchor_left = .5\nanchor_right = .5\nanchor_top = 1.0\nanchor_bottom = 1.0\noffset_left = -222.0\noffset_right = 270.0\noffset_top = -187.0\noffset_bottom = -42.0')
    label('BagShortcuts',shortcut,'快捷补给',BOLD+'horizontal_alignment = 1',17)
    node('BagHotbar','HBoxContainer',shortcut,'layout_mode = 2\nalignment = 1\ncustom_minimum_size = Vector2(0,78)\ntheme_override_constants/separation = 10',True)
    for i in range(5):
        lines.append(f'[node name="Slot{i}" parent="{shortcut}/BagHotbar" instance=ExtResource("item_slot")]\nlayout_mode = 2\ncustom_minimum_size = Vector2(78,78)\nslot_index = {i}\nis_shortcut = true')
    label('ShortcutHelp',root,'1–5 使用 · 右键解除绑定',MUTED+'anchor_left = .5\nanchor_right = .5\nanchor_top = 1.0\nanchor_bottom = 1.0\noffset_left = -222.0\noffset_right = 270.0\noffset_top = -29.0\nhorizontal_alignment = 1',13)
    button('CloseInventory',root,'返回   I / Esc','layout_mode = 0\nanchor_left = 1.0\nanchor_right = 1.0\noffset_left = -206.0\noffset_right = -32.0\noffset_top = 70.0\noffset_bottom = 112.0')
