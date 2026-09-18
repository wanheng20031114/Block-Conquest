"""Offline authoring for the standalone MOBA test1 scene, deck and interface.

Only writes this mode's resources; reused forest models and legacy UI stay intact.
The result is editable native Godot scenes, never a runtime node generator.
"""
from pathlib import Path
import math, random, json, re
from build_rogue_forest import Mesh

ROOT = Path(__file__).resolve().parents[1]
def write(rel, text):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + '\n', encoding='utf-8', newline='\n')
def q(text): return json.dumps(text, ensure_ascii=False)
def color(value, alpha=1):
    value=value.lstrip('#')
    return 'Color('+', '.join(str(round(int(value[i:i+2],16)/255,5)) for i in (0,2,4))+f', {alpha})'

CARDS=[
 ('spears','长矛方阵','spearman',4,120,'反骑兵','58a779'),
 ('archers','弓箭小队','archer',4,140,'远程压制','258fbd'),
 ('swords','剑士小队','swordsman',3,145,'近战推进','58a779'),
 ('guards','盾卫前列','shield_guard',2,155,'重甲前排','537f9c'),
 ('crossbows','弩手小队','crossbowman',3,180,'快速穿甲','258fbd'),
 ('muskets','火枪小队','musketeer',2,210,'远程重击','258fbd'),
 ('knights','骑士突击','knight',2,225,'反远程步兵','b188bd'),
 ('scouts','轻骑巡队','light_cavalry',3,180,'快速包抄','b188bd'),
 ('elephant','战象援军','war_elephant',1,300,'厚重骑兵','b188bd'),
 ('cannon','火炮支援','cannon',1,255,'远程拆塔','ef952f')]
CARD_DETAILS = {
 'spears':'派出4名长矛兵。反制骑兵，保护后排。',
 'archers':'派出4名弓箭手。在前排掩护下持续射击。',
 'swords':'派出3名剑士。承接近战，稳步推进。',
 'guards':'派出2名盾卫。重甲前排，抵御远程火力。',
 'crossbows':'派出3名弩手。近距离快速射击，穿透部分护甲。',
 'muskets':'派出2名火枪手。高伤害穿甲射击，需要前排保护。',
 'knights':'派出2名骑士。切入后排，克制远程步兵。',
 'scouts':'派出3名轻骑兵。快速支援与追击。',
 'elephant':'派出1头战象。生命充足，但仍受反骑兵附伤克制。',
 'cannon':'派出1门加农炮。远距离攻击防御建筑，畏惧贴身。'
}
FORTS = {'headquarters':(2200,6,26,2,10), 'heavy_fortress':(2600,7,42,4.5,13), 'castle':(1800,5,20,3.4,12.5), 'cannon_tower':(850,4,30,2.4,11)}

def deck():
    for id,title,unit,count,cost,category,tint in CARDS:
        write(f'data/moba/cards/{id}.tres',f'''[gd_resource type="Resource" script_class="MobaCardDefinition" format=3]
[ext_resource type="Script" path="res://scripts/moba/card_definition.gd" id="script"]
[resource]
script = ExtResource("script")
id = &"{id}"
title = "{title}"
cost = {cost}
units = PackedStringArray({', '.join(q(unit) for _ in range(count))})
description = "{CARD_DETAILS[id]}"
category = "{category}"
color = {color(tint)}
''')
    lines=['[gd_resource type="Resource" script_class="MobaDeckDefinition" format=3]', '[ext_resource type="Script" path="res://scripts/moba/deck_definition.gd" id="script"]', '[ext_resource type="Script" path="res://scripts/moba/card_definition.gd" id="card_script"]']
    lines += [f'[ext_resource type="Resource" path="res://data/moba/cards/{row[0]}.tres" id="{row[0]}"]' for row in CARDS]
    lines += ['[resource]','script = ExtResource("script")','cards = Array[ExtResource("card_script")](['+', '.join(f'ExtResource("{row[0]}")' for row in CARDS)+'])','opening_hand = PackedStringArray("spears", "archers", "swords", "guards", "cannon")']
    write('data/moba/test1_deck.tres','\n'.join(lines)+'\n')
    for kind,(hp,armor,damage,cooldown,reach) in FORTS.items():
        content=(ROOT/f'data/buildings/{kind}.tres').read_text(encoding='utf-8')
        values={'hp':hp,'melee_armor':armor,'ranged_armor':armor,'damage':damage,'cooldown':cooldown,'range':reach,'produces':'PackedStringArray()'}
        if kind=='heavy_fortress': values['splash_radius']=1.8
        for key,value in values.items():
            if re.search(r'^'+key+r' = .+$',content,re.M): content=re.sub(r'^'+key+r' = .+$',key+' = '+str(value),content,flags=re.M)
            else: content+='\n'+key+' = '+str(value)+'\n'
        write(f'data/moba/buildings/{kind}.tres',content)

