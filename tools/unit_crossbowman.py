"""Crossbowman: authored two-hand grip, cocking string and 0.20 s bolt release."""
import math
import numpy as np
from build_units import Sculpture, OUT, lathe, anim_resource, vec, farmer_arm_pose, godot_rotation, godot_euler
import trimesh as tm

WEAPON_AT = np.array((0, .21, -.38))
LEFT_GRIP = np.array((-.025, -.07, -.045))
RIGHT_GRIP = np.array((.045, -.115, .035))
KEY_TIMES = [0, .14, .20, .25, .40, .55, .70, .82, .96]
WEAPON_PITCH = [0, 0, -.018, .01, -.42, -.42, -.28, -.12, 0]
DRAW = [.01, .01, -.28, -.28, -.28, -.10, .01, .01, .01]


def build_crossbowman(advanced=False):
    if advanced:
        import unit_advanced_crossbow_knight as veteran
    s = Sculpture('crossbowman_advanced' if advanced else 'crossbowman', kind='crossbowman', grade='advanced' if advanced else '')
    body = s.joint('Body', (0, 1.05, 0))
    head = s.joint('Head', (0, 1.64, 0))
    s.add(body, lathe([(-.30,.255),(-.04,.225),(.23,.27),(.29,.205)], 10), 'blue')
    s.r(body,(0,.24,0),(0,.40,0),.115,'skin',8)
    s.add(body,lathe([(.24,.15),(.29,.145)],10,caps=False),'blue')
    # Fitted leather jerkin leaves a broad team-colored skirt and sleeves.
    if advanced:
        veteran.crossbow_cuirass(s, body)
    else:
        s.b(body, (.40,.38,.08), (0,.06,-.225), 'leather', bevel=.035)
        s.b(body, (.40,.38,.055), (0,.06,.23), 'leather', bevel=.025)
        for sign in (-1,1):
            s.b(body, (.072,.26,.057), (sign*.15,.155,-.243), 'leatherlight', rot=(0,0,sign*.10), bevel=.008)
            s.b(body, (.079,.046,.018), (sign*.154,.09,-.278), 'bronzelight', bevel=.005)
    s.add(body, lathe([(-.225,.26),(-.15,.253)],10,caps=False), 'leatherlight')
    s.b(body, (.09,.066,.025), (0,-.182,-.256), 'bronzelight', bevel=.009)
    s.b(body, (.040,.032,.03), (0,-.182,-.27), 'leather', bevel=.003)
    # A short bolt case, distinct from the archer's tall back quiver.
    s.b(body, (.17,.28,.16), (.285,-.22,.08), 'leather', rot=(0,0,.12), bevel=.017)
    s.b(body, (.18,.035,.17), (.272,-.091,.08), 'leatherlight', rot=(0,0,.12), bevel=.004)
    for x,z in [(.246,.035),(.29,.068),(.278,.11)]:
        s.r(body,(x,-.12,z),(x-.028,.01,z),.012,'woodlight',6)
        s.b(body,(.065,.055,.009),(x-.025,-.014,z),'ivory',rot=(0,0,.12),bevel=.002)
    s.b(body, (.16,.18,.10), (-.27,-.20,.095), 'leatherlight', bevel=.02)

    s.e(head, (.235,.253,.22), (0,-.015,-.01), 'skin', sub=2)
    s.e(head, (.226,.137,.215), (0,.092,.025), 'mane', sub=1)
    # A low, open blue cloth cap and narrow leather rim; the brow stays exposed.
    s.add(head, lathe([(0,.245),(.065,.26),(.14,.23),(.18,.14),(.19,.05)],10,(0,.11,.012)), 'blue')
    s.add(head, lathe([(0,.25),(.034,.259)],10,(0,.10,.012),caps=False), 'leather')
    s.b(head, (.21,.027,.115), (0,.109,-.225), 'leatherlight', bevel=.01)
    s.b(head, (.065,.065,.018), (.16,.164,-.172), 'bronzelight', rot=(0,-.65,0), bevel=.008)
    for sign in (-1,1):
        s.e(head,(.037,.067,.05),(sign*.223,-.034,-.02),'skin')
        s.b(head,(.047,.028,.018),(sign*.084,.026,-.229),'black',bevel=.003)
        s.b(head,(.074,.025,.018),(sign*.084,.071,-.216),'mane',rot=(0,0,sign*.08),bevel=.003)
    s.e(head,(.043,.058,.070),(0,-.028,-.232),'skin')
    s.b(head,(.10,.018,.018),(0,-.112,-.218),'leather',bevel=.003)
    for side,sign in [('Left',-1),('Right',1)]:
        arm=s.joint('Arm'+side,(sign*.30,1.32,-.065))
        s.e(arm,(.126,.128,.135),(sign*.014,0,0),'blue')
        if advanced:
            veteran.crossbow_shoulder(s, arm, sign)
        s.r(arm,(0,-.015,0),(sign*.045,-.24,0),.085,'blue',8)
        fore=s.joint('Forearm'+side,(sign*.045,-.24,0),arm)
        s.e(fore,(.085,.083,.085),(0,0,0),'blue')
        s.r(fore,(0,-.025,0),(sign*.023,-.175,-.041),.066,'skin',8,r2=.058)
        s.r(fore,(sign*.016,-.095,-.02),(sign*.025,-.178,-.041),.075,'leather',8,r2=.065)
        s.e(fore,(.062,.065,.07),(sign*.025,-.235,-.055),'skin')
        s.b(fore,(.031,.057,.041),(sign*-.014,-.233,-.103),'skin',bevel=.009)
        if advanced:
            veteran.crossbow_bracer(s, fore, sign)
    for name,x in [('LegLeft',-.155),('LegRight',.155)]:
        leg=s.joint(name,(x,.74,0))
        s.r(leg,(0,0,0),(0,-.51,0),.09,'wooddark',8)
        s.r(leg,(0,-.40,0),(0,-.61,0),.106,'leather',8)
        s.b(leg,(.20,.16,.29),(0,-.635,-.07),'leather',bevel=.024)
        s.b(leg,(.21,.035,.30),(0,-.712,-.07),'wooddark',bevel=.008)
        s.r(leg,(0,-.395,0),(0,-.425,0),.109,'leatherlight',8)
    waist=s.pivot('Waist',(0,1.05,0))
    for part in (body,head,'ArmLeft','ArmRight'): s.reparent(part,waist)
    weapon=s.joint('Crossbow',tuple(WEAPON_AT),waist)
    # Stock, upper bolt channel and a trigger grip below it.
    s.b(weapon,(.105,.087,.69),(0,0,-.135),'wood',bevel=.012)
    s.b(weapon,(.137,.11,.19),(0,-.022,.135),'wooddark',rot=(.06,0,0),bevel=.023)
    for x in (-.037,.037):
        s.b(weapon,(.014,.016,.46),(x,.05,-.17),'woodlight',bevel=.003)
    s.b(weapon,(.08,.19,.057),(0,-.107,.033),'wooddark',rot=(.18,0,0),bevel=.012)
    s.r(weapon,(.048,-.035,-.001),(.048,-.10,-.018),.012,'steel',6)
    s.b(weapon,(.12,.032,.064),(0,.066,.027),'steel',bevel=.008)
    # Short, flat steel limbs with reinforced roots. Horizontal silhouette.
    for sign in (-1,1):
        points=[(0,.015,-.37),(sign*.18,.026,-.42),(sign*.32,.036,-.44),(sign*.43,.045,-.40)]
        for a,b,width in zip(points,points[1:],[.05,.043,.03]):
            midpoint=(np.array(a)+np.array(b))/2
            delta=np.array(b)-np.array(a)
            s.b(weapon,(np.linalg.norm(delta)+.025,width,.052),tuple(midpoint),'steel',rot=(0,-math.atan2(delta[2],delta[0]),0),bevel=.007)
        s.e(weapon,(.029,.026,.03),points[-1],'edge')
        s.b(weapon,(.043,.095,.15),(sign*.062,.016,-.37),'leather',bevel=.007)
        string=s.joint('String'+('Left' if sign<0 else 'Right'),points[-1],weapon)
        s.r(string,(0,0,0),(0,1,0),.0065,'ivory',5)
    # A compact stirrup gives the front of the crossbow a characteristic outline.
    s.r(weapon,(-.058,-.01,-.46),(-.07,-.025,-.56),.013,'darksteel',6)
    s.r(weapon,(.058,-.01,-.46),(.07,-.025,-.56),.013,'darksteel',6)
    s.r(weapon,(-.07,-.025,-.56),(.07,-.025,-.56),.013,'darksteel',6)
    bolt=s.joint('Bolt',(0,.068,-.16),weapon)
    s.r(bolt,(0,0,.17),(0,0,-.29),.011,'woodlight',6)
    s.r(bolt,(0,0,-.27),(0,0,-.37),.029,'edge',4,r2=0)
    for sign in (-1,1):
        s.b(bolt,(.045,.009,.073),(sign*.022,0,.12),'ivory',rot=(0,sign*.12,0),bevel=.002)
    if advanced:
        veteran.crossbow_fittings(s, weapon, body)
    return s


