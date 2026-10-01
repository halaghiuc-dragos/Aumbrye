"""Blender builders for worn equipment.

Each shape is modelled once in the canonical frame the runtime fits to a body part (x wide, y up,
+z forward, origin at the minimum corner). Colour is the material *role*: eq0 metal, eq1 dark,
eq2 accent, eq3 cloth. The loader recolours them from the item's material family, so one model
serves every family and there are no per-family copies.
"""

from __future__ import annotations

import math

from bl_lib import Model
from characters import _along_z

E = 0.04
METAL, DARK, ACCENT, CLOTH = "eq0", "eq1", "eq2", "eq3"


def _ring(cx, cz, rx, rz, y):
    return dict(y=y, cx=cx, cz=cz, rx=rx, rz=rz)


def _band(m, y0, y1, cx, cz, rx, rz, thick, mat, sides=16, power=3.4, flare=1.0):
    """An open ring of material: an outer wall, an inner wall and rims, so it reads as a band."""
    outer = [
        m.ring_points(cx, cz, rx, rz, y0, sides, power),
        m.ring_points(cx, cz, rx * flare, rz * flare, y1, sides, power),
    ]
    inner = [
        m.ring_points(cx, cz, rx - thick, rz - thick, y0, sides, power),
        m.ring_points(cx, cz, (rx - thick) * flare, (rz - thick) * flare, y1, sides, power),
    ]
    m._bridge(outer, mat)
    m._bridge(list(reversed(inner)), mat)
    n = sides
    for k in range(n):
        k2 = (k + 1) % n
        m.face([outer[1][k], outer[1][k2], inner[1][k2], inner[1][k]], mat)
        m.face([outer[0][k2], outer[0][k], inner[0][k], inner[0][k2]], mat)


def _dome(m, cx, cz, rx, rz, y0, y1, mat, mat_fn=None, sides=16, power=3.2, steps=(0.0, 0.5, 0.82, 0.96, 1.0), k=(1.0, 0.98, 0.84, 0.56, 0.22)):
    rings = [_ring(cx, cz, rx * kk, rz * kk, y0 + (y1 - y0) * t) for t, kk in zip(steps, k)]
    m.loft(rings, mat, sides=sides, power=power, cap_bottom=False, mat_fn=mat_fn)


# ---------------------------------------------------------------------------------------- helmets

def helm():
    w = d = 10 * E
    h = 10 * E
    m = Model("helm")
    cx = cz = w / 2
    stops = [(0.00, 0.72), (0.14, 0.92), (0.42, 1.00), (0.70, 0.98), (0.86, 0.86), (0.96, 0.62), (1.00, 0.34)]
    rings = [_ring(cx, cz, w / 2 * k, d / 2 * k * 1.0, h * t) for t, k in stops]

    def mat_fn(i, k, n):
        t = stops[i][0]
        return DARK if 0.55 <= t < 0.70 else METAL

    m.loft(rings, METAL, sides=16, power=3.0, cap_bottom=False, mat_fn=mat_fn, top_mat=METAL)
    front = cz + d / 2 * 0.98
    m.box(cx - w * 0.33, h * 0.40, front - 0.004, cx + w * 0.33, h * 0.52, front + 0.010, DARK)        # vision slit
    m.box(cx - w * 0.05, h * 0.22, front - 0.004, cx + w * 0.05, h * 0.62, front + 0.014, METAL, chamfer=0.003)  # nasal
    for sx in (-0.18, 0.18):
        m.box(cx + w * sx - 0.008, h * 0.14, front - 0.004, cx + w * sx + 0.008, h * 0.34, front + 0.010, DARK)  # breaths
    # Cheek guards and a neck guard flaring at the base.
    for sx in (-1, 1):
        m.tapered_box((cx + sx * w * 0.44 - 0.012, cz - d * 0.10, cx + sx * w * 0.44 + 0.012, cz + d * 0.34),
                      (cx + sx * w * 0.36 - 0.010, cz - d * 0.06, cx + sx * w * 0.36 + 0.010, cz + d * 0.30), -0.006, h * 0.36, METAL, chamfer=0.003)
    m.box(cx - w * 0.40, -0.020, -0.002, cx + w * 0.40, h * 0.18, 0.016, DARK, chamfer=0.004)  # neck guard
    # Crest: a raised fin along the crown, swept back toward the nape.
    m.tapered_box((cx - 0.016, 0.03, cx + 0.016, d - 0.03), (cx - 0.009, 0.06, cx + 0.009, d - 0.08), h - 0.010, h + 0.042, ACCENT, chamfer=0.003)
    return m