def landscape():
    rng=random.Random(71032)
    mesh=Mesh('ground_moba')
    for z in range(-28,28):
        for x in range(-100,100):
            # Two broad approach tracks around friendly strongholds join at midfield.
            mesh.tri((x,-.025,z),(x+1,-.025,z),(x+1,-.025,z+1),(.4,.5,.3))
            mesh.tri((x,-.025,z),(x+1,-.025,z+1),(x,-.025,z+1),(.4,.5,.3))
    # Shared edge colors blend dirt into grass without square path boundaries.
    for i in range(len(mesh.v)//3):
        x,_,z=mesh.v[i*3:i*3+3]
        ax=abs(x)
        t=min(1,max(0,(ax-12)/23))
        lane=10*t*t*(3-2*t)
        if ax>77: lane*=max(0,(94-ax)/17)
        distance=abs(abs(z)-lane)-2.6
        for a,b,r in [(-87,0,8),(87,0,8),(-61,0,8),(61,0,8),(-37,0,7),(37,0,7),(-15,-9,4.8),(-15,9,4.8),(15,-9,4.8),(15,9,4.8)]:
            distance=min(distance,math.hypot(x-a,z-b)-r)
        distance+=.45*math.sin(ax*.63)*math.sin(z*.57)+.2*math.sin(z*1.8+ax)
        t=min(1,max(0,(.8-distance)/1.7)); t=t*t*(3-2*t)
        variation=1+.022*math.sin(ax*.7+z*.5)
        mesh.c[i*4:i*4+4]=[variation*(grass*(1-t)+dirt*t) for grass,dirt in zip((.39,.51,.33),(.62,.55,.4))]+[1]
    write('.local/moba-test1/ground.json',json.dumps({'vertices':mesh.v,'normals':mesh.n,'colors':mesh.c,'uv':mesh.uv},separators=(',',':')))
    write('tools/bake_moba_ground.gd','''extends SceneTree
func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.local/moba-test1/ground.json"))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	for i: int in range(0, source.vertices.size(), 3):
		vertices.append(Vector3(source.vertices[i], source.vertices[i+1], source.vertices[i+2]))
		normals.append(Vector3(source.normals[i], source.normals[i+1], source.normals[i+2]))
	for i: int in range(0, source.colors.size(), 4): colors.append(Color(source.colors[i], source.colors[i+1], source.colors[i+2], 1))
	for i: int in range(0, source.uv.size(), 2): uv.append(Vector2(source.uv[i], source.uv[i+1]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, load("res://assets/models/environment/rogue_forest/ground_paint.tres"))
	var result := ResourceSaver.save(mesh, "res://assets/models/environment/moba/ground.res")
	print("MOBA_GROUND result=", result, " vertices=", vertices.size())
	quit(0 if result == OK else 1)
''')
    (ROOT/'assets/models/environment/moba').mkdir(parents=True,exist_ok=True)
    assets=['tree_oak','tree_birch','tree_pine','tree_aspen','moss_rock','canvas_tent','camp_supplies','fire_circle','split_fence','stump','fallen_log','waystone','grass','flowers','fern','bush','leaf_litter','pebbles']
    resources=[f'[ext_resource type="PackedScene" path="res://assets/models/environment/rogue_forest/{a}.tscn" id="{a}"]' for a in assets]
    resources+=['[ext_resource type="ArrayMesh" path="res://assets/models/environment/moba/ground.res" id="ground"]','[ext_resource type="NavigationMesh" path="res://scenes/moba/navigation.tres" id="nav"]']
    resources+=['[sub_resource type="BoxShape3D" id="floor"]\nsize = Vector3(200, 1, 56)', '[sub_resource type="CylinderShape3D" id="trunk"]\nradius = 0.38\nheight = 5.0', '[sub_resource type="CylinderShape3D" id="rock"]\nradius = 1.4\nheight = 2.8']
    nodes=['[node name="ForestFrontier" type="Node3D"]','[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]\nnavigation_mesh = ExtResource("nav")','[node name="Environment" type="Node3D" parent="."]','[node name="Ground" type="StaticBody3D" parent="Environment"]\ncollision_layer = 1\ncollision_mask = 0','[node name="Collision" type="CollisionShape3D" parent="Environment/Ground"]\nposition = Vector3(0, -0.5, 0)\nshape = SubResource("floor")','[node name="Mesh" type="MeshInstance3D" parent="Environment/Ground"]\nmesh = ExtResource("ground")','[node name="NaturalObstacles" type="Node3D" parent="Environment"]','[node name="Dressing" type="Node3D" parent="Environment"]']
    obstacles=[]
    serial=0
    def place(asset,x,z,scale=1,angle=0,solid=None):
        nonlocal serial
        serial+=1
        nodes.append(f'[node name="{asset}_{serial}" parent="Environment/Dressing" instance=ExtResource("{asset}")]\nposition = Vector3({x:.3f}, 0, {z:.3f})\nrotation = Vector3(0, {angle:.3f}, 0)\nscale = Vector3({scale:.3f},{scale:.3f},{scale:.3f})')
        if solid:
            radius=.38 if solid=='trunk' else 1.4
            obstacles.append((x,z,radius))
            nodes.append(f'[node name="Obstacle{serial}" type="StaticBody3D" parent="Environment/NaturalObstacles"]\nposition = Vector3({x:.3f},0,{z:.3f})\ncollision_layer = 128\ncollision_mask = 0')
            nodes.append(f'[node name="Shape" type="CollisionShape3D" parent="Environment/NaturalObstacles/Obstacle{serial}"]\nposition = Vector3(0,{2.5 if solid=="trunk" else 1.4},0)\nshape = SubResource("{solid}")')
    for x0 in range(3,99,4):
        for z0 in (-25,-21,21,25):
            if rng.random()<.2: continue
            x,z=x0+rng.uniform(-1,1),z0+rng.uniform(-.9,.9)
            for sign in (-1,1): place(rng.choice(assets[:4]),sign*x,z,rng.uniform(.73,1.03),rng.random()*6.28,'trunk')
    for sign in (-1,1):
        for x,z,asset in [(78,-17.8,'canvas_tent'),(82,-18,'camp_supplies'),(75,-18,'fire_circle'),(47,18,'moss_rock'),(52,19,'fallen_log'),(28,-18,'stump'),(6,19,'moss_rock'),(23,15,'waystone'),(89,17,'split_fence'),(85,17,'split_fence')]:
            place(asset,sign*x,z,.9,0 if sign<0 else math.pi,'rock' if asset in ['moss_rock','canvas_tent'] else None)
    # Understory is one native MultiMesh per shared mesh, with persisted buffers.
    for asset in ['grass','flowers','fern','bush','leaf_litter','pebbles']:
        transforms=[]
        for i in range(150 if asset=='grass' else 50):
            x,z=rng.uniform(-98,98),rng.choice([-1,1])*rng.uniform(14.5,27)
            if asset=='pebbles': z=rng.uniform(-13,13)
            s=rng.uniform(.55,1.0); a=rng.random()*math.tau
            c,sn=math.cos(a)*s,math.sin(a)*s
            transforms.extend((c,0,sn,x,0,s,0,0,-sn,0,c,z))
        rel=f'assets/models/environment/moba/{asset}.tres'
        write(rel,'[gd_resource type="MultiMesh" format=3]\n'+f'[ext_resource type="ArrayMesh" path="res://assets/models/environment/rogue_forest/{asset}.res" id="mesh"]\n[resource]\ntransform_format = 1\ninstance_count = {len(transforms)//12}\nmesh = ExtResource("mesh")\nbuffer = PackedFloat32Array('+','.join(f'{v:.5f}' for v in transforms)+')\n')
        resources.append(f'[ext_resource type="MultiMesh" path="res://{rel}" id="batch_{asset}"]')
        nodes.append(f'[node name="{asset}Batch" type="MultiMeshInstance3D" parent="Environment/Dressing"]\nmultimesh = ExtResource("batch_{asset}")\ncast_shadow = 0')
    verts=[]; polys=[]; lookup={}
    for z in range(-26,26):
        for x in range(-98,98):
            if any((x+.5-a)**2+(z+.5-b)**2<(r+1.15)**2 for a,b,r in obstacles): continue
            poly=[]
            for p in [(x,z),(x,z+1),(x+1,z+1),(x+1,z)]:
                if p not in lookup: lookup[p]=len(verts);verts.append((p[0],0,p[1]))
                poly.append(lookup[p])
            polys.append(poly)
    write('scenes/moba/navigation.tres','[gd_resource type="NavigationMesh" format=3]\n[resource]\nvertices = PackedVector3Array('+','.join(str(v) for p in verts for v in p)+')\npolygons = Array[PackedInt32Array](['+','.join('PackedInt32Array('+','.join(map(str,p))+')' for p in polys)+'])\nagent_radius = 1.15\ncell_size = 1.0\n')
    nodes.append('[node name="Spawns" type="Node3D" parent="."]')
    for side,sign in [('Left',-1),('Right',1)]:
        nodes.append(f'[node name="{side}" type="Node3D" parent="Spawns"]')
        for name,x,z in [('HQ',87,0),('Fortress',61,0),('Castle',37,0),('NorthTower',15,-9),('SouthTower',15,9)]:
            nodes.append(f'[node name="{name}" type="Marker3D" parent="Spawns/{side}"]\nposition = Vector3({sign*x},0,{z})')
    # Resources must precede all subresources in the serialized native scene.
    resources.sort(key=lambda line: line.startswith('[sub_resource'))
    write('scenes/moba/test1_map.tscn','[gd_scene format=3]\n'+'\n'.join(resources+nodes)+'\n')
    print('MOBA_MAP',len(obstacles),'obstacles',len(polys),'walkable source cells')

class Scene:
    def __init__(self): self.resources=[];self.nodes=[]
    def ext(self,kind,path,id): self.resources.append(f'[ext_resource type="{kind}" path="res://{path}" id="{id}"]')
    def node(self,name,kind,parent=None,rect=None,props='',anchor=None,instance=None,unique=False):
        line=f'[node name="{name}"'+(f' type="{kind}"' if not instance else '')+(f' parent="{parent}"' if parent is not None else '')+(f' instance=ExtResource("{instance}")' if instance else '')+']\n'
        if unique: line+='unique_name_in_owner = true\n'
        if anchor:
            ax,ay=anchor
            line+=f'anchor_left = {ax}\nanchor_right = {ax}\nanchor_top = {ay}\nanchor_bottom = {ay}\n'
        if rect:
            x,y,w,h=rect
            line+=f'offset_left = {x}\noffset_top = {y}\noffset_right = {x+w}\noffset_bottom = {y+h}\n'
        line+=props+'\n';self.nodes.append(line)
    def label(self,name,parent,text,rect,size=18,tint='344f5a',anchor=None):
        self.node(name,'Label',parent,rect,f'text = {q(text)}\nmouse_filter = 2\nvertical_alignment = 1\ntheme_override_font_sizes/font_size = {size}\ntheme_override_colors/font_color = {color(tint)}',anchor,unique=True)
    def button(self,name,parent,text,rect,anchor=None):
        self.node(name,'Button',parent,rect,f'text = {q(text)}\nfocus_mode = 0',anchor,unique=True)
    def save(self,path): write(path,'[gd_scene format=3]\n'+'\n'.join(self.resources+self.nodes)+'\n')

def theme():
    lines=['[gd_resource type="Theme" format=3]','[sub_resource type="SystemFont" id="font"]\nfont_names = PackedStringArray("Microsoft YaHei UI", "Noto Sans CJK SC")\nfont_weight = 600']
    for id,tint in [('panel','ffffff'),('normal','edf1f2'),('hover','d8ece0'),('pressed','afd4be'),('disabled','e8eaee'),('focus','e6f1eb'),('track','e6eaf0'),('fill','58a779'),('card','ffffff')]:
        lines.append(f'[sub_resource type="StyleBoxFlat" id="{id}"]\nbg_color = {color(tint,.98)}\ncorner_radius_top_left = 14\ncorner_radius_top_right = 14\ncorner_radius_bottom_left = 14\ncorner_radius_bottom_right = 14\ncontent_margin_left = 12.0\ncontent_margin_right = 12.0\ncontent_margin_top = 7.0\ncontent_margin_bottom = 7.0')
    lines+=['[resource]','default_font = SubResource("font")','default_font_size = 18','Label/colors/font_color = '+color('344f5a'),'Button/colors/font_color = '+color('344f5a'),'Button/colors/font_hover_color = '+color('244b39'),'Button/colors/font_pressed_color = '+color('244b39'),'Button/colors/font_disabled_color = '+color('96a0a5'),'Panel/styles/panel = SubResource("panel")','PanelContainer/styles/panel = SubResource("panel")','ProgressBar/styles/background = SubResource("track")','ProgressBar/styles/fill = SubResource("fill")']
    for id in ('normal','hover','pressed','disabled','focus'): lines.append(f'Button/styles/{id} = SubResource("{id}")')
    write('assets/ui/moba/theme.tres','\n'.join(lines)+'\n')

def card_scene():
    s=Scene();s.ext('Script','scripts/moba/card_widget.gd','script');s.ext('Theme','assets/ui/moba/theme.tres','theme')
    s.node('ArmyCard','Control',rect=(0,0,144,202),props='script = ExtResource("script")\ntheme = ExtResource("theme")\nmouse_filter = 0')
    s.node('Visual','Panel','.',(0,0,144,202),'mouse_filter = 2\npivot_offset = Vector2(72,202)',unique=True)
    s.node('Accent','ColorRect','Visual',(10,0,124,6),'mouse_filter = 2\ncolor = Color(0.34,0.65,0.47,1)',unique=True)
    s.label('Title','Visual','长矛方阵',(11,10,122,28),18)
    s.node('Portrait','TextureRect','Visual',(16,43,112,103),'mouse_filter = 2\nexpand_mode = 1\nstretch_mode = 5',unique=True)
    s.label('Category','Visual','反骑兵',(12,144,119,22),13,'71818b')
    s.label('Count','Visual','4 名',(12,172,70,22),16)
    s.label('Cost','Visual','120',(77,170,56,26),22,'e3912e')
    s.label('Key','Visual','1',(10,45,22,22),13,'71818b')
    s.label('Refill','Visual','补牌中',(17,68,120,85),18,'71818b')
    s.save('scenes/moba/card.tscn')

def hud_scene():
    s=Scene()
    for kind,path,id in [('Script','scripts/moba/hud.gd','script'),('Theme','assets/ui/moba/theme.tres','theme'),('PackedScene','scenes/moba/card.tscn','card'),('Script','scripts/moba/minimap.gd','minimap'),('Script','scripts/moba/card_drop.gd','drop'),('PackedScene','scenes/model_previews.tscn','portraits'),('PackedScene','scenes/hero/hero_portrait.tscn','hero_portrait'),('PackedScene','scenes/moba/weapon_view.tscn','weapon')]: s.ext(kind,path,id)
    s.node('Interface','Control',props='anchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\nmouse_filter = 2\nscript = ExtResource("script")\ntheme = ExtResource("theme")')
    s.node('ModelPreviews',None,'.',instance='portraits')
    s.node('HeroPortrait',None,'.',instance='hero_portrait')
    s.node('WeaponView',None,'.',instance='weapon')
    s.node('Layout','Control','.',(0,0,1600,900),'mouse_filter = 2',unique=True)
    s.node('Top','Panel','Layout',(24,20,1552,62),'anchor_right = 1.0\noffset_right = -24.0',unique=True)
    s.label('ModeTitle','Layout/Top','MOBA 卡牌',(18,8,180,27),24)
    s.label('ModeSubtitle','Layout/Top','TEST 1   /   林地防线',(20,36,200,18),12,'788991')
    s.label('OurBase','Layout/Top','我方大本营  2200',(265,9,250,23),17)
    s.node('OurHealth','ProgressBar','Layout/Top',(265,39,238,7),'show_percentage = false',unique=True)
    s.label('Clock','Layout/Top','00:00',(692,7,120,28),25)
    s.label('Wave','Layout/Top','下一波 8秒',(665,36,185,20),13,'788991')
    s.label('EnemyBase','Layout/Top','敌方大本营  2200',(895,9,250,23),17)
    s.node('EnemyHealth','ProgressBar','Layout/Top',(895,39,238,7),'show_percentage = false',unique=True)
    s.label('Gold','Layout/Top','金币  240',(-278,11,180,36),25,'d98e24',anchor=(1,0))
    s.button('Pause','Layout/Top','菜单',(-85,10,69,42),anchor=(1,0))
    s.label('Toast','Layout','',(440,94,950,36),18,'344f5a')
    s.node('MapPanel','Panel','Layout',(24,-217,310,193),anchor=(0,1),unique=True)
    s.label('MapTitle','Layout/MapPanel','林地防线',(16,10,210,24),18)
    s.label('ArmyCount','Layout/MapPanel','我方 0 · 敌方 0',(16,40,278,24),13,'71818b')
    s.node('Minimap','Control','Layout/MapPanel',(16,73,278,78),'script = ExtResource("minimap")\nclip_contents = true',unique=True)
    s.label('MapHint','Layout/MapPanel','点击查看 · 右键移动英雄',(16,159,283,22),12,'71818b')
    s.node('Hand','Control','Layout',(-392,-226,784,202),'mouse_filter = 2',anchor=(.5,1),unique=True)
    for index in range(5): s.node(f'Card{index}',None,'Layout/Hand',(index*160,0,144,202),instance='card')
    s.label('HandHint','Layout','1—5 出牌  ·  双击或拖向战场  ·  所有援军从大本营出发',(-392,-250,800,21),13,'344f5a',anchor=(.5,1))
    s.node('HeroPanel','Panel','Layout',(-336,-237,312,213),anchor=(1,1),unique=True)
    s.node('Portrait','TextureRect','Layout/HeroPanel',(12,12,69,80),'mouse_filter = 2\nexpand_mode = 1\nstretch_mode = 5',unique=True)
    s.label('HeroName','Layout/HeroPanel','远行者',(90,12,206,28),20)
    s.node('HeroHealth','ProgressBar','Layout/HeroPanel',(90,47,202,13),'show_percentage = false',unique=True)
    s.label('HeroHP','Layout/HeroPanel','200 / 200',(90,61,190,23),14,'71818b')
    s.label('HeroStats','Layout/HeroPanel','近甲 3 · 远甲 3 · 无限弹药',(16,91,285,24),13,'71818b')
    s.button('Recovery','Layout/HeroPanel','E  肉体强化',(14,120,138,43))
    s.button('Morale','Layout/HeroPanel','R  士气昂扬',(160,120,138,43))
    s.button('FocusHero','Layout/HeroPanel','定位',(14,172,78,29))
    s.button('ViewMode','Layout/HeroPanel','F5  第一人称',(100,172,198,29))
    s.label('FPSHint','Layout','WASD 移动 · 左键射击 · E / R 技能 · Tab 鼠标 · F5 返回',(-430,99,930,32),16,'344f5a',anchor=(.5,0))
    s.node('DropZone','Control','Layout',(0,90,1600,550),'mouse_filter = 1\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_right = 0.0\noffset_bottom = -258.0\nscript = ExtResource("drop")',unique=True)
    s.node('DropHint','Panel','Layout/DropZone',(-250,55,500,66),'visible = false\nmouse_filter = 2',anchor=(.5,0),unique=True)
    s.label('DropText','Layout/DropZone/DropHint','松开：从大本营派出援军',(24,12,460,40),22,'438963')
    s.node('Crosshair','Label','Layout',(-10,-18,24,34),'text = "+"\nhorizontal_alignment = 1\nmouse_filter = 2\ntheme_override_colors/font_color = Color(1,1,1,1)\ntheme_override_colors/font_shadow_color = Color(0,0,0,1)\ntheme_override_constants/shadow_offset_x = 1\ntheme_override_constants/shadow_offset_y = 1\ntheme_override_font_sizes/font_size = 27\nvisible = false',anchor=(.5,.5),unique=True)
    s.node('Modal','ColorRect','Layout',props='anchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\ncolor = Color(0.15,0.24,0.28,0.45)\nvisible = false',unique=True)
    s.node('Dialog','Panel','Layout/Modal',(-210,-190,420,380),anchor=(.5,.5))
    s.label('DialogTitle','Layout/Modal/Dialog','对局暂停',(30,22,360,42),28)
    s.label('DialogDetail','Layout/Modal/Dialog','兵线、金币与技能计时已暂停',(30,70,360,58),15,'71818b')
    for i,(name,title) in enumerate([('Resume','继续对局'),('Restart','重新开始'),('Settings','设置'),('Back','返回主菜单')]): s.button(name,'Layout/Modal/Dialog',title,(30,140+i*54,360,43))
    s.save('scenes/moba/hud.tscn')

def weapon_view():
    # Reuse the actual weapon model and its established separate first-person viewport.
    src=(ROOT/'scenes/hero/hero_interface.tscn').read_text(encoding='utf-8')
    blocks=re.split(r'(?=\[)',src)
    wanted=['weapon_world','gun_texture','flash_mat','flash_mesh']
    resources=[b for b in blocks if any(b.startswith('[sub_resource ') and f'id="{id}"' in b.split('\n')[0] for id in wanted)]
    nodes=[]
    for block in blocks:
        header=block.split('\n')[0]
        if block.startswith('[node ') and ('name="WeaponViewport"' in header or 'parent="WeaponViewport' in header): nodes.append(block)
    s='[gd_scene format=3]\n[ext_resource type="PackedScene" path="res://assets/models/weapons/repeating_musket.tscn" id="weapon"]\n'+''.join(resources)
    s+='[node name="WeaponView" type="Control"]\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\nmouse_filter = 2\nvisible = false\n'+''.join(nodes)
    s+='[node name="Image" type="TextureRect" parent="."]\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\nmouse_filter = 2\ntexture = SubResource("gun_texture")\nexpand_mode = 1\nstretch_mode = 5\n'
    write('scenes/moba/weapon_view.tscn',s)

def battle_scene():
    src=(ROOT/'scenes/main.tscn').read_text(encoding='utf-8')
    src=re.sub(r'\[gd_scene[^\n]+','[gd_scene format=3]',src, count=1)
    src=src.replace('res://scripts/game.gd','res://scripts/moba/match.gd').replace('res://scenes/hud.tscn','res://scenes/moba/hud.tscn')
    new='''[ext_resource type="Script" path="res://scripts/moba/director.gd" id="director"]
[ext_resource type="Script" path="res://scripts/moba/status_effects.gd" id="statuses"]
[ext_resource type="Script" path="res://scripts/sandbox_visibility.gd" id="visibility"]
[ext_resource type="Script" path="res://scripts/moba/hero_controller.gd" id="hero_controller"]
[ext_resource type="Sky" path="res://assets/sky/clear_day.tres" id="day_sky"]
'''
    src=src.replace('[sub_resource type="ProceduralSkyMaterial"',new+'\n[sub_resource type="ProceduralSkyMaterial"',1)
    src=src.replace('sky = SubResource("sky")','sky = ExtResource("day_sky")').replace('fog_density = 0.0012','fog_density = 0.0004\nfog_sky_affect = 0.0')
    src=src.replace('position = Vector3(-29.698485,42,29.698485)','position = Vector3(0,46,36)').replace('rotation_degrees = Vector3(-45,-45,0)','rotation_degrees = Vector3(-52,0,0)').replace('size = 31.0','size = 40.0')
    src=src.replace('[node name="FogOfWar" parent="." instance=ExtResource("fog")]','[node name="FogOfWar" parent="." instance=ExtResource("fog")]\nscript = ExtResource("visibility")')
    src=src.replace('[node name="ContextCursor" parent="." instance=ExtResource("context_cursor")]','[node name="ContextCursor" parent="." instance=ExtResource("context_cursor")]\nprocess_mode = 4')
    src=src.replace('[node name="OrderPlanOverlay" parent="." instance=ExtResource("order_plan")]','[node name="OrderPlanOverlay" parent="." instance=ExtResource("order_plan")]\nprocess_mode = 4')
    src=src.replace('[node name="Vignette" type="ColorRect" parent="Atmosphere"]','[node name="Vignette" type="ColorRect" parent="Atmosphere"]\nvisible = false')
    src+='''
[node name="Director" type="Node" parent="."]
script = ExtResource("director")
[node name="StatusEffects" type="Node" parent="."]
script = ExtResource("statuses")
[node name="HeroController" type="Node3D" parent="."]
script = ExtResource("hero_controller")
process_physics_priority = -10
physics_interpolation_mode = 2
[node name="View" type="Node3D" parent="HeroController"]
[node name="Pitch" type="Node3D" parent="HeroController/View"]
[node name="Camera3D" type="Camera3D" parent="HeroController/View/Pitch"]
cull_mask = 786431
near = 0.06
far = 250.0
[node name="Listener" type="AudioListener3D" parent="HeroController/View/Pitch/Camera3D"]
'''
    write('scenes/moba/test1.tscn',src)

if __name__=='__main__':
    deck();landscape();theme();card_scene();weapon_view();hud_scene();battle_scene()
