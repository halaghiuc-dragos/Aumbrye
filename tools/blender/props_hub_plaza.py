"""Blender builders for the hub plaza: fountain, benches, banners, planters, carts, walls and floor.

Roles are the hub material names (wall, wood, accent, roof, paper, cloth, floor, floor_alt, training,
hub_iron) plus leaf_dark, leaf_light, bloom, bark, bone, candle, glass and water.
"""

from __future__ import annotations

import math
import random

from bl_lib import Model

W, WOOD, A, ROOF, PAPER, CLOTH = "wall", "wood", "accent", "roof", "paper", "cloth"
FLOOR, FLOOR_ALT, TRAIN, IRON = "floor", "floor_alt", "training", "hub_iron"
LEAF_D, LEAF_L, BLOOM, BARK, BONE, CANDLE, GLASS, WATER = "leaf_dark", "leaf_light", "bloom", "bark", "bone", "candle", "glass", "water"


def fountain():
    m = Model("fountain")
    w = Model("Water")
    m.cylinder(0, 0.0, 0, 2.55, 0.34, W, sides=24, r_top=2.4)
    m.loft([dict(y=0.0, rx=2.55, rz=2.55), dict(y=0.36, rx=2.42, rz=2.42)], W, sides=24, power=2.0, cap_bottom=False, cap_top=False)
    ring = [m.ring_points(0, 0, 2.42, 2.42, 0.36, 24, 2.0), m.ring_points(0, 0, 2.05, 2.05, 0.36, 24, 2.0)]
    for k in range(24):
        k2 = (k + 1) % 24
        m.face([ring[0][k], ring[0][k2], ring[1][k2], ring[1][k]], W)
    m.loft([dict(y=0.36, rx=2.05, rz=2.05), dict(y=0.2, rx=2.05, rz=2.05)], W, sides=24, power=2.0, cap_bottom=False, cap_top=False, mat_fn=lambda i, k, n: W)
    w.cylinder(0, 0.2, 0, 2.04, 0.25, WATER, sides=24)
    for k in range(8):
        a = math.tau * k / 8
        m.box(math.cos(a) * 2.23 - 0.16, 0.36, math.sin(a) * 2.23 - 0.16, math.cos(a) * 2.23 + 0.16, 0.5, math.sin(a) * 2.23 + 0.16, A, chamfer=0.02)
    m.cylinder(0, 0.2, 0, 0.75, 0.42, W, sides=12, r_top=0.6)
    m.loft([dict(y=0.42, rx=0.5, rz=0.5), dict(y=1.0, rx=0.4, rz=0.4), dict(y=1.12, rx=0.52, rz=0.52)], W, sides=12, power=2.0, cap_bottom=False, cap_top=False)
    m.loft([dict(y=1.12, rx=0.98, rz=0.98), dict(y=1.22, rx=0.98, rz=0.98), dict(y=1.3, rx=0.64, rz=0.64), dict(y=1.12, rx=0.52, rz=0.52)], A, sides=16, power=2.0, cap_bottom=False, cap_top=False)
    m.cylinder(0, 1.3, 0, 0.3, 1.36, W, sides=10)
    m.cylinder(0, 1.36, 0, 0.24, 1.6, A, sides=10, r_top=0.15)
    return [("Mesh", m, None), ("Water", w, None)]


def broken_column(index):
    heights = [0.7, 1.05, 1.4, 1.75]
    height = heights[index]
    m = Model("column")
    m.box(-0.65, 0.0, -0.65, 0.65, 0.26, 0.65, W, chamfer=0.03)
    drums = max(1, int(height / 0.55))
    for i in range(drums):
        w = 0.86 - i * 0.05
        ox, oz = (i % 2) * 0.06 - 0.03, ((i + 1) % 2) * 0.05
        y0 = 0.26 + 0.5 * i
        m.loft(
            [dict(y=y0, cx=ox, cz=oz, rx=w / 2, rz=w / 2), dict(y=y0 + 0.5, cx=ox, cz=oz, rx=w / 2 * 0.97, rz=w / 2 * 0.97)],
            W, sides=10, power=2.0, mat_fn=lambda i2, k, n: A if k % 5 == 0 else W,
        )
    top = 0.26 + 0.5 * drums
    m.tapered_box((-0.4, -0.4, 0.4, 0.4), (-0.3, -0.35, 0.36, 0.38), top, top + 0.3, W, chamfer=0.02)
    for i in range(3):
        sx = 0.42 - i * 0.08
        m.box(0.95 + i * 0.4 - sx / 2, 0.0, -0.6 + i * 0.55 - (0.4 - i * 0.06) / 2, 0.95 + i * 0.4 + sx / 2, 0.26, -0.6 + i * 0.55 + (0.4 - i * 0.06) / 2, W, chamfer=0.04)
    return [("Mesh", m, None)]