def crown():
    w = d = 10 * E
    h = 3 * E
    m = Model("crown")
    cx = cz = w / 2
    _band(m, 0.0, h, cx, cz, w / 2, d / 2, 0.020, ACCENT)
    pts = [(0.0, 1, 1.0), (-1, 1, 0.7), (1, 1, 0.7), (-1.0, 0, 1.0), (1.0, 0, 1.0)]
    for i in range(8):
        a = 2 * math.pi * i / 8
        px, pz = cx + math.cos(a) * (w / 2 - 0.010), cz + math.sin(a) * (d / 2 - 0.010)
        tall = 4 * E if i in (2,) else 2.6 * E if i % 2 == 0 else 1.6 * E
        m.pyramid(px - 0.014, pz - 0.014, px + 0.014, pz + 0.014, h - 0.004, h + tall, ACCENT)
    m.box(cx - 0.014, 0.008, cz + d / 2 - 0.006, cx + 0.014, 0.036, cz + d / 2 + 0.010, DARK, chamfer=0.003)
    return m


def hood():
    w = d = 12 * E
    h = 11 * E
    m = Model("hood")
    cx = cz = w / 2
    stops = [(0.0, 0.86), (0.20, 0.96), (0.52, 1.00), (0.80, 0.92), (0.94, 0.66), (1.0, 0.34)]
    rings = [_ring(cx, cz - 0.006, w / 2 * k, d / 2 * k, h * t) for t, k in stops]
    m.loft(rings, CLOTH, sides=16, power=3.0, cap_bottom=False, mat_fn=lambda i, k, n: DARK if k % 4 == 0 and i == 1 else CLOTH)
    front = cz + d / 2 * 0.96
    # The face opening: a dark hollow framed by a raised lip.
    m.box(cx - w * 0.30, h * 0.16, front - 0.020, cx + w * 0.30, h * 0.66, front + 0.002, DARK, chamfer=0.004)
    m.box(cx - w * 0.34, h * 0.62, front - 0.010, cx + w * 0.34, h * 0.70, front + 0.012, CLOTH, chamfer=0.004)
    for sx in (-1, 1):
        m.box(cx + sx * w * 0.34 - 0.008, h * 0.14, front - 0.010, cx + sx * w * 0.34 + 0.008, h * 0.66, front + 0.012, CLOTH, chamfer=0.003)
    # Mantle: the fabric gathered over the shoulders.
    m.loft([_ring(cx, cz, w / 2 * 1.14, d / 2 * 1.10, -0.010), _ring(cx, cz, w / 2 * 1.02, d / 2 * 1.0, 2 * E)], CLOTH, sides=16, power=3.0, cap_bottom=False, cap_top=False)
    return m


# ------------------------------------------------------------------------------------------ chest

def cuirass():
    w, d, h = 14 * E, 10 * E, 16 * E
    m = Model("cuirass")
    cx, cz = w / 2, d / 2
    bw = (w - 4 * E) / 2  # half-width of the body plate
    stops = [(0.24, 0.82, 0.86), (0.30, 0.84, 0.88), (0.42, 0.92, 0.94), (0.62, 1.0, 1.0), (0.80, 1.0, 0.94), (0.90, 0.86, 0.80)]
    rings = [_ring(cx, cz, bw * a, d / 2 * b * 0.98, h * t) for t, a, b in stops]

    def mat_fn(i, k, n):
        t = stops[i][0]
        front = math.sin(2 * math.pi * (n - 1 - k) / n) > 0.2
        return CLOTH if t < 0.30 else (METAL if not (front and 0.62 <= t) else METAL)

    m.loft(rings, METAL, sides=16, power=4.0, cap_bottom=False, cap_top=False, mat_fn=mat_fn)
    # Belt and a ridge that breaks up the breastplate.
    m.loft([_ring(cx, cz, bw * 0.86, d / 2 * 0.90, h * 0.22), _ring(cx, cz, bw * 0.88, d / 2 * 0.92, h * 0.32)], CLOTH, sides=16, power=4.0, cap_bottom=False, cap_top=False)
    front = cz + d / 2 * 0.98
    m.box(cx - 0.016, h * 0.40, front - 0.004, cx + 0.016, h * 0.92, front + 0.014, DARK, chamfer=0.003)
    # Collar.
    _band(m, h * 0.93, h * 1.0, cx, cz, bw * 0.62, d / 2 * 0.60, 0.014, DARK, sides=14)
    # Faulds: hanging plates in overlapping tiers, front and back, with gaps at the hips.
    for tier, (y0, y1, wf) in enumerate([(h * 0.12, h * 0.26, 0.80), (0.0, h * 0.14, 0.66)]):
        for zs in (0, 1):
            zc = cz + (d / 2 * 0.94 if zs else -d / 2 * 0.94)
            m.box(cx - bw * wf, y0, zc - 0.006, cx + bw * wf, y1, zc + 0.006, METAL, chamfer=0.004)
            m.box(cx - bw * wf, y0, zc - 0.007, cx + bw * wf, y0 + 0.010, zc + 0.007, DARK, chamfer=0.002)
    # Pauldrons: stepped domes flaring past the shoulders.
    for sx in (-1, 1):
        for i in range(3):
            x_in = cx + sx * (bw * 0.86 + i * E * 0.85)
            rx = E * (2.0 - i * 0.3)
            rz = d / 2 * (0.62 - i * 0.05)
            top = h * 0.98 - i * E * 1.15
            m.loft(
                [_ring(x_in, cz, rx * 0.95, rz, top - E * 1.6), _ring(x_in, cz, rx, rz, top - E * 0.4), _ring(x_in, cz, rx * 0.8, rz * 0.9, top)],
                METAL, sides=12, power=2.6, cap_bottom=False,
            )
        rx_out = cx + sx * (w / 2 - E * 0.4)
        m.box(rx_out - 0.006, h * 0.66, cz - d * 0.22, rx_out + 0.006, h * 0.70, cz + d * 0.22, ACCENT, chamfer=0.002)
    return m


