"""Light cavalry and elephant upgrades on their existing saved rigid rigs.

Scout armor leaves the horse exposed. Elephant armor protects forehead/chest
and braces the saddle, keeping eyes, ears, trunk, tusks and feet unobstructed.
"""
import math
import numpy as np
from build_units import polygon, matrix
from unit_advanced_infantry import plate, border
from unit_infantry_headwear import crown
from unit_model_geometry import fitted_front_panel


def scout_cap(s, part):
    # Shared ring boundaries prevent a gap between the cloth crown and rim.
    rings=[(.112,.221,.218,.009),(.137,.233,.227,.01),(.155,.235,.229,.01),
           (.216,.251,.229,.024),(.289,.156,.148,.028),(.327,.024,.024,.022)]
    loops=[[(rx*math.cos(i*math.tau/12),y,cz+rz*math.sin(i*math.tau/12)) for i in range(12)]
           for y,rx,rz,cz in rings]
    crown(s,part,loops,['leather','edge','blue','blue','blue'])


def scout_cuirass(s, part):
    # Compact overlapping chest plates; broad sleeves and side cloth stay blue.
    for profile,color in [([(-.07,.267),(.09,.333)],'darksteel'),
                          ([(.057,.335),(.17,.327),(.27,.274)],'steel')]:
        s.add(part,plate(profile,half_span=58,thickness=.025),color)
    s.add(part,plate([(-.075,.273),(-.038,.292)],half_span=58,thickness=.025),'edge')
    s.add(part,plate([(-.04,.26),(.17,.329),(.27,.269)],False,half_span=54,thickness=.023),'leather')
    for sign in (-1,1):
        s.b(part,(.058,.17,.032),(sign*.167,.19,-.276),'leather',rot=(0,-sign*.48,0),bevel=.006)
        s.b(part,(.064,.048,.027),(sign*.174,.194,-.287),'edge',rot=(0,-sign*.48,0),bevel=.005)


def scout_arm(s, part, sign, elbow, hand):
    s.b(part,(.24,.11,.29),(sign*.012,.10,0),'steel',rot=(0,0,-sign*.08),bevel=.027)
    s.b(part,(.060,.11,.24),(sign*.128,.026,0),'darksteel',rot=(0,0,-sign*.18),bevel=.013)
    a,b=np.array(elbow),np.array(hand)
    for start,end,radius,color in [(.19,.25,.084,'edge'),(.25,.66,.081,'steel'),(.66,.73,.084,'edge')]:
        s.r(part,tuple(a+(b-a)*start),tuple(a+(b-a)*end),radius,color,8)


def scout_saddle(s, body):
    for sign in (-1,1):
        s.b(body,(.045,.047,.43),(sign*.279,.488,.12),'darksteel',bevel=.008)
        for z in (-.15,.36):
            s.b(body,(.075,.14,.105),(sign*.20,.525,z),'steel',bevel=.010)
        # A small knee plate sits ahead of the calf, outside the saddle cloth.
        s.add(body,polygon([(-.057,.065),(.057,.065),(.069,-.017),(0,-.083),(-.069,-.017)],
                           .025,(sign*.57,.326,.068)), 'steel')
        # Two short leather reinforcements leave most of the blue cloth visible.
        for z in (.24,.65):
            s.b(body,(.040,.17,.056),(sign*.486,.19,z),'leather',bevel=.006)
            s.e(body,(.009,.017,.017),(sign*.509,.25,z),'edge',sub=0)


def elephant_forehead(s, head):
    rotation=(.22,0,0)
    transform=matrix((0,.30,-.566),rotation)
    outline=[(-.215,.30),(.215,.30),(.272,.055),(.18,-.16),(0,-.255),(-.18,-.16),(-.272,.055)]
    s.add(head,polygon(outline,.078,(0,.30,-.566),rotation),'darksteel')
    rim=border(outline,.83,.028,(0,0,-.048))
    rim.apply_transform(transform)
    s.add(head,rim,'edge')
    face=polygon([(x*.80,y*.80) for x,y in outline],.024,(0,0,-.046))
    face.apply_transform(transform)
    s.add(head,face,'steel')
    # A restrained team-color panel, no new crown or bars crossing the skull.
    stripe=polygon([(-.046,.205),(.046,.205),(.04,-.065),(0,-.14),(-.04,-.065)],.020,(0,0,-.065))
    stripe.apply_transform(transform)
    s.add(head,stripe,'blue')
    for x,y in [(-.16,.245),(.16,.245),(-.205,.036),(.205,.036)]:
        at=tuple((transform@np.array((x,y,-.069,1)))[:3])
        s.e(head,(.022,.022,.013),at,'gold',rot=rotation,sub=0)


