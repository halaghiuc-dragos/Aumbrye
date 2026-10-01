"""Blender builders for character body parts.

Each builder receives the part's voxel size (the rig's grid units, 0.04 m each) and returns a Model
occupying exactly the box [0, W] x [0, H] x [0, D]. The rig manifests place parts by joint and centre
them on their bounding box, so hitting that box exactly keeps every pivot, animation, mount and piece
of equipment where it was, while the surface inside the box is real modelled form.
"""

from __future__ import annotations

import math

from bl_lib import ACCENT, BASE, GLOW, LEATHER, METAL, SHADOW, Model, slot

EDGE = 0.04

TORSO_STOPS = [
    (0.00, 0.80, 0.84),
    (0.08, 0.84, 0.88),
    (0.28, 0.76, 0.82),   # waist
    (0.50, 0.90, 0.92),
    (0.72, 1.00, 1.00),   # chest
    (0.88, 1.00, 0.90),   # shoulder line
    (0.95, 0.66, 0.66),
    (1.00, 0.40, 0.46),   # neck
]

HEAD_STOPS = [
    (0.00, 0.62, 0.66),
    (0.14, 0.84, 0.86),
    (0.45, 1.00, 1.00),
    (0.78, 0.98, 0.98),
    (0.93, 0.80, 0.82),
    (1.00, 0.52, 0.56),
]


def _dims(size):
    return size[0] * EDGE, size[1] * EDGE, size[2] * EDGE


def _lerp(a, b, t):
    return a + (b - a) * t


def _profile(points, t):
    """Piecewise-linear lookup in [(t, value), ...]."""
    if t <= points[0][0]:
        return points[0][1]
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if t <= t1:
            return _lerp(v0, v1, (t - t0) / max(1e-9, t1 - t0))
    return points[-1][1]


def _rings(w, h, d, stops, cz_shift=None):
    """stops: (t, width_fraction, depth_fraction[, z_shift_fraction])."""
    out = []
    for stop in stops:
        t, fw, fd = stop[0], stop[1], stop[2]
        shift = stop[3] if len(stop) > 3 else 0.0
        out.append(
            dict(
                y=h * t, cx=w / 2, cz=d / 2 + d * shift / 2,
                rx=w / 2 * fw, rz=d / 2 * fd,
            )
        )
    return out


# ------------------------------------------------------------------------------------------
# Torso
# ------------------------------------------------------------------------------------------

def torso(size, style="player", accent_band=False):
    w, h, d = _dims(size)
    m = Model("torso")
    stops = TORSO_STOPS
    rings = _rings(w, h, d, stops)

    def mat_fn(i, k, n):
        # Sides of a ring are numbered around the loop; the front (+z) is the half where the
        # point's z is above the centre. Ring index i spans stops[i] .. stops[i + 1].
        t = stops[i][0]
        angle = 2.0 * math.pi * (n - 1 - k) / n
        front = math.sin(angle) > 0.15
        if t < 0.06:
            return slot(SHADOW)
        if 0.16 <= t < 0.30:
            return slot(LEATHER)
        if front and 0.50 <= t < 0.88:
            return slot(METAL) if style == "player" else slot(BASE)
        if t >= 0.88:
            return slot(SHADOW)
        return slot(BASE)

    m.loft(rings, slot(BASE), sides=16, power=4.0, mat_fn=mat_fn, top_mat=slot(SHADOW))
    # Belt buckle and a breastbone ridge give the front a focal point.
    cx = w / 2
    front = d / 2 + d / 2 * 0.86
    m.box(cx - w * 0.07, h * 0.18, front - 0.004, cx + w * 0.07, h * 0.30, front + 0.012, slot(ACCENT), chamfer=0.004)
    m.box(cx - w * 0.04, h * 0.52, d / 2 + d / 2 * 0.9, cx + w * 0.04, h * 0.80, d / 2 + d / 2 * 0.9 + 0.012, slot(ACCENT), chamfer=0.003)
    # Shoulder yoke ridge across the top, a ring a touch proud of the body.
    m.loft(
        _rings(w, h, d, [(0.86, 1.02, 0.92), (0.93, 1.00, 0.88)]),
        slot(METAL), sides=16, power=4.0, cap_bottom=False, cap_top=False,
    )
    if accent_band:
        m.loft(
            _rings(w, h, d, [(0.60, 0.94, 0.95), (0.66, 0.94, 0.95)]),
            slot(ACCENT), sides=16, power=4.0, cap_bottom=False, cap_top=False,
        )
    return m


# ------------------------------------------------------------------------------------------
# Head
# ------------------------------------------------------------------------------------------

