"""Advanced crossbow and cavalry fittings, merged into the original rigid parts.

Broad armor surfaces carry the upgrade at RTS scale. Fine studs use low-sided
meshes so the added equipment does not require new joints or draw calls.
"""
import math
from build_units import lathe, polygon
from unit_advanced_infantry import plate, border
from unit_model_geometry import fitted_front_panel


def crossbow_cuirass(s, part):
    for front in (True, False):
        s.add(part, plate([(-.13, .27), (.08, .315), (.22, .312), (.255, .27)], front,
                          half_span=57, thickness=.025), 'steel' if front else 'darksteel')
        s.add(part, plate([(-.137, .274), (-.094, .285)], front, half_span=57,
                          thickness=.022), 'edge')
    s.b(part, (.042, .285, .023), (0, .063, -.319), 'edge', bevel=.005)
    for sign in (-1, 1):
        s.b(part, (.071, .22, .036), (sign*.19, .17, -.255), 'leather',
            rot=(0, -sign*.5, sign*.05), bevel=.008)
        s.b(part, (.075, .048, .023), (sign*.193, .17, -.277), 'bronzelight',
            rot=(0, -sign*.5, 0), bevel=.004)
        # Short skirts leave the belt, sleeves and lower tunic in team color.
        s.b(part, (.175, .09, .038), (sign*.12, -.105, -.272), 'steel',
            rot=(0, -sign*.25, 0), bevel=.013)


def crossbow_shoulder(s, part, sign):
    s.b(part, (.245, .11, .285), (sign*.013, .100, 0), 'steel',
        rot=(0, 0, -sign*.12), bevel=.022)
    s.b(part, (.075, .12, .245), (sign*.114, .003, 0), 'darksteel',
        rot=(0, 0, -sign*.25), bevel=.014)
    s.b(part, (.081, .026, .251), (sign*.125, -.043, 0), 'edge',
        rot=(0, 0, -sign*.25), bevel=0)


def crossbow_bracer(s, part, sign):
    # Outside of the forearm, clear of palms, trigger and moving bowstring.
    s.b(part, (.11, .125, .045), (sign*.020, -.121, .031), 'steel',
        rot=(.24, 0, 0), bevel=.015)
    for y, z in [(-.070, -.010), (-.172, -.036)]:
        s.r(part, (sign*.014, y+.010, z), (sign*.018, y-.010, z-.005),
            .079 if y > -.1 else .071, 'bronzelight', 8)


def crossbow_fittings(s, weapon, body):
    # Laminated stock rails and tip shoes reinforce the existing short bow.
    for sign in (-1, 1):
        s.b(weapon, (.018, .046, .50), (sign*.058, -.012, -.155), 'edge', bevel=.004)
        s.b(weapon, (.065, .056, .075), (sign*.377, .040, -.421), 'edge',
            rot=(0, -sign*.34, 0), bevel=.007)
    s.b(weapon, (.147, .038, .19), (0, -.075, .125), 'darksteel', bevel=.008)
    s.b(body, (.187, .038, .174), (.293, -.288, .08), 'steel', rot=(0, 0, .12), bevel=.004)
    s.b(body, (.185, .035, .174), (.274, -.114, .08), 'steel', rot=(0, 0, .12), bevel=.004)
    s.b(body, (.044, .175, .024), (.291, -.20, -.010), 'edge', rot=(0, 0, .12), bevel=.004)


def knight_cuirass(s, part):
    for front in (True, False):
        s.add(part, plate([(-.07, .292), (.14, .366), (.265, .309)], front,
                          half_span=59, thickness=.031), 'steel' if front else 'darksteel')
        s.add(part, plate([(-.085, .293), (-.047, .306)], front, half_span=59), 'edge')
    s.b(part, (.043, .27, .027), (0, .102, -.364), 'edge', bevel=.006)
    for sign in (-1, 1):
        for i in range(2):
            s.b(part, (.185, .105, .04), (sign*.16, -.20-i*.085, -.227), 'steel',
                rot=(0, -sign*.16, -sign*.15), bevel=.018)
        s.add(part, polygon([(-.070,.06),(.070,.06),(.085,-.02),(0,-.09),(-.085,-.02)],
                           .033,(sign*.56,-.31,-.007)), 'edge')


