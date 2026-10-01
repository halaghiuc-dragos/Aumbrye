"""Blender builders for room dressing: braziers, torches, landmarks, beacons, crates and floor pieces.

Roles as in prop_library.gd, plus `pulse`, the room's accent glow (coloured per room from `options`).
"""

from __future__ import annotations

import math
import random

from bl_lib import Model

W, A, T, TR, I, DI, ST = "wall", "accent", "timber", "trim", "iron", "darkiron", "steel"
GLOW, CRYSTAL, FLAME, EMBER, PULSE, FLOOR = "glow", "crystal", "flame", "ember", "pulse", "floor"


def brazier():
    m = Model("brazier")
    for k in range(3):
        a = math.tau * k / 3
        m.tube((math.cos(a) * 0.30, 0.0, math.sin(a) * 0.30), (math.cos(a) * 0.12, 0.62, math.sin(a) * 0.12), 0.032, 0.026, I, sides=5)
    m.loft(
        [dict(y=0.56, rx=0.14, rz=0.14), dict(y=0.66, rx=0.24, rz=0.24), dict(y=0.80, rx=0.30, rz=0.30)],
        I, sides=10, power=2.0, cap_top=False,
    )
    m.loft([dict(y=0.78, rx=0.31, rz=0.31), dict(y=0.82, rx=0.31, rz=0.31)], A, sides=10, power=2.0, cap_bottom=False, cap_top=False)
    m.cylinder(0.0, 0.78, 0.0, 0.26, 0.80, EMBER, sides=10)
    m.cone(0.0, 0.80, 0.0, 0.20, 1.22, FLAME, sides=7)
    m.cone(0.03, 0.88, 0.0, 0.10, 1.12, EMBER, sides=5)
    for k in range(3):
        a = math.tau * k / 3 + 0.5
        m.tube((math.cos(a) * 0.14, 0.82, math.sin(a) * 0.14), (math.cos(a) * 0.22, 1.02, math.sin(a) * 0.22), 0.04, 0.012, FLAME, sides=4)
    return [("Mesh", m, None)]


def ceiling_torch():
    m = Model("ceiling_torch")
    m.tube((0.0, 0.0, 0.0), (0.0, 0.42, 0.0), 0.015, 0.015, I, sides=4)
    m.box(-0.16, 0.0, -0.16, 0.16, 0.05, 0.16, I, chamfer=0.01)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.tube((sx * 0.13, 0.0, sz * 0.13), (sx * 0.13, -0.22, sz * 0.13), 0.013, 0.013, I, sides=4)
    m.box(-0.16, -0.25, -0.16, 0.16, -0.21, 0.16, I, chamfer=0.01)
    m.box(-0.08, -0.20, -0.08, 0.08, -0.02, 0.08, GLOW, chamfer=0.01)
    m.cone(0.0, -0.02, 0.0, 0.08, 0.06, FLAME, sides=5)
    return [("Mesh", m, None)]


# ---------------------------------------------------------------------------------- landmarks

def _landmark_crystal():
    m = Model("landmark")
    p = Model("Pulse")
    m.box(-0.36, 0.0, -0.58, 0.36, 0.4, -0.06, W, chamfer=0.05)
    p.tube((-0.34, 0.0, 0.0), (-0.36, 1.05, 0.0), 0.27, 0.2, PULSE, sides=6)
    p.tube((-0.36, 1.05, 0.0), (-0.40, 1.5, 0.0), 0.2, 0.012, PULSE, sides=6)
    m.tube((0.28, 0.0, 0.12), (0.30, 0.64, 0.12), 0.2, 0.15, A, sides=5)
    m.tube((0.30, 0.64, 0.12), (0.32, 0.92, 0.12), 0.15, 0.01, A, sides=5)
    for k in range(4):
        a = 0.6 + k * 1.3
        m.tube((math.cos(a) * 0.25, 0.0, math.sin(a) * 0.25), (math.cos(a) * 0.5, 0.42 + 0.06 * k, math.sin(a) * 0.5), 0.07, 0.01, A, sides=4)
    return [("Mesh", m, None), ("Pulse", p, None)]


def _landmark_swamp():
    m = Model("landmark")
    m.sphere(0.0, 0.18, 0.0, 0.7, W, sides=9, rings=3, ry=0.2, rz=0.52)
    for k in range(7):
        a = math.tau * k / 7
        m.tube((math.cos(a) * 0.65, 0.05, math.sin(a) * 0.46), (math.cos(a) * 0.25, 0.42, math.sin(a) * 0.18), 0.06, 0.04, A, sides=5)
    for x, z, h in [(-0.28, 0.1, 0.98), (0.32, -0.16, 0.74), (0.05, 0.3, 0.6), (-0.1, -0.3, 0.84)]:
        m.tube((x, 0.3, z), (x + 0.03, h, z), 0.03, 0.012, A, sides=4)
        m.cylinder(x + 0.03, h, z, 0.05, h + 0.14, TR, sides=5, r_top=0.04)
    m.sphere(0.0, 0.46, 0.0, 0.1, GLOW, sides=6, rings=3)
    return [("Mesh", m, None)]


