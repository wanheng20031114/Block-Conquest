"""Build only the modular capsule hero and musket; never rewrite troop assets.

Geometry is baked offline. Native scene hierarchies and AnimationPlayers remain
editable in Godot. Run build_hero_meshes.gd afterwards to bake the part meshes.
"""
from pathlib import Path
import json
import math
import re
import numpy as np
import trimesh as tm
from build_units import box, ellipsoid, rod, lathe, ring, anim_resource, vec

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/heroes/capsule'
WEAPON = ROOT / 'assets/models/weapons/repeating_musket'
COLORS = {'cloth': (32, 133, 167, 26), 'face': (239, 214, 159, 51),
          'hand': (32, 133, 167, 77), 'boot': (87, 57, 39, 102),
          'team': (32, 133, 167, 230), 'leather': (112, 70, 38, 0),
          'gold': (196, 146, 61, 128), 'steel': (56, 65, 69, 128),
          'wood': (131, 79, 41, 0), 'black': (28, 31, 29, 0),
          'ivory': (237, 228, 192, 0)}
BODY_SECTIONS = 48
BODY_PROFILE = [(float(.77-.40*math.cos(t)), float(.405*math.sin(t)))
                for t in np.linspace(0, math.pi/2, 9)]
BODY_PROFILE += [(y,.405) for y in [1.05,1.40,1.75,2.05,2.28]]
BODY_PROFILE += [(float(2.28+.40*math.sin(t)), float(.405*math.cos(t)))
                 for t in np.linspace(0, math.pi/2, 9)[1:]]
EXPRESSIONS = ['Smile','Happy','Wink','Focused','Surprised','Sleepy']
ACCESSORIES = ['Hat','Beret','TrailHat','Backpack','Nose','Glasses','Scarf','Moustache','Feather']


