"""Blender builders for portals, their accents and the market stall.

Roles are the hub material names (wall, accent, floor, wood, roof, umbral, training, dragon, forge,
cathedral); the game supplies the real materials for each.
"""

from __future__ import annotations

import math

from bl_lib import Model

W, A, FLOOR = "wall", "accent", "floor"
RING_SEGMENTS, RING_CENTER_Y, RING_RADIUS, RING_DEPTH = 24, 1.85, 1.62, 0.62


def _wedge(m, a0, a1, r0, r1, z0, z1, mat, chamfer=0.012):
    """An arch stone: the ring segment between two angles and radii, extruded along z."""
    cx, cy = 0.0, RING_CENTER_Y
    p = lambda a, r: (cx + math.cos(a) * r, cy + math.sin(a) * r)
    pts = [p(a0, r0), p(a1, r0), p(a1, r1), p(a0, r1)]
    m.plate([(x, y, z0) for x, y in pts], (0, 0, 1), z1 - z0, mat)
    # A slightly proud face plate so every stone has its own edge.
    inset = 0.012
    pts2 = [p(a0 + 0.012, r0 + inset), p(a1 - 0.012, r0 + inset), p(a1 - 0.012, r1 - inset), p(a0 + 0.012, r1 - inset)]
    m.plate([(x, y, z1) for x, y in pts2], (0, 0, 1), chamfer, mat)


def portal_arch():
    m = Model("portal_arch")
    m.box(-2.1, 0.0, -1.2, 2.1, 0.24, 1.2, W, chamfer=0.03)
    m.box(-1.85, 0.24, -1.05, 1.85, 0.44, 1.05, W, chamfer=0.03)
    m.box(-1.65, 0.44, -0.9, 1.65, 0.56, 0.9, A, chamfer=0.02)
    m.box(-1.4, 0.48, -0.4, 1.4, 0.62, 1.1, FLOOR, chamfer=0.01)
    d = RING_DEPTH
    da = math.tau / RING_SEGMENTS
    for i in range(RING_SEGMENTS):
        a = math.tau * i / RING_SEGMENTS
        proud = 0.0 if i % 2 == 0 else 0.08
        _wedge(m, a - da * 0.47, a + da * 0.47, RING_RADIUS - 0.23, RING_RADIUS + 0.23 + proud * 0.5, -d / 2 - proud / 2, d / 2 + proud / 2, W)
        # accent band on the face
        bx, by = math.cos(a) * (RING_RADIUS - 0.28), RING_CENTER_Y + math.sin(a) * (RING_RADIUS - 0.28)
        m.tube((bx - math.sin(a) * 0.08, by + math.cos(a) * 0.08, d / 2 + 0.08), (bx + math.sin(a) * 0.08, by - math.cos(a) * 0.08, d / 2 + 0.08), 0.06, 0.06, A, sides=4)
    m.box(-0.37, RING_CENTER_Y + RING_RADIUS - 0.23, -d / 2 - 0.08, 0.37, RING_CENTER_Y + RING_RADIUS + 0.39, d / 2 + 0.08, A, chamfer=0.03)
    m.box(-0.45, RING_CENTER_Y - RING_RADIUS - 0.22, -d / 2 - 0.06, 0.45, RING_CENTER_Y - RING_RADIUS + 0.12, d / 2 + 0.06, A, chamfer=0.03)
    for side in (-1, 1):
        pier_top = RING_CENTER_Y - 0.4
        m.box(side * 1.42 - 0.31, 0.56, -0.43, side * 1.42 + 0.31, pier_top, 0.43, W, chamfer=0.04)
        m.box(side * 1.42 - 0.4, 0.56, -0.5, side * 1.42 + 0.4, 0.78, 0.5, A, chamfer=0.03)
        m.box(side * 1.84 - 0.08, 1.42, 0.05, side * 1.84 + 0.08, 1.58, 0.55, W, chamfer=0.012)
        m.cylinder(side * 1.84, 1.56, 0.5, 0.17, 1.80, A, sides=8, r_top=0.23)
        m.cylinder(side * 1.84, 1.80, 0.5, 0.2, 1.84, W, sides=8)
    m.box(-1.3, 0.56, 0.3, 1.3, 0.68, 0.54, A, chamfer=0.02)
    return [("Mesh", m, None)]


def accent_torch_pair():
    m = Model("accent")
    for sx in (-1, 1):
        x = sx * 2.05
        m.box(x - 0.11, 0.1, 0.04, x + 0.11, 0.25, 0.26, A, chamfer=0.015)
        m.tube((x, 0.25, 0.15), (x, 2.75, 0.15), 0.1, 0.085, A, sides=6)
        for y in (0.9, 1.6, 2.3):
            m.cylinder(x, y, 0.15, 0.12, y + 0.06, A, sides=6)
        m.cylinder(x, 2.7, 0.15, 0.13, 2.95, A, sides=8, r_top=0.19)
        m.cone(x, 2.95, 0.15, 0.15, 3.3, "flame", sides=6)
    return [("Mesh", m, None)]


