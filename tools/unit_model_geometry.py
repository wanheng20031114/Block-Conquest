"""Shared offline surface fitting for rigid unit armor."""
import numpy as np
import trimesh as tm


def fitted_front_panel(skin, rows, columns=7, inset=.025, center_x=0.0):
    """Project a closed plate onto the actual faceted surface, offline only.

    Rows are (height, half-width), optionally offset by center_x. Intersect triangles so
    forehead/chest armor fits the mesh, rather than a guessed enclosing sphere.
    """
    triangles = skin.triangles
    a = triangles[:, 0]
    u = triangles[:, 1] - a
    v = triangles[:, 2] - a
    determinant = u[:, 0]*v[:, 1]-u[:, 1]*v[:, 0]
    valid = abs(determinant) > 1e-10
    a, u, v, determinant = a[valid], u[valid], v[valid], determinant[valid]
    front = []
    for y, half_width in rows:
        for x in np.linspace(-half_width, half_width, columns) + center_x:
            q = np.array((x, y)) - a[:, :2]
            b = (q[:, 0]*v[:, 1]-q[:, 1]*v[:, 0])/determinant
            c = (u[:, 0]*q[:, 1]-u[:, 1]*q[:, 0])/determinant
            inside = (b >= -1e-7) & (c >= -1e-7) & (b+c <= 1+1e-7)
            assert inside.any(), f'Armor point outside source surface: {x}, {y}'
            z = np.min((a[:, 2]+b*u[:, 2]+c*v[:, 2])[inside])
            front.append((x,y,z-inset))
    # The back embeds slightly in the coat; the visible shell never floats.
    vertices = front + [(x,y,z+inset+.01) for x,y,z in front]
    count=len(front)
    faces=[]
    def quad(a,b,c,d): faces.extend(((a,b,c),(a,c,d)))
    for row in range(len(rows)-1):
        for col in range(columns-1):
            i=row*columns+col
            quad(i,i+columns,i+columns+1,i+1)
            quad(i+count,i+1+count,i+columns+1+count,i+columns+count)
    perimeter=list(range(columns))+[row*columns+columns-1 for row in range(1,len(rows))]
    perimeter+=list(range(count-2,count-columns-1,-1))+[row*columns for row in range(len(rows)-2,0,-1)]
    for a,b in zip(perimeter,perimeter[1:]+perimeter[:1]): quad(a,b,b+count,a+count)
    mesh=tm.Trimesh(vertices=vertices,faces=faces,process=False)
    mesh.fix_normals()
    assert mesh.is_watertight
    return mesh
