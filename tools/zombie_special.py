"""The bell bearer and door bearer, isolated monster sculptures."""
import math
from build_units import P, lathe, polygon
from unit_zombie import cut_block
from zombie_variant_common import base_variant

GRIP = (0, -.265, -.008)


def _palette():
    P.update({"zombie_coat": (89, 91, 76), "zombie_coat_edge": (130, 125, 101),
              "zombie_doorwood": (109, 93, 66), "zombie_doorlight": (133, 114, 80),
              "zombie_doordark": (81, 73, 56)})


def _track(s, part, values, times, prop="rotation"):
    return (s.part_path(part) + ":" + prop, values, times)


def build_zombie_door():
    s = base_variant("zombie_door")
    _palette()
    s.monster_rest.update({"ArmLeft": (.90, .02, -.16), "ForearmLeft": (.55, 0, 0),
                           "ArmRight": (.38, -.04, .18), "ForearmRight": (.25, 0, 0)})
    door = s.joint("Door", GRIP, "ForearmLeft")
    s.monster_rest[door] = (-1.45, -.04, .02)
    # Five differently worn planks form a broken outline. Cracks remain shallow
    # and do not expose a paper-thin shield; both faces have real wood depth.
    for i, (low, high) in enumerate([(-.77, .54), (-.79, .58), (-.75, .58), (-.78, .55), (-.67, .46)]):
        x = (i - 2) * .15
        pts = [(x-.073, low+.04), (x-.060, low), (x+.073, low+.02),
               (x+.073, high-.035), (x+.050, high), (x-.073, high-.014)]
        s.add(door, polygon(pts, .085, pos=(0, 0, -.18)),
              "zombie_doorlight" if i in (1, 4) else "zombie_doorwood")
        for y in (-.30, .18):
            s.b(door, (.009, .22, .004), (x+.038, y, -.224), "zombie_doordark", rot=(0, 0, .025*(i-2)), bevel=0)
    for y in (.35, -.51):
        s.b(door, (.776, .081, .030), (0, y, -.236), "darksteel", bevel=.008)
        for x in (-.31, -.14, .14, .31):
            s.b(door, (.024, .024, .014), (x, y, -.257), "steel", bevel=.005)
        s.b(door, (.74, .068, .043), (0, y, -.114), "zombie_doordark", bevel=.006)
    # Former lock and hinges, with a new rear handgrip and forearm strap.
    s.b(door, (.089, .177, .022), (.235, -.04, -.236), "darksteel", bevel=.006)
    s.r(door, (.24, -.06, -.259), (.24, -.015, -.259), .016, "black", sections=6)
    for y in (.37, -.47):
        s.r(door, (-.37, y-.083, -.195), (-.37, y+.083, -.195), .035, "darksteel", sections=8)
    for y in (-.092, .092):
        s.r(door, (0, y, -.128), (0, y, .002), .023, "zombie_doordark", sections=6)
    s.r(door, (0, -.102, 0), (0, .102, 0), .030, "leather", sections=8)
    for x in (-.14, .14):
        s.r(door, (x, .15, -.127), (x, .15, .07), .021, "leather", sections=6)
    s.r(door, (-.14, .15, .07), (.14, .15, .07), .021, "leather", sections=6)
    # Extra worn protection, kept subordinate to the door silhouette.
    s.b("Body", (.43, .080, .38), (0, -.115, 0), "leather", bevel=.014)
    s.b("ArmRight", (.272, .096, .29), (0, .015, 0), "darksteel", rot=(0, 0, -.12), bevel=.018)
    for x in (-.083, .083):
        s.b("ArmRight", (.026, .020, .016), (x, .015, -.147), "steel", bevel=.005)
    s.monster_attack_length = 1.12
    t = [0, .20, .31, .40, .53, .82, 1.12]
    rest = s.monster_rest
    s.monster_tracks = [
        _track(s, "ArmRight", [rest["ArmRight"], (.41, -.06, .26), (.49, -.1, .26),
                               (1.45, -.14, .20), (1.50, -.14, .19), (.88, -.06, .20), rest["ArmRight"]], t),
        _track(s, "ForearmRight", [rest["ForearmRight"], (.67, 0, 0), (.78, 0, 0),
                                   (.10, 0, 0), (.08, 0, 0), (.29, 0, 0), rest["ForearmRight"]], t),
        _track(s, "Waist", [rest["Waist"], (.09, -.025, -.025), (.08, -.035, -.025),
                           (.14, .055, -.025), (.14, .06, -.025), (.11, .02, -.025), rest["Waist"]], t)]
    return s


