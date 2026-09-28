"""Offline geometry primitives for Block Conquest architecture and nature.

All visible detail is exported as actual low-poly GLB geometry, grouped by
material family.  Godot only instances the saved models; it does not build
individual shingles, stones, spokes or grass blades while the game runs.
"""
from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path

import numpy as np
import trimesh as tm
from shapely import constrained_delaunay_triangles
from shapely.geometry import Polygon

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/block_war/architecture"
OUT.mkdir(parents=True, exist_ok=True)
RNG = np.random.default_rng(932710)

C = {
    "stone": (197, 177, 134), "stone_light": (226, 211, 172),
    "plaster": (218, 202, 164), "mortar": (130, 118, 94),
    "wood": (101, 66, 39), "wood_light": (145, 104, 62),
    "wood_dark": (62, 43, 31), "iron": (71, 76, 72),
    "iron_light": (132, 138, 130), "gold": (209, 159, 64),
    "slate": (44, 78, 121), "slate_light": (62, 100, 145),
    "terracotta": (158, 77, 46), "terracotta_light": (190, 104, 58),
    "blue": (38, 85, 129), "red": (140, 45, 34),
    "dark": (42, 37, 31), "glass": (48, 66, 62),
    "leaf": (91, 105, 54), "leaf_light": (125, 131, 65),
    "grass": (136, 129, 74), "grass_light": (171, 153, 91),
    "earth": (126, 98, 60), "sand": (166, 132, 79),
    "road": (195, 159, 102), "water": (71, 96, 92),
    "paving": (148, 137, 113), "road_mortar": (104, 91, 66),
    "canvas": (180, 166, 131), "burlap": (154, 127, 82),
    "straw": (157, 129, 62), "straw_light": (193, 164, 87),
    "granite": (103, 103, 94), "granite_light": (142, 141, 123),
    "ore_rock": (78, 83, 82), "ore_rock_light": (115, 119, 107),
    "gold_light": (238, 190, 82), "gold_dark": (170, 119, 39),
    "leaf_dark": (55, 75, 47), "leaf_pine": (68, 89, 50),
    "bark": (95, 67, 45), "bark_light": (129, 90, 51),
}


def color(value, variation=0.0):
    value = C.get(value, value) if isinstance(value, str) else value
    return np.array([*np.clip(np.asarray(value, dtype=float) * (1.0 + variation), 0, 255), 255], dtype=np.uint8)