def pose(s,time=0,attack=False):
    pitch=float(np.interp(time,KEY_TIMES,WEAPON_PITCH)) if attack else 0
    draw=float(np.interp(time,KEY_TIMES,DRAW)) if attack else .01
    rotation=(pitch,0,0)
    basis=godot_rotation(rotation)
    positions={'Left':LEFT_GRIP.copy(),'Right':RIGHT_GRIP.copy()}
    # Right hand pulls the string and seats a short bolt, then returns to trigger.
    if attack:
        pull=float(np.interp(time,[0,.32,.46,.70,.82,.96],[0,0,1,1,0,0]))
        string_grip=np.array((.025,.035,draw+.025))
        positions['Right']=(1-pull)*RIGHT_GRIP+pull*string_grip
    result={s.part_path('Crossbow')+':rotation':rotation}
    for side in ('Left','Right'):
        upper,fore=farmer_arm_pose(s,side,WEAPON_AT+basis@positions[side])
        result[s.part_path('Arm'+side)+':rotation']=upper
        result[s.part_path('Forearm'+side)+':rotation']=fore
    for side in ('Left','Right'):
        part='String'+side
        direction=np.array((0,.045,draw))-np.array(s.joints[part])
        result[s.part_path(part)+':rotation']=godot_euler(tm.geometry.align_vectors((0,1,0),direction)[:3,:3])
        result[s.part_path(part)+':scale']=(1,float(np.linalg.norm(direction)),1)
    return result