def head(size, style="player", accent_band=False):
    w, h, d = _dims(size)
    m = Model("head")
    stops = HEAD_STOPS
    rings = _rings(w, h, d, stops)

    def mat_fn(i, k, n):
        t = stops[i][0]
        if t < 0.14:
            return slot(SHADOW)
        if accent_band and 0.45 <= t < 0.78:
            return slot(ACCENT)
        return slot(BASE) if t >= 0.14 else slot(SHADOW)

    m.loft(rings, slot(BASE), sides=16, power=3.4, mat_fn=mat_fn, top_mat=slot(BASE))
    # Brow ridge and nose bridge: read as a face even without a plate.
    cx, front = w / 2, d / 2 + d / 2 * 0.98
    m.box(cx - w * 0.36, h * 0.56, front - 0.012, cx + w * 0.36, h * 0.66, front + 0.012, slot(SHADOW), chamfer=0.003)
    m.box(cx - w * 0.06, h * 0.30, front - 0.010, cx + w * 0.06, h * 0.56, front + 0.014, slot(BASE), chamfer=0.002)
    return m


# ------------------------------------------------------------------------------------------
# Limbs
# ------------------------------------------------------------------------------------------

def arm(size, style="player"):
    """An arm hanging from a shoulder at the top (y = H) to a hand at the bottom (y = 0)."""
    w, h, d = _dims(size)
    m = Model("arm")
    stops = [
        (0.00, 0.78, 0.82),   # fist
        (0.10, 0.86, 0.92),
        (0.16, 0.74, 0.76),   # wrist
        (0.34, 0.90, 0.90),   # bracer
        (0.48, 0.80, 0.82),   # elbow
        (0.66, 0.98, 0.98),
        (0.90, 1.00, 1.00),
        (1.00, 0.86, 0.90),
    ]
    rings = _rings(w, h, d, stops)

    def mat_fn(i, k, n):
        t = stops[i][0]
        if t < 0.16:
            return slot(LEATHER)
        if t < 0.46:
            return slot(METAL)
        if t < 0.50:
            return slot(SHADOW)
        return slot(BASE)

    m.loft(rings, slot(BASE), sides=12, power=3.4, mat_fn=mat_fn, top_mat=slot(SHADOW), cap_bottom=True)
    return m


def leg(size, style="player"):
    """A leg hanging from the hip at the top (y = H) to a boot on the ground (y = 0)."""
    w, h, d = _dims(size)
    m = Model("leg")
    stops = [
        (0.00, 0.92, 1.00, 0.00),   # sole, spanning the whole depth
        (0.09, 0.96, 1.00, 0.00),
        (0.18, 0.84, 0.66, -0.30),  # boot shaft
        (0.32, 0.86, 0.66, -0.30),
        (0.40, 0.92, 0.72, -0.24),  # knee guard
        (0.52, 0.80, 0.68, -0.28),
        (0.72, 1.00, 0.78, -0.20),  # thigh
        (0.96, 1.00, 0.80, -0.18),
        (1.00, 0.90, 0.76, -0.18),
    ]
    rings = _rings(w, h, d, stops)

    def mat_fn(i, k, n):
        t = stops[i][0]
        if t < 0.05:
            return slot(SHADOW)
        if t < 0.34:
            return slot(LEATHER)
        if t < 0.50:
            return slot(METAL)
        return slot(BASE)

    m.loft(rings, slot(BASE), sides=12, power=3.4, mat_fn=mat_fn, top_mat=slot(SHADOW))
    # Boot toe cap, so the foot has a clear front.
    m.box(w * 0.10, 0.0, d * 0.62, w * 0.90, h * 0.09, d, slot(LEATHER), chamfer=0.006)
    return m


# ------------------------------------------------------------------------------------------
# Attachments
# ------------------------------------------------------------------------------------------

def visor(size):
    w, h, d = _dims(size)
    m = Model("visor")
    m.box(0, 0, 0, w, h, d, slot(METAL), chamfer=min(0.006, h * 0.3))
    m.box(w * 0.08, h * 0.30, d - 0.010, w * 0.92, h * 0.70, d + 0.000, slot(GLOW))
    return m


def belttrim(size):
    w, h, d = _dims(size)
    m = Model("belttrim")
    m.loft(
        [dict(y=0, cx=w / 2, cz=d / 2, rx=w / 2 * 0.98, rz=d / 2), dict(y=h, cx=w / 2, cz=d / 2, rx=w / 2, rz=d / 2)],
        slot(LEATHER), sides=16, power=4.0, cap_bottom=False, cap_top=False,
    )
    m.box(w / 2 - w * 0.10, 0.0, d - 0.012, w / 2 + w * 0.10, h, d + 0.008, slot(ACCENT), chamfer=0.003)
    for sx in (0.18, 0.82):
        m.box(w * sx - 0.02, h * 0.15, d - 0.010, w * sx + 0.02, h * 0.85, d + 0.004, slot(METAL), chamfer=0.002)
    return m


