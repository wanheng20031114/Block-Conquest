"""Author the MOBA console as editable native Godot scenes, never at runtime.

Only UI resources are written. The generated icon sheet is an authored input.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def write(path, text):
    # Godot's text-resource Variant parser requires a leading zero in decimals.
    text = re.sub(r'(?<![\w.])(-?)\.(\d)', r'\g<1>0.\2', text)
    (ROOT / path).write_text(text.rstrip() + '\n', encoding='utf-8', newline='\n')


def color(hex_value, alpha=1):
    return 'Color(' + ', '.join(str(round(int(hex_value[i:i+2], 16) / 255, 5)) for i in (0, 2, 4)) + f', {alpha})'


def style(name, tint, radius=10, border=None, shadow=0, alpha=1):
    result = f'[sub_resource type="StyleBoxFlat" id="{name}"]\nbg_color = {color(tint, alpha)}\n'
    for corner in ['top_left', 'top_right', 'bottom_left', 'bottom_right']:
        result += f'corner_radius_{corner} = {radius}\n'
    x_margin, y_margin = (0.0, 0.0) if name in ('track', 'fill') else (10.0, 4.0)
    result += f'content_margin_left = {x_margin}\ncontent_margin_right = {x_margin}\ncontent_margin_top = {y_margin}\ncontent_margin_bottom = {y_margin}\n'
    if border:
        for side in ['left', 'top', 'right', 'bottom']:
            result += f'border_width_{side} = 1\n'
        result += f'border_color = {color(border)}\n'
    if shadow:
        result += f'shadow_color = Color(0.12, 0.22, 0.25, 0.13)\nshadow_size = {shadow}\nshadow_offset = Vector2(0, 3)\n'
    return result


class Scene:
    def __init__(self):
        self.resources = []
        self.nodes = []

    def ext(self, kind, path, name):
        self.resources.append(f'[ext_resource type="{kind}" path="res://{path}" id="{name}"]')

    def node(self, name, kind, parent=None, rect=None, props='', anchor=None, instance=None, unique=True):
        line = f'[node name="{name}"'
        if not instance:
            line += f' type="{kind}"'
        if parent is not None:
            line += f' parent="{parent}"'
        if instance:
            line += f' instance=ExtResource("{instance}")'
        line += ']\n'
        if unique:
            line += 'unique_name_in_owner = true\n'
        if anchor:
            ax, ay = anchor
            line += f'anchor_left = {ax}\nanchor_right = {ax}\nanchor_top = {ay}\nanchor_bottom = {ay}\n'
        if rect:
            x, y, w, h = rect
            line += f'offset_left = {x}\noffset_top = {y}\noffset_right = {x+w}\noffset_bottom = {y+h}\n'
        line += props + '\n'
        self.nodes.append(line)

    def label(self, name, parent, text, rect, size=16, tint='344f5a', anchor=None, extra=''):
        self.node(name, 'Label', parent, rect, 'text = ' + json.dumps(text, ensure_ascii=False) + f'\nmouse_filter = 2\nvertical_alignment = 1\ntheme_override_font_sizes/font_size = {size}\ntheme_override_colors/font_color = {color(tint)}\n' + extra, anchor)

    def icon(self, name, parent, resource, rect, props=''):
        self.node(name, 'TextureRect', parent, rect, f'texture = ExtResource("{resource}")\nmouse_filter = 2\nexpand_mode = 1\nstretch_mode = 5\n' + props)

    def panel(self, name, parent, rect, variation, anchor=None, extra=''):
        self.node(name, 'Panel', parent, rect, f'theme_type_variation = &"{variation}"\nmouse_filter = 2\n' + extra, anchor)

    def bar(self, name, parent, rect, extra=''):
        self.node(name, 'ProgressBar', parent, rect, 'show_percentage = false\nmouse_filter = 2\n' + extra)

    def animation(self, name, length, tracks):
        result = f'[sub_resource type="Animation" id="{name}"]\nresource_name = "{name}"\nlength = {length}\n'
        for index, (path, times, values) in enumerate(tracks):
            prefix = f'tracks/{index}'
            result += f'{prefix}/type = "value"\n{prefix}/path = NodePath("{path}")\n{prefix}/interp = 1\n{prefix}/enabled = true\n'
            result += f'{prefix}/keys = {{"times": PackedFloat32Array({", ".join(map(str,times))}), "transitions": PackedFloat32Array({", ".join(["1"]*len(times))}), "update": 0, "values": [{", ".join(values)}]}}\n'
        self.resources.append(result)

    def player(self, name, parent, animations, autoplay=''):
        library = name + '_library'
        self.resources.append(f'[sub_resource type="AnimationLibrary" id="{library}"]\n_data = {{' + ', '.join(f'&"{key}": SubResource("{key}")' for key in animations) + '}\n')
        self.node(name, 'AnimationPlayer', parent, props=f'libraries = {{&"": SubResource("{library}")}}\n' + (f'autoplay = "{autoplay}"' if autoplay else ''))

    def save(self, path):
        write(path, '[gd_scene format=3]\n' + '\n'.join(self.resources + self.nodes))


def theme():
    resources = ['[gd_resource type="Theme" format=3]', '[sub_resource type="SystemFont" id="font"]\nfont_names = PackedStringArray("Microsoft YaHei UI", "Noto Sans CJK SC")\nfont_weight = 600']
    for args in [('panel','f7fafb',14,'d7e1e4',3), ('console','f2f6f7',24,'ffffff',8),
                 ('card','ffffff',12,'ccdce1',4), ('art','edf5f4',8,None,0),
                 ('key','58a779',8,None,0), ('slot','e7eef0',12,'d5e1e5',0),
                 ('normal','f9fbfc',10,'d5e1e5',0), ('hover','e3f0e9',10,'87b9a0',1),
                 ('pressed','cee5d8',10,'75a78f',0), ('disabled','edf1f3',10,'dae3e7',0),
                 ('focus','e3f0e9',10,'58a779',1), ('track','dce6e9',4,None,0),
                 ('fill','58a779',4,None,0), ('inset','e8eff0',10,'d5e1e5',0),
                 ('coin','fbf3e3',10,None,0)]:
        resources.append(style(*args))
    items = ['[resource]', 'default_font = SubResource("font")', 'default_font_size = 16',
             'Label/colors/font_color = '+color('344f5a'), 'Button/colors/font_color = '+color('344f5a'),
             'Button/colors/font_hover_color = '+color('245c43'), 'Button/colors/font_pressed_color = '+color('245c43'),
             'Button/colors/font_disabled_color = '+color('85989f'), 'Panel/styles/panel = SubResource("panel")',
             'PanelContainer/styles/panel = SubResource("panel")', 'ProgressBar/styles/background = SubResource("track")',
             'ProgressBar/styles/fill = SubResource("fill")', 'TooltipLabel/colors/font_color = '+color('344f5a'),
             'TooltipLabel/font_sizes/font_size = 16', 'TooltipPanel/styles/panel = SubResource("panel")']
    for key in ['normal','hover','pressed','disabled','focus']:
        items.append(f'Button/styles/{key} = SubResource("{key}")')
    for name, key in [('Console','console'),('PaperCard','card'),('CardArt','art'),('Keycap','key'),('CardSlot','slot'),('Inset','inset'),('CoinBadge','coin')]:
        items += [f'{name}/base_type = &"Panel"', f'{name}/styles/panel = SubResource("{key}")']
    write('assets/ui/moba/theme.tres', '\n'.join(resources + items))


def card_scene():
    s = Scene()
    s.ext('Script', 'scripts/moba/card_widget.gd', 'script')
    s.ext('Theme', 'assets/ui/moba/theme.tres', 'theme')
    for icon in ['army', 'coin']:
        s.ext('Texture2D', f'assets/ui/moba/{icon}_icon.tres', icon)
    s.node('ArmyCard','Control',rect=(0,0,160,214),props='script = ExtResource("script")\ntheme = ExtResource("theme")\nmouse_filter = 0\nmouse_default_cursor_shape = 2')
    s.panel('Slot','.',(0,0,160,214),'CardSlot')
    s.node('Refill','Control','.',(0,0,160,214),'mouse_filter = 2\nvisible = false')
    s.icon('RefillIcon','Refill','army',(58,56,44,35),'modulate = Color(0.7,0.8,0.8,0.6)')
    s.label('RefillTitle','Refill','补充援军',(12,102,136,25),16,'6f8891',extra='horizontal_alignment = 1')
    s.label('RefillTime','Refill','1.5 秒',(12,132,136,23),14,'78919a',extra='horizontal_alignment = 1')
    s.bar('RefillProgress','Refill',(28,169,104,4))
    s.node('Lift','Control','.',(0,0,160,214),'mouse_filter = 2\npivot_offset = Vector2(80,214)')
    s.panel('Visual','Lift',(0,0,160,214),'PaperCard',extra='pivot_offset = Vector2(80,107)')
    p = 'Lift/Visual'
    s.panel('Art','Lift/Visual',(7,43,146,128),'CardArt')
    s.icon('Silhouette',p,'army',(85,80,58,49),'modulate = Color(1,1,1,0.055)')
    s.icon('Portrait',p,'army',(7,43,146,132))
    s.panel('Accent',p,(1,1,158,6),'Keycap')
    s.panel('KeyBadge',p,(1,1,34,38),'Keycap')
    s.label('Key',p,'1',(1,4,34,31),19,'ffffff',extra='horizontal_alignment = 1')
    s.label('Title',p,'长矛方阵',(43,9,109,23),17)
    s.label('Category',p,'反骑兵',(43,31,110,17),11,'76919a')
    s.node('Rule','ColorRect',p,(11,175,138,1),'color = Color(0.88,0.92,0.93,1)\nmouse_filter = 2')
    s.icon('ArmyIcon',p,'army',(13,185,19,17))
    s.label('Count',p,'×4',(36,181,38,27),18)
    s.panel('Price',p,(82,181,68,27),'CoinBadge')
    s.icon('Coin',p,'coin',(88,186,17,17))
    s.label('Cost',p,'120',(109,181,42,27),19,'b37a27')
    s.animation('enter',.34,[('Lift/Visual:position',[0,.22,.34],['Vector2(0,32)','Vector2(0,-3)','Vector2(0,0)']),('Lift/Visual:scale',[0,.22,.34],['Vector2(.93,.93)','Vector2(1.015,1.015)','Vector2(1,1)']),('Lift/Visual:modulate',[0,.16,.34],['Color(1,1,1,0)','Color(1,1,1,1)','Color(1,1,1,1)']),('Lift/Visual:rotation',[0,.34],['0.035','0.0'])])
    s.animation('dispatch',.25,[('Lift/Visual:position',[0,.09,.25],['Vector2(0,0)','Vector2(0,-24)','Vector2(0,-94)']),('Lift/Visual:scale',[0,.09,.25],['Vector2(1,1)','Vector2(1.035,1.035)','Vector2(.86,.86)']),('Lift/Visual:modulate',[0,.09,.25],['Color(1,1,1,1)','Color(1,1,1,1)','Color(1,1,1,0)']),('Lift/Visual:rotation',[0,.25],['0.0','-0.035'])])
    s.animation('reject',.24,[('Lift/Visual:position',[0,.045,.09,.15,.24],['Vector2(0,0)','Vector2(-5,0)','Vector2(5,0)','Vector2(-2,0)','Vector2(0,0)'])])
    s.player('Motion','.',['enter','dispatch','reject'])
    s.save('scenes/moba/card.tscn')
    p = Scene()
    p.ext('PackedScene','scenes/moba/card.tscn','card')
    p.node('CardDragPreview','Control',props='mouse_filter = 2')
    p.node('Card',None,'.',(-80,-196,160,214),'mouse_filter = 2',instance='card')
    p.save('scenes/moba/card_drag_preview.tscn')


def skill_scene():
    s = Scene()
    s.ext('Script','scripts/moba/skill_button.gd','script')
    s.ext('Texture2D','assets/ui/moba/recovery_icon.tres','icon')
    s.node('SkillButton','Button',rect=(0,0,146,86),props='script = ExtResource("script")\nfocus_mode = 0\nmouse_default_cursor_shape = 2')
    s.node('Content','Control','.',(0,0,146,86),'mouse_filter = 2\npivot_offset = Vector2(73,43)')
    s.icon('Icon','Content','icon',(12,10,25,27))
    s.label('Title','Content','肉体强化',(43,8,95,27),16)
    s.label('Detail','Content','25生命/秒 · 5秒',(12,37,127,20),11,'78919a')
    s.panel('Keycap','Content',(12,60,20,18),'Inset')
    s.label('Key','Content','E',(12,59,20,20),12,extra='horizontal_alignment = 1')
    s.label('Status','Content','可释放',(40,58,96,21),12,'548b6e')
    s.bar('Cooldown','Content',(12,80,122,3))
    s.animation('cast',.38,[('Content:scale',[0,.1,.24,.38],['Vector2(1,1)','Vector2(.96,.96)','Vector2(1.035,1.035)','Vector2(1,1)']),('Content:modulate',[0,.1,.38],['Color(1,1,1,1)','Color(.6,1,.78,1)','Color(1,1,1,1)'])])
    s.animation('ready',.45,[('Content:modulate',[0,.16,.45],['Color(1,1,1,1)','Color(.52,1,.7,1)','Color(1,1,1,1)'])])
    s.player('Motion','.',['cast','ready'])
    s.save('scenes/moba/skill_button.tscn')


def portraits_scene():
    # Camera framing is mode-local: codex and production portraits stay unchanged.
    s = Scene()
    s.ext('PackedScene','scenes/model_previews.tscn','base')
    s.node('ModelPreviews',None,instance='base',unique=False)
    for kind,size in [('swordsman',2.13),('shield_guard',2.35),('spearman',2.75),('archer',2.16),('crossbowman',2.16),('musketeer',2.5),('knight',3.05),('light_cavalry',2.75),('war_elephant',4.15),('cannon',2.95)]:
        s.nodes.append(f'[node name="Camera3D" parent="{kind}/World" index="5"]\nsize = {size}\n')
    s.save('scenes/moba/card_portraits.tscn')


def hud_scene():
    s = Scene()
    for kind,path,name in [('Script','scripts/moba/hud.gd','script'),('Theme','assets/ui/moba/theme.tres','theme'),('PackedScene','scenes/moba/card.tscn','card'),('PackedScene','scenes/moba/skill_button.tscn','skill'),('Script','scripts/moba/minimap.gd','minimap'),('Script','scripts/moba/card_drop.gd','drop'),('PackedScene','scenes/moba/card_portraits.tscn','portraits'),('PackedScene','scenes/hero/hero_portrait.tscn','hero_portrait'),('PackedScene','scenes/moba/weapon_view.tscn','weapon')]:
        s.ext(kind,path,name)
    for icon in ['forest','army','recovery','morale','focus','view','shield','coin']:
        s.ext('Texture2D',f'assets/ui/moba/{icon}_icon.tres',icon)
    s.node('Interface','Control',props='anchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\nmouse_filter = 2\nscript = ExtResource("script")\ntheme = ExtResource("theme")')
    for name,resource in [('ModelPreviews','portraits'),('HeroPortrait','hero_portrait'),('WeaponView','weapon')]:
        s.node(name,None,'.',instance=resource)
    s.node('Layout','Control','.',(0,0,1600,900),'mouse_filter = 2')
    s.panel('Top','Layout',(24,20,1552,62),'Panel',extra='anchor_right = 1.0\noffset_right = -24.0\nmouse_filter = 0')
    s.icon('ModeIcon','Layout/Top','army',(17,17,26,26))
    s.label('ModeTitle','Layout/Top','MOBA 卡牌',(53,6,180,30),23)
    s.label('ModeSubtitle','Layout/Top','TEST 1   /   林地防线',(55,36,200,18),11,'78919a')
    for x in [245,654,864,1224]:
        s.node('Divider'+str(x),'ColorRect','Layout/Top',(x,14,1,34),'color = Color(.83,.88,.9,1)\nmouse_filter = 2')
    s.label('OurBase','Layout/Top','我方大本营  4400',(267,9,330,23),17)
    s.bar('OurHealth','Layout/Top',(267,39,363,7))
    s.label('Clock','Layout/Top','00:00',(678,6,160,30),25,extra='horizontal_alignment = 1')
    s.label('Wave','Layout/Top','第 1 波 · 8.0 秒',(671,36,178,20),12,'78919a',extra='horizontal_alignment = 1')
    s.label('EnemyBase','Layout/Top','敌方大本营  4400',(886,9,290,23),17)
    s.bar('EnemyHealth','Layout/Top',(886,39,315,7))
    s.icon('GoldIcon','Layout/Top','coin',(1251,21,25,25))
    s.label('Gold','Layout/Top','240',(1285,10,125,38),25,'aa7124')
    s.node('Pause','Button','Layout/Top',(-100,11,82,40),'text = "菜单"\nfocus_mode = 0',anchor=(1,0))
    s.panel('ToastPanel','Layout',(-250,97,500,38),'Panel',anchor=(.5,0),extra='visible = false')
    s.label('Toast','Layout/ToastPanel','',(14,0,472,38),15,extra='horizontal_alignment = 1')
    # One continuous surface owns all bottom widgets and blocks battlefield input.
    s.node('ConsoleAnchor','Control','Layout',(0,-280,1600,280),'anchor_right = 1.0\noffset_right = 0.0\nmouse_filter = 2',anchor=(0,1))
    s.panel('Console','Layout/ConsoleAnchor',(0,0,1600,280),'Console',extra='anchor_right = 1.0\noffset_right = 0.0\nmouse_filter = 0')
    c = 'Layout/ConsoleAnchor/Console'
    s.node('LeftDivider','ColorRect',c,(340,20,1,240),'color = Color(.81,.87,.89,1)\nmouse_filter = 2')
    s.node('RightDivider','ColorRect',c,(-340,20,1,240),'color = Color(.81,.87,.89,1)\nmouse_filter = 2',anchor=(1,0))
    s.node('MapPanel','Control',c,(-318,16,294,249),'mouse_filter = 2',anchor=(1,0))
    m = c+'/MapPanel'
    s.icon('ForestIcon',m,'forest',(0,3,24,30))
    s.label('MapTitle',m,'林地防线',(36,1,174,32),21)
    s.node('SmallerHUD','Button',m,(218,0,32,32),'text = "−"\nfocus_mode = 0\ntooltip_text = "缩小底部面板（最低 70%）"')
    s.node('LargerHUD','Button',m,(258,0,32,32),'text = "+"\nfocus_mode = 0\ntooltip_text = "放大底部面板（最高 100%）"')
    s.label('ArmyCount',m,'我方 0 / 240  ·  敌方 0',(0,42,294,25),14,'6d858e')
    s.panel('MapFrame',m,(0,78,294,116),'Inset')
    s.node('Minimap','Control',m,(6,84,282,104),'script = ExtResource("minimap")\nclip_contents = true')
    s.icon('MapFocusIcon',m,'focus',(0,214,19,23))
    s.label('MapHint',m,'点击查看 · 右键移动英雄',(29,211,266,28),12,'728b95')
    s.node('HandHeading','Control',c,(-432,12,864,32),'mouse_filter = 2',anchor=(.5,0))
    h = c+'/HandHeading'
    s.icon('ArmyHeadingIcon',h,'army',(0,6,25,22))
    s.label('HandTitle',h,'援军部署',(37,0,120,33),21)
    s.label('HandHint',h,'从大本营出发',(163,3,160,27),13,'78919a')
    s.label('HandKeys',h,'1—5 出牌  /  双击或上拖',(625,3,239,27),12,'78919a',extra='horizontal_alignment = 2')
    s.node('Hand','Control',c,(-432,52,864,214),'mouse_filter = 2',anchor=(.5,0))
    for index in range(5):
        s.node('Card'+str(index),None,c+'/Hand',(index*176,0,160,214),instance='card',unique=False)
    s.node('HeroPanel','Control',c,(24,15,300,250),'mouse_filter = 2')
    p = c+'/HeroPanel'
    s.panel('PortraitWell',p,(0,1,72,86),'Inset')
    s.icon('Portrait',p,'army',(0,-3,76,93))
    s.label('HeroName',p,'远行者',(87,1,206,29),22)
    s.bar('HeroHealth',p,(88,39,205,10))
    s.label('HeroHP',p,'200 / 200',(88,51,205,23),14,'69818a')
    s.icon('ArmorIcon',p,'shield',(3,94,17,20))
    s.label('HeroStats',p,'近甲 3 · 远甲 3 · 无限弹药',(29,89,264,29),12,'6b8590')
    s.node('Recovery',None,p,(0,126,146,86),instance='skill',props='title = "肉体强化"\ndetail = "25生命/秒 · 5秒"\nhotkey = "E"\ncooldown_seconds = 20.0\nicon_texture = ExtResource("recovery")')
    s.node('Morale',None,p,(154,126,146,86),instance='skill',props='title = "士气昂扬"\ndetail = "范围移速 +25%"\nhotkey = "R"\ncooldown_seconds = 25.0\nicon_texture = ExtResource("morale")')
    s.node('FocusHero','Button',p,(0,220,92,29),'text = "跟随中"\nfocus_mode = 0\ntooltip_text = "Y 切换镜头跟随；空格定位英雄。\n中键拖动或点击小地图可自由观察。"\nicon = ExtResource("focus")\nexpand_icon = true\ntheme_override_constants/icon_max_width = 15')
    s.node('ViewMode','Button',p,(100,220,200,29),'text = "F5  第一人称"\nfocus_mode = 0\nicon = ExtResource("view")\nexpand_icon = true\ntheme_override_constants/icon_max_width = 21')
    s.label('FPSHint','Layout','WASD 移动 · 左键射击 · E / R 技能 · Tab 鼠标 · F5 返回',(-430,99,860,32),16,anchor=(.5,0),extra='horizontal_alignment = 1')
    s.node('DropZone','Control','Layout',(0,90,1600,520),'mouse_filter = 1\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_right = 0.0\noffset_bottom = -289.0\nscript = ExtResource("drop")')
    s.panel('DropHint','Layout/DropZone',(-236,63,472,54),'Panel',anchor=(.5,0),extra='visible = false\npivot_offset = Vector2(236,27)')
    s.icon('DropIcon','Layout/DropZone/DropHint','army',(18,14,30,25))
    s.label('DropText','Layout/DropZone/DropHint','松开：从大本营派出援军',(62,6,391,42),20,'3d8260')
    s.label('Crosshair','Layout','+',(-10,-18,24,34),27,'ffffff',anchor=(.5,.5),extra='horizontal_alignment = 1\nvisible = false\ntheme_override_colors/font_shadow_color = Color(0,0,0,1)\ntheme_override_constants/shadow_offset_x = 1\ntheme_override_constants/shadow_offset_y = 1')
    s.node('Modal','ColorRect','Layout',props='anchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\ncolor = Color(0.15,0.24,0.28,0.45)\nvisible = false\nz_index = 50')
    s.panel('Dialog','Layout/Modal',(-210,-240,420,480),'Panel',anchor=(.5,.5))
    s.label('DialogTitle','Layout/Modal/Dialog','对局暂停',(30,22,360,42),28)
    s.label('DialogDetail','Layout/Modal/Dialog','WASD 移动 · 左键射击 · 右键指挥\nE / R 技能 · Y 跟随 · H 原地待命',(30,70,360,58),15,'71818b')
    s.label('HUDScaleLabel','Layout/Modal/Dialog','底部面板 85%',(30,135,360,26),16)
    s.node('HUDScale','HSlider','Layout/Modal/Dialog',(30,172,360,28),'min_value = 70.0\nmax_value = 100.0\nstep = 5.0\nvalue = 85.0\nfocus_mode = 0')
    for index,(name,title) in enumerate([('Resume','继续对局'),('Restart','重新开始'),('Settings','设置'),('Back','返回主菜单')]):
        s.node(name,'Button','Layout/Modal/Dialog',(30,232+index*54,360,43),props=f'text = "{title}"\nfocus_mode = 0')
    s.animation('console_enter',.4,[('Layout/ConsoleAnchor/Console:position',[0,.28,.4],['Vector2(0,80)','Vector2(0,-2)','Vector2(0,0)']),('Layout/ConsoleAnchor/Console:modulate',[0,.24,.4],['Color(1,1,1,0)','Color(1,1,1,1)','Color(1,1,1,1)'])])
    s.player('Entrance','.',['console_enter'],'console_enter')
    s.save('scenes/moba/hud.tscn')


def build():
    theme()
    card_scene()
    skill_scene()
    portraits_scene()
    hud_scene()


if __name__ == '__main__':
    build()
