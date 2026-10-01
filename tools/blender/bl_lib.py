"""Shared Blender (bpy) modelling helpers for the Aumbrye art pipeline.

Every model is authored in Godot's coordinate frame (x right, y up, +z forward, metres) and converted
to Blender's Z-up frame at vertex creation, so the glTF exporter's Y-up conversion lands each vertex
back on its authored coordinates.

Colour is carried by material *names*, which the Godot loader (`VoxelMeshBuilder`) resolves:
  slotN       index N into the standard character palette list [2, 3, 4, 5, 6, 7, 1] of the
              biome's eight-colour palette (0 base, 1 shadow, 2 accent, 3 leather, 4 metal, 5 glow)
  lit_RRGGBB  a literal colour, never snapped to a biome palette

Every face is flat shaded: the pixel pipeline quantises light, so hard facets read as clean pixel
planes instead of muddy gradients.
"""

from __future__ import annotations

import math
import os

import bmesh
import bpy

# Character palette indices, matching the character palette.
BASE, SHADOW, ACCENT, LEATHER, METAL, GLOW, HAIR = range(7)


def gd(x: float, y: float, z: float) -> tuple[float, float, float]:
    """Godot coordinates to Blender coordinates."""
    return (x, -z, y)


_material_cache: dict[str, bpy.types.Material] = {}


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _material_cache.clear()


def material(name: str) -> bpy.types.Material:
    mat = _material_cache.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = False
        _material_cache[name] = mat
    return mat


def slot(index: int) -> str:
    return f"slot{index}"


def literal(rgb: tuple[float, float, float]) -> str:
    r, g, b = (max(0, min(255, int(round(c * 255)))) for c in rgb)
    return f"lit_{r:02x}{g:02x}{b:02x}"


