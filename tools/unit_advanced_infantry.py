"""Veteran sword infantry fittings, consolidated into their existing rigid parts.

No crowns or oversized crests: broad steel panels, layered joints and reinforced
shields carry the grade. Face, grip, weapon length and animation pivots stay put.
"""
import math
import numpy as np
from build_units import lathe, polygon, tm


def plate(profile, front=True, half_span=62, thickness=.035):
    """Closed curved cuirass following the octagonal tunic, with real edge depth."""
    angles = np.radians(np.linspace((270 if front else 90)-half_span,
                                   (270 if front else 90)+half_span, 7))
    verts = [(math.cos(a)*(r-inset), y, math.sin(a)*(r-inset))
             for inset in (0, thickness) for y, r in profile for a in angles]
    width = len(angles)
    layer = len(profile)*width
    faces = []
    def quad(a,b,c,d): faces.extend(((a,b,c),(a,c,d)))
    for row in range(len(profile)-1):
        for col in range(width-1):
            a = row*width+col
            quad(a,a+1,a+1+width,a+width)
            quad(a+layer,a+width+layer,a+width+1+layer,a+1+layer)
    boundary = list(range(width)) + [row*width+width-1 for row in range(1,len(profile))]
    boundary += list(range(layer-2,layer-width-1,-1)) + [row*width for row in range(len(profile)-2,0,-1)]
    for a,b in zip(boundary,boundary[1:]+boundary[:1]): quad(a,a+layer,b+layer,b)
    mesh = tm.Trimesh(vertices=verts, faces=faces, process=False)
    mesh.fix_normals()
    assert mesh.is_watertight
    return mesh


def border(points, inner_scale, depth, center):
    """A closed polygonal rim, leaving the team-colored shield face visible."""
    count = len(points)
    x,y,z = center
    verts = [(x+px*scale,y+py*scale,z+dz)
             for dz in (-depth/2,depth/2) for scale in (1,inner_scale) for px,py in points]
    faces = []
    def quad(a,b,c,d): faces.extend(((a,b,c),(a,c,d)))
    for i in range(count):
        j=(i+1)%count
        quad(i,j,j+count,i+count)
        quad(i+2*count,i+3*count,j+3*count,j+2*count)
        quad(i,i+2*count,j+2*count,j)
        quad(i+count,j+count,j+3*count,i+3*count)
    mesh=tm.Trimesh(vertices=verts,faces=faces,process=False)
    mesh.fix_normals()
    assert mesh.is_watertight
    return mesh


def cuirass(s, part, heavy=False):
    # The front and back shells fit outside the blue tunic. Their upper edge
    # stays below the head joint; blue side gaps and the skirt remain readable.
    radius = .36 if heavy else .34
    profile = [(-.12,radius-.075),(.07,radius),(.235,radius+.018),(.285,radius-.003)]
    for front in (True,False):
        s.add(part,plate(profile,front),"steel" if front else "darksteel")
        s.add(part,plate([(-.13,radius-.071),(-.087,radius-.051)],front),"edge")
        s.add(part,plate([(.233,radius+.024),(.276,radius+.012)],front),"edge")
    # A central ridge and two short lower plates read as constructed armor,
    # rather than a larger unbroken silver block.
    s.b(part,(.048,.26,.032),(0,.085,-radius-.012),"edge",bevel=.008)
    for sign in (-1,1):
        s.b(part,(.095,.22,.23),(sign*(radius-.055),.02,.005),"darksteel",bevel=.025)
        for index in range(2):
            s.b(part,(.23 if heavy else .205,.084,.092),
                (sign*.145,-.225-index*.067,-.225),"steel",rot=(0,0,-sign*.07),bevel=.017)
        strap_z=math.sqrt((radius+.014)**2-.19**2)+.012
        s.b(part,(.065,.075,.035),(sign*.19,.248,-strap_z),"leather",
            rot=(0,-sign*.5,0),bevel=.008)
        s.b(part,(.065,.050,.035),(sign*.19,.249,strap_z),"steel",
            rot=(0,sign*.5,0),bevel=.008)


def pauldron(s, part, sign, heavy=False):
    # A shallow cap and two overlapping side lames replace the ordinary round
    # shoulder. They belong to the arm mesh, so no extra animated nodes are used.
    s.e(part,(.24,.155,.245),(sign*.035,.022,0),"darksteel")
    s.b(part,(.39,.135,.425),(sign*.055,.098,-.012),"steel",rot=(0,0,sign*-.09),bevel=.045)
    for index in range(2):
        s.b(part,(.13,.125,.37-index*.03),
            (sign*(.204+index*.025),-.03-index*.09,0),"steel",
            rot=(0,0,sign*-.27),bevel=.025)
        s.b(part,(.13,.027,.377-index*.03),
            (sign*(.217+index*.025),-.082-index*.09,0),"edge",
            rot=(0,0,sign*-.27),bevel=0)
    if heavy:
        s.b(part,(.23,.046,.35),(sign*.10,.178,0),"darksteel",bevel=.014)
    s.e(part,(.026,.020,.012),(sign*.10,.077,-.228),"gold",sub=0)


def bracer(s, part, elbow, wrist):
    a,b=np.array(elbow),np.array(wrist)
    for start,end,radius,color in [(0.13,.78,.116,'darksteel'),(.18,.44,.120,'steel'),(.48,.77,.123,'steel')]:
        s.r(part,tuple(a+(b-a)*start),tuple(a+(b-a)*end),radius,color,8)
    s.r(part,tuple(a+(b-a)*.72),tuple(a+(b-a)*.79),.127,'edge',8)