def votive_cairn():
    m = Model("cairn")
    y = 0.0
    for i, w in enumerate([1.1, 0.86, 0.64, 0.44]):
        h = 0.24 - i * 0.03
        ox, oz = (i % 2) * 0.05, ((i + 1) % 2) * 0.04
        m.box(ox - w / 2, y, oz - w * 0.45, ox + w / 2, y + h, oz + w * 0.45, W, chamfer=0.03)
        y += h
    m.tube((0, y, 0), (0, y + 0.5, 0), 0.07, 0.05, IRON, sides=6)
    for i in range(3):
        a = math.tau * i / 3
        x, z = math.cos(a) * 0.34, math.sin(a) * 0.34
        ch = 0.2 + i * 0.06
        m.tube((x, y, z), (x, y + ch, z), 0.055, 0.05, BONE, sides=6)
        m.cone(x, y + ch, z, 0.04, y + ch + 0.1, CANDLE, sides=5)
    return [("Mesh", m, None)]


def growth_banner_pole():
    m = Model("pole")
    pole_h = 3.6
    m.box(-0.25, 0.0, -0.25, 0.25, 0.2, 0.25, W, chamfer=0.03)
    m.tube((0, 0.2, 0), (0, 0.2 + pole_h, 0), 0.085, 0.075, WOOD, sides=8)
    m.box(-0.12, 0.2 + pole_h, -0.12, 0.12, 0.2 + pole_h + 0.05, 0.12, A, chamfer=0.01)
    m.pyramid(-0.12, -0.12, 0.12, 0.12, pole_h + 0.25, pole_h + 0.5, A)
    m.sphere(0, pole_h + 0.22, 0, 0.1, A, sides=6, rings=3)
    return [("Mesh", m, None)]


def banner_cloth(pole_h, cross_w, cloth_w, cloth_h, cross_y, cloth_y):
    m = Model("cloth")
    z = 0.16
    m.box(-cross_w / 2, cross_y - 0.06, z - 0.06, cross_w / 2, cross_y + 0.06, z + 0.06, WOOD, chamfer=0.01)
    # A banner that ends in a swallow-tail, with an embroidered band.
    top, bot = cloth_y + cloth_h / 2, cloth_y - cloth_h / 2
    m.plate([(-cloth_w / 2, top, z), (cloth_w / 2, top, z), (cloth_w / 2, bot, z), (0.0, bot + cloth_h * 0.14, z), (-cloth_w / 2, bot, z)], (0, 0, 1), 0.05, CLOTH)
    m.box(-cloth_w * 0.38, top - cloth_h * 0.3, z + 0.05, cloth_w * 0.38, top - cloth_h * 0.22, z + 0.065, A)
    for sx in (-1, 1):
        m.sphere(sx * cross_w / 2, cross_y, z, 0.06, A, sides=6, rings=3)
    return [("Mesh", m, None)]


def growth_trophy():
    m = Model("trophy")
    m.box(-0.45, 0.0, -0.3, 0.45, 0.9, 0.3, W, chamfer=0.03)
    m.box(-0.35, 0.9, -0.25, 0.35, 0.96, 0.25, WOOD, chamfer=0.01)
    m.box(-0.25, 0.96, -0.2, 0.25, 1.46, 0.2, A, chamfer=0.03)
    m.sphere(0, 1.3, 0.12, 0.17, A, sides=8, rings=4, rz=0.1)
    for sx in (-1, 1):
        m.tube((sx * 0.2, 1.46, 0.0), (sx * 0.5, 1.92, 0.0), 0.1, 0.02, TRAIN, sides=5)
    return [("Mesh", m, None)]


