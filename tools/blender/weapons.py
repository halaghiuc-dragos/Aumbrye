"""Blender builders for hand-held weapons.

Frames follow the runtime weapon kit: the origin is the grip. Swords, daggers and axes reach toward
-y, spears, staves and bows toward +y, and a shield's face looks along -x.
Colours: `steel`, `steel_dark`, `leather`, `wood` are literals; `slot2` is the biome accent.
"""

from __future__ import annotations

import math

from bl_lib import ACCENT, Model, literal, slot

STEEL = literal((0.74, 0.78, 0.84))
STEEL_LIGHT = literal((0.86, 0.90, 0.95))
STEEL_DARK = literal((0.34, 0.36, 0.42))
LEATHER = literal((0.30, 0.20, 0.14))
LEATHER_DARK = literal((0.20, 0.13, 0.09))
WOOD = literal((0.48, 0.34, 0.24))
WOOD_DARK = literal((0.36, 0.25, 0.17))
CORD = literal((0.82, 0.80, 0.72))
ACC = slot(ACCENT)


def _round_rings(y0, y1, r0, r1, steps=1, cx=0.0, cz=0.0):
    return [
        dict(y=y0 + (y1 - y0) * i / steps, cx=cx, cz=cz, rx=r0 + (r1 - r0) * i / steps, rz=r0 + (r1 - r0) * i / steps)
        for i in range(steps + 1)
    ]


def _grip(m, y_low, y_high, radius, mat=LEATHER, wrap=LEATHER_DARK):
    """A wrapped grip: a cylinder with raised bands."""
    m.cylinder(0.0, y_low, 0.0, radius, y_high, mat, sides=8)
    n = max(2, int((y_high - y_low) / 0.022))
    for i in range(n):
        y = y_low + (y_high - y_low) * (i + 0.5) / n
        m.cylinder(0.0, y - 0.004, 0.0, radius * 1.16, y + 0.004, wrap, sides=8)


def _blade(m, tip_y, base_y, width, thick, taper_from=0.7, mat=STEEL, edge=STEEL_LIGHT, fuller=True):
    """A double-edged blade lofted between base_y (wide end) and tip_y (point). Either may be lower."""
    down = tip_y < base_y
    length = abs(base_y - tip_y)
    rings = []
    stops = [(0.0, 1.0), (taper_from, 0.92), (0.90, 0.55), (0.985, 0.16), (1.0, 0.02)]
    for f, k in stops:
        y = base_y + (tip_y - base_y) * f
        rings.append(dict(y=y, cx=0.0, cz=0.0, rx=width / 2 * k, rz=thick / 2 * (0.5 + 0.5 * k)))
    rings.sort(key=lambda r: r["y"])
    m.loft(rings, mat, sides=8, power=1.35, cap_bottom=True, cap_top=True)
    if fuller:
        y_a = base_y + (tip_y - base_y) * 0.06
        y_b = base_y + (tip_y - base_y) * 0.78
        lo, hi = min(y_a, y_b), max(y_a, y_b)
        for zs in (-1, 1):
            m.box(-width * 0.05, lo, zs * (thick / 2 * 0.62), width * 0.05, hi, zs * (thick / 2 * 0.62) + zs * 0.003, STEEL_DARK)
    # Bright edge lines along both sides.
    for xs in (-1, 1):
        y_a = base_y + (tip_y - base_y) * 0.04
        y_b = base_y + (tip_y - base_y) * 0.80
        lo, hi = min(y_a, y_b), max(y_a, y_b)
        m.box(xs * width * 0.44, lo, -thick * 0.06, xs * width * 0.48 + xs * 0.002, hi, thick * 0.06, edge)


def sword(blade_len, blade_w, guard_span=2.6, name="sword"):
    m = Model(name)
    grip_len = 0.13 if blade_len < 0.8 else 0.20
    _grip(m, -0.02 + (0.0), 0.02 + grip_len - 0.05, blade_w * 0.36)
    # Pommel: a faceted disc with a jewel.
    py = 0.02 + grip_len - 0.04
    m.cylinder(0.0, py, 0.0, blade_w * 0.55, py + 0.05, ACC, sides=8, r_top=blade_w * 0.42)
    m.cone(0.0, py + 0.05, 0.0, blade_w * 0.28, py + 0.075, ACC, sides=6)
    # Cross-guard with swept quillons.
    gy = -0.07
    span = blade_w * guard_span
    for sx in (-1, 1):
        m.tapered_box(
            (min(0, sx * span / 2), -blade_w * 0.30, max(0, sx * span / 2), blade_w * 0.30),
            (min(0, sx * span / 2) + (0.0 if sx > 0 else 0.0), -blade_w * 0.18, max(0, sx * span / 2), blade_w * 0.18),
            gy - 0.030, gy + 0.030, ACC, chamfer=0.004,
        )
        m.box(sx * span / 2 - (0.012 if sx > 0 else 0.0), gy - 0.048, -blade_w * 0.16, sx * span / 2 + (0.0 if sx > 0 else 0.012), gy + 0.030, blade_w * 0.16, ACC, chamfer=0.003)
    m.box(-blade_w * 0.55, gy - 0.032, -blade_w * 0.32, blade_w * 0.55, gy + 0.034, blade_w * 0.32, ACC, chamfer=0.006)
    _blade(m, -0.09 - blade_len, -0.09 + 0.004, blade_w, blade_w * 0.42)
    return m


