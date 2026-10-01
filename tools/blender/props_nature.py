"""Blender builders for the outdoor arenas: turf, flowers, trees, hedges, the castle backdrop and birds.

Roles are the outdoor diorama's material names (grass, grass_alt, grass_dark, blade, blade_alt,
stem, birch, flower_*, wall, accent, wood) plus `bird`, a dark silhouette.
"""

from __future__ import annotations

import math
import random

from bl_lib import Model

G, GA, GD = "grass", "grass_alt", "grass_dark"
BL, BLA, STEM, BIRCH = "blade", "blade_alt", "stem", "birch"
W, A, WOOD = "wall", "accent", "wood"


def _lump(m, cx, cy, cz, rx, ry, rz, mat, sides=8, rings=4):
    m.sphere(cx, cy, cz, rx, mat, sides=sides, rings=rings, ry=ry, rz=rz)


def grass_tuft(variant):
    rng = random.Random("tuft%d" % variant)
    m = Model("tuft")
    for i in range(rng.randint(4, 6)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.0, 0.16)
        x, z = math.cos(a) * d, math.sin(a) * d
        h = rng.uniform(0.2, 0.52)
        lean = (rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12))
        mat = BL if rng.random() > 0.45 else BLA
        mid = (x + lean[0] * 0.5, h * 0.6, z + lean[1] * 0.5)
        tip = (x + lean[0], h, z + lean[1])
        m.tube((x, 0.0, z), mid, 0.045, 0.03, mat, sides=4)
        m.tube(mid, tip, 0.03, 0.004, mat, sides=4)
    return [("Mesh", m, None)]


def flower(colour):
    m = Model("flower")
    h = 0.32
    m.tube((0, 0, 0), (0.01, h, 0.0), 0.03, 0.022, STEM, sides=4)
    role = "flower_" + colour
    for k in range(6):
        a = math.tau * k / 6
        m.pyramid(math.cos(a) * 0.07 - 0.045, math.sin(a) * 0.07 - 0.045, math.cos(a) * 0.07 + 0.045, math.sin(a) * 0.07 + 0.045, h, h + 0.05, role, apex=(math.cos(a) * 0.1, math.sin(a) * 0.1))
    m.sphere(0.01, h + 0.04, 0.0, 0.05, role, sides=6, rings=3, ry=0.04)
    return [("Mesh", m, None)]


def oak():
    m = Model("oak")
    m.loft([dict(y=0.0, rx=0.34, rz=0.34), dict(y=0.35, rx=0.23, rz=0.23), dict(y=1.6, rx=0.2, rz=0.2), dict(y=2.3, rx=0.16, rz=0.16)], WOOD, sides=8, power=2.2, cap_bottom=False)
    for k in range(5):
        a = math.tau * k / 5 + 0.3
        m.tube((math.cos(a) * 0.12, 1.7, math.sin(a) * 0.12), (math.cos(a) * 0.95, 2.5 + 0.1 * (k % 2), math.sin(a) * 0.95), 0.09, 0.05, WOOD, sides=5)
    for k in range(6):
        a = math.tau * k / 6
        _lump(m, math.cos(a) * 0.85, 2.7 + 0.12 * (k % 3), math.sin(a) * 0.85, 0.85, 0.65, 0.85, G if k % 2 == 0 else GA)
    _lump(m, 0.0, 3.25, 0.0, 1.25, 0.85, 1.25, G)
    _lump(m, 0.15, 3.0, -0.1, 0.9, 0.6, 0.9, GA)
    return [("Mesh", m, None)]


def pine():
    m = Model("pine")
    m.loft([dict(y=0.0, rx=0.22, rz=0.22), dict(y=0.3, rx=0.15, rz=0.15), dict(y=3.2, rx=0.11, rz=0.11)], WOOD, sides=6, power=2.0, cap_bottom=False)
    for layer in range(5):
        r = 1.0 - layer * 0.17
        y = 1.4 + layer * 0.66
        m.cone(0, y, 0, r, y + 1.0, GD, sides=8)
        m.loft([dict(y=y - 0.05, rx=r * 0.96, rz=r * 0.96), dict(y=y + 0.06, rx=r * 0.9, rz=r * 0.9)], G if layer % 2 else GD, sides=8, power=2.0, cap_bottom=False, cap_top=False)
    m.cone(0, 4.6, 0, 0.14, 5.2, GD, sides=5)
    return [("Mesh", m, None)]