def growth_marker():
    m = Model("marker")
    m.box(-0.5, 0.0, -0.5, 0.5, 0.2, 0.5, W, chamfer=0.03)
    m.box(-0.25, 0.2, -0.15, 0.25, 1.7, 0.15, W, chamfer=0.04)
    m.pyramid(-0.25, -0.15, 0.25, 0.15, 1.7, 1.85, W)
    m.box(-0.21, 0.75, 0.15, 0.21, 1.45, 0.19, A, chamfer=0.005)
    for k in range(4):
        m.box(-0.14, 0.88 + k * 0.14, 0.19, 0.14 - (k % 2) * 0.08, 0.93 + k * 0.14, 0.205, W)
    return [("Mesh", m, None)]


def growth_shelf():
    m = Model("shelf")
    m.box(-0.8, 0.0, -0.25, 0.8, 2.2, 0.25, WOOD, chamfer=0.02)
    m.box(-0.86, 2.2, -0.29, 0.86, 2.28, 0.29, ROOF, chamfer=0.01)
    for i in range(4):
        y = 0.35 + i * 0.5
        m.box(-0.75, y - 0.03, -0.25, 0.75, y + 0.03, 0.27, ROOF, chamfer=0.006)
        for b in range(5):
            mat = PAPER if b % 2 == 0 else A
            m.box(-0.66 + b * 0.28, y + 0.03, -0.12, -0.54 + b * 0.28, y + 0.03 + 0.4 - (b % 3) * 0.04, 0.18, mat, chamfer=0.006)
    return [("Mesh", m, None)]


def growth_board():
    m = Model("board")
    for sx in (-1, 1):
        m.box(sx * 0.9 - 0.07, 0.0, -0.07, sx * 0.9 + 0.07, 2.0, 0.07, WOOD, chamfer=0.01)
    m.box(-1.0, 1.05, -0.05, 1.0, 2.35, 0.05, A, chamfer=0.015)
    m.box(-1.06, 2.35, -0.07, 1.06, 2.42, 0.07, ROOF, chamfer=0.01)
    for i in range(3):
        m.box(-0.8 + i * 0.6, 1.42, 0.05, -0.4 + i * 0.6, 1.98, 0.08, PAPER, chamfer=0.003)
    return [("Mesh", m, None)]


def growth_workshop():
    m = Model("workshop")
    m.box(-1.1, 0.87, -0.4, 1.1, 1.03, 0.4, WOOD, chamfer=0.015)
    for sx in (-1, 1):
        m.box(sx * 0.88 - 0.09, 0.0, -0.34, sx * 0.88 + 0.09, 0.95, 0.34, W, chamfer=0.015)
    m.box(-0.66, 1.03, -0.14, -0.18, 1.15, 0.14, W, chamfer=0.01)
    m.tube((-0.66, 1.12, 0.0), (-0.92, 1.12, 0.0), 0.06, 0.02, W, sides=4)
    m.box(0.45, 0.97, -0.11, 0.67, 1.51, 0.11, A, chamfer=0.01)
    for k in range(3):
        m.tube((0.56, 1.3 + 0.07 * k, 0.11), (0.56 + 0.16, 1.2 + 0.07 * k, 0.11), 0.018, 0.018, IRON, sides=4)
    return [("Mesh", m, None)]


def railing(span=4.0):
    m = Model("railing")
    m.box(-span / 2, 0.97, -0.045, span / 2, 1.06, 0.045, IRON, chamfer=0.01)
    m.box(-span / 2, 0.385, -0.035, span / 2, 0.455, 0.035, IRON, chamfer=0.008)
    bars = max(3, int(span / 0.38))
    for i in range(bars):
        x = -span / 2 + span * (i + 0.5) / bars
        m.tube((x, 0.0, 0.0), (x, 1.25, 0.0), 0.035, 0.03, IRON, sides=4)
        m.pyramid(x - 0.045, -0.045, x + 0.045, 0.045, 1.25, 1.42, IRON)
    for sx in (-1, 1):
        m.box(sx * span / 2 - 0.08, 0.0, -0.08, sx * span / 2 + 0.08, 1.5, 0.08, IRON, chamfer=0.012)
        m.sphere(sx * span / 2, 1.56, 0, 0.09, IRON, sides=6, rings=3)
    return [("Mesh", m, None)]