def surface_z(x, y, offset=.007):
    """The front of the actual polygonal cylinder, including its rounded crown."""
    radius = np.interp(y, *np.array(BODY_PROFILE).T)
    angles = np.linspace(math.pi, math.tau, BODY_SECTIONS//2+1)
    return float(np.interp(x, radius*np.cos(angles), radius*np.sin(angles))-offset)


def face_patch(cx, cy, rx, ry, color='face', offset=.007, power=1.0, rings=8, segments=48):
    # Small conforming triangles cannot cut a chord through the cylinder like
    # the old single-centre fan. The same surface function positions features.
    vertices = [(cx,cy,surface_z(cx,cy,offset))]
    for band in range(1,rings+1):
        for i in range(segments):
            t = math.tau*i/segments
            x = cx+rx*(band/rings)*math.copysign(abs(math.cos(t))**power,math.cos(t))
            y = cy+ry*(band/rings)*math.copysign(abs(math.sin(t))**power,math.sin(t))
            vertices.append((x,y,surface_z(x,y,offset)))
    faces = [(0,i+1,(i+1)%segments+1) for i in range(segments)]
    for band in range(rings-1):
        for i in range(segments):
            a,b = 1+band*segments+i,1+band*segments+(i+1)%segments
            faces += [(a,a+segments,b+segments),(a,b+segments,b)]
    mesh = tm.Trimesh(vertices=vertices,faces=faces,process=False)
    if mesh.face_normals[:,2].mean()>0: mesh.invert()
    return mesh,color


def face_line(points, width=.007, offset=.013, color='black'):
    vertices=[]
    for index,(x,y) in enumerate(points):
        tangent=np.array(points[min(index+1,len(points)-1)])-points[max(0,index-1)]
        normal=np.array([-tangent[1],tangent[0]])/np.linalg.norm(tangent)*width
        for sign in [-1,1]:
            xx,yy=np.array([x,y])+normal*sign
            vertices.append((xx,yy,surface_z(xx,yy,offset)))
    faces=[]
    for i in range(len(points)-1):
        a=i*2
        faces += [(a,a+1,a+3),(a,a+3,a+2)]
    mesh=tm.Trimesh(vertices=vertices,faces=faces,process=False)
    if mesh.face_normals[:,2].mean()>0: mesh.invert()
    return mesh,color


def expression(style):
    pieces=[]
    for side in [-1,1]:
        x=side*.137
        if style=='Happy' or (style=='Wink' and side==1):
            pieces.append(face_line([(x+t,2.31+.042*math.sin(math.pi*(t+.046)/.092))
                                     for t in np.linspace(-.046,.046,13)],.009))
        elif style=='Sleepy':
            pieces.append(face_line([(x+t,2.325-.012*math.cos(t/.043*math.pi/2))
                                     for t in np.linspace(-.043,.043,11)],.008))
        else:
            pieces.append(face_patch(x,2.325,.028,.064,'black',.014,rings=3,segments=24))
        if style=='Focused':
            pieces.append(face_line([(x+t,2.422+side*t*.38) for t in np.linspace(-.055,.055,8)],.010))
    if style=='Surprised':
        pieces.append(face_patch(0,2.168,.027,.040,'black',.014,rings=3,segments=24))
    elif style=='Focused':
        pieces.append(face_line([(t,2.174) for t in np.linspace(-.035,.035,8)],.006))
    else:
        width=.068 if style=='Happy' else .045
        dip=.032 if style=='Happy' else .020
        pieces.append(face_line([(t,2.182-dip*math.cos(t/width*math.pi/2))
                                 for t in np.linspace(-width,width,15)],.006))
    return pieces


def save_part(folder, name, pieces):
    painted = []
    for mesh, color in pieces:
        rgb = np.array(COLORS[color][:3]) / 255
        linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
        rgba = np.append(linear * 255, COLORS[color][3]).astype(np.uint8)
        mesh.visual = tm.visual.ColorVisuals(mesh=mesh, vertex_colors=np.tile(rgba, (len(mesh.vertices), 1)))
        painted.append(mesh)
    mesh = tm.util.concatenate(painted)
    mesh.unmerge_vertices()
    color = mesh.visual.vertex_colors.copy()
    mesh.visual = tm.visual.TextureVisuals(material=tm.visual.material.PBRMaterial(
        name='HeroSurface', baseColorFactor=[255]*4, metallicFactor=0, roughnessFactor=.86, alphaMode='OPAQUE'))
    mesh.visual.vertex_attributes['color'] = color
    scene = tm.Scene(mesh)
    (folder / f'{name}.glb').write_bytes(scene.export(file_type='glb', include_normals=True))
    return len(mesh.faces)


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    WEAPON.mkdir(parents=True, exist_ok=True)
    parts = {'Body': [(lathe(BODY_PROFILE, BODY_SECTIONS, caps=False), 'cloth')]}
    parts['Face'] = [face_patch(0,2.285,.300,.278,power=.85,rings=12,segments=64)]
    for style in EXPRESSIONS: parts['Face'+style] = expression(style)
    parts['Belt'] = [(lathe([(1.04,.417),(1.13,.417)],48),'leather'),
                     (box((.15,.13,.06),(.20,1.085,-.379),bevel=.015),'gold'),
                     (box((.20,.28,.13),(-.35,.94,-.24),bevel=.03),'leather')]
    strap=[face_line([(x,1.54-x*.96) for x in np.linspace(-.345,.35,36)],.061,.035,'wood')]
    for x in [-.23,-.10,.03]:
        y=1.54-x*.96
        z=surface_z(x,y,.065)
        strap += [(rod((x-.034,y-.038,z),(x+.034,y+.038,z),.025,12),'gold'),
                  (rod((x-.05,y-.056,z),(x-.035,y-.039,z),.027,12),'leather')]
    parts['Bandolier']=strap
    parts['BackMark']=[(box((.26,.32,.027),(0,1.98,.411),bevel=.055),'team'),
                       (rod((-.05,1.92,.434),(.06,2.02,.434),.022,6),'ivory')]
    parts['Hat']=[(ellipsoid((.27,.12,.27),(0,2.62,.20),rot=(.42,0,.10),sub=2),'leather'),
                  (ring(.22,.022,(0,2.61,.20),rot=(math.pi/2+.42,0,.10),n=32,m=6),'wood'),
                  (box((.085,.06,.03),(-.16,2.66,.01),bevel=.014),'team')]
    parts['Beret']=[(ellipsoid((.36,.12,.34),(-.065,2.61,.10),rot=(.1,0,-.18),sub=2),'cloth'),
                    (lathe([(2.54,.26),(2.59,.28)],32,pos=(0,0,.12)),'leather'),
                    (ellipsoid((.07,.016,.07),(-.11,2.726,.10),sub=2),'gold')]
    parts['TrailHat']=[(ellipsoid((.49,.043,.45),(0,2.54,.10),rot=(.08,0,0),sub=2),'leather'),
                       (ellipsoid((.29,.19,.27),(0,2.61,.14),sub=2),'wood'),
                       (lathe([(2.58,.287),(2.63,.27)],32,pos=(0,0,.14)),'team')]
    parts['Backpack']=[(box((.47,.62,.22),(0,1.50,.42),bevel=.07),'leather'),
                       (box((.50,.20,.24),(0,1.74,.435),bevel=.035),'wood'),
                       (box((.08,.27,.03),(0,1.64,.571),bevel=.006),'gold')]
    parts['Nose']=[(ellipsoid((.05,.06,.10),(0,2.225,-.43),sub=2),'face')]
    glasses=[]
    for x in [-.137,.137]:
        glasses += [face_line([(x+.089*math.cos(t),2.325+.09*math.sin(t))
                               for t in np.linspace(0,math.tau,49)],.010,.025,'gold')]
    glasses += [face_line([(-.045,2.33),(0,2.347),(.045,2.33)],.009,.025,'gold')]
    parts['Glasses']=glasses
    parts['Scarf']=[(lathe([(1.87,.427),(1.97,.434),(2.01,.414)],48),'team'),
                    (box((.18,.41,.04),(.29,1.69,-.33),rot=(0,0,.14),bevel=.04),'team'),
                    (ellipsoid((.103,.084,.065),(.28,1.915,-.338),sub=2),'team')]
    parts['Moustache']=[face_line([(x,2.205-.022*math.sin(abs(x)/.09*math.pi))
                                  for x in np.linspace(-.095,.095,35)],.017,.019,'leather')]
    parts['Feather']=[(rod((-.19,2.61,.15),(-.36,2.99,.20),.012,10),'gold'),
                     (ellipsoid((.052,.21,.026),(-.28,2.83,.18),rot=(0,0,-.38),sub=2),'ivory')]
    parts['Arms']=[(ellipsoid((.14,.23,.15),(-.40,1.43,-.16),rot=(-.6,0,-.2),sub=2),'cloth'),
                   (rod((-.43,1.30,-.25),(.24,1.41,-.64),.097,16),'cloth'),
                   (ellipsoid((.14,.125,.15),(.27,1.41,-.64),sub=2),'hand'),
                   (ellipsoid((.14,.23,.15),(.43,1.44,-.08),rot=(-.25,0,.3),sub=2),'cloth'),
                   (rod((.47,1.29,-.16),(.34,1.42,-.20),.10,16),'cloth'),
                   (ellipsoid((.13,.12,.14),(.34,1.42,-.20),sub=2),'hand')]
    # The whole grip rotates about chest height; the independent gun and both
    # mittens share that pivot, so resting/reload poses preserve their contacts.
    for mesh,_color in parts['Arms']: mesh.apply_translation((0,-1.45,0))
    for label,x in [('LegLeft',-.21),('LegRight',.21)]:
        parts[label]=[(rod((0,.18,0),(0,-.22,0),.10,8),'cloth'),
                      (box((.28,.25,.40),(0,-.215,-.075),bevel=.045),'boot'),
                      (box((.30,.045,.42),(0,-.327,-.075),bevel=.014),'black'),
                      (lathe([(-.16,.145),(-.06,.145)],10),'boot')]
    counts={n:save_part(OUT,n,p) for n,p in parts.items()}
    gun=[(box((.18,.18,.84),(0,-.015,.06),bevel=.035),'wood'),
         (box((.20,.27,.34),(0,-.085,.54),rot=(.18,0,0),bevel=.04),'wood'),
         (rod((0,.08,.22),(0,.08,-.90),.062,16),'steel'),
         (box((.20,.20,.21),(0,.035,.035),bevel=.018),'gold'),
         (box((.11,.13,.15),(0,-.085,.07),bevel=.018),'steel'),
         (rod((0,.08,-.88),(0,.08,-.95),.074,16),'steel'),
         (rod((0,.08,-.951),(0,.08,-.956),.048,16),'black'),
         (ring(.042,.012,(0,-.12,.26),rot=(0,math.pi/2,0),n=10,m=4),'steel'),
         (box((.035,.045,.06),(0,.145,-.81),bevel=.004),'steel')]
    weapon_count=save_part(WEAPON,'Musket',gun)
    (OUT/'parts.json').write_text(json.dumps(list(parts)),encoding='utf-8')
    (WEAPON/'parts.json').write_text('["Musket"]',encoding='utf-8')
    (WEAPON.parent/'repeating_musket.tscn').write_text('''[gd_scene format=3]
[ext_resource type="ArrayMesh" path="res://assets/models/weapons/repeating_musket/Musket.res" id="mesh"]
[node name="RepeatingMusket" type="Node3D"]
[node name="Mesh" type="MeshInstance3D" parent="."]
mesh = ExtResource("mesh")
[node name="Muzzle" type="Marker3D" parent="."]
position = Vector3(0, 0.08, -0.96)
''',encoding='utf-8')
    lines=['[gd_scene format=3]', '[ext_resource type="Script" path="res://scripts/hero/hero_visual.gd" id="script"]',
           '[ext_resource type="PackedScene" path="res://assets/models/weapons/repeating_musket.tscn" id="weapon"]']
    for p in parts:
        lines.append(f'[ext_resource type="ArrayMesh" path="res://assets/models/heroes/capsule/{p}.res" id="{p}"]')
    idle=[('Rig:position',[(0,0,0),(0,.012,0),(0,0,0)])]
    walk=[('Rig:position',[(0,0,0),(0,.025,0),(0,0,0),(0,.025,0),(0,0,0)])]
    for p,sign in [('LegLeft',1),('LegRight',-1)]:
        idle.append((f'Rig/{p}:rotation',[(0,0,0),(0,0,0)]))
        walk.append((f'Rig/{p}:rotation',[(sign*a,0,0) for a in [0,.5,0,-.5,0]]))
    strike=[('Rig/Aim:position',[(0,1.45,0),(0,1.458,.075),(0,1.45,0)], [0,.065,.32]),
            ('Rig/Aim:rotation',[(0,0,0),(0,0,0),(0,.65,0)],[0,.36,.65])]
    reload=[('Rig/Aim:rotation',[(0,.65,0),(.40,.65,-.15),(.40,.65,-.15),(0,.65,0)],[0,.25,1.50,1.8]),
            ('Rig/Aim:position',[(0,1.45,0),(0,1.45,0)],[0,1.8])]
    lines += [anim_resource('idle',2.6,idle,True),anim_resource('walk',.48,walk,True),
              anim_resource('strike',.65,strike),anim_resource('reload',1.8,reload),
              '[sub_resource type="AnimationLibrary" id="move"]\n_data = {&"idle": SubResource("Animation_idle"), &"walk": SubResource("Animation_walk")}',
              '[sub_resource type="AnimationLibrary" id="attack"]\n_data = {&"strike": SubResource("Animation_strike"), &"reload": SubResource("Animation_reload")}',
              '[node name="CapsuleHero" type="Node3D"]\nscript = ExtResource("script")\nkind = "hero"\nprojectile_socket = NodePath("Rig/Aim/WeaponSocket/Weapon/Muzzle")',
              '[node name="Rig" type="Node3D" parent="."]', '[node name="Aim" type="Node3D" parent="Rig"]\nposition = Vector3(0,1.45,0)\nrotation = Vector3(0,.65,0)',
              '[node name="Accessories" type="Node3D" parent="Rig"]',
              '[node name="Expressions" type="Node3D" parent="Rig"]']
    for p in parts:
        parent='Rig/Aim' if p=='Arms' else 'Rig/Accessories' if p in ACCESSORIES else 'Rig/Expressions' if p.startswith('Face') and p!='Face' else 'Rig'
        at=(-.21,.35,0) if p=='LegLeft' else (.21,.35,0) if p=='LegRight' else (0,0,0)
        hidden=(p in ACCESSORIES and p!='Hat') or (p.startswith('Face') and p not in ['Face','FaceSmile'])
        lines.append(f'[node name="{p}" type="MeshInstance3D" parent="{parent}"]\nposition = {vec(at)}\nmesh = ExtResource("{p}")'+ ('\nvisible = false' if hidden else ''))
    lines += ['[node name="WeaponSocket" type="Marker3D" parent="Rig/Aim"]\nposition = Vector3(.32,0,-.10)',
              '[node name="Weapon" parent="Rig/Aim/WeaponSocket" instance=ExtResource("weapon")]',
              '[node name="Locomotion" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("move")}\nautoplay = "idle"',
              '[node name="Attack" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("attack")}',
              '[node name="VisibilityNotifier" type="VisibleOnScreenNotifier3D" parent="."]\naabb = AABB(-1,0,-1.4,2,3,2.2)',
              '[connection signal="screen_entered" from="VisibilityNotifier" to="." method="_on_screen_entered"]',
              '[connection signal="screen_exited" from="VisibilityNotifier" to="." method="_on_screen_exited"]']
    scene_text=re.sub(r'(?<![A-Za-z0-9_])\.(\d)',r'0.\1','\n\n'.join(lines)+'\n')
    (OUT.parent/'capsule.tscn').write_text(scene_text,encoding='utf-8')
    visible=sum(n for p,n in counts.items() if (p not in ACCESSORIES or p=='Hat') and
                (not p.startswith('Face') or p in ['Face','FaceSmile']))+weapon_count
    (OUT/'geometry.json').write_text(json.dumps({'body_radial_segments':BODY_SECTIONS,'parts':counts,
        'weapon':weapon_count,'default_visible_triangles':visible},indent=2)+'\n',encoding='utf-8')
    print(f'Capsule hero: {visible} visible triangles; {sum(counts.values())+weapon_count} including optional parts')


if __name__=='__main__': build()