def tusk_socket(s, head, base, following):
    a,b=np.array(base),np.array(following)
    direction=(b-a)/np.linalg.norm(b-a)
    # Each band follows its actual tusk axis, not a free-floating torus.
    for start,end,radius,color in [(0,.018,.126,'edge'),(.018,.113,.121,'darksteel'),(.113,.133,.119,'gold')]:
        s.r(head,tuple(a+direction*start),tuple(a+direction*end),radius,color,9)


def elephant_breastplate(s, body, skin):
    for rows in [[(-.43,.32),(-.25,.42),(-.08,.475)],[(-.11,.48),(.025,.485),(.16,.44)]]:
        s.add(body,fitted_front_panel(skin,rows,inset=.055),'steel')
        low,width=rows[0]
        s.add(body,fitted_front_panel(skin,[(low,width),(low+.028,width+.012)],inset=.066),'edge')
    for sign in (-1,1):
        # Flush attachment straps follow the chest facets without exposed rod ends.
        s.add(body,fitted_front_panel(skin,[(.08,.033),(.22,.033),(.36,.033)],columns=3,inset=.03,center_x=sign*.43),'leather')
        s.add(body,fitted_front_panel(skin,[(.20,.045),(.25,.045)],columns=3,inset=.045,center_x=sign*.43),'edge')


def elephant_saddle(s, body):
    for sign in (-1,1):
        s.b(body,(.055,.08,.82),(sign*.447,.87,.17),'darksteel',bevel=.012)
        for z in (-.20,.56):
            s.b(body,(.095,.23,.127),(sign*.37,.92,z),'darksteel',bevel=.017)
            s.e(body,(.027,.027,.015),(sign*.37,.95,z+(-.070 if z<0 else .070)),'edge',sub=0)
        # A steel top binding reinforces each side of the large blue cloth.
        s.b(body,(.058,.055,1.055),(sign*.88,.355,.205),'steel',bevel=.01)
        for z in (-.24,.66):
            s.b(body,(.060,.12,.062),(sign*.89,.315,z),'edge',bevel=.007)


def elephant_rider(s, rider):
    s.add(rider,plate([(-.015,.266),(.15,.318),(.25,.318),(.30,.274)],half_span=57,thickness=.027),'steel')
    s.add(rider,plate([(-.022,.272),(.012,.280)],half_span=57,thickness=.025),'edge')
    s.add(rider,plate([(-.005,.26),(.15,.307),(.25,.315),(.30,.274)],False,half_span=53,thickness=.025),'leather')
    for sign in (-1,1):
        s.b(rider,(.25,.095,.28),(sign*.28,.334,-.012),'steel',rot=(0,0,-sign*.10),bevel=.024)
        s.b(rider,(.078,.096,.25),(sign*.40,.266,-.012),'darksteel',rot=(0,0,-sign*.20),bevel=.013)
        s.b(rider,(.15,.12,.041),(sign*.417,-.30,-.156),'steel',bevel=.02)


def elephant_rider_cap(s, part):
    # A continuous blue crown over a leather band with a narrow steel edge.
    rings=[(.131,.213,.222,.003),(.164,.243,.228,.01),(.192,.245,.231,.018),
           (.257,.200,.193,.026),(.313,.080,.077,.03),(.320,.021,.020,.03)]
    loops=[[(rx*math.cos(i*math.tau/12),y,cz+rz*math.sin(i*math.tau/12)) for i in range(12)]
           for y,rx,rz,cz in rings]
    crown(s,part,loops,['leather','edge','blue','blue','blue'])