def greave(s, part, heavy=False):
    width=.145 if heavy else .132
    s.add(part,polygon([(-width,.03),(-width*.7,.125),(width*.7,.125),(width,.03),
                        (width*.75,-.095),(0,-.13),(-width*.75,-.095)],
                       .056,(0,-.277,-.129)),"edge")
    s.b(part,(.20 if heavy else .18,.23,.065),(0,-.443,-.110),"darksteel",bevel=.022)
    s.b(part,(.046,.205,.033),(0,-.443,-.149),"edge",bevel=.006)
    s.b(part,(.22 if heavy else .205,.070,.155),(0,-.605,-.156),"steel",bevel=.025)
    s.b(part,(.22 if heavy else .205,.024,.044),(0,-.58,-.108),"edge",bevel=.006)


def helmet_fittings(s, part, heavy=False):
    if heavy:
        # Follows the saved open-faced helmet, leaving its eyes at y=.06 clear.
        s.add(part,lathe([(.151,.309),(.190,.308)],12,(0,0,-.025),caps=False),"darksteel")
        s.b(part,(.09,.10,.25),(0,.357,-.005),"darksteel",bevel=.025)
        s.b(part,(.055,.085,.22),(0,.385,-.005),"blue",bevel=.012)
        s.b(part,(.46,.055,.085),(0,-.169,.199),"darksteel",bevel=.014)
        for sign in (-1,1):
            s.e(part,(.028,.028,.013),(sign*.249,.021,-.223),"edge",sub=0)
    else:
        # A low cloth crest and charcoal brow band are readable from above,
        # without the tall horsehair plume reserved for a future royal grade.
        s.add(part,lathe([(-.012,.342),(.031,.340)],12,(0,0,-.10),caps=False),"darksteel")
        s.add(part,polygon([(-.055,-.045),(.09,-.045),(.13,.05),(.10,.13),(-.04,.11)],
                           .065,(0,.35,-.10),(0,math.pi/2,0)),"blue")
        s.b(part,(.075,.038,.17),(0,.326,-.085),"darksteel",bevel=.010)
        for sign in (-1,1):
            s.e(part,(.022,.022,.013),(sign*.224,.002,-.351),"edge",sub=0)


def sword_fittings(s, part):
    s.b(part,(.33,.065,.078),(0,.073,0),"darksteel",rot=(0,0,.05),bevel=.017)
    for sign in (-1,1):
        s.b(part,(.067,.055,.086),(sign*.141,.080,0),"edge",rot=(0,0,sign*.13),bevel=.015)
    s.b(part,(.116,.063,.049),(0,.137,0),"steel",bevel=.011)
    s.e(part,(.045,.040,.048),(0,-.17,0),"edge",sub=0)


def sword_shield(s, part, center):
    x,y,z=center
    outline=[(-.29,.34),(.29,.34),(.28,-.09),(0,-.43),(-.28,-.09)]
    s.add(part,polygon(outline,.105,center),"darksteel")
    s.add(part,polygon([(a*.83,b*.84) for a,b in outline],.025,(x,y,z-.063)),"blue")
    s.add(part,border(outline,.84,.038,(x,y,z-.062)),"steel")
    # Steel corner braces and a silver boss; modest gold cross retains identity.
    for sign in (-1,1):
        s.b(part,(.075,.22,.038),(x+sign*.227,y+.175,z-.085),"edge",rot=(0,0,sign*.16),bevel=.011)
    s.b(part,(.048,.51,.024),(x,y+.012,z-.09),"gold",bevel=.006)
    s.b(part,(.36,.048,.026),(x,y+.075,z-.091),"gold",bevel=.006)
    s.e(part,(.085,.085,.040),(x,y+.075,z-.108),"steel")
    s.e(part,(.034,.034,.012),(x,y+.075,z-.145),"goldlight",sub=0)


def guard_shield(s, part, outline, center):
    x,y,z=center
    # Extend thickness forward only: the back face and both grip supports retain
    # their original positions, so gauntlets remain connected to the handle.
    s.add(part,polygon(outline,.16,(x,y,z-.020)),"darksteel")
    s.add(part,polygon([(a*.88,b*.93) for a,b in outline],.018,(x,y,-.488)),"wood")
    s.add(part,polygon([(a*.84,b*.89) for a,b in outline],.025,(x,y,-.674)),"blue")
    s.add(part,border(outline,.86,.050,(x,y,-.675)),"steel")
    s.b(part,(.138,1.09,.049),(x,y,-.707),"darksteel",bevel=.018)
    s.b(part,(.042,.96,.029),(x,y,-.741),"edge",bevel=.008)
    s.b(part,(.65,.082,.045),(x,y+.22,-.713),"steel",bevel=.014)
    s.e(part,(.101,.099,.045),(x,y+.22,-.747),"edge")
    s.e(part,(.039,.04,.014),(x,y+.22,-.79),"gold",sub=0)
    for sign in (-1,1):
        for yy in (-.44,.45):
            s.b(part,(.12,.18,.050),(x+sign*.328,y+yy,-.70),"edge",rot=(0,0,sign*-.08),bevel=.020)
            s.e(part,(.024,.024,.013),(x+sign*.328,y+yy,-.733),"darksteel",sub=0)