def write_asset(path, data):
    """Publish complete files atomically while the user's editor auto-imports."""
    if isinstance(data,str):
        data=data.encode("utf-8")
    if path.exists() and path.read_bytes()==data:
        return
    temporary=path.with_suffix(path.suffix+".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def family(value):
    if not isinstance(value, str):
        return "Earth"
    if value in ("iron", "iron_light", "gold", "gold_light", "gold_dark"):
        return "Metal"
    if value in ("blue", "red", "canvas", "burlap"):
        return "Fabric"
    if "wood" in value or "bark" in value:
        return "Timber"
    if "leaf" in value or "grass" in value:
        return "Foliage"
    if value in ("slate", "slate_light", "terracotta", "terracotta_light"):
        return "Roof"
    if value in ("glass", "water"):
        return "Glass"
    return "Stone"


def transform(pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    mat = tm.transformations.euler_matrix(*rot)
    mat[:3, :3] = mat[:3, :3] @ np.diag(scale)
    mat[:3, 3] = pos
    return mat


def extruded_contour(points, depth, center_z):
    """Preserve concave breaks in a masonry silhouette with ear clipping."""
    def cross2(a,b):
        return a[0]*b[1]-a[1]*b[0]
    points=np.asarray(points,dtype=float)
    area=sum(cross2(points[i],points[(i+1)%len(points)]) for i in range(len(points)))
    if area<0:
        points=points[::-1]
    remaining=list(range(len(points)))
    triangles=[]
    while len(remaining)>3:
        for index,current in enumerate(remaining):
            previous=remaining[index-1]
            following=remaining[(index+1)%len(remaining)]
            a,b,c=points[previous],points[current],points[following]
            if cross2(b-a,c-b)<=1e-9:
                continue
            occupied=False
            for other in remaining:
                if other in (previous,current,following):continue
                p=points[other]
                if min(cross2(b-a,p-a),cross2(c-b,p-b),cross2(a-c,p-c))>=-1e-9:
                    occupied=True
                    break
            if not occupied:
                triangles.append([previous,current,following])
                remaining.pop(index)
                break
        else:
            raise ValueError("The masonry contour must be a simple polygon")
    triangles.append(remaining)
    count=len(points)
    verts=[[x,y,z] for z in (center_z-depth/2,center_z+depth/2) for x,y in points]
    faces=[tri[::-1] for tri in triangles]+[[i+count for i in tri] for tri in triangles]
    for i in range(count):
        j=(i+1)%count
        faces.extend([[i,j,count+j],[i,count+j,count+i]])
    mesh=tm.Trimesh(verts,faces,process=False)
    mesh.fix_normals()
    return mesh


class Model:
    def __init__(self):
        self.parts = defaultdict(list)

    def add(self, mesh, material="stone", pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), variation=0.0):
        mesh = mesh.copy()
        mesh.apply_transform(transform(pos, rot, scale))
        mesh.visual.vertex_colors = np.tile(color(material, variation), (len(mesh.vertices), 1))
        mesh.metadata["heraldry"] = isinstance(material,str) and material in ("blue","red","slate","slate_light")
        self.parts[family(material)].append(mesh)
        return mesh

    def box(self, size, pos, material="stone", rot=(0, 0, 0), bevel=0.0, variation=0.0):
        size = np.asarray(size, dtype=float)
        if bevel:
            radius = min(bevel, min(size) * .24)
            verts = []
            for axis in range(3):
                for a in (-1, 1):
                    for b in (-1, 1):
                        for d in (-1, 1):
                            p = np.array([a, b, d]) * (size * .5 - radius)
                            p[axis] += np.sign(p[axis]) * radius
                            verts.append(p)
            mesh = tm.convex.convex_hull(np.asarray(verts))
        else:
            mesh = tm.creation.box(size)
        return self.add(mesh, material, pos, rot, variation=variation)

    def cylinder(self, radius, height, pos, material="wood", sections=10, rot=(0, 0, 0), variation=0.0):
        mesh = tm.creation.cylinder(radius=radius, height=height, sections=sections)
        mesh.apply_transform(tm.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0]))
        return self.add(mesh, material, pos, rot, variation=variation)

    def cone(self, r1, r2, height, pos, material="wood", sections=8, rot=(0, 0, 0)):
        verts = []
        for y, r in ((-height / 2, r1), (height / 2, r2)):
            verts.extend([(math.cos(a * math.tau / sections) * r, y, math.sin(a * math.tau / sections) * r) for a in range(sections)])
        faces = []
        for i in range(sections):
            j = (i + 1) % sections
            faces += [[i, j, sections + j], [i, sections + j, sections + i]]
        faces += [[0, i + 1, i] for i in range(1, sections - 1)]
        faces += [[sections, sections + i, sections + i + 1] for i in range(1, sections - 1)]
        mesh = tm.Trimesh(verts, faces, process=False)
        mesh.fix_normals()
        return self.add(mesh, material, pos, rot)

    def beam(self, start, end, width=.16, material="wood", depth=None, bevel=.012):
        start, end = np.asarray(start, float), np.asarray(end, float)
        delta = end - start
        mesh = tm.creation.box((width, np.linalg.norm(delta), depth or width))
        mat = tm.geometry.align_vectors([0, 1, 0], delta)
        mesh.apply_transform(mat)
        return self.add(mesh, material, (start + end) / 2)

    def polygon(self, points, thickness=.12, material="stone", axis="z", variation=0.0):
        # Convex polygons used for stone fractures, roof gables and fabric.
        points = np.asarray(points)
        if axis == "z":
            verts = [[x, y, z] for z in (-thickness / 2, thickness / 2) for x, y in points]
        else:
            verts = [[x, y, z] for y in (-thickness / 2, thickness / 2) for x, z in points]
        return self.add(tm.convex.convex_hull(np.asarray(verts)), material, variation=variation)

    def ring(self, inner, outer, height, pos, material="iron", sections=14, rot=(0, 0, 0)):
        verts = []
        for y in (-height / 2, height / 2):
            for radius in (inner, outer):
                verts.extend([(math.cos(a * math.tau / sections) * radius, y, math.sin(a * math.tau / sections) * radius) for a in range(sections)])
        faces = []
        for a in range(sections):
            b = (a + 1) % sections
            for q0, q1, q2, q3 in ((a, b, sections + b, sections + a), (2*sections+a, 3*sections+a, 3*sections+b, 2*sections+b), (a, 2*sections+a, 2*sections+b, b), (sections+a, sections+b, 3*sections+b, 3*sections+a)):
                faces.extend([[q0, q1, q2], [q0, q2, q3]])
        mesh = tm.Trimesh(verts, faces, process=False)
        mesh.fix_normals()
        return self.add(mesh, material, pos, rot)

    def absorb(self, other, pos=(0, 0, 0), rot=0.0, scale=(1, 1, 1)):
        mat = transform(pos, (0, rot, 0), scale)
        for group, meshes in other.parts.items():
            for mesh in meshes:
                item = mesh.copy()
                item.apply_transform(mat)
                self.parts[group].append(item)

    def save(self, name, wrapper=True):
        scene = tm.Scene()
        for group, meshes in self.parts.items():
            merged = tm.util.concatenate(meshes)
            if wrapper:
                merged.vertices[:, 1] = np.maximum(merged.vertices[:, 1], 0.0)
            # Compare triangles by position without welding their vertices:
            # neighboring stones/soil regions intentionally keep distinct colors
            # and hard normals at an otherwise shared geometric edge.
            triangles=np.round(merged.triangles,8)
            order=np.lexsort((triangles[:,:,2],triangles[:,:,1],triangles[:,:,0]),axis=1)
            canonical=np.take_along_axis(triangles,order[:,:,None],axis=1)
            _,unique=np.unique(canonical.reshape((-1,9)),axis=0,return_index=True)
            merged.update_faces(np.sort(unique))
            merged.update_faces(merged.nondegenerate_faces(height=1e-7))
            merged.unmerge_vertices()
            rgba = merged.visual.vertex_colors.copy()
            srgb = rgba[:, :3].astype(np.float32) / 255.0
            linear = np.where(srgb <= .04045, srgb / 12.92, ((srgb + .055) / 1.055) ** 2.4)
            rgba[:, :3] = np.round(linear * 255).astype(np.uint8)
            roughness = .82
            metalness = 0.0
            if group == "Metal":
                metalness, roughness = .65, .38
            elif group == "Glass":
                metalness, roughness = .05, .32
            material = tm.visual.material.PBRMaterial(name=group, baseColorFactor=[255, 255, 255, 255], metallicFactor=metalness, roughnessFactor=roughness, doubleSided=False)
            merged.visual = tm.visual.TextureVisuals(material=material)
            merged.visual.vertex_attributes["color"] = rgba
            # Export glTF COLOR_0 alongside PBR materials.
            merged.vertex_attributes["_COLOR_0"] = rgba.astype(np.float32) / 255.0
            scene.add_geometry(merged, node_name=group, geom_name=group)
        # trimesh exports vertex color automatically for ColorVisuals, with a
        # neutral PBR material added afterwards below to retain exact palette.
        for geometry in scene.geometry.values():
            rgba = (geometry.vertex_attributes.pop("_COLOR_0") * 255).astype(np.uint8)
            mat = geometry.visual.material
            geometry.visual = tm.visual.ColorVisuals(mesh=geometry, vertex_colors=rgba)
            geometry.metadata["material_family"] = mat.name
        floor_offset = scene.bounds[0, 1]
        if wrapper and floor_offset > 0.0001:
            for geometry in scene.geometry.values():
                geometry.vertices[:, 1] -= floor_offset

        def materials(tree):
            tree["materials"] = []
            for mesh in tree["meshes"]:
                group = mesh["name"]
                metalness, roughness = (.65, .38) if group == "Metal" else (0.0, .84)
                if group == "Glass":
                    metalness, roughness = .05, .34
                index = len(tree["materials"])
                tree["materials"].append({"name": group, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": metalness, "roughnessFactor": roughness}, "doubleSided": group in ("Fabric", "Foliage")})
                for primitive in mesh["primitives"]:
                    primitive["material"] = index
        blob = tm.exchange.gltf.export_glb(scene, include_normals=True, tree_postprocessor=materials)
        write_asset(OUT / f"{name}.glb",blob)
        bounds = scene.bounds
        print(f"{name}: {sum(len(g.faces) for g in scene.geometry.values()):,} triangles, {len(scene.geometry)} meshes, bounds {np.round(bounds, 2).tolist()}")
        return {"bounds": bounds.tolist(), "triangles": sum(len(g.faces) for g in scene.geometry.values()), "meshes": len(scene.geometry)}