def accent_rune_ring():
    m = Model("accent")
    m.box(-1.6, 0.11, 0.76, 1.6, 0.29, 0.94, "umbral", chamfer=0.02)
    for k in range(7):
        x = -1.35 + 0.45 * k
        m.box(x - 0.05, 0.29, 0.8, x + 0.05, 0.36, 0.9, A)
    return [("Mesh", m, None)]


def accent_training_torches():
    m = Model("accent")
    for sx in (-1, 1):
        m.box(sx * 1.0 - 0.11, 0.11, 0.64, sx * 1.0 + 0.11, 0.33, 0.86, "training", chamfer=0.02)
        x = sx * 2.05
        m.tube((x, 0.2, 0.12), (x, 2.9, 0.12), 0.09, 0.08, "training", sides=6)
        m.cone(x, 2.9, 0.12, 0.13, 3.25, "flame", sides=6)
    return [("Mesh", m, None)]


def accent_dragon_horns():
    m = Model("accent")
    for sx in (-1, 1):
        m.tube((sx * 0.5, 3.85, 0.0), (sx * 0.9, 4.45, 0.0), 0.15, 0.03, "dragon", sides=6)
        m.plate([(sx * 2.05, 1.9, 0.18), (sx * 2.7, 2.1, 0.18), (sx * 2.45, 1.85, 0.18), (sx * 2.75, 1.65, 0.18), (sx * 2.3, 1.75, 0.18), (sx * 2.05, 1.6, 0.18)], (0, 0, 1), 0.1, "dragon")
    m.sphere(0.0, 0.28, 0.85, 0.2, "forge", sides=6, rings=3)
    return [("Mesh", m, None)]


def accent_cathedral_trim():
    m = Model("accent")
    m.box(-0.11, 3.66, 0.03, 0.11, 4.44, 0.21, "cathedral", chamfer=0.01)
    m.box(-0.33, 4.23, 0.03, 0.33, 4.41, 0.21, "cathedral", chamfer=0.01)
    for sx in (-1, 1):
        m.box(sx * 2.05 - 0.1, 0.15, 0.02, sx * 2.05 + 0.1, 3.05, 0.22, "cathedral", chamfer=0.01)
        m.pyramid(sx * 2.05 - 0.12, -0.0, sx * 2.05 + 0.12, 0.24, 3.05, 3.4, "cathedral")
    return [("Mesh", m, None)]


def merchant_stall():
    m = Model("merchant_stall")
    m.box(-1.6, 0.0, -0.8, 1.6, 0.12, 0.8, "wood", chamfer=0.02)
    m.box(-1.4, 0.12, -0.6, 1.4, 1.02, 0.6, W, chamfer=0.03)
    m.box(-1.5, 1.02, -0.66, 1.5, 1.1, 0.66, A, chamfer=0.02)
    for sx in (-1, 1):
        m.box(sx * 1.45 - 0.06, 0.12, -0.72, sx * 1.45 + 0.06, 1.75, -0.6, "wood", chamfer=0.01)
    m.plate([(-1.7, 1.75, -0.75), (1.7, 1.75, -0.75), (1.7, 1.52, -0.05), (-1.7, 1.52, -0.05)], (0, 1, 0), 0.06, "roof")
    for k in range(7):
        x = -1.5 + 0.5 * k
        m.plate([(x, 1.52, -0.05), (x + 0.25, 1.52, -0.05), (x + 0.125, 1.32, -0.05)], (0, 0, 1), 0.02, A if k % 2 else "roof")
    m.box(-0.18, 1.3, -0.4, 0.18, 1.78, -0.32, A, chamfer=0.01)
    for sx in (-1, 1):
        m.box(sx * 0.95 - 0.23, 0.12, 0.33, sx * 0.95 + 0.23, 0.58, 0.77, "wood", chamfer=0.015)
        m.box(sx * 0.95 - 0.25, 0.3, 0.31, sx * 0.95 + 0.25, 0.36, 0.79, "roof", chamfer=0.01)
    for x, h in ((-0.9, 0.22), (-0.45, 0.3), (0.05, 0.18), (0.6, 0.28)):
        m.sphere(x, 1.02 + h / 2 + 0.02, 0.0, 0.11, A, sides=6, rings=3, ry=h / 2)
    return [("Mesh", m, None)]


BUILDERS = {
    "portal_arch": portal_arch,
    "portal_accent_torch_pair": accent_torch_pair, "portal_accent_rune_ring": accent_rune_ring,
    "portal_accent_training_torches": accent_training_torches, "portal_accent_dragon_horns": accent_dragon_horns,
    "portal_accent_cathedral_trim": accent_cathedral_trim, "merchant_stall": merchant_stall,
}