def birch():
    m = Model("birch")
    m.loft([dict(y=0.0, rx=0.17, rz=0.17), dict(y=0.3, rx=0.13, rz=0.13), dict(y=2.8, rx=0.1, rz=0.1)], BIRCH, sides=6, power=2.0, cap_bottom=False)
    for y in (0.3, 0.75, 1.3, 1.8, 2.35):
        m.box(-0.11, y, -0.11, 0.11, y + 0.07, 0.11, STEM, chamfer=0.01)
    for k in range(4):
        a = math.tau * k / 4
        m.tube((0.0, 2.2, 0.0), (math.cos(a) * 0.5, 2.9, math.sin(a) * 0.5), 0.04, 0.025, BIRCH, sides=4)
    for k in range(5):
        a = math.tau * k / 5 + 0.4
        _lump(m, math.cos(a) * 0.5, 3.0 + 0.1 * (k % 2), math.sin(a) * 0.5, 0.55, 0.48, 0.55, GA if k % 2 == 0 else G)
    _lump(m, 0.0, 3.4, 0.0, 0.7, 0.55, 0.7, GA)
    return [("Mesh", m, None)]


def bush():
    m = Model("bush")
    for i in range(3):
        a = i / 3 * math.tau
        _lump(m, math.cos(a) * 0.55, 0.45, math.sin(a) * 0.55, 0.62, 0.45, 0.62, GD if i % 2 == 0 else G)
    _lump(m, 0.0, 0.7, 0.0, 0.55, 0.42, 0.55, G)
    return [("Mesh", m, None)]


def flowering_tree():
    m = Model("flowering")
    m.loft([dict(y=0.0, rx=0.3, rz=0.3), dict(y=0.3, rx=0.2, rz=0.2), dict(y=1.7, rx=0.15, rz=0.15)], WOOD, sides=7, power=2.2, cap_bottom=False)
    for k in range(4):
        a = math.tau * k / 4 + 0.2
        m.tube((0, 1.4, 0), (math.cos(a) * 0.8, 2.1, math.sin(a) * 0.8), 0.07, 0.04, WOOD, sides=5)
    for k in range(7):
        a = math.tau * k / 7
        _lump(m, math.cos(a) * 0.7, 2.2 + 0.1 * (k % 3), math.sin(a) * 0.7, 0.6, 0.5, 0.6, "flower_purple")
    _lump(m, 0.0, 2.65, 0.0, 0.95, 0.7, 0.95, "flower_purple")
    for k in range(6):
        a = math.tau * k / 6 + 0.6
        _lump(m, math.cos(a) * 0.55, 2.0, math.sin(a) * 0.55, 0.22, 0.16, 0.22, G)
    return [("Mesh", m, None)]


def hedge():
    m = Model("hedge")
    rng = random.Random("hedge")
    m.box(-1.1, 0.0, -0.6, 1.1, 0.72, 0.6, GD, chamfer=0.12)
    for i in range(10):
        x = rng.uniform(-0.95, 0.95)
        _lump(m, x, 0.78, rng.uniform(-0.3, 0.3), 0.3, 0.2, 0.34, G if i % 2 else GD, sides=6, rings=3)
    for sx in (-1, 1):
        m.box(sx * 1.08 - 0.05, 0.0, -0.55, sx * 1.08 + 0.05, 0.3, 0.55, W, chamfer=0.01)
    return [("Mesh", m, None)]


def garden_bed():
    m = Model("bed")
    m.box(-4.0, 0.0, -1.6, 4.0, 0.12, 1.6, GD, chamfer=0.03)
    for sx in (-1, 1):
        m.box(sx * 4.0 - 0.1, 0.0, -1.7, sx * 4.0 + 0.1, 0.22, 1.7, W, chamfer=0.02)
    for sz in (-1, 1):
        m.box(-4.1, 0.0, sz * 1.6 - 0.1, 4.1, 0.22, sz * 1.6 + 0.1, W, chamfer=0.02)
    rng = random.Random("bed")
    for i in range(12):
        x, z = rng.uniform(-3.5, 3.5), rng.uniform(-1.2, 1.2)
        role = "flower_red" if i % 3 == 0 else "flower_yellow"
        m.tube((x, 0.1, z), (x, 0.26, z), 0.025, 0.02, STEM, sides=4)
        m.sphere(x, 0.3, z, 0.1, role, sides=6, rings=3, ry=0.08)
    return [("Mesh", m, None)]