def hub_brazier():
    m = Model("brazier")
    c = Model("Coals")
    m.box(-0.31, 0.0, -0.31, 0.31, 0.16, 0.31, W, chamfer=0.02)
    m.loft([dict(y=0.16, rx=0.11, rz=0.11), dict(y=0.7, rx=0.09, rz=0.09), dict(y=1.16, rx=0.12, rz=0.12)], WOOD, sides=8, power=2.0, cap_bottom=False, cap_top=False)
    m.loft([dict(y=1.15, rx=0.2, rz=0.2), dict(y=1.3, rx=0.36, rz=0.36), dict(y=1.49, rx=0.38, rz=0.38)], A, sides=12, power=2.0, cap_top=False)
    for k in range(8):
        a = math.tau * k / 8
        m.box(math.cos(a) * 0.37 - 0.04, 1.42, math.sin(a) * 0.37 - 0.04, math.cos(a) * 0.37 + 0.04, 1.56, math.sin(a) * 0.37 + 0.04, A, chamfer=0.008)
    c.cylinder(0, 1.46, 0, 0.3, 1.54, TRAIN, sides=10)
    for k in range(4):
        a = math.tau * k / 4 + 0.4
        c.cone(math.cos(a) * 0.12, 1.54, math.sin(a) * 0.12, 0.09, 1.72, TRAIN, sides=4)
    return [("Mesh", m, None), ("Coals", c, None)]


def banner_avenue_pole():
    m = Model("pole")
    top = 6.45
    pole_h = top - 0.24
    m.box(-0.31, 0.0, -0.31, 0.31, 0.24, 0.31, W, chamfer=0.03)
    m.box(-0.21, 0.24, -0.21, 0.21, 0.44, 0.21, W, chamfer=0.02)
    m.tube((0, 0.24, 0), (0, top, 0), 0.1, 0.085, WOOD, sides=8)
    for band in range(2):
        m.box(-0.14, 4.3 + band * 1.0, -0.14, 0.14, 4.4 + band * 1.0, 0.14, W, chamfer=0.01)
    m.box(-0.25, 6.2 - 0.07, -0.07, 0.25, 6.2 + 0.07, 0.07, WOOD, chamfer=0.01)
    m.tube((0, top, 0), (0, top + 0.12, 0), 0.06, 0.05, TRAIN, sides=4)
    m.sphere(0, top + 0.16, 0, 0.13, TRAIN, sides=6, rings=3)
    return [("Mesh", m, None)]


def market_clutter():
    m = Model("clutter")
    m.box(-0.4, 0.0, -0.4, 0.4, 0.8, 0.4, WOOD, chamfer=0.02)
    for y in (0.0, 0.7):
        m.box(-0.42, y, -0.42, 0.42, y + 0.1, 0.42, ROOF, chamfer=0.01)
    m.box(0.29, 0.8, -0.15, 0.95, 1.46, 0.51, WOOD, chamfer=0.02)
    m.box(0.27, 0.8, -0.17, 0.97, 0.88, 0.53, ROOF, chamfer=0.01)
    m.loft([dict(y=0.0, cx=-0.85, cz=0.3, rx=0.26, rz=0.26), dict(y=0.4, cx=-0.85, cz=0.3, rx=0.31, rz=0.31), dict(y=0.9, cx=-0.85, cz=0.3, rx=0.27, rz=0.27)], A, sides=10, power=2.0, mat_fn=lambda i, k, n: ROOF if k % 3 == 0 else A, top_mat=ROOF)
    m.loft([dict(y=0.0, cx=0.3, cz=-0.85, rx=0.36, rz=0.3), dict(y=0.22, cx=0.3, cz=-0.85, rx=0.36, rz=0.3), dict(y=0.42, cx=0.3, cz=-0.85, rx=0.2, rz=0.17)], FLOOR_ALT, sides=10, power=2.2)
    return [("Mesh", m, None)]


def planter_tree():
    m = Model("tree")
    rng = random.Random("planter_tree")
    m.box(-0.95, 0.0, -0.95, 0.95, 0.44, 0.95, W, chamfer=0.04)
    m.box(-0.78, 0.44, -0.78, 0.78, 0.52, 0.78, FLOOR_ALT, chamfer=0.02)
    m.tube((0, 0.5, 0), (0.05, 2.0, 0.0), 0.19, 0.12, WOOD, sides=7)
    for k in range(4):
        a = math.tau * k / 4 + 0.4
        m.tube((0.03, 1.5, 0.0), (math.cos(a) * 0.7, 2.1 + 0.1 * (k % 2), math.sin(a) * 0.7), 0.07, 0.04, WOOD, sides=5)
    canopy = [(0.0, 2.35, 0.0, 1.25, 0.55, LEAF_D), (0.3, 2.85, -0.14, 0.95, 0.5, LEAF_L), (-0.16, 3.35, 0.18, 0.66, 0.42, LEAF_D)]
    for cx, cy, cz, r, ry, mat in canopy:
        m.sphere(cx, cy, cz, r, mat, sides=9, rings=4, ry=ry)
    for _ in range(14):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.4, 1.0)
        m.sphere(math.cos(a) * d, rng.uniform(2.2, 3.3), math.sin(a) * d, 0.28, LEAF_L if rng.random() < 0.5 else LEAF_D, sides=6, rings=3)
    return [("Mesh", m, None)]


