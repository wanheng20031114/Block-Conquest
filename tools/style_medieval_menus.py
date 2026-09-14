"""One-way theme migration for existing authored menu nodes; leaves 3D edits intact."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BASE = 'res://assets/ui/medieval/'

def blocks(text):
    return re.split(r'(?=^\[(?:node|sub_resource|ext_resource|connection) )',text,flags=re.M)

def ordered_resources(text):
    parts=blocks(text)
    count = 1 + sum(b.startswith(('[ext_resource ', '[sub_resource ')) for b in parts)
    header = re.sub(r'load_steps=\d+', f'load_steps={count}', parts[0])
    return header+''.join(b for b in parts[1:] if b.startswith('[ext_resource '))+''.join(b for b in parts[1:] if not b.startswith('[ext_resource '))

def prop(block,key,value):
    pattern = r'^'+re.escape(key)+r' = .*\n'
    if re.search(pattern,block,re.M):
        return re.sub(pattern,key+' = '+value+'\n',block,flags=re.M)
    return block.rstrip()+'\n'+key+' = '+value+'\n\n'

def lobby(text):
    text=text.replace('res://assets/ui/menu_theme.tres',BASE+'theme.tres')
    result=[]
    for block in blocks(text):
        if block.startswith('[sub_resource type="SystemFont" id="Bold"]'):
            block='[ext_resource type="Font" path="'+BASE+'fonts/title.tres" id="med_title"]\n\n'
        for old,new in [('Primary','primary'),('PrimaryHover','primary_hover'),('Pressed','pressed')]:
            if block.startswith(f'[sub_resource type="StyleBoxFlat" id="{old}"]'):
                block=f'[ext_resource type="StyleBox" path="{BASE}styles/{new}.tres" id="med_{old}"]\n\n'
        if block.startswith('[node '):
            name=re.search(r'name="([^"]+)"',block).group(1)
            if name=='Brand':
                block=prop(block,'offset_left','88.0')
                block=prop(block,'offset_top','126.0')
                block=prop(block,'offset_right','640.0')
            if name=='MainMenu':
                block=prop(block,'theme_override_constants/separation','10')
                block=prop(block,'offset_top','315.0')
            if name in ('Title','Brand','MapTitle','RoomTitle') and 'type="Label"' in block.splitlines()[0]:
                block=prop(block,'theme_override_fonts/font','ExtResource("med_title")')
            if 'parent="CanvasLayer/UI/MainMenu"' in block.splitlines()[0] and 'type="Button"' in block.splitlines()[0]:
                block=prop(block,'alignment','1')
                block=prop(block,'theme_override_fonts/font','ExtResource("med_title")')
                block=prop(block,'theme_override_font_sizes/font_size','25')
                block=block.replace('     →','')
            if 'type="Button"' in block.splitlines()[0]:
                block=re.sub(r'^theme_override_colors/font(?:_focus|_hover)?_color = Color\(0\.075[^\n]+\n','',block,flags=re.M)
            if name=='RogueMode':
                block=re.sub(r'^theme_override_colors/font_color = .*\n','',block,flags=re.M)
            if name=='SoloMenu':
                block=prop(block,'theme_type_variation','&"MedievalPrimary"')
            if name in ('Settings','QuitGame','CloseSolo','CloseOnline','CopyInvite','LeaveRoom') and 'type="Button"' in block.splitlines()[0]:
                block=prop(block,'theme_type_variation','&"MedievalCompact"')
            if 'type="Label"' in block.splitlines()[0]:
                if '/SoloPanel' in block.splitlines()[0] or '/OnlinePanel' in block.splitlines()[0]:
                    block=prop(block,'theme_override_colors/font_color','Color(0.23,0.30,0.28,1)')
                elif '/Brand' in block.splitlines()[0]:
                    block=prop(block,'theme_override_colors/font_color','Color(0.94,0.95,0.86,1)')
                elif name in ('ControlsHint','Version','Footer','Hint'):
                    block=prop(block,'theme_override_colors/font_color','Color(0.77,0.84,0.75,1)')
            if name=='Heraldry':
                continue
        result.append(block)
    text=''.join(result)
    for old,new in [('Bold','med_title'),('Primary','med_Primary'),('PrimaryHover','med_PrimaryHover'),('Pressed','med_Pressed')]:
        text=text.replace(f'SubResource("{old}")',f'ExtResource("{new}")')
    text=re.sub(r'^\[ext_resource[^\n]*id="med_crest"\]\n\n','',text,flags=re.M)
    text=text.replace('vec3(0.045,0.036,0.026)','vec3(0.10,0.18,0.17)')
    return ordered_resources(text)

def settings(text):
    text=text.replace('res://assets/ui/menu_theme.tres',BASE+'theme.tres')
    pos=text.index('[node ')
    if 'id="med_paper"' not in text:
        text=text[:pos]+f'[ext_resource type="StyleBox" path="{BASE}styles/parchment.tres" id="med_paper"]\n[ext_resource type="Font" path="{BASE}fonts/title.tres" id="med_title"]\n\n'+text[pos:]
    result=[]
    for block in blocks(text):
        if block.startswith('[node '):
            head=block.splitlines()[0]
            name=re.search(r'name="([^"]+)"',head).group(1)
            if 'name="Panel" type="PanelContainer"' in head:
                block=prop(block,'theme_override_styles/panel','ExtResource("med_paper")')
            if 'type="Label"' in head:
                block=prop(block,'theme_override_colors/font_color','Color(0.23,0.30,0.28,1)')
                block=prop(block,'theme_override_constants/shadow_offset_y','0')
                if name in ('Brand','SectionTitle','DisplayCountdown'):
                    block=prop(block,'theme_override_fonts/font','ExtResource("med_title")')
            if name=='Done':
                block=prop(block,'theme_type_variation','&"MedievalPrimary"')
            if 'parent="Menu/Center/Panel/Layout/Body/Categories"' in head and 'type="Button"' in head:
                block=prop(block,'alignment','1')
                block=prop(block,'theme_type_variation','&"MedievalTab"')
            elif name in ('Close','Reset','Cancel','Apply') and 'type="Button"' in head:
                block=prop(block,'theme_type_variation','&"MedievalCompact"')
        result.append(block)
    return ordered_resources(''.join(result))

if __name__=='__main__':
    for path,transform in [('scenes/lobby.tscn',lobby),('scenes/settings_menu.tscn',settings)]:
        file=ROOT/path
        file.write_text(transform(file.read_text(encoding='utf-8')),encoding='utf-8',newline='\n')
        print('Styled native scene:',path)