def castle_backdrop():
    m = Model("castle")
    span = 52.0
    wh = 12.0
    m.box(-span / 2, 0.0, -0.6, span / 2, wh, 0.6, W, chamfer=0.1)
    m.box(-span / 2, 0.0, -0.75, span / 2, 0.9, 0.75, W, chamfer=0.08)
    for k in range(int(span / 4)):
        x = -span / 2 + 2.0 + k * 4.0
        m.box(x - 0.2, 0.9, 0.6, x + 0.2, wh - 0.6, 0.85, W, chamfer=0.03)
    m.box(-span / 2 - 0.1, wh - 0.6, -0.8, span / 2 + 0.1, wh, 0.95, A, chamfer=0.06)
    for i in range(11):
        t = i / 10
        x = -span / 2 + 1.0 + t * (span - 2.0)
        m.box(x - 0.75, wh, -0.5, x + 0.75, wh + 1.3, 0.5, A, chamfer=0.06)
    for k in range(9):
        x = -span / 2 + 5.0 + k * 5.2
        m.box(x - 0.15, 4.0, 0.6, x + 0.15, 7.0, 0.7, "darkiron")
    for tx in (-span * 0.42, span * 0.42):
        m.tapered_box((tx - 1.9, -1.4, tx + 1.9, 2.2), (tx - 1.7, -1.3, tx + 1.7, 2.1), 0.0, wh + 3.5, W, chamfer=0.08)
        m.box(tx - 2.1, wh + 3.5, -1.6, tx + 2.1, wh + 4.05, 2.4, A, chamfer=0.06)
        for k in range(8):
            a = math.tau * k / 8
            cx, cz = tx + math.cos(a) * 1.75, 0.4 + math.sin(a) * 1.75
            m.box(cx - 0.3, wh + 4.05, cz - 0.3, cx + 0.3, wh + 4.6, cz + 0.3, W, chamfer=0.04)
        m.cone(tx, wh + 4.05, 0.4, 1.4, wh + 7.4, A, sides=8)
        for y in (6.0, 10.0):
            m.box(tx - 0.2, y, 2.05, tx + 0.2, y + 1.0, 2.25, "darkiron")
    m.box(-2.5, 0.0, 0.4, 2.5, 6.5, 2.4, A, chamfer=0.08)
    m.box(-1.0, 0.0, 2.35, 1.0, 3.6, 2.5, "darkiron", chamfer=0.04)
    m.box(-1.2, 3.4, 2.3, 1.2, 3.75, 2.55, W, chamfer=0.03)
    m.box(-2.7, 6.5, 0.2, 2.7, 7.0, 2.6, W, chamfer=0.05)
    for k in range(6):
        x = -2.3 + k * 0.92
        m.box(x - 0.3, 7.0, 0.3, x + 0.3, 7.55, 2.5, W, chamfer=0.03)
    return [("Mesh", m, None)]


def bird():
    body = Model("Body")
    body.box(-0.08, -0.06, -0.25, 0.08, 0.06, 0.25, "bird", chamfer=0.02)
    body.box(-0.05, -0.04, 0.22, 0.05, 0.05, 0.38, "bird", chamfer=0.015)
    body.box(-0.05, -0.025, -0.43, 0.05, 0.025, -0.21, "bird", chamfer=0.01)
    objs = [("Body", body, None)]
    for side, name in ((-1, "WingL"), (1, "WingR")):
        w = Model(name)
        w.box(min(side * 0.04, side * 0.43), -0.025, -0.14, max(side * 0.04, side * 0.43), 0.025, 0.14, "bird", chamfer=0.01)
        objs.append((name, w, (0.0, 0.0, 0.0)))
        t = Model("Outer")
        lo, hi = (side * 0.0, side * 0.34)
        t.box(min(lo, hi), -0.02, -0.13, max(lo, hi), 0.02, 0.07, "bird", chamfer=0.008)
        objs.append(("Outer" + name, t, (side * 0.43, 0.0, 0.0), name))
    return objs


def grass_module(parity):
    m = Model("grass")
    rng = random.Random("grassmod%d" % parity)
    m.box(-5.0, -0.1, -5.0, 5.0, 0.0, 5.0, G, chamfer=0.0)
    for row in range(5):
        for col in range(5):
            cx, cz = -4.0 + col * 2.0, -4.0 + row * 2.0
            alt = ((row + col + parity) % 2) == 1
            m.box(cx - 0.99, 0.0, cz - 0.99, cx + 0.99, 0.12, cz + 0.99, GA if alt else G, chamfer=0.03)
            for _ in range(3):
                x, z = cx + rng.uniform(-0.8, 0.8), cz + rng.uniform(-0.8, 0.8)
                m.pyramid(x - 0.05, z - 0.05, x + 0.05, z + 0.05, 0.12, 0.12 + rng.uniform(0.04, 0.09), GD if alt else GA)
    return [("Mesh", m, None)]


def ground_plate():
    m = Model("plate")
    m.box(-0.5, 0.0, -0.5, 0.5, 0.1, 0.5, GD)
    return [("Mesh", m, None)]


BUILDERS = {
    "nature/tuft_0": lambda: grass_tuft(0), "nature/tuft_1": lambda: grass_tuft(1), "nature/tuft_2": lambda: grass_tuft(2),
    "nature/flower_red": lambda: flower("red"), "nature/flower_yellow": lambda: flower("yellow"),
    "nature/flower_purple": lambda: flower("purple"), "nature/flower_white": lambda: flower("white"),
    "nature/oak": oak, "nature/pine": pine, "nature/birch": birch, "nature/bush": bush,
    "nature/flowering_tree": flowering_tree, "nature/hedge": hedge, "nature/garden_bed": garden_bed,
    "nature/castle_backdrop": castle_backdrop, "nature/bird": bird,
    "nature/grass_module_0": lambda: grass_module(0), "nature/grass_module_1": lambda: grass_module(1),
    "nature/ground_plate": ground_plate,
}