def flower_trough():
    m = Model("trough")
    m.box(-1.15, 0.0, -0.39, 1.15, 0.46, 0.39, WOOD, chamfer=0.03)
    m.box(-1.2, 0.36, -0.42, 1.2, 0.46, 0.42, ROOF, chamfer=0.01)
    m.box(-1.02, 0.46, -0.3, 1.02, 0.56, 0.3, FLOOR_ALT, chamfer=0.01)
    for i in range(5):
        x = -0.82 + i * 0.41
        h = 0.34 + ((i * 7) % 3) * 0.12
        m.pyramid(x - 0.15, -0.15, x + 0.15, 0.15, 0.56, 0.56 + h, LEAF_L)
        m.tube((x, 0.56, 0.0), (x + 0.02, 0.56 + h, 0.02), 0.03, 0.02, LEAF_L, sides=4)
        m.sphere(x + 0.02, 0.62 + h, 0.02, 0.1, BLOOM, sides=6, rings=3)
    return [("Mesh", m, None)]


def bench():
    m = Model("bench")
    m.box(-1.0, 0.38, -0.3, 1.0, 0.54, 0.3, WOOD, chamfer=0.015)
    for k in range(3):
        m.box(-1.0, 0.54, -0.3 + k * 0.2 + 0.005, 1.0, 0.545, -0.3 + k * 0.2 + 0.015, ROOF)
    for sx in (-1, 1):
        m.box(sx * 0.78 - 0.09, 0.0, -0.27, sx * 0.78 + 0.09, 0.4, 0.27, W, chamfer=0.015)
        m.box(sx * 0.78 - 0.07, 0.4, -0.3, sx * 0.78 + 0.07, 1.0, -0.2, W, chamfer=0.012)
    m.box(-1.0, 0.56, -0.3, 1.0, 1.02, -0.18, WOOD, chamfer=0.015)
    m.box(-0.98, 0.72, -0.18, 0.98, 0.78, -0.14, ROOF)
    return [("Mesh", m, None)]


def lantern_cord():
    """An 11 m cord along z with five hanging lanterns; lights are added in code at the glass."""
    m = Model("cord")
    span = 11.0
    bunting_y = 6.2
    m.box(-0.035, bunting_y - 0.035, -span / 2, 0.035, bunting_y + 0.035, span / 2, WOOD)
    for i in range(5):
        t = (i + 1) / 6
        z = -span / 2 + span * t
        drop = 0.2 + (i % 2) * 0.1
        m.tube((0, bunting_y, z), (0, bunting_y - drop, z), 0.02, 0.02, WOOD, sides=4)
        y = bunting_y - drop
        m.box(-0.15, y - 0.09, z - 0.15, 0.15, y, z + 0.15, A, chamfer=0.01)
        m.pyramid(-0.13, z - 0.13, 0.13, z + 0.13, y, y + 0.08, A)
        m.box(-0.13, y - 0.39, z - 0.13, 0.13, y - 0.09, z + 0.13, GLASS, chamfer=0.01)
        m.box(-0.15, y - 0.44, z - 0.15, 0.15, y - 0.39, z + 0.15, A, chamfer=0.008)
    return [("Mesh", m, None)]