def _landmark_frozen():
    m = Model("landmark")
    p = Model("Pulse")
    m.cylinder(0.0, 0.0, 0.0, 0.5, 0.2, W, sides=8, r_top=0.4)
    p.tube((0.0, 0.0, 0.0), (0.02, 1.25, 0.0), 0.34, 0.22, PULSE, sides=6)
    p.tube((0.02, 1.25, 0.0), (0.05, 1.82, 0.0), 0.22, 0.01, PULSE, sides=6)
    m.tube((0.43, 0.0, 0.14), (0.45, 0.55, 0.14), 0.22, 0.14, A, sides=5)
    m.tube((0.45, 0.55, 0.14), (0.47, 0.8, 0.14), 0.14, 0.01, A, sides=5)
    for k in range(5):
        a = 0.2 + k * 1.25
        m.tube((math.cos(a) * 0.35, 0.0, math.sin(a) * 0.35), (math.cos(a) * 0.6, 0.3 + 0.05 * k, math.sin(a) * 0.6), 0.06, 0.008, A, sides=4)
    return [("Mesh", m, None), ("Pulse", p, None)]


def _landmark_vault():
    m = Model("landmark")
    p = Model("Pulse")
    m.box(-0.59, 0.0, -0.19, 0.59, 1.24, 0.19, I, chamfer=0.04)
    m.box(-0.66, 0.0, -0.26, 0.66, 0.14, 0.26, ST, chamfer=0.03)
    for y in (0.4, 0.85):
        m.box(-0.52, y, 0.18, 0.52, y + 0.08, 0.23, DI, chamfer=0.01)
    for sx in (-0.4, 0.4):
        m.tube((sx, 1.24, 0.0), (sx, 1.5, 0.0), 0.06, 0.05, ST, sides=6)
    p.box(-0.25, 1.24, -0.26, 0.25, 1.4, 0.26, PULSE, chamfer=0.02)
    for k in range(4):
        m.sphere(-0.42 + 0.28 * k, 0.65, 0.22, 0.045, GLOW, sides=6, rings=3)
    return [("Mesh", m, None), ("Pulse", p, None)]


def _landmark_cathedral():
    m = Model("landmark")
    p = Model("Pulse")
    m.box(-0.52, 0.0, -0.31, 0.52, 0.22, 0.31, W, chamfer=0.03)
    m.box(-0.44, 0.22, -0.24, 0.44, 1.22, 0.24, W, chamfer=0.04)
    m.pyramid(-0.52, -0.31, 0.52, 0.31, 1.22, 1.5, A)
    m.box(-0.16, 0.45, 0.22, 0.16, 0.95, 0.28, DI, chamfer=0.01)
    m.box(-0.03, 0.55, 0.27, 0.03, 0.9, 0.3, A)
    m.box(-0.12, 0.72, 0.27, 0.12, 0.78, 0.3, A)
    p.cone(0.0, 1.5, 0.0, 0.14, 1.95, PULSE, sides=6)
    return [("Mesh", m, None), ("Pulse", p, None)]


def _landmark_castle():
    m = Model("landmark")
    p = Model("Pulse")
    m.box(-0.5, 0.0, -0.5, 0.5, 0.2, 0.5, W, chamfer=0.03)
    m.tapered_box((-0.36, -0.36, 0.36, 0.36), (-0.3, -0.3, 0.3, 0.3), 0.2, 1.62, W, chamfer=0.03)
    for y in (0.55, 1.05):
        m.box(-0.39, y, -0.39, 0.39, y + 0.1, 0.39, A, chamfer=0.015)
    m.box(-0.52, 1.62, -0.52, 0.52, 1.72, 0.52, A, chamfer=0.02)
    p.box(-0.3, 1.72, -0.3, 0.3, 1.82, 0.3, PULSE, chamfer=0.015)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box(sx * 0.4 - 0.07, 1.72, sz * 0.4 - 0.07, sx * 0.4 + 0.07, 1.86, sz * 0.4 + 0.07, W, chamfer=0.01)
    return [("Mesh", m, None), ("Pulse", p, None)]


# ------------------------------------------------------------------------------------ beacons

def beacon_treasure():
    m = Model("beacon")
    m.box(-0.58, 0.0, -0.36, 0.58, 0.48, 0.36, PULSE, chamfer=0.05)
    m.cone(0.0, 0.48, 0.0, 0.17, 0.92, PULSE, sides=5)
    return [("Mesh", m, None)]