def dagger(blade_len, blade_w):
    m = Model("dagger")
    _grip(m, -0.02, 0.10, blade_w * 0.38)
    m.cylinder(0.0, 0.09, 0.0, blade_w * 0.6, 0.13, ACC, sides=6, r_top=blade_w * 0.35)
    m.box(-blade_w * 1.1, -0.075, -blade_w * 0.30, blade_w * 1.1, -0.040, blade_w * 0.30, ACC, chamfer=0.004)
    _blade(m, -0.06 - blade_len, -0.06, blade_w, blade_w * 0.40, taper_from=0.5, fuller=False)
    return m


def axe():
    """A bearded battle axe, reaching toward -y from the grip."""
    m = Model("axe")
    shaft_top, shaft_bot = 0.10, -0.66
    m.cylinder(0.0, shaft_bot, 0.0, 0.020, shaft_top, WOOD, sides=8)
    _grip(m, -0.10, 0.10, 0.024)
    m.cylinder(0.0, shaft_top - 0.01, 0.0, 0.034, shaft_top + 0.03, ACC, sides=8)  # butt cap
    # Head: a curved bit hanging off the socket, on the +x side, with a spike opposite.
    hy = -0.56
    m.box(-0.030, hy - 0.10, -0.030, 0.030, hy + 0.10, 0.030, ACC, chamfer=0.006)  # socket
    bit = [(0.020, hy + 0.14), (0.15, hy + 0.20), (0.17, hy + 0.05), (0.15, hy - 0.10), (0.11, hy - 0.22), (0.020, hy - 0.10)]
    m.plate([(x, y, -0.022) for x, y in bit], (0, 0, 1), 0.044, STEEL)
    edge = [(0.15, hy + 0.20), (0.17, hy + 0.05), (0.15, hy - 0.10), (0.11, hy - 0.22), (0.10, hy - 0.20), (0.135, hy - 0.10), (0.15, hy + 0.05), (0.135, hy + 0.18)]
    m.plate([(x, y, -0.012) for x, y in edge], (0, 0, 1), 0.024, STEEL_LIGHT)
    m.box(-0.10, hy - 0.020, -0.014, -0.030, hy + 0.020, 0.014, STEEL_DARK, chamfer=0.003)  # back spike
    return m


def staff():
    m = Model("staff")
    m.cylinder(0.0, -0.20, 0.0, 0.017, 0.50, WOOD, sides=8)
    _grip(m, -0.20, -0.02, 0.023)
    # Twisted-looking shaft bands.
    for i in range(6):
        y = 0.05 + i * 0.07
        m.cylinder(0.0, y, 0.0, 0.021, y + 0.012, WOOD_DARK, sides=8)
    # Cradle: four prongs holding a focus crystal.
    for k in range(4):
        a = math.pi / 2 * k + math.pi / 4
        x, z = math.cos(a) * 0.05, math.sin(a) * 0.05
        m.tapered_box((x - 0.008, z - 0.008, x + 0.008, z + 0.008), (x * 1.5 - 0.005, z * 1.5 - 0.005, x * 1.5 + 0.005, z * 1.5 + 0.005), 0.48, 0.66, WOOD_DARK, chamfer=0.002)
    m.cylinder(0.0, 0.46, 0.0, 0.032, 0.50, ACC, sides=8, r_top=0.026)
    # Focus: an octahedron.
    m.pyramid(-0.045, -0.045, 0.045, 0.045, 0.56, 0.66, ACC)
    m.pyramid(-0.045, -0.045, 0.045, 0.045, 0.56, 0.46, ACC)
    return m


