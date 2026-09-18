"""Advanced spear/longbow fittings; all geometry stays in existing rigid parts."""
import math
import numpy as np
from build_units import lathe, polygon, tm
from unit_advanced_infantry import plate


def spear_torso(s, part):
    # Three overlapping curved lames keep the levy lighter than sword infantry.
    s.add(part, plate([(-.145,.287),(.08,.352),(.283,.369)], half_span=55), "darksteel")
    for low, high, r0, r1 in [(-.145,.025,.291,.338),(-.005,.155,.334,.366),(.125,.29,.364,.365)]:
        s.add(part, plate([(low,r0),(high,r1)], half_span=54, thickness=.028), "steel")
        s.add(part, plate([(low,r0+.008),(low+.024,r0+.014)], half_span=54, thickness=.016), "edge")
    s.add(part, plate([(-.13,.281),(.07,.345),(.27,.355)], front=False, half_span=55), "steel")
    s.add(part, plate([(.232,.365),(.27,.357)], front=False, half_span=55, thickness=.022), "edge")
    for sign in (-1,1):
        s.b(part,(.075,.24,.24),(sign*.285,.045,.005),"darksteel",bevel=.018)
        s.b(part,(.058,.083,.038),(sign*.16,.242,-.340),"leather",rot=(0,-sign*.4,0),bevel=.009)
        s.b(part,(.19,.08,.062),(sign*.13,-.25,-.224),"steel",rot=(0,0,-sign*.07),bevel=.013)
        s.b(part,(.17,.07,.056),(sign*.13,-.315,-.211),"darksteel",rot=(0,0,-sign*.07),bevel=.013)


def spear_shoulder(s, part, sign):
    s.e(part,(.223,.155,.225),(sign*.035,.012,0),"darksteel")
    s.b(part,(.35,.108,.395),(sign*.045,.091,-.004),"steel",rot=(0,0,-sign*.10),bevel=.033)
    s.b(part,(.11,.13,.335),(sign*.205,-.052,0),"steel",rot=(0,0,-sign*.22),bevel=.020)
    s.b(part,(.105,.027,.34),(sign*.218,-.11,0),"edge",rot=(0,0,-sign*.22))
    s.e(part,(.018,.018,.012),(sign*.06,.074,-.207),"gold",sub=0)


def spear_bracer(s, part, elbow, wrist):
    a,b=np.array(elbow),np.array(wrist)
    for begin,end,radius,color in [(.18,.65,.113,"darksteel"),(.23,.62,.116,"steel"),(.65,.74,.12,"edge")]:
        s.r(part,tuple(a+(b-a)*begin),tuple(a+(b-a)*end),radius,color,8)


def spear_greave(s, part):
    s.add(part,polygon([(-.082,.052),(.082,.052),(.098,-.02),(0,-.10),(-.098,-.02)],
                       .047,(0,-.258,-.136)),"steel")
    s.b(part,(.15,.22,.047),(0,-.423,-.108),"steel",bevel=.021)
    s.b(part,(.038,.21,.024),(0,-.421,-.141),"edge",bevel=.005)
    s.b(part,(.194,.035,.172),(0,-.50,-.010),"leather",bevel=.008)


def spear_shield(s, part):
    # The original small wooden board stays visible between two narrow straps.
    for x in (-.24-.085,-.24+.085):
        s.b(part,(.038,.448,.024),(x,-.37,-.489),"darksteel",bevel=.006)
        for y in (-.55,-.19):
            s.e(part,(.012,.012,.009),(x,y,-.505),"edge",sub=0)


def spear_fittings(s, part):
    for y in (1.26,1.34):
        s.r(part,(0,y,0),(0,y+.03,0),.057,"darksteel",10)
        s.r(part,(0,y+.009,0),(0,y+.021,0),.059,"edge",10)
    s.r(part,(0,-.21,0),(0,-.15,0),.040,"blue",10)