def beacon_secret():
    m = Model("beacon")
    m.box(-0.59, 0.0, -0.59, 0.59, 0.1, 0.59, PULSE, chamfer=0.02)
    m.cone(0.0, 0.1, 0.0, 0.12, 0.74, PULSE, sides=5)
    for k in range(4):
        a = math.pi / 4 + math.pi / 2 * k
        m.box(math.cos(a) * 0.4 - 0.05, 0.1, math.sin(a) * 0.4 - 0.05, math.cos(a) * 0.4 + 0.05, 0.16, math.sin(a) * 0.4 + 0.05, PULSE)
    return [("Mesh", m, None)]


def beacon_puzzle():
    m = Model("beacon")
    for x, y, z, h in [(-0.42, 0.0, 0.0, 0.48), (0.0, 0.0, 0.12, 0.84), (0.42, 0.0, 0.0, 0.48)]:
        m.cone(x, y, z, 0.14, y + h, PULSE, sides=4)
    return [("Mesh", m, None)]


def beacon_arena():
    m = Model("beacon")
    for x in (-0.44, 0.44):
        m.box(x - 0.14, 0.0, -0.14, x + 0.14, 0.16, 0.14, PULSE, chamfer=0.02)
        m.cone(x, 0.16, 0.0, 0.18, 1.3, PULSE, sides=4)
    return [("Mesh", m, None)]


# ------------------------------------------------------------------------------ floor pieces

def dais():
    """A low stepped platform, 1 unit wide (scaled in x to the room) and 2 deep."""
    m = Model("dais")
    m.box(-0.5, 0.0, -1.0, 0.5, 0.08, 1.0, A, chamfer=0.012)
    m.box(-0.48, 0.08, -0.85, 0.48, 0.16, 0.85, A, chamfer=0.012)
    m.box(-0.46, 0.16, -0.7, 0.46, 0.17, 0.7, FLOOR)
    return [("Mesh", m, None)]


def arena_ring():
    """A flat ring of runes and studs, unit radius; scaled in x and z to the room."""
    m = Model("arena_ring")
    n = 36
    outer = [m.ring_points(0, 0, 1.0, 1.0, 0.0, n, 2.0), m.ring_points(0, 0, 1.0, 1.0, 0.045, n, 2.0)]
    inner = [m.ring_points(0, 0, 0.95, 0.95, 0.0, n, 2.0), m.ring_points(0, 0, 0.95, 0.95, 0.045, n, 2.0)]
    m._bridge(outer, A)
    m._bridge(list(reversed(inner)), A)
    for k in range(n):
        k2 = (k + 1) % n
        m.face([outer[1][k], outer[1][k2], inner[1][k2], inner[1][k]], A)
    for k in range(24):
        a = math.tau * k / 24
        r = 0.975
        m.box(math.cos(a) * r - 0.012, 0.04, math.sin(a) * r - 0.012, math.cos(a) * r + 0.012, 0.055, math.sin(a) * r + 0.012, PULSE)
    return [("Mesh", m, None)]


def plinth():
    m = Model("plinth")
    m.box(-1.25, 0.0, -1.25, 1.25, 0.06, 1.25, A, chamfer=0.01)
    m.box(-1.05, 0.06, -1.05, 1.05, 0.1, 1.05, W, chamfer=0.01)
    for k in range(8):
        a = math.tau * k / 8
        m.box(math.cos(a) * 0.82 - 0.05, 0.1, math.sin(a) * 0.82 - 0.05, math.cos(a) * 0.82 + 0.05, 0.13, math.sin(a) * 0.82 + 0.05, A)
    return [("Mesh", m, None)]


def pedestal():
    m = Model("pedestal")
    m.box(-0.8, 0.0, -0.6, 0.8, 0.14, 0.6, W, chamfer=0.03)
    m.box(-0.7, 0.14, -0.5, 0.7, 0.42, 0.5, A, chamfer=0.03)
    m.box(-0.76, 0.42, -0.56, 0.76, 0.5, 0.56, W, chamfer=0.02)
    for sx in (-1, 1):
        m.box(sx * 0.6 - 0.04, 0.5, -0.4, sx * 0.6 + 0.04, 0.62, 0.4, A, chamfer=0.01)
    return [("Mesh", m, None)]