def pauldron(size):
    """A shoulder plate: a domed cap with a rim, hanging over the top of the arm."""
    w, h, d = _dims(size)
    m = Model("pauldron")
    stops = [
        (0.00, 1.00, 1.00),
        (0.35, 0.98, 0.98),
        (0.70, 0.82, 0.84),
        (1.00, 0.52, 0.56),
    ]
    m.loft(_rings(w, h, d, stops), slot(METAL), sides=12, power=2.8, cap_bottom=False, top_mat=slot(METAL))
    m.loft(
        _rings(w, h * 0.26, d, [(0.0, 1.0, 1.0), (1.0, 0.99, 0.99)]),
        slot(ACCENT), sides=12, power=2.8, cap_bottom=False, cap_top=False,
    )
    return m


def hood(head_size):
    """A cowl grown around the head: crown, back and sides, open at the face, dropping at the neck."""
    hw, hh, hd = _dims(head_size)
    pad = EDGE
    drop = 3 * EDGE
    w, h, d = hw + pad * 2, hh + pad + drop, hd + pad * 2
    m = Model("hood")
    stops = [
        (0.00, 0.70, 0.74),
        (0.26, 0.92, 0.94),
        (0.55, 1.00, 1.00),
        (0.86, 0.98, 0.98),
        (1.00, 0.58, 0.60),
    ]
    rings = _rings(w, h, d, stops)
    front_z = d / 2 + d / 2 * 0.7

    m.loft(rings, slot(BASE), sides=16, power=3.2, cap_bottom=False, top_mat=slot(BASE))
    # Cut nothing: the open face is faked by a lighter rim proud of the front.
    m.box(w * 0.18, h * 0.30, d - 0.014, w * 0.82, h * 0.74, d + 0.004, slot(METAL), chamfer=0.003)
    m.box(w * 0.26, h * 0.36, d - 0.010, w * 0.74, h * 0.68, d + 0.008, slot(SHADOW))
    return m


def _along_z(m, sections, w, h, d, mat, mat_fn=None, power=2.6, sides=12):
    """Loft along z. sections: (t, width_frac, height_frac, y_centre_frac, x_centre_frac)."""
    layers = []
    for sec in sections:
        t, fw, fh = sec[0], sec[1], sec[2]
        cy = h * (sec[3] if len(sec) > 3 else 0.5)
        cx = w * (sec[4] if len(sec) > 4 else 0.5)
        ring = m.ring_points(cx, cy, w / 2 * fw, h / 2 * fh, 0.0, sides, power)
        layers.append([(x, zloc, d * t) for (x, _y, zloc) in ring])
    m._bridge(layers, mat, mat_fn)
    m.face(list(reversed(layers[0])), mat)
    m.face(layers[-1], mat)


def quadruped_torso(size):
    w, h, d = _dims(size)
    m = Model("torso")
    sections = [
        (0.00, 0.60, 0.62), (0.10, 0.84, 0.86), (0.30, 1.00, 1.00), (0.55, 0.96, 0.92),
        (0.80, 0.84, 0.80), (1.00, 0.66, 0.64),
    ]
    # Rib bands and a darker belly.
    def mat_fn(i, k, n):
        if k % 12 in (5, 6, 7):
            return slot(SHADOW)
        return slot(SHADOW) if i % 2 == 1 and k % 3 == 0 else slot(BASE)
    _along_z(m, sections, w, h, d, slot(BASE), mat_fn)
    # Spine ridge.
    m.tapered_box((w / 2 - 0.01, d * 0.08, w / 2 + 0.01, d * 0.92), (w / 2 - 0.005, d * 0.10, w / 2 + 0.005, d * 0.90), h - 0.006, h + 0.026, slot(ACCENT))
    return m


def hound_head(size):
    w, h, d = _dims(size)
    m = Model("head")
    _along_z(
        m,
        [(0.00, 0.80, 0.86, 0.5), (0.35, 1.00, 1.00, 0.5), (0.62, 0.72, 0.64, 0.42), (0.92, 0.50, 0.42, 0.36), (1.00, 0.42, 0.34, 0.34)],
        w, h, d, slot(BASE), lambda i, k, n: slot(SHADOW) if i >= 3 and k % 12 in (4, 5, 6, 7, 8) else slot(BASE),
    )
    # Ears, eyes and a fang row.
    for sx in (0.22, 0.78):
        m.pyramid(w * sx - 0.02, d * 0.26, w * sx + 0.02, d * 0.36, h * 0.98, h * 1.32, slot(SHADOW))
        m.box(w * sx - 0.008, h * 0.62, d * 0.64, w * sx + 0.008, h * 0.74, d * 0.64 + 0.012, slot(GLOW))
    m.box(w * 0.32, 0.0, d * 0.90, w * 0.68, 0.012, d * 0.99, slot(ACCENT))
    return m


