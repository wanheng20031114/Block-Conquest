"""Musketeer: saved rigid rig, shoulder fire and a muzzle-loading ramrod cycle."""
import math
import numpy as np
from build_units import Sculpture, OUT, lathe, polygon, anim_resource, vec, farmer_arm_pose, godot_rotation

TIMES = [0,.22,.35,.40,.58,.85,1.02,1.20,1.34,1.46,1.60,1.72,1.94,2.16]
PITCH = [-.18,0,0,.065,-.05,1.50,1.50,1.50,1.50,1.50,1.50,1.40,.42,-.18]
RELOAD = [0,0,0,0,0,1,1,1,1,1,1,.9,.25,0]
ANCHOR = np.array((.20,.42,-.23))
LOADING_ANCHOR = np.array((.09,-.41,-.36))
LEFT_GRIP = np.array((-.085,-.09,-.10))
RIGHT_GRIP = np.array((.02,-.10,.10))


def build_musketeer():
    s = Sculpture('musketeer')
    body=s.joint('Body',(0,1.05,0))
    s.add(body,lathe([(-.32,.265),(-.10,.235),(.20,.265),(.29,.19)],10),'blue')
    s.r(body,(0,.25,0),(0,.4,0),.11,'skin',8)
    s.add(body,lathe([(.25,.145),(.30,.132)],10,caps=False),'ivory')
    # Open coat, cream collar and a broad leather bandolier with powder measures.
    for sign in (-1,1):
        s.b(body,(.115,.24,.037),(sign*.125,.145,-.233),'leather',rot=(0,0,sign*-.15),bevel=.012)
        s.b(body,(.080,.074,.041),(sign*.073,.255,-.198),'ivory',rot=(0,0,sign*.35),bevel=.008)
    s.b(body,(.065,.57,.040),(0,-.005,-.255),'leatherlight',rot=(0,0,-.58),bevel=.009)
    s.b(body,(.065,.54,.03),(0,.025,.229),'leather',rot=(0,0,.58),bevel=.005)
    for index in range(4):
        x=-.10+index*.066
        y=.13-index*.088
        s.r(body,(x,y,-.293),(x+.009,y-.076,-.303),.027,'woodlight',6)
        s.r(body,(x,y-.001,-.293),(x+.002,y-.021,-.296),.031,'bronze',6)
    s.add(body,lathe([(-.19,.247),(-.12,.246)],10,caps=False),'leather')
    s.b(body,(.093,.074,.027),(0,-.155,-.262),'bronzelight',bevel=.007)
    s.b(body,(.048,.034,.031),(0,-.155,-.277),'leather',bevel=.003)
    s.b(body,(.19,.23,.15),(.30,-.245,.055),'leather',rot=(0,0,.12),bevel=.017)
    s.b(body,(.20,.06,.165),(.286,-.14,.055),'leatherlight',rot=(0,0,.12),bevel=.011)
    s.e(body,(.065,.11,.06),(-.275,-.23,.055),'woodlight')
    s.r(body,(-.275,-.17,.055),(-.275,-.095,.055),.025,'bronze',6)
    for y in [.15,.025,-.265]: s.e(body,(.017,.017,.012),(.14,y,-.219),'gold')

    head=s.joint('Head',(0,1.64,0))
    s.e(head,(.235,.253,.22),(0,-.015,-.01),'skin',sub=2)
    s.e(head,(.228,.139,.22),(0,.085,.025),'mane')
    # An asymmetric folded felt brim, kept above the eyebrows.
    brim=lathe([(0,.385),(.033,.385)],12,pos=(0,.136,0))
    for vertex in brim.vertices:
        if vertex[0] < -.18: vertex[1] += (-vertex[0]-.18)*.42
    s.add(head,brim,'wooddark')
    s.add(head,lathe([(.163,.242),(.265,.22),(.34,.175),(.347,.10)],10),'wooddark')
    s.add(head,lathe([(.168,.246),(.218,.238)],10,caps=False),'blue')
    s.b(head,(.073,.064,.027),(-.15,.204,-.197),'gold',rot=(0,.6,0),bevel=.009)
    feather=polygon([(-.025,-.13),(-.064,.02),(-.042,.19),(0,.30),(.041,.17),(.035,.015)],.017,
                    pos=(-.246,.35,.04),rot=(0,0,.36))
    s.add(head,feather,'ivory')
    s.r(head,(-.215,.21,.04),(-.321,.59,.04),.006,'rope',5)
    for sign in (-1,1):
        s.e(head,(.037,.067,.05),(sign*.223,-.034,-.02),'skin')
        s.b(head,(.047,.028,.018),(sign*.084,.027,-.229),'black',bevel=.003)
        s.b(head,(.074,.025,.018),(sign*.084,.073,-.216),'mane',rot=(0,0,sign*.06),bevel=.003)
    s.e(head,(.043,.058,.070),(0,-.028,-.232),'skin')
    for sign in (-1,1): s.b(head,(.065,.021,.025),(sign*.027,-.081,-.23),'mane',rot=(0,0,sign*.16),bevel=.004)
    s.b(head,(.085,.014,.018),(0,-.118,-.215),'leather',bevel=.003)

    for side,sign in [('Left',-1),('Right',1)]:
        arm=s.joint('Arm'+side,(sign*.30,1.32,-.065))
        s.e(arm,(.125,.125,.132),(sign*.014,0,0),'blue')
        s.r(arm,(0,-.015,0),(sign*.045,-.24,0),.083,'blue',8)
        fore=s.joint('Forearm'+side,(sign*.045,-.24,0),arm)
        s.e(fore,(.083,.082,.083),(0,0,0),'blue')
        s.r(fore,(0,-.025,0),(sign*.023,-.17,-.04),.070,'blue',8,r2=.06)
        s.r(fore,(sign*.017,-.115,-.026),(sign*.025,-.181,-.042),.077,'ivory',8,r2=.067)
        s.e(fore,(.062,.065,.07),(sign*.025,-.235,-.055),'skin')
        s.b(fore,(.029,.055,.041),(sign*-.014,-.233,-.103),'skin',bevel=.008)
    for name,x in [('LegLeft',-.155),('LegRight',.155)]:
        leg=s.joint(name,(x,.74,0))
        s.r(leg,(0,0,0),(0,-.46,0),.09,'ivory',8)
        s.r(leg,(0,-.35,0),(0,-.61,0),.106,'leather',8)
        s.r(leg,(0,-.345,0),(0,-.405,0),.119,'leatherlight',8)
        s.b(leg,(.20,.16,.29),(0,-.635,-.07),'leather',bevel=.024)
        s.b(leg,(.21,.035,.30),(0,-.712,-.07),'wooddark',bevel=.008)

    waist=s.pivot('Waist',(0,1.05,0))
    for part in (body,head,'ArmLeft','ArmRight'): s.reparent(part,waist)
    gun=s.joint('Musket',tuple(ANCHOR),waist)
    s.b(gun,(.09,.082,.77),(0,-.015,-.185),'wood',bevel=.012)
    s.add(gun,polygon([(-.01,.02),(.31,-.02),(.35,-.14),(.27,-.18),(.035,-.105)],.115,
                     rot=(0,-math.pi/2,0)),'wooddark')
    s.b(gun,(.12,.025,.17),(0,-.145,.28),'bronze',rot=(-.2,0,0),bevel=.005)
    # Hollow barrel: the last rings turn inward to a dark recessed bore.
    profile=[(-.86,.043),(-.825,.043),(.10,.061),(.14,.061)]
    s.add(gun,lathe(profile,10,pos=(0,.067,0),rot=(math.pi/2,0,0),caps=False),'darksteel')
    s.add(gun,lathe([(.136,.061),(.14,.061)],10,pos=(0,.067,0),rot=(math.pi/2,0,0)),'darksteel')
    s.add(gun,lathe([(-.862,.043),(-.862,.027),(-.77,.027)],10,pos=(0,.067,0),rot=(math.pi/2,0,0),caps=False),'steel')
    s.add(gun,lathe([(-.771,.0265),(-.768,.0265)],10,pos=(0,.067,0),rot=(math.pi/2,0,0)),'black')
    # Bands are neutral steel; team identity stays on coat and hat ribbon.
    for z in [-.67,-.30,.04]:
        s.r(gun,(0,.067,z-.012),(0,.067,z+.012),.063,'steel',10)
    s.b(gun,(.020,.028,.038),(0,.119,-.72),'steel',bevel=.002)
    s.b(gun,(.10,.046,.11),(.035,.025,.045),'bronze',bevel=.010)
    s.r(gun,(.036,-.059,.035),(.036,-.11,.075),.008,'steel',6)
    for a,b in [((0,-.055,.015),(0,-.16,.033)),((0,-.16,.033),(0,-.15,.145)),((0,-.15,.145),(0,-.04,.145))]:
        s.r(gun,a,b,.011,'bronze',6)
    hammer=s.joint('Hammer',(.074,.081,.075),gun)
    s.r(hammer,(0,0,0),(0,.081,-.032),.018,'steel',6)
    s.b(hammer,(.039,.029,.054),(0,.083,-.045),'black',bevel=.006)
    rod=s.joint('Ramrod',(0,.067,-1.0),gun)
    s.r(rod,(0,0,0),(0,0,.50),.009,'steel',6)
    s.r(rod,(0,0,-.008),(0,0,.033),.017,'woodlight',6)
    return s


