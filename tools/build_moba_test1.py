"""Offline authoring for the standalone MOBA test1 scene, deck and interface.

Only writes this mode's resources; reused forest models and legacy UI stay intact.
The result is editable native Godot scenes, never a runtime node generator.
"""
from pathlib import Path
import math, random, json, re
from build_moba_ground import build as build_ground

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
FORTS = {'headquarters':(4400,8,55,1.4,12), 'heavy_fortress':(5000,9,85,3.2,14), 'castle':(3400,7,40,2.3,13), 'cannon_tower':(1800,6,55,1.8,12)}

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
        if kind == 'cannon_tower':
            content = re.sub(r'^description = .+$', 'description = "厚石炮台上的回转重炮，炮弹溅射周围敌军。高耐久与范围火力镇守前线，需要防备远处的攻城器。"', content, flags=re.M)
        values={'hp':hp,'melee_armor':armor,'ranged_armor':armor,'damage':damage,'cooldown':cooldown,'range':reach,'produces':'PackedStringArray()'}
        values['model_yaw'] = math.pi if kind in ('castle', 'heavy_fortress') else 0.0
        values['weapon_rest_yaw'] = math.pi if kind == 'cannon_tower' else 0.0
        if kind != 'headquarters': values['splash_radius'] = {'heavy_fortress':2.8, 'castle':1.4, 'cannon_tower':1.6}[kind]
        for key,value in values.items():
            if re.search(r'^'+key+r' = .+$',content,re.M): content=re.sub(r'^'+key+r' = .+$',key+' = '+str(value),content,flags=re.M)
            else: content+='\n'+key+' = '+str(value)+'\n'
        write(f'data/moba/buildings/{kind}.tres',content)

def landscape():
    rng=random.Random(71032)
    (ROOT/'assets/models/environment/moba').mkdir(parents=True,exist_ok=True)
    assets=['tree_oak','tree_birch','tree_pine','tree_aspen','moss_rock','canvas_tent','camp_supplies','fire_circle','split_fence','stump','fallen_log','waystone','grass','flowers','fern','bush','leaf_litter','pebbles']
    resources=[f'[ext_resource type="PackedScene" path="res://assets/models/environment/rogue_forest/{a}.tscn" id="{a}"]' for a in assets]
    resources.append('[ext_resource type="PackedScene" path="res://scenes/moba/ground_details.tscn" id="ground_details"]')
    resources+=['[ext_resource type="ArrayMesh" path="res://assets/models/environment/moba/ground.res" id="ground"]','[ext_resource type="NavigationMesh" path="res://scenes/moba/navigation.tres" id="nav"]']
    resources+=['[sub_resource type="BoxShape3D" id="floor"]\nsize = Vector3(200, 1, 56)', '[sub_resource type="CylinderShape3D" id="trunk"]\nradius = 0.38\nheight = 5.0', '[sub_resource type="CylinderShape3D" id="rock"]\nradius = 1.4\nheight = 2.8']
    nodes=['[node name="ForestFrontier" type="Node3D"]','[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]\nnavigation_mesh = ExtResource("nav")','[node name="Environment" type="Node3D" parent="."]','[node name="Ground" type="StaticBody3D" parent="Environment"]\ncollision_layer = 1\ncollision_mask = 0','[node name="Collision" type="CollisionShape3D" parent="Environment/Ground"]\nposition = Vector3(0, -0.5, 0)\nshape = SubResource("floor")','[node name="Mesh" type="MeshInstance3D" parent="Environment/Ground"]\nmesh = ExtResource("ground")','[node name="NaturalObstacles" type="Node3D" parent="Environment"]','[node name="Dressing" type="Node3D" parent="Environment"]']
    nodes.append('[node name="SurfaceDetails" parent="Environment" instance=ExtResource("ground_details")]')
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
    build_ground()
    print('MOBA_MAP',len(obstacles),'obstacles',len(polys),'walkable source cells')

# UI has a separate authoring tool so visual revisions do not regenerate the map.
from build_moba_ui import build as build_ui


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
    src=src.replace('script = ExtResource("camera")', 'script = ExtResource("camera")\nkeyboard_pan = false')
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
    deck();landscape();build_ui();weapon_view();battle_scene()
