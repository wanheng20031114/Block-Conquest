"""Author editable encounter scenes and one-metre navigation sources offline."""
from pathlib import Path
import math
import random

ROOT = Path(__file__).resolve().parents[1]
SCENES = ROOT / "scenes/rogue"
DATA = ROOT / "data/rogue/battles"
SCENES.mkdir(parents=True, exist_ok=True)
DATA.mkdir(parents=True, exist_ok=True)

def write(path, text):
    path.write_text(text, encoding="utf-8")

def nav(kind, width, depth, obstacles):
    verts, polygons, lookup = [], [], {}
    for z in range(-depth//2+2, depth//2-2):
        for x in range(-width//2 if kind=='outpost' else -width//2+2, width//2-2):
            if any((x+.5-ox)**2+(z+.5-oz)**2 < (radius+1.15)**2 for ox,oz,radius in obstacles):
                continue
            indices=[]
            for corner in [(x,z),(x,z+1),(x+1,z+1),(x+1,z)]:
                if corner not in lookup:
                    lookup[corner]=len(verts)
                    verts.append((corner[0],0,corner[1]))
                indices.append(lookup[corner])
            polygons.append(indices)
    text='[gd_resource type="NavigationMesh" format=3]\n\n[resource]\n'
    text+='vertices = PackedVector3Array('+', '.join(str(v) for p in verts for v in p)+')\n'
    text+='polygons = Array[PackedInt32Array](['+', '.join('PackedInt32Array('+', '.join(map(str,p))+')' for p in polygons)+'])\n'
    text+='agent_radius = 1.15\ncell_size = 1.0\ncell_height = 0.2\n'
    write(SCENES/f'battle_{kind}_navigation.tres',text)

def make_map(kind,width,depth):
    rng=random.Random(301 if kind=='outpost' else 303)
    foliage=[]
    for side in [-1,1]:
        for x in range(-width//2+3,width//2-2,4):
            foliage.append((x+rng.uniform(-1,1),side*(depth/2-2.5)+rng.uniform(-.5,.5),rng.uniform(.8,1.25)))
        for z in range(-depth//2+7,depth//2-4,5):
            if kind=='outpost' and side==-1 and abs(z)<17:
                continue
            foliage.append((side*(width/2-2.5),z,rng.uniform(.8,1.2)))
    for x,z in ([(-24,-23),(-21,-22),(-25,23),(-22,24),(23,-26),(25,-24),(23,24),(25,26)] if kind=='outpost' else [(-21,-21),(-24,-20),(22,-22),(24,-20),(-23,23),(-20,25),(23,23),(20,25)]):
        foliage.append((x,z,1.2))
    obstacles=[(x,z,.38*s) for x,z,s in foliage]
    nav(kind,width,depth,obstacles)
    text=f'''[gd_scene format=3]
[ext_resource type="NavigationMesh" path="res://scenes/rogue/battle_{kind}_navigation.tres" id="nav"]
[ext_resource type="PackedScene" path="res://assets/models/environment/tree_oak.tscn" id="oak"]
[ext_resource type="PackedScene" path="res://assets/models/environment/tree_pine.tscn" id="pine"]
[ext_resource type="PackedScene" path="res://assets/models/environment/campfire.tscn" id="fire"]
[ext_resource type="PackedScene" path="res://assets/models/environment/crate.tscn" id="crate"]
[sub_resource type="StandardMaterial3D" id="grass"]
albedo_color = Color(0.24, 0.31, 0.19, 1)
roughness = 1.0
[sub_resource type="StandardMaterial3D" id="path"]
albedo_color = Color(0.47, 0.40, 0.27, 1)
roughness = 1.0
[sub_resource type="BoxMesh" id="ground"]
size = Vector3({width}, 0.8, {depth})
material = SubResource("grass")
[sub_resource type="BoxShape3D" id="floor"]
size = Vector3({width}, 1, {depth})
[sub_resource type="CylinderShape3D" id="trunk"]
radius = 0.42
height = 4.0
[sub_resource type="BoxMesh" id="east_road"]
size = Vector3({width-6}, 0.025, 7)
material = SubResource("path")
[sub_resource type="BoxMesh" id="cross_road"]
size = Vector3(7, 0.025, {depth-6})
material = SubResource("path")
[node name="{kind.title()}" type="Node3D"]
metadata/map_id = "rogue_{kind}"
metadata/map_size = Vector2({width}, {depth})
[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]
navigation_mesh = ExtResource("nav")
[node name="Environment" type="Node3D" parent="."]
[node name="Ground" type="StaticBody3D" parent="Environment"]
collision_layer = 1
collision_mask = 0
[node name="CollisionShape3D" type="CollisionShape3D" parent="Environment/Ground"]
position = Vector3(0, -0.5, 0)
shape = SubResource("floor")
[node name="Mesh" type="MeshInstance3D" parent="Environment/Ground"]
position = Vector3(0, -0.4, 0)
mesh = SubResource("ground")
[node name="Road" type="MeshInstance3D" parent="Environment"]
mesh = SubResource("east_road")
position = Vector3(0, 0.018, 0)
[node name="CrossRoad" type="MeshInstance3D" parent="Environment"]
mesh = SubResource("cross_road")
position = Vector3({9 if kind=='outpost' else 0}, 0.023, 0)
[node name="NaturalObstacles" type="Node3D" parent="Environment"]
'''
    for i,(x,z,s) in enumerate(foliage):
        model='pine' if i%3 else 'oak'
        text+=f'''[node name="Tree{i}" type="StaticBody3D" parent="Environment/NaturalObstacles"]
position = Vector3({x:.3f}, 0, {z:.3f})
scale = Vector3({s:.3f}, {s:.3f}, {s:.3f})
collision_layer = 128
collision_mask = 0
[node name="CollisionShape3D" type="CollisionShape3D" parent="Environment/NaturalObstacles/Tree{i}"]
position = Vector3(0, 2, 0)
shape = SubResource("trunk")
[node name="Model" parent="Environment/NaturalObstacles/Tree{i}" instance=ExtResource("{model}")]
rotation = Vector3(0, {rng.random()*6.28:.3f}, 0)
'''
    text+='[node name="Buildings" type="Node3D" parent="."]\n'
    buildings=[('defense_tower',x,z) for x,z in [(-8,-15),(-8,15),(15,0),(36,-16),(36,16)]]+[('barracks',x,z) for x,z in [(9,-20),(9,20),(42,0)]] if kind=='outpost' else [('headquarters',0,0)]
    for i,(k,x,z) in enumerate(buildings):
        text+=f'[node name="Building{i}" type="Marker3D" parent="Buildings"]\nposition = Vector3({x}, 0, {z})\nmetadata/kind = "{k}"\n'
    text+='[node name="Defenders" type="Node3D" parent="."]\n'
    defenders=[('swordsman',-1,-14,False),('swordsman',-1,14,False),('swordsman',18,-8,False),('swordsman',18,8,False),('swordsman',36,-6,False),('swordsman',36,6,False),('archer',3,-17,False),('archer',3,17,False),('archer',29,-12,False),('archer',29,12,False),('spearman',6,-8,True),('spearman',8,-8,True),('archer',7,-10,True),('spearman',6,8,True),('spearman',8,8,True),('archer',7,10,True)] if kind=='outpost' else []
    for i,(k,x,z,search) in enumerate(defenders):
        text+=f'[node name="Defender{i}" type="Marker3D" parent="Defenders"]\nposition = Vector3({x}, 0, {z})\nmetadata/kind = "{k}"\nmetadata/search = {str(search).lower()}\n'
    text+='[node name="Entrances" type="Node3D" parent="."]\n'
    for name,x,z in [('West',-33,0),('North',0,-33),('East',33,0),('South',0,33)]:
        text+=f'[node name="{name}" type="Marker3D" parent="Entrances"]\nposition = Vector3({x}, 0, {z})\n'
    for i,(x,z) in enumerate([(-39,-10),(-39,10)] if kind=='outpost' else [(-8,-8),(8,8)]):
        text+=f'[node name="Camp{i}" parent="Environment" instance=ExtResource("fire")]\nposition = Vector3({x}, 0, {z})\n'
        text+=f'[node name="Crate{i}" parent="Environment" instance=ExtResource("crate")]\nposition = Vector3({x+2}, 0, {z+2})\n'
    write(SCENES/f'battle_{kind}_map.tscn',text)
    resource=f'''[gd_resource type="Resource" script_class="RogueBattleDefinition" format=3]
[ext_resource type="Script" path="res://scripts/rogue/rogue_battle_definition.gd" id="script"]
[ext_resource type="PackedScene" path="res://scenes/rogue/battle_{kind}_map.tscn" id="map"]
[resource]
script = ExtResource("script")
id = "{kind}"
title = "{'前哨站' if kind=='outpost' else '围剿'}"
difficulty = 1
emergency_hp_multiplier = 1.25
emergency_damage_multiplier = 1.15
size = Vector2({width}, {depth})
map_scene = ExtResource("map")
'''
    if kind=='siege':
        resource+='duration = 150.0\nenemy_cap = 24\nbase_hp = 1800.0\nbase_armor = 3.0\nbase_damage = 24.0\nbase_range = 10.0\nbase_cooldown = 2.0\n'
        units=[['swordsman']*2+['spearman']*2,['swordsman']*3+['archer']*2,['swordsman']*3+['spearman']+['archer']*2,['swordsman']*3+['shield_guard']+['archer']*2+['light_cavalry'],['swordsman']*3+['shield_guard']+['archer']*3+['light_cavalry'],['swordsman']*4+['shield_guard']+['archer']*2+['light_cavalry','catapult'],['swordsman']*4+['shield_guard']+['archer']*2+['light_cavalry','catapult']]
        resource+='waves = Array[Dictionary](['+', '.join('{"time": '+str(10+i*20)+', "units": ['+', '.join('"'+k+'"' for k in wave)+']}' for i,wave in enumerate(units))+'])\n'
    else:
        resource+='tower_hp = 360.0\ntower_armor = 2.0\ntower_damage = 9.0\ntower_range = 10.0\nbarracks_hp = 520.0\n'
        resource+='emergency_reinforcements = Array[Dictionary](['+', '.join('{"kind": "'+k+'", "position": Vector3('+str(x)+', 0, 7)}' for k,x in [('swordsman',24),('swordsman',26),('archer',28),('archer',30)])+'])\n'
    write(DATA/f'{kind}.tres',resource)

def battle_scene():
    text=(ROOT/'scenes/main.tscn').read_text(encoding='utf-8')
    text=text.replace('[gd_scene load_steps=37 format=3]','[gd_scene format=3]')
    text=text.replace('res://scripts/game.gd','res://scripts/rogue/rogue_battle.gd').replace('res://scenes/hud.tscn','res://scenes/rogue/battle_hud.tscn')
    text=text.replace('Color(0.62,0.52,0.35,1)','Color(0.43,0.49,0.32,1)')
    text=text.replace('position = Vector3(-29.698485,42,29.698485)','position = Vector3(0,46,39)').replace('rotation_degrees = Vector3(-45,-45,0)','rotation_degrees = Vector3(-50,0,0)')
    animations=''
    for kind,points in [('outpost',[(32,0,0),(-8,0,0),(-25,0,0)]),('siege',[(0,0,-12),(0,0,8),(0,0,0)])]:
        animations+=f'''[sub_resource type="Animation" id="intro_{kind}"]
resource_name = "{kind}"
length = 6.0
tracks/0/type = "value"
tracks/0/path = NodePath("CameraRig:position")
tracks/0/interp = 1
tracks/0/keys = {{"times": PackedFloat32Array(0, 3, 6), "transitions": PackedFloat32Array(1, 1, 1), "update": 0, "values": [{', '.join('Vector3('+', '.join(map(str,p))+')' for p in points)}]}}
tracks/1/type = "value"
tracks/1/path = NodePath("CameraRig/Camera3D:size")
tracks/1/keys = {{"times": PackedFloat32Array(0, 6), "transitions": PackedFloat32Array(1, 1), "update": 0, "values": [49.0, 39.0]}}
'''
    animations+='''[sub_resource type="AnimationLibrary" id="intros"]
_data = {"outpost": SubResource("intro_outpost"), "siege": SubResource("intro_siege")}
'''
    text=text.replace('[node name="积木争霸" type="Node3D"]',animations+'\n[node name="林间远征作战" type="Node3D"]')
    text+='\n[node name="Intro" type="AnimationPlayer" parent="."]\nlibraries = {&"": SubResource("intros")}\n'
    write(SCENES/'battle.tscn',text)

# battle_hud.tscn is an authored scene. Keep its shared material styles and layout
# under editor control; rebuilding world geometry must not replace the interface.

make_map('outpost',112,64)
make_map('siege',80,80)
battle_scene()
print('Authored two rogue maps, battle scene and balance resources; authored HUD preserved.')