def hound_tail(size):
    w, h, d = _dims(size)
    m = Model("tail")
    _along_z(
        m,
        [(0.00, 1.00, 1.00, 0.5), (0.4, 0.80, 0.84, 0.62), (0.75, 0.62, 0.66, 0.78), (1.00, 0.36, 0.40, 0.92)],
        w, h, d, slot(BASE), lambda i, k, n: slot(SHADOW) if i % 2 else slot(BASE), sides=8,
    )
    return m


def hound_leg(size):
    w, h, d = _dims(size)
    m = Model("leg")
    stops = [
        (0.00, 1.00, 1.00, 0.0), (0.10, 0.92, 0.96, 0.0), (0.24, 0.62, 0.60, -0.10),
        (0.50, 0.70, 0.66, -0.20), (0.74, 0.96, 0.92, -0.10), (1.00, 1.00, 1.00, 0.0),
    ]
    m.loft(
        _rings(w, h, d, stops), slot(BASE), sides=10, power=2.6,
        mat_fn=lambda i, k, n: slot(LEATHER) if stops[i][0] < 0.12 else slot(BASE), top_mat=slot(SHADOW),
    )
    return m


def bow(size):
    """A recurve bow standing in the hand: two limbs bowed toward the target, string between."""
    w, h, d = _dims(size)
    m = Model("bow")
    limb = 0.012
    steps = 10
    pts = []
    for i in range(steps + 1):
        t = i / steps
        y = h * t
        bulge = math.sin(t * math.pi)
        z = d * 0.5 + (0.5 - abs(t - 0.5)) * 0.0 + bulge * d * -0.35 + (1 - bulge) * d * 0.35
        pts.append((y, z))
    rings = [
        dict(y=y, cx=w / 2, cz=z, rx=limb * (1.3 - 0.6 * abs(2 * (y / h) - 1) * 0.0), rz=limb * 0.9)
        for y, z in pts
    ]
    m.loft(rings, slot(LEATHER), sides=6, power=2.4)
    m.box(w / 2 - 0.004, 0.0, d * 0.5 + d * 0.35 - 0.002, w / 2 + 0.004, h, d * 0.5 + d * 0.35 + 0.002, slot(ACCENT))
    m.box(w / 2 - 0.02, h * 0.44, d * 0.5 - d * 0.35 - 0.012, w / 2 + 0.02, h * 0.56, d * 0.5 - d * 0.35 + 0.012, slot(METAL), chamfer=0.004)
    return m


def shield(size):
    """A kite-ish tower shield: slab face, raised rim, central boss and studs."""
    w, h, d = _dims(size)
    m = Model("shield")
    # The face looks along +x for a shield carried on the left arm (its broad side is h x d).
    outline = [
        (d * 0.05, h * 0.05), (d * 0.95, h * 0.05), (d, h * 0.25), (d, h * 0.92), (d * 0.5, h), (0.0, h * 0.92), (0.0, h * 0.25),
    ]
    m.plate([(w * 0.5, y, z) for z, y in outline], (1, 0, 0), w * 0.5, slot(LEATHER))
    m.plate([(0.0, y, z) for z, y in reversed(outline)][::-1], (1, 0, 0), w * 0.5, slot(BASE))
    m.box(w * 0.98, h * 0.08, d * 0.06, w * 1.0 + 0.012, h * 0.94, d * 0.94, slot(METAL), chamfer=0.004)
    m.loft(
        [dict(y=h * 0.42, cx=w + 0.004, cz=d * 0.5, rx=0.004, rz=0.044), dict(y=h * 0.58, cx=w + 0.004, cz=d * 0.5, rx=0.004, rz=0.03)],
        slot(ACCENT), sides=8, power=2.0,
    )
    m.box(w * 0.98, h * 0.06, d * 0.44, w + 0.016, h * 0.94, d * 0.56, slot(ACCENT), chamfer=0.003)
    return m


def target_stripe(size):
    w, h, d = _dims(size)
    m = Model("stripe")
    m.box(0, 0, 0, w, h, d, slot(ACCENT), chamfer=0.004)
    m.box(w * 0.3, 0.0, d - 0.004, w * 0.7, h, d + 0.010, slot(SHADOW), chamfer=0.003)
    return m