class Model:
    """A bmesh under construction. Faces are tagged with a material name."""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self._mats: list[str] = []

    # -- low level -------------------------------------------------------------------------
    def _mat_index(self, mat: str) -> int:
        if mat not in self._mats:
            self._mats.append(mat)
        return self._mats.index(mat)

    def vert(self, x: float, y: float, z: float):
        return self.bm.verts.new(gd(x, y, z))

    def face(self, points: list[tuple[float, float, float]], mat: str):
        verts = [self.vert(*p) for p in points]
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return None
        f.material_index = self._mat_index(mat)
        f.smooth = False
        return f

    def quad(self, a, b, c, d, mat: str):
        return self.face([a, b, c, d], mat)

    # -- primitives ------------------------------------------------------------------------
    def box(self, x0, y0, z0, x1, y1, z1, mat: str, chamfer: float = 0.0, top_mat: str | None = None):
        """Axis-aligned box, optionally with chamfered edges (a small bevel that catches light)."""
        c = min(chamfer, (x1 - x0) * 0.45, (y1 - y0) * 0.45, (z1 - z0) * 0.45)
        if c <= 1e-6:
            self._box_faces(x0, y0, z0, x1, y1, z1, mat, top_mat)
            return
        # Chamfer by building the inner box and connecting to the outer faces.
        self.tapered_box((x0, z0, x1, z1), (x0, z0, x1, z1), y0, y1, mat, chamfer=c, top_mat=top_mat)

    def _box_faces(self, x0, y0, z0, x1, y1, z1, mat, top_mat=None):
        p = lambda x, y, z: (x, y, z)
        # +z, -z, +x, -x, +y, -y (counter-clockwise seen from outside)
        self.quad(p(x0, y0, z1), p(x1, y0, z1), p(x1, y1, z1), p(x0, y1, z1), mat)
        self.quad(p(x1, y0, z0), p(x0, y0, z0), p(x0, y1, z0), p(x1, y1, z0), mat)
        self.quad(p(x1, y0, z1), p(x1, y0, z0), p(x1, y1, z0), p(x1, y1, z1), mat)
        self.quad(p(x0, y0, z0), p(x0, y0, z1), p(x0, y1, z1), p(x0, y1, z0), mat)
        self.quad(p(x0, y1, z1), p(x1, y1, z1), p(x1, y1, z0), p(x0, y1, z0), top_mat or mat)
        self.quad(p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1), p(x0, y0, z1), mat)

    def tapered_box(self, bottom, top, y0, y1, mat, chamfer=0.0, top_mat=None):
        """A frustum: `bottom` and `top` are (x0, z0, x1, z1) rectangles at y0 and y1."""
        rings = [
            dict(y=y0, rect=bottom),
            dict(y=y1, rect=top),
        ]
        if chamfer > 0:
            rings = [
                dict(y=y0, rect=self._inset(bottom, chamfer)),
                dict(y=y0 + chamfer, rect=bottom),
                dict(y=y1 - chamfer, rect=top),
                dict(y=y1, rect=self._inset(top, chamfer)),
            ]
        self.rect_loft(rings, mat, top_mat=top_mat)

    @staticmethod
    def _inset(rect, d):
        x0, z0, x1, z1 = rect
        d = min(d, (x1 - x0) * 0.49, (z1 - z0) * 0.49)
        return (x0 + d, z0 + d, x1 - d, z1 - d)

    def rect_loft(self, rings, mat, top_mat=None, cap_bottom=True, cap_top=True):
        pts = []
        for r in rings:
            x0, z0, x1, z1 = r["rect"]
            y = r["y"]
            pts.append([(x0, y, z1), (x1, y, z1), (x1, y, z0), (x0, y, z0)])
        self._bridge(pts, mat)
        if cap_bottom:
            self.face(list(reversed(pts[0])), mat)
        if cap_top:
            self.face(pts[-1], top_mat or mat)

    def ring_points(self, cx, cz, rx, rz, y, sides=16, power=4.0, twist=0.0):
        """A superellipse cross-section at height y: power 2 is an ellipse, higher is a squircle."""
        out = []
        e = 2.0 / power
        for i in range(sides):
            a = twist + 2.0 * math.pi * i / sides
            c, s = math.cos(a), math.sin(a)
            x = cx + rx * math.copysign(abs(c) ** e, c)
            z = cz + rz * math.copysign(abs(s) ** e, s)
            out.append((x, y, z))
        # Godot z forward: order so the loop is counter-clockwise seen from above (+y).
        out.reverse()
        return out

    def loft(self, rings, mat, sides=16, power=4.0, top_mat=None, cap_bottom=True, cap_top=True, mat_fn=None):
        """Loft superellipse rings (dicts: y, cx, cz, rx, rz, optional power/twist) bottom to top."""
        pts = [
            self.ring_points(
                r.get("cx", 0.0), r.get("cz", 0.0), r["rx"], r["rz"], r["y"], sides,
                r.get("power", power), r.get("twist", 0.0),
            )
            for r in rings
        ]
        self._bridge(pts, mat, mat_fn)
        if cap_bottom:
            self.face(list(reversed(pts[0])), mat)
        if cap_top:
            self.face(pts[-1], top_mat or mat)

    def _bridge(self, pts, mat, mat_fn=None):
        for i in range(len(pts) - 1):
            lo, hi = pts[i], pts[i + 1]
            n = len(lo)
            for k in range(n):
                k2 = (k + 1) % n
                m = mat_fn(i, k, n) if mat_fn else mat
                # lo is counter-clockwise from above; the side quad faces outward.
                self.face([lo[k], lo[k2], hi[k2], hi[k]], m)

    def prism(self, points_xz, y0, y1, mat, top_mat=None):
        """Extrude a 2D outline (x, z; counter-clockwise seen from above) between y0 and y1."""
        n = len(points_xz)
        lo = [(x, y0, z) for x, z in points_xz]
        hi = [(x, y1, z) for x, z in points_xz]
        for k in range(n):
            k2 = (k + 1) % n
            self.face([lo[k], lo[k2], hi[k2], hi[k]], mat)
        self.face(hi, top_mat or mat)
        self.face(list(reversed(lo)), mat)

    def plate(self, points, thickness_dir, thickness, mat):
        """Extrude a planar polygon along a direction. The polygon's winding is corrected so the
        start cap faces away from the extrusion, whatever order the points were given in."""
        pts = [tuple(p) for p in points]
        nx = ny = nz = 0.0
        for i, (x0, y0, z0) in enumerate(pts):
            x1, y1, z1 = pts[(i + 1) % len(pts)]
            nx += (y0 - y1) * (z0 + z1)
            ny += (z0 - z1) * (x0 + x1)
            nz += (x0 - x1) * (y0 + y1)
        if nx * thickness_dir[0] + ny * thickness_dir[1] + nz * thickness_dir[2] > 0:
            pts.reverse()
        d = tuple(c * thickness for c in thickness_dir)
        back = [(p[0] + d[0], p[1] + d[1], p[2] + d[2]) for p in pts]
        n = len(pts)
        self.face(pts, mat)
        self.face(list(reversed(back)), mat)
        for k in range(n):
            k2 = (k + 1) % n
            self.face([pts[k2], pts[k], back[k], back[k2]], mat)

    def sphere(self, cx, cy, cz, r, mat, sides=10, rings=5, ry=None, rz=None):
        """A faceted sphere (or spheroid when ry/rz differ from r)."""
        ry = r if ry is None else ry
        rz = r if rz is None else rz
        ring_defs = []
        for i in range(rings + 1):
            a = -math.pi / 2 + math.pi * i / rings
            k = math.cos(a)
            ring_defs.append(dict(y=cy + ry * math.sin(a), cx=cx, cz=cz, rx=max(r * k, 1e-4), rz=max(rz * k, 1e-4)))
        self.loft(ring_defs, mat, sides=sides, power=2.0, cap_bottom=False, cap_top=False)

    def tube(self, p0, p1, r0, r1, mat, sides=6, caps=(True, True)):
        """A tapered tube between two arbitrary points (Godot coordinates)."""
        a = [p1[i] - p0[i] for i in range(3)]
        ln = math.sqrt(sum(c * c for c in a)) or 1.0
        a = [c / ln for c in a]
        helper = (0.0, 1.0, 0.0) if abs(a[1]) < 0.9 else (1.0, 0.0, 0.0)
        u = [a[1] * helper[2] - a[2] * helper[1], a[2] * helper[0] - a[0] * helper[2], a[0] * helper[1] - a[1] * helper[0]]
        ul = math.sqrt(sum(c * c for c in u)) or 1.0
        u = [c / ul for c in u]
        v = [a[1] * u[2] - a[2] * u[1], a[2] * u[0] - a[0] * u[2], a[0] * u[1] - a[1] * u[0]]

        def ring(p, r):
            return [
                tuple(p[i] + (u[i] * math.cos(2 * math.pi * k / sides) + v[i] * math.sin(2 * math.pi * k / sides)) * r for i in range(3))
                for k in range(sides)
            ]

        lo, hi = ring(p0, r0), ring(p1, r1)
        self._bridge([lo, hi], mat)
        if caps[0]:
            self.face(list(reversed(lo)), mat)
        if caps[1]:
            self.face(hi, mat)

    def cylinder(self, cx, y0, cz, r, y1, mat, sides=8, r_top=None, top_mat=None):
        rt = r if r_top is None else r_top
        self.loft(
            [dict(y=y0, cx=cx, cz=cz, rx=r, rz=r), dict(y=y1, cx=cx, cz=cz, rx=rt, rz=rt)],
            mat, sides=sides, power=2.0, top_mat=top_mat,
        )

    def cone(self, cx, y0, cz, r, y1, mat, sides=8):
        base = self.ring_points(cx, cz, r, r, y0, sides, 2.0)
        apex = (cx, y1, cz)
        n = len(base)
        for k in range(n):
            k2 = (k + 1) % n
            self.face([base[k], base[k2], apex], mat)
        self.face(list(reversed(base)), mat)

    def pyramid(self, x0, z0, x1, z1, y0, y1, mat, apex=None):
        ax, az = apex if apex else ((x0 + x1) / 2, (z0 + z1) / 2)
        base = [(x0, y0, z1), (x1, y0, z1), (x1, y0, z0), (x0, y0, z0)]
        tip = (ax, y1, az)
        for k in range(4):
            k2 = (k + 1) % 4
            self.face([base[k], base[k2], tip], mat)
        self.face(list(reversed(base)), mat)

    # -- output ----------------------------------------------------------------------------
    def finish(self, origin=None) -> bpy.types.Object:
        """Bake to an object. `origin` (Godot coordinates) becomes the object's pivot, so a lid can
        hinge about its own origin while its geometry stays where it was modelled."""
        if origin is not None:
            bmesh.ops.translate(self.bm, verts=self.bm.verts[:], vec=tuple(-c for c in gd(*origin)))
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(self.name, mesh)
        if origin is not None:
            obj.location = gd(*origin)
        bpy.context.scene.collection.objects.link(obj)
        for m in self._mats:
            mesh.materials.append(material(m))
        return obj


def bounds(obj) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    """Godot-frame AABB of an object: ((minx, miny, minz), (maxx, maxy, maxz))."""
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for v in obj.data.vertices:
        gx, gy, gz = v.co.x, v.co.z, -v.co.y
        for i, c in enumerate((gx, gy, gz)):
            lo[i] = min(lo[i], c)
            hi[i] = max(hi[i], c)
    return tuple(lo), tuple(hi)


def export_glb(obj, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_normals=True,
        export_texcoords=False,
        export_cameras=False,
        export_lights=False,
        export_image_format="NONE",
    )
    bpy.data.objects.remove(obj, do_unlink=True)


def export_glb_multi(objs, path: str) -> None:
    """Export several named objects into one glb; each becomes a child node under the file's root."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
        export_materials="EXPORT", export_normals=True, export_texcoords=False, export_cameras=False,
        export_lights=False, export_image_format="NONE",
    )
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