def secret_panel():
    m = Model("secret_panel")
    m.box(-0.175, 0.0, -1.1, 0.175, 2.4, 1.1, A, chamfer=0.03)
    m.box(-0.2, 0.0, -1.14, 0.2, 0.14, 1.14, W, chamfer=0.02)
    m.box(-0.2, 2.3, -1.14, 0.2, 2.44, 1.14, W, chamfer=0.02)
    for z in (-0.6, 0.0, 0.6):
        m.box(0.165, 0.4, z - 0.15, 0.2, 2.0, z + 0.15, W, chamfer=0.01)
    m.box(0.165, 1.1, -0.04, 0.2, 1.3, 0.04, PULSE)
    return [("Mesh", m, None)]


def puzzle_core():
    m = Model("puzzle_core")
    m.box(-0.6, 0.0, -0.6, 0.6, 0.18, 0.6, W, chamfer=0.03)
    m.box(-0.5, 0.18, -0.5, 0.5, 0.8, 0.5, A, chamfer=0.03)
    m.box(-0.55, 0.8, -0.55, 0.55, 0.9, 0.55, W, chamfer=0.02)
    m.pyramid(-0.3, -0.3, 0.3, 0.3, 0.9, 1.16, GLOW)
    m.pyramid(-0.3, -0.3, 0.3, 0.3, 0.9, 0.78, GLOW)
    return [("Mesh", m, None)]


def puzzle_orb():
    m = Model("puzzle_orb")
    m.box(-0.3, 0.0, -0.3, 0.3, 0.12, 0.3, W, chamfer=0.03)
    m.pyramid(-0.22, -0.22, 0.22, 0.22, 0.12, 0.4, GLOW)
    m.pyramid(-0.22, -0.22, 0.22, 0.22, 0.12, 0.05, GLOW)
    return [("Mesh", m, None)]


# --------------------------------------------------------------------------------- clutter

def crate():
    m = Model("crate")
    m.box(-0.45, 0.0, -0.45, 0.45, 0.9, 0.45, T, chamfer=0.02)
    for y in (0.0, 0.78):
        m.box(-0.47, y, -0.47, 0.47, y + 0.12, 0.47, TR, chamfer=0.01)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box(sx * 0.42 - 0.05, 0.0, sz * 0.42 - 0.05, sx * 0.42 + 0.05, 0.9, sz * 0.42 + 0.05, TR, chamfer=0.008)
    for zs in (-1, 1):
        m.plate([(x, y, zs * 0.455) for x, y in [(-0.4, 0.12), (-0.33, 0.12), (0.4, 0.78), (0.33, 0.78)]], (0, 0, zs), 0.012, TR)
    return [("Mesh", m, None)]


def barrel():
    m = Model("barrel")
    m.loft(
        [dict(y=0.0, rx=0.30, rz=0.30), dict(y=0.3, rx=0.37, rz=0.37), dict(y=0.6, rx=0.39, rz=0.39), dict(y=0.9, rx=0.36, rz=0.36), dict(y=1.0, rx=0.29, rz=0.29)],
        T, sides=12, power=2.0, mat_fn=lambda i, k, n: TR if k % 3 == 0 else T, top_mat=TR,
    )
    for y, r in ((0.12, 0.33), (0.45, 0.395), (0.78, 0.375)):
        m.loft([dict(y=y - 0.03, rx=r + 0.006, rz=r + 0.006), dict(y=y + 0.03, rx=r + 0.006, rz=r + 0.006)], I, sides=12, power=2.0, cap_bottom=False, cap_top=False)
    return [("Mesh", m, None)]


def sack():
    m = Model("sack")
    m.loft(
        [dict(y=0.0, rx=0.26, rz=0.22), dict(y=0.2, rx=0.32, rz=0.27), dict(y=0.42, rx=0.27, rz=0.23), dict(y=0.58, rx=0.14, rz=0.12), dict(y=0.66, rx=0.17, rz=0.15)],
        TR, sides=10, power=2.2,
    )
    m.loft([dict(y=0.52, rx=0.16, rz=0.14), dict(y=0.56, rx=0.16, rz=0.14)], T, sides=10, power=2.0, cap_bottom=False, cap_top=False)
    return [("Mesh", m, None)]


BUILDERS = {
    "brazier": brazier, "ceiling_torch": ceiling_torch,
    "landmark_crystal": _landmark_crystal, "landmark_swamp": _landmark_swamp, "landmark_frozen": _landmark_frozen,
    "landmark_vault": _landmark_vault, "landmark_cathedral": _landmark_cathedral, "landmark_castle": _landmark_castle,
    "beacon_treasure": beacon_treasure, "beacon_secret": beacon_secret, "beacon_puzzle": beacon_puzzle, "beacon_arena": beacon_arena,
    "dais": dais, "arena_ring": arena_ring, "plinth": plinth, "pedestal": pedestal, "secret_panel": secret_panel,
    "puzzle_core": puzzle_core, "puzzle_orb": puzzle_orb, "crate": crate, "barrel": barrel, "sack": sack,
}