def cloak():
    w, d, h = 14 * E, 10 * E, 16 * E
    m = Model("cloak")
    cx, cz = w / 2, d / 2
    bw = (w - 6 * E) / 2
    # The garment underneath, so a cloak still covers a chest.
    rings = [_ring(cx, cz, bw * a, (d / 2 - E) * b, h * t) for t, a, b in [(0.20, 0.82, 0.86), (0.40, 0.92, 0.94), (0.62, 1.0, 1.0), (0.80, 1.0, 0.94), (0.86, 0.82, 0.78)]]
    m.loft(rings, DARK, sides=16, power=4.0, cap_bottom=False, cap_top=False)
    # Mantle over the shoulders.
    m.loft(
        [_ring(cx, cz, w / 2 * 0.92, d / 2 * 0.94, h * 0.72), _ring(cx, cz, w / 2 * 1.0, d / 2, h * 0.82), _ring(cx, cz, w / 2 * 0.86, d / 2 * 0.88, h * 0.94), _ring(cx, cz, w / 2 * 0.56, d / 2 * 0.60, h)],
        CLOTH, sides=16, power=3.2, cap_bottom=False, cap_top=False,
    )
    # The drape: a tapering, seamed fall down the back with a wider hem.
    back = 0.0
    m.tapered_box((cx - w * 0.46, back, cx + w * 0.46, back + 0.016), (cx - w * 0.30, back, cx + w * 0.30, back + 0.016), h * 0.12, h * 0.80, CLOTH, chamfer=0.003)
    m.tapered_box((cx - w * 0.52, back - 0.004, cx + w * 0.52, back + 0.020), (cx - w * 0.46, back - 0.002, cx + w * 0.46, back + 0.018), 0.0, h * 0.14, CLOTH, chamfer=0.003)
    m.box(cx - 0.010, h * 0.02, back - 0.006, cx + 0.010, h * 0.74, back + 0.018, DARK, chamfer=0.002)
    for sx in (-0.26, 0.26):
        m.box(cx + w * sx - 0.006, h * 0.06, back - 0.004, cx + w * sx + 0.006, h * 0.70, back + 0.018, DARK, chamfer=0.002)
    m.box(cx - 0.014, h * 0.82, cz + d / 2 * 0.90, cx + 0.014, h * 0.94, cz + d / 2 * 0.90 + 0.016, ACCENT, chamfer=0.003)  # clasp
    return m


# --------------------------------------------------------------------------------- hands and feet

def _disc(m, cx, cy, r, z0, z1, mat, mat_fn=None, sides=20):
    layers = []
    for z in (z0, z1):
        ring = m.ring_points(cx, cy, r, r, 0.0, sides, 2.0)
        layers.append([(x, zz, z) for (x, _y, zz) in ring])
    m._bridge(layers, mat, mat_fn)
    m.face(list(reversed(layers[0])), mat)
    m.face(layers[1], mat)