def cart():
    m = Model("cart")
    m.box(-1.15, 0.66, -0.62, 1.15, 0.9, 0.62, WOOD, chamfer=0.015)
    for k in range(5):
        m.box(-1.15, 0.9, -0.62 + k * 0.25, 1.15, 0.905, -0.62 + k * 0.25 + 0.012, ROOF)
    for sz in (-1, 1):
        m.box(-1.15, 0.9, sz * 0.57 - 0.06, 1.15, 1.32, sz * 0.57 + 0.06, WOOD, chamfer=0.012)
        m.box(-1.15, 1.28, sz * 0.57 - 0.08, 1.15, 1.34, sz * 0.57 + 0.08, ROOF, chamfer=0.008)
    m.box(-1.15, 0.9, -0.62, -1.03, 1.32, 0.62, WOOD, chamfer=0.012)
    for sz in (-1, 1):
        cx, cz = 0.35, sz * 0.68
        m.tube((cx, 0.44, cz - 0.08), (cx, 0.44, cz + 0.08), 0.44, 0.44, A, sides=12)
        m.tube((cx, 0.44, cz - 0.09), (cx, 0.44, cz + 0.09), 0.1, 0.1, W, sides=8)
        for k in range(6):
            a = math.tau * k / 6
            m.tube((cx, 0.44, cz + 0.085), (cx + math.cos(a) * 0.4, 0.44 + math.sin(a) * 0.4, cz + 0.085), 0.03, 0.03, WOOD, sides=4)
    m.tube((0.35, 0.44, -0.6), (0.35, 0.44, 0.6), 0.06, 0.06, W, sides=6)
    for sz in (-1, 1):
        m.tube((-1.05, 0.66, sz * 0.48), (-2.3, 0.2, sz * 0.48), 0.06, 0.05, WOOD, sides=4)
    m.box(-0.66, 0.9, -0.31, -0.04, 1.52, 0.31, FLOOR_ALT, chamfer=0.03)
    m.box(0.2, 0.9, -0.03, 0.7, 1.4, 0.47, A, chamfer=0.02)
    return [("Mesh", m, None)]


def woodpile():
    m = Model("woodpile")
    for row in range(3):
        count = 4 - row
        for i in range(count):
            z = -0.36 + i * 0.27 + row * 0.13
            y = 0.15 + row * 0.27
            mat = BARK if (i + row) % 2 == 0 else WOOD
            m.tube((-0.75, y, z), (0.75, y, z), 0.13, 0.13, mat, sides=8)
    m.tube((-0.75, 0.15, -0.36), (-0.85, 0.15, -0.36), 0.05, 0.05, WOOD, sides=4)
    for sx in (-1, 1):
        m.box(sx * 0.82 - 0.04, 0.0, -0.5, sx * 0.82 + 0.04, 0.85, -0.42, WOOD, chamfer=0.008)
        m.box(sx * 0.82 - 0.04, 0.0, 0.42, sx * 0.82 + 0.04, 0.85, 0.5, WOOD, chamfer=0.008)
    return [("Mesh", m, None)]


def pot():
    m = Model("pot")
    m.loft([dict(y=0.0, rx=0.22, rz=0.22), dict(y=0.3, rx=0.32, rz=0.32), dict(y=0.5, rx=0.34, rz=0.34)], A, sides=10, power=2.0)
    m.cylinder(0, 0.48, 0, 0.37, 0.56, A, sides=10)
    m.cylinder(0, 0.5, 0, 0.27, 0.56, FLOOR_ALT, sides=10)
    m.sphere(0, 0.82, 0, 0.3, LEAF_D, sides=8, rings=4, ry=0.26)
    m.sphere(0.04, 1.1, -0.03, 0.2, LEAF_D, sides=7, rings=3, ry=0.17)
    m.sphere(-0.1, 1.2, 0.12, 0.09, BLOOM, sides=6, rings=3)
    m.sphere(0.12, 1.05, 0.14, 0.06, BLOOM, sides=6, rings=3)
    return [("Mesh", m, None)]


# ---------------------------------------------------------------------------- walls and floor

def parapet_segment():
    """2.68 m of crenellated wall walk: two merlon cycles (0.82 wide, 0.52 gap)."""
    length, h, thick = 2.68, 1.55, 0.72
    m = Model("parapet")
    m.box(-length / 2, -h / 2, -thick / 2, length / 2, h / 2, thick / 2, W, chamfer=0.03)
    m.box(-length / 2 - 0.09, h / 2, -thick / 2 - 0.07, length / 2 + 0.09, h / 2 + 0.14, thick / 2 + 0.07, A, chamfer=0.02)
    for cx in (-0.67, 0.67):
        m.box(cx - 0.41, h / 2 + 0.14, -thick / 2 - 0.05, cx + 0.41, h / 2 + 0.62, thick / 2 + 0.05, W, chamfer=0.035)
        m.box(cx - 0.45, h / 2 + 0.6, -thick / 2 - 0.08, cx + 0.45, h / 2 + 0.68, thick / 2 + 0.08, A, chamfer=0.02)
        m.box(cx - 0.04, h / 2 + 0.3, thick / 2 + 0.04, cx + 0.04, h / 2 + 0.52, thick / 2 + 0.06, "hub_iron")
    for x in (-0.9, 0.0, 0.9):
        m.box(x - 0.11, -h / 2 + 0.4, thick / 2 - 0.0, x + 0.11, -h / 2 + 0.52, thick / 2 + 0.08, A, chamfer=0.008)
        m.box(x - 0.08, -h / 2 + 0.1, thick / 2 - 0.0, x + 0.08, -h / 2 + 0.4, thick / 2 + 0.05, A, chamfer=0.008)
    return [("Mesh", m, None)]


