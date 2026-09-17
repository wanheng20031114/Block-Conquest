"""Build only the current defensive building; never rebuild the environment set.

python tools/build_defenses.py cannon_tower
Godot --headless --path . --script res://tools/build_defense_meshes.gd
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
import trimesh as tm
from build_environment import Model, arched_gate, stone_rows, write_asset

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/environment/cannon_tower"


def export_part(name, model):
    scene = tm.Scene()
    count = 0
    for family, pieces in model.parts.items():
        for piece in pieces:
            rgba = piece.visual.vertex_colors.copy()
            srgb = rgba[:, :3].astype(float) / 255
            rgba[:, :3] = np.round(np.where(srgb <= .04045, srgb / 12.92, ((srgb + .055) / 1.055) ** 2.4) * 255).astype(np.uint8)
            rgba[:, 3] = 255 if piece.metadata.get("heraldry", False) else 0
            piece.visual = tm.visual.ColorVisuals(mesh=piece, vertex_colors=rgba)
        mesh = tm.util.concatenate(pieces)
        mesh.update_faces(mesh.nondegenerate_faces())
        mesh.unmerge_vertices()
        count += len(mesh.faces)
        scene.add_geometry(mesh, node_name=family, geom_name=family)
    write_asset(OUT / (name + ".glb"), scene.export(file_type="glb", include_normals=True))
    return {"part": name, "families": list(model.parts), "triangles": count}


def cannon_tower():
    base, mount, barrel = Model(), Model(), Model()
    # Broad stone footing, alternating courses, a recessed rear access door.
    base.box((4.98, .32, 4.98), (0, .16, 0), "stone", bevel=.12)
    base.box((4.58, .26, 4.58), (0, .44, 0), "stone_light", bevel=.07)
    base.box((4.12, 2.18, 4.12), (0, 1.63, 0), "mortar", bevel=.11)
    for yaw in (0, math.pi/2, math.pi, -math.pi/2):
        wall = Model()
        stone_rows(wall, 4.18, 2.16, .17, (0, .55, 2.06), rows=5)
        base.absorb(wall, rot=yaw)
    # Pilasters make the masonry read as a fortification from RTS height.
    for x in (-1.9, 1.9):
        for z in (-1.9, 1.9):
            base.box((.55, 2.3, .55), (x, 1.7, z), "stone_light", bevel=.055)
            base.box((.7, .18, .7), (x, .66, z), "stone", bevel=.035)
    arched_gate(base, 1.12, 1.85, .2, (0, .48, 2.18))
    base.box((1.7, .18, .55), (0, .38, 2.16), "stone_light", bevel=.04)
    base.box((4.72, .25, 4.72), (0, 2.85, 0), "stone_light", bevel=.06)
    base.box((4.55, .18, 4.55), (0, 3.05, 0), "wood_dark", bevel=.05)
    for x in np.linspace(-1.93, 1.93, 11):
        base.box((.35, .08, 4.32), (x, 3.17, 0), "wood_light", bevel=.016)
    # Corner merlons leave open arcs in front of the rotating gun.
    for x in (-1.96, 1.96):
        for z in (-1.96, 1.96):
            base.box((.68, .66, .68), (x, 3.31, z), "stone", bevel=.06)
            base.box((.76, .14, .76), (x, 3.68, z), "stone_light", bevel=.045)
    # Team-coloured shield banners on the three solid walls, brass cannonballs crest.
    for yaw in (math.pi, math.pi/2, -math.pi/2):
        crest = Model()
        shape = [(-.65, 2.48), (.65, 2.48), (.65, 1.53), (0, 1.16), (-.65, 1.53)]
        crest.polygon(shape, .07, "gold")
        panel = Model()
        panel.polygon([(x*.9, 1.87+(y-1.87)*.9) for x,y in shape], .04, "blue")
        crest.absorb(panel, pos=(0,0,.065))
        for x,y in ((-.19,1.8),(.19,1.8),(0,2.1)):
            crest.cylinder(.12, .05, (x,y,.12), "gold_light", 10, (math.pi/2,0,0))
        base.absorb(crest, pos=(math.sin(yaw)*2.19, 0, math.cos(yaw)*2.19), rot=yaw)
    # Stationary bearing below the independently rotating gun carriage.
    base.cylinder(1.23,.16,(0,3.29,0),"iron",24)
    base.ring(1.1,1.26,.07,(0,3.38,0),"gold",24)
    mount.cylinder(.99,.22,(0,.1,0),"wood",20)
    mount.box((1.66,.2,1.8),(0,.28,.2),"wood_dark",bevel=.04)
    for x in (-.65,.65):
        mount.box((.24,1.07,1.35),(x,.80,.25),"wood_light",bevel=.05)
        mount.box((.29,.14,1.5),(x,.4,.25),"iron",bevel=.025)
        mount.cylinder(.2,.34,(x,1.18,0),"iron",12,(0,0,math.pi/2))
        mount.cylinder(.12,.025,(x+math.copysign(.185,x),1.18,0),"gold",12,(0,0,math.pi/2))
    # Longitudinal Z gun, muzzle towards -Z. Hollow muzzle, no fake black decal.
    barrel.cone(.37,.47,2.64,(0,0,-.66),"iron",20,(math.pi/2,0,0))
    barrel.ring(.245,.41,.38,(0,0,-2.16),"iron",20,(math.pi/2,0,0))
    barrel.ring(.245,.455,.13,(0,0,-2.37),"iron_light",20,(math.pi/2,0,0))
    barrel.cylinder(.25,.015,(0,0,-1.99),"dark",20,(math.pi/2,0,0))
    barrel.cone(.46,.30,.4,(0,0,.86),"iron",16,(math.pi/2,0,0))
    barrel.cylinder(.13,.22,(0,0,1.14),"gold",12,(math.pi/2,0,0))
    for z,r in ((-.95,.44),(.46,.49)):
        barrel.ring(r-.03,r+.025,.10,(0,0,z),"gold",20,(math.pi/2,0,0))
        barrel.ring(r-.01,r+.036,.052,(0,0,z),"blue",20,(math.pi/2,0,0))
    # Fuse socket and sight give the back and top a legible orientation.
    barrel.box((.12,.13,.16),(0,.47,.55),"gold",bevel=.025)
    barrel.box((.06,.09,.12),(0,.40,-1.70),"iron_light",bevel=.012)
    parts = [export_part(n,m) for n,m in (("base",base),("mount",mount),("barrel",barrel))]
    write_asset(OUT / "parts.json", json.dumps(parts, indent=2)+"\n")
    print("Cannon tower:", sum(p["triangles"] for p in parts), "triangles;", sum(len(p["families"]) for p in parts), "rigid surfaces")


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("building", choices=["cannon_tower"])
    parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    cannon_tower()