def buckler():
    r = 5 * E
    m = Model("buckler")
    cx = cy = r
    _disc(m, cx, cy, r, 0.0, 2 * E, METAL)
    # Rim ring.
    outer = []
    inner = []
    for z in (0.0, 2 * E + 0.004):
        outer.append([(x, zz, z) for (x, _y, zz) in m.ring_points(cx, cy, r, r, 0.0, 20, 2.0)])
        inner.append([(x, zz, z) for (x, _y, zz) in m.ring_points(cx, cy, r - 0.012, r - 0.012, 0.0, 20, 2.0)])
    m._bridge(outer, DARK)
    m._bridge(list(reversed(inner)), DARK)
    for k in range(20):
        k2 = (k + 1) % 20
        m.face([outer[1][k], outer[1][k2], inner[1][k2], inner[1][k]], DARK)
    # Domed boss.
    for kk, z in [(0.30, 2 * E), (0.28, 2 * E + 0.010), (0.20, 2 * E + 0.020), (0.08, 2 * E + 0.026)]:
        pass
    layers = []
    for kk, z in [(0.30, 2 * E), (0.28, 2 * E + 0.010), (0.20, 2 * E + 0.020), (0.07, 2 * E + 0.028)]:
        layers.append([(x, zz, z) for (x, _y, zz) in m.ring_points(cx, cy, r * kk * 1.6, r * kk * 1.6, 0.0, 12, 2.0)])
    m._bridge(layers, ACCENT)
    m.face(layers[-1], ACCENT)
    # Radial studs.
    for i in range(6):
        a = 2 * math.pi * i / 6
        m.box(cx + math.cos(a) * r * 0.62 - 0.005, cy + math.sin(a) * r * 0.62 - 0.005, 2 * E, cx + math.cos(a) * r * 0.62 + 0.005, cy + math.sin(a) * r * 0.62 + 0.005, 2 * E + 0.008, ACCENT)
    return m


def _plate_xy(m, outline, z0, z1, mat):
    m.plate([(x, y, z0) for x, y in outline], (0, 0, 1), z1 - z0, mat)


def kiteshield():
    w, h = 9 * E, 15 * E
    m = Model("kiteshield")
    outline = [(0.0, h * 0.62), (w * 0.16, h * 0.98), (w * 0.84, h * 0.98), (w, h * 0.62), (w * 0.86, h * 0.30), (w * 0.5, 0.0), (w * 0.14, h * 0.30)]
    # A plate wound so its front (+z) faces the viewer.
    m.plate(list(reversed([(x, y, 0.0) for x, y in outline])), (0, 0, 1), 2 * E, METAL)
    # Raised rim along every edge.
    n = len(outline)
    for i in range(n):
        (xa, ya), (xb, yb) = outline[i], outline[(i + 1) % n]
        dx, dy = xb - xa, yb - ya
        ln = math.hypot(dx, dy)
        nx, ny = -dy / ln * 0.008, dx / ln * 0.008
        pts = [(xa - nx, ya - ny, 2 * E), (xb - nx, yb - ny, 2 * E), (xb + nx, yb + ny, 2 * E), (xa + nx, ya + ny, 2 * E)]
        m.face(pts, DARK)
    # Central band and boss.
    m.box(w * 0.04, h * 0.58, 2 * E, w * 0.96, h * 0.66, 2 * E + 0.010, ACCENT, chamfer=0.003)
    m.box(w * 0.44, h * 0.10, 2 * E, w * 0.56, h * 0.94, 2 * E + 0.008, ACCENT, chamfer=0.003)
    layers = []
    for k, z in [(1.0, 2 * E), (0.86, 2 * E + 0.010), (0.54, 2 * E + 0.020), (0.18, 2 * E + 0.026)]:
        layers.append([(x + w / 2, zz + h * 0.62, z) for (x, _y, zz) in m.ring_points(0.0, 0.0, 0.052 * k, 0.052 * k, 0.0, 10, 2.0)])
    m._bridge(layers, ACCENT)
    m.face(layers[-1], DARK)
    return m


def towershield():
    w, h = 10 * E, 18 * E
    m = Model("towershield")
    m.box(0, 0, 0, w, h, 2 * E, METAL, chamfer=0.008)
    for x0, x1 in ((0.0, 0.014), (w - 0.014, w)):
        m.box(x0, 0, 0, x1, h, 2 * E + 0.008, DARK, chamfer=0.003)
    m.box(0, h - 0.014, 0, w, h, 2 * E + 0.008, DARK, chamfer=0.003)
    m.box(0, 0, 0, w, 0.014, 2 * E + 0.008, DARK, chamfer=0.003)
    m.box(w * 0.4, 0.03, 2 * E, w * 0.6, h - 0.03, 2 * E + 0.010, ACCENT, chamfer=0.003)
    for y in (0.22, 0.50, 0.64):
        m.box(w * 0.10, y - 0.006, 2 * E, w * 0.90, y + 0.006, 2 * E + 0.006, DARK, chamfer=0.002)
    layers = []
    for k, z in [(1.0, 2 * E), (0.86, 2 * E + 0.010), (0.54, 2 * E + 0.022), (0.18, 2 * E + 0.030)]:
        layers.append([(x + w / 2, zz + h * 0.5, z) for (x, _y, zz) in m.ring_points(0.0, 0.0, 0.07 * k, 0.05 * k, 0.0, 12, 2.0)])
    m._bridge(layers, ACCENT)
    m.face(layers[-1], ACCENT)
    return m


BUILDERS = {
    "helm": helm, "crown": crown, "hood": hood, "cuirass": cuirass, "cloak": cloak,
    "buckler": buckler, "kiteshield": kiteshield, "towershield": towershield,
}