def spear():
    m = Model("spear")
    m.cylinder(0.0, 0.10, 0.0, 0.026, 1.50, WOOD, sides=8)
    _grip(m, -0.02, 0.14, 0.034)
    m.cone(0.0, -0.02, 0.0, 0.026, -0.08, STEEL_DARK, sides=6)  # butt spike
    # Collar and ribbons.
    m.cylinder(0.0, 1.46, 0.0, 0.040, 1.56, ACC, sides=8)
    for k, x in enumerate((-0.03, 0.03)):
        m.box(x - 0.010, 1.16 - k * 0.04, -0.004, x + 0.010, 1.46, 0.004, ACC)
    # Leaf blade with a mid-rib.
    rings = [
        dict(y=1.55, cx=0, cz=0, rx=0.030, rz=0.016),
        dict(y=1.62, cx=0, cz=0, rx=0.062, rz=0.020),
        dict(y=1.72, cx=0, cz=0, rx=0.050, rz=0.016),
        dict(y=1.84, cx=0, cz=0, rx=0.016, rz=0.008),
        dict(y=1.90, cx=0, cz=0, rx=0.002, rz=0.002),
    ]
    m.loft(rings, STEEL, sides=8, power=1.35)
    for zs in (-1, 1):
        m.box(-0.006, 1.58, zs * 0.017, 0.006, 1.84, zs * 0.017 + zs * 0.003, STEEL_DARK)
    return m


def bow():
    m = Model("bow")
    steps = 12
    limb = []
    for i in range(steps + 1):
        t = i / steps
        y = -0.60 + 1.20 * t
        # Recurve: the limbs sweep forward (+z) toward the tips.
        z = 0.02 + 0.10 * math.sin(t * math.pi) * 0.0 + 0.14 * (abs(2 * t - 1) ** 1.6) - 0.02
        r = 0.020 * (1.0 - 0.45 * abs(2 * t - 1))
        limb.append(dict(y=y, cx=0.0, cz=z, rx=r * 0.8, rz=r * 1.1))
    m.loft(limb, WOOD, sides=6, power=2.2)
    tip_z = limb[-1]["cz"]
    m.box(-0.010, -0.60, tip_z - 0.010, 0.010, -0.575, tip_z + 0.014, ACC)
    m.box(-0.010, 0.575, tip_z - 0.010, 0.010, 0.60, tip_z + 0.014, ACC)
    # String, and a leather grip wrap on the riser.
    m.box(-0.0035, -0.585, tip_z + 0.010, 0.0035, 0.585, tip_z + 0.017, CORD)
    m.cylinder(0.0, -0.09, 0.0, 0.032, 0.09, LEATHER, sides=8)
    m.cylinder(0.0, -0.02, 0.0, 0.040, 0.02, ACC, sides=8)
    return m


def shield():
    """A heater shield, face toward -x."""
    m = Model("shield")
    outline = [  # (z, y), counter-clockwise as seen from -x
        (-0.25, 0.32), (0.25, 0.32), (0.26, 0.10), (0.20, -0.12), (0.08, -0.26), (0.0, -0.30),
        (-0.08, -0.26), (-0.20, -0.12), (-0.26, 0.10),
    ]
    # Back board: thick wooden slab.
    m.plate([(-0.02, y, z) for z, y in outline], (1, 0, 0), 0.06, WOOD_DARK)
    # Front plate and rim.
    m.plate([(-0.03, y, z * 0.94) for z, y in outline], (-1, 0, 0), 0.022, STEEL_DARK)
    for zs in (-0.25, 0.25):
        m.box(-0.078, -0.14, zs - 0.012, -0.03, 0.32, zs + 0.012, ACC, chamfer=0.004)
    m.box(-0.078, 0.30, -0.26, -0.03, 0.335, 0.26, ACC, chamfer=0.004)
    # Cross bar and central boss.
    m.box(-0.076, 0.03, -0.24, -0.05, 0.075, 0.24, LEATHER, chamfer=0.003)
    m.box(-0.076, -0.30, -0.020, -0.05, 0.30, 0.020, LEATHER, chamfer=0.003)
    boss_c = (-0.058, 0.055, 0.0)
    # A domed boss built as a stack of rings along -x.
    layers = []
    for k, xo in [(1.0, 0.0), (0.92, -0.020), (0.66, -0.036), (0.30, -0.046)]:
        ring = m.ring_points(0.0, 0.0, 0.075 * k, 0.075 * k, 0.0, 10, 2.0)
        layers.append([(boss_c[0] + xo, boss_c[1] + pz, px) for (px, _py, pz) in ring])
    m._bridge(layers, ACC)
    m.face(layers[-1], ACC)
    return m


def unknown():
    m = Model("unknown")
    m.box(-0.04, -0.06, -0.04, 0.04, 0.06, 0.04, STEEL_DARK, chamfer=0.006)
    m.box(-0.08, -0.10, -0.02, 0.08, -0.06, 0.02, ACC, chamfer=0.004)
    return m


BUILDERS = {
    "sword": lambda: sword(0.62, 0.09),
    "greatsword": lambda: sword(0.95, 0.13, guard_span=2.3, name="greatsword"),
    "dagger": lambda: dagger(0.34, 0.07),
    "axe": axe,
    "staff": staff,
    "spear": spear,
    "bow": bow,
    "shield": shield,
    "unknown": unknown,
}
