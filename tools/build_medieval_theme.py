"""Package the generated material atlas into native, editor-owned Godot theme resources.

Image work is deterministic crop/scale only; source alpha is preserved, never inferred
from RGB. The generated source atlas is kept beside its provenance for later art edits.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'assets/ui/medieval'

def write(path, text):
    target = BASE / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding='utf-8', newline='\n')

def texture_style(name, texture, margins, padding, tint='Color(1, 1, 1, 1)', center=True):
    lines = ['[gd_resource type="StyleBoxTexture" load_steps=2 format=3]', '',
             f'[ext_resource type="Texture2D" path="res://assets/ui/medieval/textures/{texture}.png" id="texture"]', '', '[resource]',
             'texture = ExtResource("texture")', 'modulate_color = ' + tint,
             'axis_stretch_horizontal = 0', 'axis_stretch_vertical = 0',
             'draw_center = ' + str(center).lower()]
    for side, value in zip(('left','top','right','bottom'), margins):
        lines.append(f'texture_margin_{side} = {value}.0')
    for side, value in zip(('left','top','right','bottom'), padding):
        lines.append(f'content_margin_{side} = {value}.0')
    write(f'styles/{name}.tres', '\n'.join(lines) + '\n')

def flat_style(name, color, border, widths=1, pad=(8,4,8,4)):
    lines = ['[gd_resource type="StyleBoxFlat" format=3]', '', '[resource]', f'bg_color = Color({color})',f'border_color = Color({border})']
    for side, value in zip(('left','top','right','bottom'),pad):
        lines += [f'content_margin_{side} = {value}.0',f'border_width_{side} = {widths}']
    for corner in ('top_left','top_right','bottom_left','bottom_right'):
        lines.append(f'corner_radius_{corner} = 6')
    write(f'styles/{name}.tres','\n'.join(lines)+'\n')

def main():
    atlases = {name: Image.open(BASE / f'source/{name}.png').convert('RGBA')
               for name in ('controls', 'panels')}
    pieces = {
        'strip': ('controls', (64,132,1475,237),700),
        'button': ('controls', (63,310,758,451),280),
        'primary': ('controls', (782,311,1475,451),280),
        'compact': ('controls', (63,535,507,647),176),
        'tab': ('controls', (550,535,991,647),176),
        'tab_idle': ('controls', (1032,535,1475,647),176),
        'ledge': ('controls', (63,732,1475,843),700),
        'sidebar': ('panels', (53,50,616,973),320),
        'card': ('panels', (674,51,1485,496),480),
        'map_frame': ('panels', (678,524,1485,972),480),
    }
    (BASE / 'textures').mkdir(parents=True, exist_ok=True)
    for name,(source,box,width) in pieces.items():
        piece = atlases[source].crop(box)
        piece = piece.resize((width, round(piece.height*width/piece.width)), Image.Resampling.LANCZOS)
        piece.save(BASE / 'textures' / (name+'.png'))
    # Each role has its own source proportions. Keep the illustrated corners fixed;
    # small controls must never inherit the large paper card's corner dimensions.
    texture_style('panel','card',(24,24,24,24),(24,20,24,20))
    texture_style('card','card',(24,24,24,24),(24,20,24,20))
    texture_style('panel_compact','card',(16,16,16,16),(16,10,16,10))
    texture_style('map_frame','map_frame',(28,28,28,28),(0,0,0,0),center=False)
    texture_style('parchment','card',(24,24,24,24),(28,24,28,24))
    texture_style('sidebar','sidebar',(65,72,72,70),(28,26,28,30))
    texture_style('strip','strip',(30,22,30,22),(36,10,36,10))
    texture_style('ledge','ledge',(34,16,34,16),(26,12,26,12))
    texture_style('button','button',(24,18,24,18),(26,7,26,7))
    texture_style('hover','button',(24,18,24,18),(26,7,26,7),'Color(1.04, 1.04, 1.02, 1)')
    texture_style('pressed','primary',(24,18,24,18),(26,7,26,7),'Color(1.10, 1.10, 1.10, 1)')
    texture_style('disabled','button',(24,18,24,18),(26,7,26,7),'Color(0.91, 0.93, 0.9, 0.85)')
    texture_style('primary','primary',(24,18,24,18),(28,9,28,9),'Color(1.10, 1.10, 1.10, 1)')
    texture_style('primary_hover','primary',(24,18,24,18),(28,9,28,9),'Color(1.15, 1.16, 1.13, 1)')
    texture_style('button_compact','compact',(20,14,20,14),(22,4,22,4))
    texture_style('compact_hover','compact',(20,14,20,14),(22,4,22,4),'Color(1.04, 1.04, 1.02, 1)')
    texture_style('compact_pressed','tab',(20,14,20,14),(22,4,22,4),'Color(1.12, 1.12, 1.12, 1)')
    texture_style('tab','tab',(20,14,20,14),(24,5,24,5),'Color(1.12, 1.12, 1.12, 1)')
    texture_style('tab_idle','tab_idle',(20,14,20,14),(24,5,24,5),'Color(1.16, 1.16, 1.16, 1)')
    flat_style('inset','0.94, 0.92, 0.85, 1','0.76, 0.79, 0.70, 0.8')
    flat_style('focus','0, 0, 0, 0','0.33, 0.53, 0.48, 0.75',2,(0,0,0,0))
    flat_style('selection','0.69, 0.79, 0.64, 0.95','0.54, 0.68, 0.56, 1',1,(8,5,8,5))
    flat_style('track','0.78, 0.81, 0.74, 1','0.65, 0.71, 0.64, 1',1,(0,2,0,2))
    flat_style('fill','0.49, 0.65, 0.56, 1','0.49, 0.65, 0.56, 1',1,(0,2,0,2))
    write('fonts/title.tres','[gd_resource type="FontVariation" load_steps=2 format=3]\n\n[ext_resource type="FontFile" path="res://assets/ui/medieval/fonts/ZCOOLKuaiLe-Regular.ttf" id="font"]\n\n[resource]\nbase_font = ExtResource("font")\nspacing_glyph = 1\n')
    write('fonts/body.tres','[gd_resource type="SystemFont" format=3]\n\n[resource]\nfont_names = PackedStringArray("Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC")\n')
    glyphs = {
        'arrow': '<path d="M5 7 L10 12 L15 7" fill="none" stroke="#435951" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
        'check': '<rect x="2" y="2" width="16" height="16" rx="5" fill="#91ab85"/><path d="M5 10 L9 14 L16 6" fill="none" stroke="#f7f2df" stroke-width="2.3" stroke-linecap="round"/>',
        'unchecked': '<rect x="2" y="2" width="16" height="16" rx="5" fill="#f3ecd8" stroke="#8b9f88"/>',
        'thumb': '<rect x="3" y="2" width="14" height="16" rx="6" fill="#e8d2ab" stroke="#ad9272"/><path d="M8 7 V13 M12 7 V13" stroke="#847c67" stroke-linecap="round"/>',
        'cross': '<path d="M5 5 L15 15 M15 5 L5 15" stroke="#52645f" stroke-width="2" stroke-linecap="round"/>',
    }
    for name,paths in glyphs.items():
        write('icons/'+name+'.svg','<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">'+paths+'</svg>\n')
    styles = ['panel','panel_compact','parchment','button','hover','pressed','disabled','primary','primary_hover','inset','focus','selection','track','fill','button_compact','compact_hover','compact_pressed','tab','tab_idle']
    lines = ['[gd_resource type="Theme" format=3]', '']
    for name in styles:
        lines.append(f'[ext_resource type="StyleBox" path="res://assets/ui/medieval/styles/{name}.tres" id="{name}"]')
    for name in ('title','body'):
        lines.append(f'[ext_resource type="Font" path="res://assets/ui/medieval/fonts/{name}.tres" id="{name}"]')
    for name in glyphs:
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/ui/medieval/icons/{name}.svg" id="{name}"]')
    lines += ['', '[resource]', 'default_font = ExtResource("body")', 'default_font_size = 18',
              'Label/colors/font_color = Color(0.22, 0.28, 0.27, 1)',
              'Label/colors/font_shadow_color = Color(0, 0, 0, 0)',
              'Label/constants/shadow_offset_x = 0',
              'Label/constants/shadow_offset_y = 0',
              'MedievalTitle/base_type = &"Label"', 'MedievalTitle/fonts/font = ExtResource("title")',
              'MedievalTitle/colors/font_color = Color(0.24, 0.35, 0.32, 1)',
              'MedievalTitle/font_sizes/font_size = 28',
              'MedievalPrimary/base_type = &"Button"',
              'MedievalPrimary/styles/normal = ExtResource("primary")',
              'MedievalPrimary/styles/hover = ExtResource("primary_hover")',
              'MedievalPrimary/styles/pressed = ExtResource("pressed")',
              'MedievalPrimary/fonts/font = ExtResource("title")',
              'MedievalPrimary/font_sizes/font_size = 23',
              'MedievalCompact/base_type = &"Button"',
              'MedievalCompact/styles/normal = ExtResource("button_compact")',
              'MedievalCompact/styles/hover = ExtResource("compact_hover")',
              'MedievalCompact/styles/pressed = ExtResource("compact_pressed")',
              'MedievalCompact/styles/hover_pressed = ExtResource("compact_pressed")',
              'MedievalCompact/styles/disabled = ExtResource("button_compact")',
              'MedievalCompact/font_sizes/font_size = 16',
              'MedievalTab/base_type = &"Button"',
              'MedievalTab/styles/normal = ExtResource("tab_idle")',
              'MedievalTab/styles/hover = ExtResource("tab")',
              'MedievalTab/styles/pressed = ExtResource("tab")',
              'MedievalTab/styles/hover_pressed = ExtResource("tab")']
    for kind in ('Button','OptionButton','MenuButton','CheckButton','CheckBox'):
        for state,style in [('normal','button'),('hover','hover'),('pressed','pressed'),('hover_pressed','pressed'),('disabled','disabled'),('focus','focus')]:
            lines.append(f'{kind}/styles/{state} = ExtResource("{style}")')
        for state,color in [('font_color','0.16, 0.23, 0.20, 1'),('font_hover_color','0.13, 0.20, 0.17, 1'),('font_pressed_color','0.13, 0.20, 0.17, 1'),('font_hover_pressed_color','0.13, 0.20, 0.17, 1'),('font_disabled_color','0.32, 0.38, 0.34, 1'),('font_focus_color','0.13, 0.20, 0.17, 1')]:
            lines.append(f'{kind}/colors/{state} = Color({color})')
    lines += ['OptionButton/icons/arrow = ExtResource("arrow")','OptionButton/constants/arrow_margin = 10']
    for kind in ('CheckBox','CheckButton'):
        for state,icon in [('checked','check'),('unchecked','unchecked'),('checked_disabled','check'),('unchecked_disabled','unchecked')]:
            lines.append(f'{kind}/icons/{state} = ExtResource("{icon}")')
    for kind in ('Panel','PanelContainer','PopupPanel','PopupMenu','Window'):
        lines.append(f'{kind}/styles/panel = ExtResource("panel")')
    lines += ['PopupMenu/styles/hover = ExtResource("selection")','PopupMenu/colors/font_color = Color(0.22,0.28,0.27,1)',
              'PopupMenu/colors/font_hover_color = Color(0.18,0.30,0.25,1)','PopupMenu/font_sizes/font_size = 17',
              'PopupMenu/colors/font_disabled_color = Color(0.32,0.38,0.34,1)',
              'PopupMenu/colors/font_accelerator_color = Color(0.28,0.35,0.30,1)',
              'PopupMenu/colors/font_separator_color = Color(0.28,0.35,0.30,1)',
              'TooltipPanel/styles/panel = ExtResource("panel_compact")','TooltipLabel/font_sizes/font_size = 16',
              'TooltipLabel/colors/font_color = Color(0.22,0.28,0.27,1)',
              'RichTextLabel/colors/default_color = Color(0.22,0.28,0.27,1)',
              'RichTextLabel/colors/font_selected_color = Color(0.13,0.20,0.17,1)',
              'RichTextLabel/colors/selection_color = Color(0.69,0.79,0.64,1)']
    for kind in ('LineEdit','TextEdit','ItemList','Tree'):
        lines += [f'{kind}/styles/normal = ExtResource("inset")',f'{kind}/styles/panel = ExtResource("inset")',
                  f'{kind}/styles/focus = ExtResource("focus")',f'{kind}/styles/read_only = ExtResource("inset")',
                  f'{kind}/colors/font_color = Color(0.22,0.28,0.27,1)',f'{kind}/colors/font_selected_color = Color(0.18,0.30,0.25,1)',
                  f'{kind}/colors/selection_color = Color(0.69,0.79,0.64,1)']
    lines += ['LineEdit/colors/caret_color = Color(0.25,0.4,0.35,1)',
              'LineEdit/colors/font_placeholder_color = Color(0.32,0.38,0.34,1)',
              'LineEdit/colors/font_uneditable_color = Color(0.32,0.38,0.34,1)',
              'TextEdit/colors/font_placeholder_color = Color(0.32,0.38,0.34,1)',
              'TextEdit/colors/font_readonly_color = Color(0.32,0.38,0.34,1)',
              'ItemList/styles/selected = ExtResource("selection")','ItemList/styles/selected_focus = ExtResource("selection")',
              'ItemList/styles/hovered = ExtResource("selection")',
              'ItemList/styles/hovered_selected = ExtResource("selection")',
              'ItemList/styles/hovered_selected_focus = ExtResource("selection")',
              'ItemList/colors/font_hovered_color = Color(0.13,0.20,0.17,1)',
              'ItemList/colors/font_hovered_selected_color = Color(0.13,0.20,0.17,1)',
              'Tree/styles/selected = ExtResource("selection")',
              'Tree/styles/selected_focus = ExtResource("selection")',
              'Tree/styles/hovered = ExtResource("selection")',
              'Tree/styles/hovered_dimmed = ExtResource("inset")',
              'Tree/styles/hovered_selected = ExtResource("selection")',
              'Tree/styles/hovered_selected_focus = ExtResource("selection")',
              'Tree/colors/font_hovered_color = Color(0.13,0.20,0.17,1)',
              'Tree/colors/font_hovered_selected_color = Color(0.13,0.20,0.17,1)',
              'Tree/colors/font_hovered_dimmed_color = Color(0.28,0.35,0.30,1)',
              'Tree/colors/font_disabled_color = Color(0.32,0.38,0.34,1)',
              'Tree/colors/custom_button_font_highlight = Color(0.13,0.20,0.17,1)',
              'ProgressBar/colors/font_color = Color(0.13,0.20,0.17,1)',
              'ProgressBar/constants/outline_size = 0',
              'ProgressBar/styles/background = ExtResource("track")','ProgressBar/styles/fill = ExtResource("fill")']
    for kind in ('HSlider','VSlider'):
        lines += [f'{kind}/styles/slider = ExtResource("track")',f'{kind}/styles/grabber_area = ExtResource("fill")',
                  f'{kind}/styles/grabber_area_highlight = ExtResource("fill")']
        for state in ('grabber','grabber_highlight','grabber_disabled'):
            lines.append(f'{kind}/icons/{state} = ExtResource("thumb")')
    for kind in ('HScrollBar','VScrollBar'):
        lines += [f'{kind}/styles/scroll = ExtResource("track")',f'{kind}/styles/grabber = ExtResource("fill")',
                  f'{kind}/styles/grabber_highlight = ExtResource("fill")',f'{kind}/styles/grabber_pressed = ExtResource("fill")']
    for kind in ('TabBar','TabContainer'):
        lines += [f'{kind}/styles/tab_selected = ExtResource("pressed")',f'{kind}/styles/tab_unselected = ExtResource("button")',
                  f'{kind}/styles/tab_hovered = ExtResource("hover")',f'{kind}/styles/panel = ExtResource("panel")',
                  f'{kind}/styles/tab_disabled = ExtResource("disabled")',f'{kind}/styles/tab_focus = ExtResource("focus")',
                  f'{kind}/colors/font_selected_color = Color(0.13,0.20,0.17,1)',
                  f'{kind}/colors/font_hovered_color = Color(0.13,0.20,0.17,1)',
                  f'{kind}/colors/font_unselected_color = Color(0.22,0.28,0.27,1)',
                  f'{kind}/colors/font_disabled_color = Color(0.32,0.38,0.34,1)']
    for state in ('font_color','font_hover_color','font_focus_color','font_pressed_color'):
        lines.append(f'LinkButton/colors/{state} = Color(0.13,0.20,0.17,1)')
    lines += ['VBoxContainer/constants/separation = 10','HBoxContainer/constants/separation = 12']
    write('theme.tres','\n'.join(lines)+'\n')
    print('Medieval theme:',len(pieces),'generated material crops; shared native Theme and StyleBox resources')

if __name__ == '__main__':
    main()