def pose(s,time=0,attack=False):
    reload=float(np.interp(time,TIMES,RELOAD)) if attack else 0
    pitch=float(np.interp(time,TIMES,PITCH)) if attack else -.18
    # Raise the barrel before lowering its butt; keep the support hand in reach.
    anchor=ANCHOR*(1-reload*reload)+LOADING_ANCHOR*(reload*reload)
    anchor[0]=ANCHOR[0]*(1-reload)+LOADING_ANCHOR[0]*reload
    recoil=float(np.interp(time,[0,.35,.40,.58,2.16],[0,0,.035,0,0])) if attack else 0
    anchor=anchor+np.array((0,0,recoil))
    yaw=.30*(1-reload)
    rotation=(pitch,yaw,0)
    basis=godot_rotation(rotation)
    left=LEFT_GRIP.copy()
    left[2]-=.37*max(0,(reload-.45)/.55)
    left[1]+=.145*reload
    rod_slide=float(np.interp(time,[0,1.20,1.34,1.46,1.60,2.16],[0,0,.20,0,.20,.20])) if attack else 0
    targets={'Left':anchor+basis@left,'Right':anchor+basis@RIGHT_GRIP}
    if attack:
        # A reachable powder pouch, followed by the real ramrod handle.
        pouch=np.array((.30,-.12,.035))
        tamp=anchor+basis@np.array((.02,.067,-1.0+rod_slide))
        if time>1.60:
            tamp=LOADING_ANCHOR+godot_rotation((1.50,0,0))@np.array((.02,.067,-.80))
        weight=float(np.interp(time,[0,.58,.80,1.18,1.60,1.85,2.16],[0,0,1,1,1,0,0]))
        to_muzzle=float(np.interp(time,[0,.98,1.18,2.16],[0,0,1,1]))
        targets['Right']=targets['Right']*(1-weight)+(pouch*(1-to_muzzle)+tamp*to_muzzle)*weight
    result={s.part_path('Musket')+':rotation':rotation,s.part_path('Musket')+':position':tuple(anchor),
            s.part_path('Waist')+':rotation':(0,-yaw,0),s.part_path('Head')+':rotation':(0,yaw,0),
            s.part_path('Ramrod')+':position':(0,.067,-1.0+rod_slide),
            s.part_path('Hammer')+':rotation':(float(np.interp(time,[0,.35,.37,1.84,2.02,2.16],[0,0,-.85,-.85,0,0])) if attack else 0,0,0)}
    for side in ('Left','Right'):
        distance=np.linalg.norm(targets[side]-np.array(s.joints['Arm'+side]))
        if distance>.485: raise ValueError(f'{side} hand unreachable at {time:.3f}: {distance:.4f}')
        upper,fore=farmer_arm_pose(s,side,targets[side])
        result[s.part_path('Arm'+side)+':rotation']=upper
        result[s.part_path('Forearm'+side)+':rotation']=fore
    return result