def write_crossbowman_scene(s):
    parts=list(s.parts)
    lines=['[gd_scene format=3]','[ext_resource type="Script" path="res://scripts/unit_visual.gd" id="1_script"]']
    for i,p in enumerate(parts):
        lines.append(f'[ext_resource type="ArrayMesh" path="res://assets/models/units/{s.name}/{p}.res" id="{i+2}_{p}"]')
    rest=pose(s)
    idle=[(path,[value,value]) for path,value in rest.items()]
    walk=[(path,[value,value]) for path,value in rest.items()]
    # Offline IK sampling keeps both palms attached during the changing gun pitch.
    times=sorted(set([round(i*.02,4) for i in range(49)]+KEY_TIMES))
    samples=[pose(s,t,True) for t in times]
    strike=[(path,[sample[path] for sample in samples],times) for path in rest]
    for part,sign in [('LegLeft',1),('LegRight',-1)]:
        path=s.part_path(part)+':rotation'
        idle.append((path,[(0,0,0)]*2))
        walk.append((path,[(sign*a,0,0) for a in [0,.39,0,-.39,0]]))
        strike.append((path,[(0,0,0)]*2))
    for part in ('Waist','Head'):
        for tracks in (idle,walk,strike):tracks.append((s.part_path(part)+':rotation',[(0,0,0)]*2))
    idle.append(('Rig:position',[(0,0,0),(0,.010,0),(0,0,0)]))
    walk.append(('Rig:position',[(0,y,0) for y in [0,.022,0,.022,0]]))
    strike.append(('Rig:position',[(0,0,0)]*2))
    for tracks in (idle,walk):tracks.append((s.part_path('Bolt')+':visible',[True,True]))
    strike.append((s.part_path('Bolt')+':visible',[True,False,True],[0,.20,.74]))
    grade_property = f'\ngrade = &"{s.grade}"' if s.grade else ''
    lines += [anim_resource('idle',2.6,idle,True),anim_resource('walk',.72,walk,True),anim_resource('strike',.96,strike),
        '[sub_resource type="AnimationLibrary" id="AnimationLibrary_locomotion"]\n_data = {&"idle": SubResource("Animation_idle"), &"walk": SubResource("Animation_walk")}',
        '[sub_resource type="AnimationLibrary" id="AnimationLibrary_attack"]\n_data = {&"strike": SubResource("Animation_strike")}',
        f'[node name="Crossbowman" type="Node3D"]\nscript = ExtResource("1_script")\nkind = "crossbowman"{grade_property}\nprojectile_socket = NodePath("Rig/Action/Waist/Crossbow/ProjectileSocket")',
        '[node name="Rig" type="Node3D" parent="."]','[node name="Action" type="Node3D" parent="Rig"]']
    emitted=set()
    def emit(part):
        if part in emitted:return
        parent=s.parents[part]
        if parent:emit(parent)
        parent_path=s.part_path(parent) if parent else 'Rig/Action'
        if part in s.pivots:
            block=f'[node name="{part}" type="Node3D" parent="{parent_path}"]\nposition = {vec(s.joints[part])}'
        else:
            block=f'[node name="{part}" type="MeshInstance3D" parent="{parent_path}"]\nposition = {vec(s.joints[part])}\nmesh = ExtResource("{parts.index(part)+2}_{part}")'
        for prop in ('rotation','scale'):
            path=s.part_path(part)+':'+prop
            if path in rest:block+='\n'+prop+' = '+vec(rest[path])
        lines.append(block)
        emitted.add(part)
    for part in parts:emit(part)
    lines += ['[node name="ProjectileSocket" type="Marker3D" parent="Rig/Action/Waist/Crossbow"]\nposition = Vector3(0,0.068,-0.535)',
        '[node name="Locomotion" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("AnimationLibrary_locomotion")}\nautoplay = "idle"',
        '[node name="Attack" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("AnimationLibrary_attack")}',
        '[node name="VisibilityNotifier" type="VisibleOnScreenNotifier3D" parent="."]\naabb = AABB(-2,-1,-2,4,4,4)',
        '[connection signal="screen_entered" from="VisibilityNotifier" to="." method="_on_screen_entered"]',
        '[connection signal="screen_exited" from="VisibilityNotifier" to="." method="_on_screen_exited"]']
    (OUT/(s.name+'.tscn')).write_text('\n\n'.join(lines)+'\n',encoding='utf-8')