def knight_shoulder(s, part, sign):
    s.b(part, (.37, .14, .42), (sign*.02, .075, -.005), 'steel',
        rot=(0, 0, -sign*.12), bevel=.045)
    for i in range(2):
        s.b(part, (.108, .12, .33-i*.025), (sign*(.18+i*.023), -.018-i*.073, 0),
            'steel', rot=(0, 0, -sign*.24), bevel=.017)
    s.b(part, (.30, .031, .033), (sign*.025, .097, -.204), 'edge', bevel=.006)
    s.e(part, (.024, .024, .015), (sign*.07, .045, -.211), 'gold', sub=0)


def knight_helmet(s, part):
    # Same closed helmet and modest cloth crest; collar and brow are reinforced.
    s.add(part, lathe([(-.12,.29),(0,.33),(.14,.29),(.24,.20),(.29,.075)],12), 'steel')
    s.add(part, lathe([(-.13,.304),(-.08,.335),(-.045,.333)],12,caps=False), 'edge')
    s.b(part,(.42,.15,.095),(0,-.16,-.218),'black',bevel=.035)
    for sign in (-1,1):
        s.add(part,polygon([(-.095,.08),(.095,.08),(.072,-.15),(-.07,-.20)],.045,
                          (sign*.155,-.225,-.262),(0,sign*.22,sign*.08)), 'steel')
    s.b(part,(.059,.25,.048),(0,-.16,-.292),'edge',bevel=.012)
    s.b(part,(.43,.030,.04),(0,-.101,-.283),'edge',bevel=.006)
    for angle in (-60,-30,0,30,60):
        a=math.radians(angle)
        s.e(part,(.017,.017,.017),(math.sin(a)*.34,-.05,-math.cos(a)*.34),'gold',sub=0)
    s.add(part, plate([(-.28,.248),(-.18,.284)], False, half_span=78, thickness=.025),'darksteel')
    s.b(part,(.052,.25,.12),(0,.20,.015),'edge',bevel=.022)
    for i in range(2):
        s.e(part,(.086,.117,.25),(0,.29-i*.032,.09+i*.20),'blue',rot=(.35,0,0))


def knight_shield(s, part):
    center=(-.30,-.35,-.465)
    x,y,z=center
    pts=[(-.319,.374),(.319,.374),(.308,-.099),(0,-.473),(-.308,-.099)]
    s.add(part,polygon(pts,.095,center),'darksteel')
    s.add(part,polygon([(a*.83,b*.83) for a,b in pts],.025,(x,y,z-.058)),'blue')
    s.add(part,border(pts,.83,.035,(x,y,z-.059)),'edge')
    s.b(part,(.055,.583,.022),(x,y+.015,z-.080),'goldlight',bevel=0)
    s.b(part,(.418,.055,.022),(x,y+.075,z-.081),'goldlight',bevel=0)
    s.e(part,(.070,.070,.033),(x,y+.075,z-.10),'gold',sub=0)
    for a,b in pts:
        s.e(part,(.019,.019,.011),(x+a*.91,y+b*.91,z-.084),'gold',sub=0)


def knight_horse_armor(s, body, skin):
    # A three-piece peytral follows the chest, below the moving neck. The
    # broad blue side cloth remains exposed, unlike full royal horse barding.
    # Stay inside the chest's projected silhouette; beyond it a ray would hit
    # the barrel behind the chest and incorrectly fold the plate into the horse.
    for low, high, w0, w1 in [(-.24,-.05,.23,.31),(-.075,.16,.315,.315)]:
        s.add(body,fitted_front_panel(skin,[(low,w0),((low+high)/2,(w0+w1)/2),(high,w1)],inset=.050),'steel')
        s.add(body,fitted_front_panel(skin,[(low,w0),(low+.025,w0+.013)],inset=.058),'edge')
    for sign in (-1,1):
        s.b(body,(.055,.070,.35),(sign*.352,.15,-.565),'leather',rot=(0,-sign*.22,0),bevel=.01)
        s.b(body,(.062,.076,.039),(sign*.328,.15,-.673),'edge',rot=(0,-sign*.22,0),bevel=.007)
        s.b(body,(.08,.045,.45),(sign*.268,.48,.12),'darksteel',bevel=.009)
    s.b(body,(.49,.037,.106),(0,.61,.36),'edge',rot=(-.18,0,0),bevel=.01)
    # Forehead plate tapers between the eyes rather than covering them.
    s.add(body,fitted_front_panel(skin,[(.60,.047),(.73,.13),(.80,.147),(.87,.153),(.91,.10)],columns=5,inset=.050),'steel')
    s.add(body,fitted_front_panel(skin,[(.60,.012),(.73,.018),(.87,.018),(.91,.012)],columns=3,inset=.063),'edge')