def write_musketeer_scene(s):
    parts=list(s.parts)
    lines=['[gd_scene format=3]','[ext_resource type="Script" path="res://scripts/unit_visual.gd" id="1_script"]']
    for i,p in enumerate(parts): lines.append(f'[ext_resource type="ArrayMesh" path="res://assets/models/units/musketeer/{p}.res" id="{i+2}_{p}"]')
    rest=pose(s)
    idle=[(path,[value,value]) for path,value in rest.items()]
    walk=[(path,[value,value]) for path,value in rest.items()]
    times=sorted(set([round(i*.02,4) for i in range(109)]+TIMES))
    samples=[pose(s,t,True) for t in times]
    strike=[(path,[sample[path] for sample in samples],times) for path in rest]
    for part,sign in [('LegLeft',1),('LegRight',-1)]:
        path=s.part_path(part)+':rotation'
        idle.append((path,[(0,0,0)]*2))
        walk.append((path,[(sign*a,0,0) for a in [0,.39,0,-.39,0]]))
    idle.append(('Rig:position',[(0,0,0),(0,.009,0),(0,0,0)]))
    walk.append(('Rig:position',[(0,y,0) for y in [0,.02,0,.02,0]]))
    for tracks in (idle,walk): tracks.append((s.part_path('Ramrod')+':visible',[False,False]))
    strike.append((s.part_path('Ramrod')+':visible',[False,True,False],[0,1.18,1.64]))
    lines += [anim_resource('idle',2.6,idle,True),anim_resource('walk',.72,walk,True),anim_resource('strike',2.16,strike),
        '[sub_resource type="AnimationLibrary" id="AnimationLibrary_locomotion"]\n_data = {&"idle": SubResource("Animation_idle"), &"walk": SubResource("Animation_walk")}',
        '[sub_resource type="AnimationLibrary" id="AnimationLibrary_attack"]\n_data = {&"strike": SubResource("Animation_strike")}',
        '[node name="Musketeer" type="Node3D"]\nscript = ExtResource("1_script")\nkind = "musketeer"\nprojectile_socket = NodePath("Rig/Action/Waist/Musket/ProjectileSocket")',
        '[node name="Rig" type="Node3D" parent="."]','[node name="Action" type="Node3D" parent="Rig"]']
    emitted=set()
    def emit(part):
        if part in emitted:return
        parent=s.parents[part]
        if parent:emit(parent)
        parent_path=s.part_path(parent) if parent else 'Rig/Action'
        block=f'[node name="{part}" type="'+('Node3D' if part in s.pivots else 'MeshInstance3D')+f'" parent="{parent_path}"]\nposition = {vec(s.joints[part])}'
        if part not in s.pivots:block+=f'\nmesh = ExtResource("{parts.index(part)+2}_{part}")'
        for prop in ('rotation','scale'):
            path=s.part_path(part)+':'+prop
            if path in rest:block+='\n'+prop+' = '+vec(rest[path])
        if part=='Ramrod':block+='\nvisible = false'
        lines.append(block)
        emitted.add(part)
    for part in parts:emit(part)
    lines += ['[node name="ProjectileSocket" type="Marker3D" parent="Rig/Action/Waist/Musket"]\nposition = Vector3(0,0.067,-0.863)',
        '[node name="Locomotion" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("AnimationLibrary_locomotion")}\nautoplay = "idle"',
        '[node name="Attack" type="AnimationPlayer" parent="."]\ncallback_mode_process = 0\nlibraries = {&"": SubResource("AnimationLibrary_attack")}',
        '[node name="VisibilityNotifier" type="VisibleOnScreenNotifier3D" parent="."]\naabb = AABB(-2,-1,-2,4,4,4)',
        '[connection signal="screen_entered" from="VisibilityNotifier" to="." method="_on_screen_entered"]',
        '[connection signal="screen_exited" from="VisibilityNotifier" to="." method="_on_screen_exited"]']
    (OUT/'musketeer.tscn').write_text('\n\n'.join(lines)+'\n',encoding='utf-8')
