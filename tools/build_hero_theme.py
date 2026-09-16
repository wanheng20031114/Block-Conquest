"""Author native translucent hero UI styles, isolated from the RTS theme."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'assets/ui/hero'


def flat(name,color,border='0.86,0.87,0.81,0.22',width=1,padding=10,radius=7):
    lines=['[gd_resource type="StyleBoxFlat" format=3]','[resource]',f'bg_color = Color({color})',f'border_color = Color({border})']
    for side in ['left','top','right','bottom']:
        lines += [f'border_width_{side} = {width}',f'content_margin_{side} = {float(padding)}']
    for corner in ['top_left','top_right','bottom_left','bottom_right']:
        lines += [f'corner_radius_{corner} = {radius}']
    (OUT/'styles'/f'{name}.tres').write_text('\n'.join(lines)+'\n',encoding='utf-8')


def build_theme():
    (OUT/'styles').mkdir(parents=True,exist_ok=True)
    flat('panel','0.065,0.078,0.085,0.74',padding=22,radius=12)
    flat('button','0.075,0.090,0.095,0.52',padding=9)
    flat('hover','0.25,0.29,0.28,0.78',border='0.90,0.87,0.71,0.85',padding=9)
    flat('selected','0.26,0.28,0.22,0.86',border='0.90,0.77,0.46,0.92',padding=9)
    flat('inset','0.035,0.045,0.052,0.48',padding=10)
    flat('popup','0.075,0.09,0.095,0.98',padding=12)
    flat('slot','0.08,0.095,0.10,0.40',border='0.90,0.91,0.84,0.50',padding=0)
    flat('slot_hover','0.31,0.34,0.28,0.65',border='0.99,0.89,0.59,0.95',padding=0)
    flat('keycap','0.94,0.94,0.87,0.95',width=0,padding=0,radius=3)
    flat('track','0.05,0.065,0.07,0.65',width=0,padding=0,radius=2)
    flat('fill','0.69,0.81,0.53,0.95',width=0,padding=0,radius=2)
    (OUT/'styles/empty.tres').write_text('[gd_resource type="StyleBoxEmpty" format=3]\n[resource]\n',encoding='utf-8')
    styles=['panel','button','hover','selected','inset','popup','slot','slot_hover','keycap','track','fill','empty']
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