def build_zombie_bell():
    s = base_variant("zombie_bell")
    _palette()
    # A patched sleeveless watchman's coat. No hood obscures the flat expression.
    for sign in (-1, 1):
        pts = [(sign*.245, .20), (sign*.18, .22), (sign*.10, -.39), (sign*.24, -.36)]
        s.add("Body", polygon(pts, .028, pos=(0, 0, -.193)), "zombie_coat")
    s.b("Body", (.39, .052, .026), (0, -.13, -.213), "leather", bevel=.004)
    s.b("Body", (.065, .056, .016), (-.05, -.13, -.234), "bronze", bevel=.005)
    for y in (-.05, .065, .175):
        s.b("Body", (.019, .032, .010), (.217, y, -.213), "zombie_coat_edge", bevel=.002)
    s.b("Body", (.19, .245, .11), (-.265, -.22, .08), "leather", bevel=.012)
    s.b("Body", (.205, .055, .128), (-.265, -.12, .08), "leatherlight", bevel=.007)
    s.b("Body", (.031, .080, .023), (-.265, -.18, .010), "bronze", bevel=.004)
    # Small discarded bell on belt, versus the clearly larger working bell.
    s.add("Body", lathe([(-.29,.061),(-.27,.060),(-.20,.024),(-.185,.022)], sections=8, pos=(.274,0,.04)), "bronze")
    s.r("Body", (.274,-.18,.04), (.274,-.10,.04), .013, "leather", sections=6)
    s.monster_rest.update({"ArmRight": (.65, -.05, .18), "ForearmRight": (.48, 0, 0),
                           "ArmLeft": (.40, .02, -.13), "ForearmLeft": (.30, 0, 0)})
    bell = s.joint("Bell", GRIP, "ForearmRight")
    s.monster_rest[bell] = (-1.13, 0, 0)
    s.r(bell, (0, -.17, 0), (0, .09, 0), .029, "wood", sections=8)
    s.r(bell, (0, .075, 0), (0, .105, 0), .043, "leather", sections=8)
    # Follow the wall into the interior so the opening is genuinely hollow.
    shell = [(-.16,.046),(-.21,.065),(-.32,.105),(-.43,.190),(-.47,.20),
             (-.49,.196),(-.49,.170),(-.458,.166),(-.416,.157),(-.315,.073),(-.223,.037),(-.19,.025)]
    s.add(bell, lathe(shell, sections=12, caps=False), "bronze")
    s.add(bell, lathe([(-.474,.203),(-.488,.202),(-.492,.193)], sections=12, caps=False), "bronzelight")
    s.add(bell, lathe([(-.21,.068),(-.23,.073)], sections=12, caps=False), "darksteel")
    clapper = s.joint("Clapper", (0,-.208,0), bell)
    s.r(clapper, (0,0,0), (0,-.241,0), .012, "darksteel", sections=6)
    s.add(clapper, lathe([(-.264,.012),(-.256,.035),(-.227,.035),(-.218,.014)], sections=8), "darksteel")
    s.monster_rest[clapper] = (0,0,0)
    s.monster_socket = ("ForearmLeft", (0,-.345,-.012))
    s.monster_attack_length = .95
    t = [0,.17,.27,.35,.48,.70,.95]
    r = s.monster_rest
    s.monster_tracks = [
        _track(s,"ArmLeft",[r["ArmLeft"],(.30,.08,-.19),(.41,.08,-.19),(1.36,.03,-.17),(1.43,.02,-.16),(.75,.02,-.13),r["ArmLeft"]],t),
        _track(s,"ForearmLeft",[r["ForearmLeft"],(.66,0,0),(.72,0,0),(.10,0,0),(.09,0,0),(.24,0,0),r["ForearmLeft"]],t)]
    t = [0,.25,.45,.62,.80,.98,1.16,1.34,1.52,1.72,2.0]
    arm = [r["ArmRight"],(.9,-.1,.30),(1.24,-.1,.37),(1.30,-.1,.37),(1.24,-.1,.37),
           (1.30,-.1,.37),(1.24,-.1,.37),(1.30,-.1,.37),(1.10,-.1,.30),(.82,-.06,.22),r["ArmRight"]]
    wrist = [r[bell],(-1.38,0,0),(-1.70,0,0),(-1.38,0,0),(-1.85,0,0),(-1.38,0,0),
             (-1.85,0,0),(-1.38,0,0),(-1.58,0,0),(-1.28,0,0),r[bell]]
    claps = [(a,0,0) for a in [0,-.18,.28,-.32,.32,-.32,.32,-.32,.20,-.10,0]]
    s.monster_extra_clips["rally"] = (2.0, [_track(s,"ArmRight",arm,t), _track(s,bell,wrist,t), _track(s,clapper,claps,t)])
    return s
