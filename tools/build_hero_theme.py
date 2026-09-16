"""Author native translucent hero UI styles, isolated from the RTS theme."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'assets/ui/hero'


def flat(name,color,border='0.69,0.79,0.88,0.20',width=1,padding=10,radius=9,shadow=0,shadow_color='0.015,0.025,0.045,0.45',shadow_y=0):
    lines=['[gd_resource type="StyleBoxFlat" format=3]','[resource]',f'bg_color = Color({color})',f'border_color = Color({border})']
    for side in ['left','top','right','bottom']:
        lines += [f'border_width_{side} = {width}',f'content_margin_{side} = {float(padding)}']
    for corner in ['top_left','top_right','bottom_left','bottom_right']:
        lines += [f'corner_radius_{corner} = {radius}']
    lines += [f'shadow_size = {shadow}',f'shadow_color = Color({shadow_color})',f'shadow_offset = Vector2(0,{shadow_y})','corner_detail = 8']
    (OUT/'styles'/f'{name}.tres').write_text('\n'.join(lines)+'\n',encoding='utf-8')


def build_theme():
    (OUT/'styles').mkdir(parents=True,exist_ok=True)
    flat('panel','0.10,0.16,0.23,0.88',padding=22,radius=14,shadow=12,shadow_y=4)
    flat('glass_frame','0,0,0,0',padding=0,radius=14,shadow=10,shadow_y=4)
    flat('header','0.025,0.055,0.095,0.88',width=0,padding=10,radius=9)
    flat('button','0.075,0.13,0.20,0.76',padding=9,shadow=3,shadow_y=2)
    flat('hover','0.20,0.33,0.43,0.9',border='0.70,0.89,1,0.85',padding=9)
    flat('selected','0.12,0.30,0.40,0.85',border='0.62,0.9,1,1',padding=9)
    flat('primary','0.82,0.95,1,1',border='0.52,0.84,1,1',padding=9,shadow=8,shadow_color='0.18,0.71,1,0.28')
    flat('primary_hover','0.97,1,1,1',border='0.7,0.94,1,1',padding=9,shadow=10,shadow_color='0.18,0.71,1,0.45')
    flat('inset','0.025,0.055,0.095,0.60',padding=10)
    flat('popup','0.065,0.115,0.18,0.98',padding=12,shadow=6)
    flat('slot','0.04,0.08,0.135,0.48',border='0.83,0.88,0.92,0.67',padding=0,radius=10)
    flat('slot_empty','0.025,0.06,0.105,0.40',border='0.67,0.76,0.86,0.32',padding=0,radius=10)
    flat('slot_hover','0.17,0.28,0.36,0.75',border='0.8,0.95,1,1',padding=0,radius=10,shadow=5,shadow_color='0.23,0.72,0.9,0.16')
    flat('slot_selected','0.12,0.26,0.34,0.72',border='0.67,0.93,1,1',width=2,padding=0,radius=10,shadow=6,shadow_color='0.3,0.79,1,0.22')
    flat('weapon','0.045,0.055,0.075,0.65',border='1,0.79,0.65,1',width=2,padding=0,radius=12,shadow=7,shadow_color='1,0.52,0.36,0.30')
    flat('keycap','0.91,0.95,0.97,1',border='0.54,0.63,0.70,1',width=1,padding=1,radius=5,shadow=2,shadow_y=2)
    flat('chip','0.02,0.04,0.07,0.9',width=0,padding=3,radius=5)
    flat('track','0.02,0.045,0.07,0.72',width=0,padding=0,radius=3)
    flat('fill','0.48,0.86,1,1',width=0,padding=0,radius=3)
    flat('health_track','0.20,0.025,0.055,0.95',border='0.04,0.025,0.04,0.95',width=3,padding=3,radius=17,shadow=4)
    flat('health_fill','1,0.27,0.31,1',border='1,0.58,0.58,1',width=2,padding=2,radius=14,shadow=4,shadow_color='0.95,0.16,0.24,0.35')
    (OUT/'font_bold.tres').write_text('[gd_resource type="SystemFont" format=3]\n[resource]\nfont_names = PackedStringArray("Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC")\nfont_weight = 700\n',encoding='utf-8')
    (OUT/'font_numbers.tres').write_text('[gd_resource type="SystemFont" format=3]\n[resource]\nfont_names = PackedStringArray("Bahnschrift", "Arial")\nfont_weight = 700\n',encoding='utf-8')
    (OUT/'styles/empty.tres').write_text('[gd_resource type="StyleBoxEmpty" format=3]\n[resource]\n',encoding='utf-8')
    styles=['panel','button','hover','selected','inset','popup','slot','slot_hover','keycap','track','fill','empty','header','primary','primary_hover','glass_frame','chip']
    lines=['[gd_resource type="Theme" format=3]',
           '[ext_resource type="Font" path="res://assets/ui/medieval/fonts/body.tres" id="font"]']
    for name in styles:
        lines.append(f'[ext_resource type="StyleBox" path="res://assets/ui/hero/styles/{name}.tres" id="{name}"]')
    lines += ['[resource]','default_font = ExtResource("font")','default_font_size = 17',
              'Label/colors/font_color = Color(0.96,0.95,0.88,1)',
              'Label/colors/font_shadow_color = Color(0.025,0.03,0.03,0.7)',
              'Label/constants/shadow_offset_y = 1','Label/constants/line_spacing = 2']
    for kind in ['Button','OptionButton','CheckBox','CheckButton']:
        for state,style in [('normal','button'),('hover','hover'),('pressed','selected'),('hover_pressed','selected'),('disabled','button'),('focus','hover')]:
            lines.append(f'{kind}/styles/{state} = ExtResource("{style}")')
        for state in ['font_color','font_hover_color','font_pressed_color','font_hover_pressed_color','font_focus_color']:
            lines.append(f'{kind}/colors/{state} = Color(0.96,0.95,0.88,1)')
        lines.append(f'{kind}/colors/font_disabled_color = Color(0.65,0.68,0.66,0.65)')
    lines += ['PanelContainer/styles/panel = ExtResource("panel")',
              'HeroHeader/base_type = &"PanelContainer"',
              'HeroHeader/styles/panel = ExtResource("header")',
              'HeroPrimary/base_type = &"Button"',
              'HeroPrimary/styles/normal = ExtResource("primary")',
              'HeroPrimary/styles/hover = ExtResource("primary_hover")',
              'HeroPrimary/styles/pressed = ExtResource("primary")',
              'HeroPrimary/colors/font_color = Color(0.12,0.29,0.38,1)',
              'HeroPrimary/colors/font_hover_color = Color(0.07,0.22,0.30,1)',
              'HeroPrimary/colors/font_pressed_color = Color(0.07,0.22,0.30,1)',
              'TabContainer/styles/panel = ExtResource("empty")',
              'TabContainer/styles/tab_selected = ExtResource("selected")',
              'TabContainer/styles/tab_unselected = ExtResource("button")',
              'TabContainer/styles/tab_hovered = ExtResource("hover")',
              'TabContainer/colors/font_selected_color = Color(0.96,0.95,0.88,1)',
              'TabContainer/colors/font_unselected_color = Color(0.70,0.75,0.72,1)',
              'TabContainer/constants/side_margin = 0',
              'PopupPanel/styles/panel = ExtResource("popup")',
              'PopupMenu/styles/panel = ExtResource("popup")',
              'PopupMenu/styles/hover = ExtResource("hover")',
              'PopupMenu/colors/font_color = Color(0.96,0.95,0.88,1)',
              'PopupMenu/colors/font_hover_color = Color(1,0.91,0.65,1)',
              'LineEdit/styles/normal = ExtResource("inset")',
              'LineEdit/styles/focus = ExtResource("hover")',
              'LineEdit/colors/font_color = Color(0.96,0.95,0.88,1)',
              'LineEdit/colors/caret_color = Color(0.96,0.95,0.88,1)',
              'LineEdit/colors/selection_color = Color(0.4,0.47,0.38,1)',
              'ProgressBar/styles/background = ExtResource("track")',
              'ProgressBar/styles/fill = ExtResource("fill")',
              'TooltipPanel/styles/panel = ExtResource("popup")',
              'TooltipLabel/colors/font_color = Color(0.96,0.95,0.88,1)',
              'TooltipLabel/font_sizes/font_size = 16',
              'VBoxContainer/constants/separation = 10','HBoxContainer/constants/separation = 12']
    (OUT/'theme.tres').write_text('\n'.join(lines)+'\n',encoding='utf-8')


if __name__=='__main__': build_theme()