def archer_strap(s, part):
    # A continuous leather ribbon follows the curved cuirass instead of a flat
    # diagonal box that cuts through it. Closed thickness prevents backface gaps.
    stations=np.linspace(-.17,.28,7)
    verts=[]
    for inset in (0,.022):
        for y in stations:
            x=(y+.17)*.64-.125
            for edge in (-1,1):
                xx=x+edge*.034
                yy=y-edge*.021
                radius=float(np.interp(yy,[-.20,.02,.23,.31],[.298,.35,.372,.343]))
                verts.append((xx,yy,-math.sqrt(radius*radius-xx*xx)-.014+inset))
    layer=len(stations)*2
    faces=[]
    def quad(a,b,c,d): faces.extend(((a,b,c),(a,c,d)))
    for row in range(len(stations)-1):
        a=row*2
        quad(a,a+1,a+3,a+2)
        quad(a+layer,a+2+layer,a+3+layer,a+1+layer)
        quad(a,a+2,a+2+layer,a+layer)
        quad(a+1,a+1+layer,a+3+layer,a+3)
    quad(0,layer,layer+1,1)
    quad(layer-2,layer-1,2*layer-1,2*layer-2)
    mesh=tm.Trimesh(vertices=verts,faces=faces,process=False)
    mesh.fix_normals()
    assert mesh.is_watertight
    s.add(part,mesh,"leather")
    s.b(part,(.105,.048,.03),(.035,.08,-.359),"gold",rot=(0,0,-.57),bevel=.008)


def archer_torso(s, part):
    for front in (True,False):
        for low,high,r0,r1 in [(-.17,.04,.291,.345),(.01,.18,.342,.368),(.15,.295,.367,.348)]:
            s.add(part,plate([(low,r0),(high,r1)],front,half_span=52,thickness=.03),"leatherlight" if front else "leather")
            s.add(part,plate([(low,r0+.009),(low+.022,r0+.013)],front,half_span=52,thickness=.019),"leather")
    for sign in (-1,1):
        for y,z in [(.065,-.272),(.224,-.282)]:
            s.e(part,(.016,.016,.013),(sign*.224,y,z),"gold",sub=0)
        s.b(part,(.195,.115,.06),(sign*.14,-.272,-.207),"leatherlight",rot=(0,0,-sign*.10),bevel=.018)
    archer_strap(s,part)


def archer_shoulder(s, part, sign):
    s.e(part,(.218,.147,.220),(sign*.035,.005,0),"leather")
    s.b(part,(.33,.105,.355),(sign*.045,.079,-.005),"leatherlight",rot=(0,0,-sign*.10),bevel=.030)
    s.b(part,(.12,.112,.29),(sign*.196,-.076,0),"leatherlight",rot=(0,0,-sign*.23),bevel=.022)
    s.b(part,(.12,.023,.298),(sign*.205,-.126,0),"leather",rot=(0,0,-sign*.23))
    for x in (-.075,.075):
        s.e(part,(.013,.013,.01),(sign*.045+x,.052,-.192),"gold",sub=0)


def archer_bracer(s, part, elbow, wrist):
    a,b=np.array(elbow),np.array(wrist)
    s.r(part,tuple(a+(b-a)*.13),tuple(a+(b-a)*.77),.112,"leather",8)
    for low,high in [(.17,.27),(.65,.75)]:
        s.r(part,tuple(a+(b-a)*low),tuple(a+(b-a)*high),.117,"leatherlight",8)
    center=(a+b)*.5+np.array((0,0,-.106))
    s.b(part,(.108,.142,.03),tuple(center),"leatherlight",bevel=.012)


def archer_gaiter(s, part):
    s.b(part,(.163,.22,.049),(0,-.425,-.104),"leatherlight",bevel=.018)
    for y in (-.33,-.49):
        s.b(part,(.195,.037,.183),(0,y,-.009),"leather",bevel=.008)
        s.b(part,(.043,.035,.018),(.068,y,-.111),"gold",bevel=.004)


def archer_quiver(s, part):
    center=(.19,.03,.345)
    for low,high,r in [(-.27,-.21,.119),(.18,.235,.150)]:
        s.add(part,lathe([(low,r),(high,r+.003)],10,center,(0,0,-.14),caps=False),"leatherlight")
    s.add(part,lathe([(-.298,.109),(-.251,.116)],10,center,(0,0,-.14)),"darksteel")
    s.b(part,(.061,.30,.026),(.225,.002,.481),"leatherlight",rot=(0,0,-.14),bevel=.009)


def archer_bow(s, part, points):
    def point(y):
        return (0,y,float(np.interp(y,[p[1] for p in points],[p[2] for p in points])))
    for sign in (-1,1):
        s.r(part,point(sign*.16),point(sign*.22),.040,"leather",8)
        s.r(part,point(sign*.45),point(sign*.50),.039,"leather",8)
        s.r(part,point(sign*.53),point(sign*.565),.036,"steel",8)
        s.r(part,point(sign*.114),point(sign*.143),.043,"gold",8)
