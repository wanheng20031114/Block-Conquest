"""Shared seated rider anatomy for ordinary and advanced elephants.

The pelvis, legs and footrests are part of the saddle/body rigid mesh. Only the
upper body leans during an attack; it cannot drag the legs through the seat.
All geometry is authored offline and saved in the existing fourteen-part rig.
"""
from build_units import lathe
from unit_model_geometry import fitted_front_panel

RIDER_ORIGIN = (0, 1.08, .12)


def seated_legs(s, body, advanced):
    # The seat top is .895. Thighs rest above it and the shins clear the cloth
    # edge at x=.66; boots stay above the side drape's .39 upper edge.
    s.b(body,(.49,.075,.34),(0,.9325,.17),"leather",bevel=.025)
    s.e(body,(.225,.11,.20),(0,1.035,.17),"leather")
    for sign in (-1,1):
        hip=(sign*.14,1.035,.12)
        knee=(sign*.58,1.025,.08)
        ankle=(sign*.91,.61,.01)
        s.r(body,hip,knee,.100,"leather",8)
        s.e(body,(.106,.102,.106),knee,"leather")
        s.r(body,knee,ankle,.085,"blue",8)
        s.b(body,(.19,.17,.29),(sign*.92,.52,-.005),"leather",bevel=.028)
        s.b(body,(.245,.034,.325),(sign*.92,.418,-.005),"darksteel",bevel=.006)
        # Rearward straps skirt the cloth corner, instead of cutting through it.
        s.r(body,(sign*.42,.88,.25),(sign*.69,.78,.23),.018,"leather",6)
        s.r(body,(sign*.69,.78,.23),(sign*.96,.435,.16),.018,"leather",6)
        if advanced:
            s.b(body,(.17,.13,.038),(sign*.58,1.025,-.026),"steel",bevel=.018)


def upper_body(s, rider, advanced):
    # Short seated hem clears the front rail while the waist remains in the
    # cushion. Both grades use the same silhouette and hand/rail clearances.
    tunic=lathe([(-.085,.218),(.02,.235),(.25,.29),(.34,.22)],8)
    s.add(rider,tunic,"blue")
    if advanced:
        from unit_advanced_cavalry import elephant_rider
        elephant_rider(s,rider)
    else:
        # A flat slab intersected the bulging tunic. Fit the actual front faces.
        rows=[(.01,.16),(.02,.18),(.16,.21),(.25,.21),(.30,.16)]
        s.add(rider,fitted_front_panel(tunic,rows,inset=.030),"steel")
    s.b(rider,(.44,.075,.38),(0,-.045,0),"leather",bevel=.02)
    s.b(rider,(.083,.075,.032),(0,-.038,-.213),"gold")
    for side in (-1,1):
        s.e(rider,(.15,.12,.155),(side*.28,.25,-.01),"steel")
        elbow=(side*.32,.06,-.24)
        hand=(side*.16,.08,-.42)
        s.r(rider,(side*.28,.18,-.03),elbow,.083,"blue",8)
        s.r(rider,elbow,hand,.073,"leather",8)
        s.e(rider,(.073,.067,.079),hand,"skin")
        # The rail end stays embedded inside the wood over the complete lean
        # cycle. The grasped end remains inside the palm, above the rail cap.
        s.r(rider,(side*.16,.08,-.455),(side*.29,-.10,-.33),.016,"rope",6)
