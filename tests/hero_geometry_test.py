"""Guard the curved face against the original large-triangle penetration bug."""
from pathlib import Path
import sys
import json
import unittest
import numpy as np
import trimesh

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_hero import BODY_SECTIONS, surface_z


class HeroGeometryTest(unittest.TestCase):
    def test_baked_face_stays_attached_above_cylinder(self):
        scene = trimesh.load(ROOT / 'assets/models/heroes/capsule/Face.glb')
        mesh = trimesh.util.concatenate(list(scene.geometry.values()))
        # Sample triangle interiors as well as vertices: the old fan passed a
        # vertex-only check, yet its interiors cut across the curved body.
        samples = np.concatenate([mesh.vertices, mesh.triangles_center,
                                  mesh.triangles[:, 0]*.6 + mesh.triangles[:, 1]*.2 + mesh.triangles[:, 2]*.2])
        offsets = np.array([surface_z(x,y,0)-z for x,y,z in samples])
        self.assertGreater(float(offsets.min()), .001)
        self.assertLess(float(offsets.max()), .010)
        self.assertGreater(float(np.ptp(mesh.vertices[:,2])), .08, 'Face is a curved patch, not a flat plate')

    def test_detail_is_bounded_and_default_is_authored(self):
        data = json.loads((ROOT / 'assets/models/heroes/capsule/geometry.json').read_text())
        self.assertEqual(BODY_SECTIONS,48)
        self.assertEqual(data['body_radial_segments'],48)
        self.assertLess(data['default_visible_triangles'],12000)
        self.assertEqual(len([name for name in data['parts'] if name.startswith('Face') and name!='Face']),6)


if __name__ == '__main__': unittest.main()