def parapet_turret():
    m = Model("turret")
    parapet_h = 1.55
    th = parapet_h + 2.45
    m.box(-0.75, 0.0, -0.75, 0.75, 0.3, 0.75, W, chamfer=0.04)
    m.tapered_box((-0.675, -0.675, 0.675, 0.675), (-0.62, -0.62, 0.62, 0.62), 0.3, th - 0.2, W, chamfer=0.04)
    for y in (1.2, 2.4):
        m.box(-0.7, y, -0.7, 0.7, y + 0.1, 0.7, A, chamfer=0.015)
    for zs in (-1, 1):
        m.box(-0.04, 1.6, zs * 0.62 - 0.02, 0.04, 2.3, zs * 0.62 + 0.02, "hub_iron")
    m.box(-0.78, th - 0.2, -0.78, 0.78, th, 0.78, A, chamfer=0.025)
    for i in range(4):
        a = i * math.tau / 4
        x, z = math.cos(a) * 0.62, math.sin(a) * 0.62
        m.box(x - 0.21, th, z - 0.21, x + 0.21, th + 0.38, z + 0.21, W, chamfer=0.03)
    return [("Mesh", m, None)]


def floor_module(parity):
    """Ten metres of plaza paving: 5x5 tiles of 2 m, alternating by `parity`."""
    m = Model("floor")
    rng = random.Random("hub_floor_%d" % parity)
    m.box(-5.0, -0.1, -5.0, 5.0, 0.0, 5.0, FLOOR, chamfer=0.0)
    for row in range(5):
        for col in range(5):
            cx, cz = -4.0 + col * 2.0, -4.0 + row * 2.0
            alt = ((row + col + parity) % 2) == 1
            mat = FLOOR_ALT if alt else FLOOR
            m.box(cx - 0.98, 0.0, cz - 0.98, cx + 0.98, 0.12, cz + 0.98, mat, chamfer=0.02)
            # Worn corners and a few chips.
            for _ in range(2):
                x = cx + rng.uniform(-0.8, 0.8)
                z = cz + rng.uniform(-0.8, 0.8)
                s = rng.uniform(0.05, 0.14)
                m.box(x - s, 0.12, z - s, x + s, 0.125, z + s, FLOOR if alt else FLOOR_ALT)
    return [("Mesh", m, None)]


BUILDERS = {
    "hub/fountain": fountain,
    "hub/votive_cairn": votive_cairn, "hub/growth_banner_pole": growth_banner_pole,
    "hub/banner_cloth_growth": lambda: banner_cloth(6.2, 0.7, 0.62, 1.3, 3.5, 2.85),
    "hub/banner_cloth_avenue": lambda: banner_cloth(6.2, 0.9, 0.8, 1.7, 3.5, 2.6),
    "hub/growth_trophy": growth_trophy, "hub/growth_marker": growth_marker, "hub/growth_shelf": growth_shelf,
    "hub/growth_board": growth_board, "hub/growth_workshop": growth_workshop, "hub/railing": railing,
    "hub/brazier": hub_brazier, "hub/banner_avenue_pole": banner_avenue_pole, "hub/market_clutter": market_clutter,
    "hub/planter_tree": planter_tree, "hub/flower_trough": flower_trough, "hub/bench": bench,
    "hub/lantern_cord": lantern_cord, "hub/cart": cart, "hub/woodpile": woodpile, "hub/pot": pot,
    "hub/parapet_segment": parapet_segment, "hub/parapet_turret": parapet_turret,
    "hub/floor_module_0": lambda: floor_module(0), "hub/floor_module_1": lambda: floor_module(1),
}
for _i in range(4):
    BUILDERS["hub/broken_column_%d" % _i] = (lambda i=_i: broken_column(i))
