"""Blender builders for interactable props: chests, levers, bonfires, doors, traps and friends.

Materials are surface roles, not colours (see scripts/art/props/prop_library.gd). Each builder
returns a list of (object_name, Model, origin_or_None); named objects become named nodes in Godot.
"""

from __future__ import annotations

import math

from bl_lib import Model

W, A, T, TR, I, DI, ST = "wall", "accent", "timber", "trim", "iron", "darkiron", "steel"
GLOW, ORB, FLAME, EMBER, CRYSTAL, WARN, TINT = "glow", "orb", "flame", "ember", "crystal", "warn", "tint"
DOOR_W, DOOR_H = 3.0, 4.5


def _profile_dome(a, b, cy, cz, n=9):
    """A half-ellipse in (z, y), from back (-z) over the top to front (+z)."""
    pts = []
    for i in range(n + 1):
        t = math.pi * (1 - i / n)
        pts.append((cz + a * math.cos(t), cy + b * math.sin(t)))
    return pts


def chest():
    body = Model("Body")
    for sx in (-1, 1):
        for sz in (-1, 1):
            body.box(sx * 0.48 - 0.08, 0.0, sz * 0.33 - 0.08, sx * 0.48 + 0.08, 0.13, sz * 0.33 + 0.08, I, chamfer=0.012)
    body.box(-0.59, 0.12, -0.43, 0.59, 0.60, 0.43, T, chamfer=0.014)
    for y in (0.22, 0.32, 0.42, 0.52):
        for zs in (-1, 1):
            body.box(-0.575, y - 0.004, zs * 0.43 - 0.003 + (0.002 if zs > 0 else 0), 0.575, y + 0.004, zs * 0.43 + 0.009 * zs, TR)
    body.box(-0.61, 0.17, -0.45, 0.61, 0.27, 0.45, I, chamfer=0.01)
    body.box(-0.61, 0.56, -0.45, 0.61, 0.62, 0.45, I, chamfer=0.01)
    for sx in (-1, 1):
        body.box(sx * 0.42 - 0.045, 0.12, -0.46, sx * 0.42 + 0.045, 0.62, 0.46, I, chamfer=0.008)
        for z in (-0.38, 0.38):
            body.box(sx * 0.42 - 0.02, 0.24, z - 0.02 + (0.06 if z > 0 else -0.06), sx * 0.42 + 0.02, 0.28, z + 0.02 + (0.06 if z > 0 else -0.06), ST)
    body.box(-0.15, 0.33, 0.43, 0.15, 0.59, 0.50, I, chamfer=0.008)            # lock plate
    body.box(-0.035, 0.42, 0.495, 0.035, 0.51, 0.515, W)                         # keyhole
    body.box(-0.012, 0.36, 0.495, 0.012, 0.42, 0.515, W)
    body.box(-0.54, 0.563, -0.39, 0.54, 0.585, 0.39, GLOW)                       # light from within
    body.sphere(0.0, 1.06, 0.0, 0.09, GLOW, sides=8, rings=4)                    # orb
    lid = Model("Lid")
    prof = _profile_dome(0.45, 0.27, 0.60, 0.0)
    lid.plate([(-0.6, y, z) for z, y in [(-0.45, 0.60)] + prof[1:-1] + [(0.45, 0.60)]], (1, 0, 0), 1.2, T)
    for x in (-0.42, 0.42):
        band = [(z * 1.035, 0.60 + (y - 0.60) * 1.06) for z, y in prof]
        lid.plate([(x - 0.045, y, z) for z, y in [(-0.465, 0.60)] + band[1:-1] + [(0.465, 0.60)]], (1, 0, 0), 0.09, I)
    lid.box(-0.39, 0.83, -0.25, 0.39, 0.89, 0.25, A, chamfer=0.01)               # inlay
    lid.box(-0.08, 0.50, 0.42, 0.08, 0.72, 0.51, A, chamfer=0.01)                # hasp
    for sx in (-1, 1):
        lid.box(sx * 0.28 - 0.10, 0.58, -0.51, sx * 0.28 + 0.10, 0.70, -0.40, I, chamfer=0.006)
    return [("Body", body, None), ("Lid", lid, (0.0, 0.6, -0.44))]


def lever():
    m = Model("lever")
    m.box(-0.45, 0.0, -0.45, 0.45, 0.55, 0.45, W, chamfer=0.04)
    m.box(-0.50, 0.0, -0.50, 0.50, 0.10, 0.50, W, chamfer=0.03)
    m.box(-0.12, 0.55, -0.30, 0.12, 0.575, 0.30, DI)                              # slot
    m.box(-0.30, 0.20, 0.45, 0.30, 0.36, 0.475, A, chamfer=0.01)                  # gear plate
    for sx in (-0.24, 0.24):
        m.sphere(sx, 0.28, 0.48, 0.035, ST, sides=6, rings=3)
    m.cylinder(0.0, 0.55, 0.0, 0.07, 1.16, A, sides=8, r_top=0.055)
    m.box(-0.30, 0.99, -0.06, 0.30, 1.11, 0.06, A, chamfer=0.012)                  # crossbar
    m.sphere(0.28, 1.05, 0.0, 0.10, GLOW, sides=8, rings=4)
    m.sphere(-0.28, 1.05, 0.0, 0.05, ST, sides=6, rings=3)
    return [("Mesh", m, None)]


def bonfire():
    m = Model("bonfire")
    for i in range(9):
        a = 2 * math.pi * i / 9
        r = 0.36 + 0.03 * (i % 2)
        x, z = math.cos(a) * r, math.sin(a) * r
        m.sphere(x, 0.11, z, 0.13 + 0.025 * (i % 3), W, sides=6, rings=3, ry=0.10 + 0.02 * (i % 2))
    m.cylinder(0.0, 0.02, 0.0, 0.30, 0.06, DI, sides=10)
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.3
        m.tube((math.cos(a) * 0.30, 0.10, math.sin(a) * 0.30), (math.cos(a + 0.4) * 0.05, 0.62 + 0.03 * (i % 2), math.sin(a + 0.4) * 0.05), 0.055, 0.045, T, sides=6)
    m.tube((-0.02, 0.05, 0.0), (0.0, 0.85, 0.0), 0.028, 0.02, A, sides=6)        # the planted sword's blade
    m.box(-0.11, 0.60, -0.022, 0.11, 0.66, 0.022, A, chamfer=0.006)
    m.cylinder(0.0, 0.66, 0.0, 0.024, 0.80, A, sides=6)
    m.cone(0.0, 0.52, 0.0, 0.22, 1.12, FLAME, sides=7)
    m.sphere(0.0, 0.72, 0.0, 0.15, FLAME, sides=7, rings=3)
    m.cone(0.04, 1.02, 0.0, 0.13, 1.48, EMBER, sides=6)
    for i in range(5):
        a = 2 * math.pi * i / 5
        m.pyramid(math.cos(a) * 0.15 - 0.03, math.sin(a) * 0.15 - 0.03, math.cos(a) * 0.15 + 0.03, math.sin(a) * 0.15 + 0.03, 0.62, 0.92 + 0.05 * i, FLAME)
    return [("Mesh", m, None)]


def lectern():
    m = Model("lectern")
    m.box(-0.33, 0.0, -0.33, 0.33, 0.14, 0.33, W, chamfer=0.02)
    m.tapered_box((-0.27, -0.27, 0.27, 0.27), (-0.21, -0.21, 0.21, 0.21), 0.14, 1.04, W, chamfer=0.02)
    m.box(-0.29, 0.98, -0.29, 0.29, 1.06, 0.29, A, chamfer=0.012)
    m.box(-0.30, 0.46, -0.30, 0.30, 0.50, 0.30, A, chamfer=0.01)
    m.plate([(-0.38, y, z) for z, y in [(-0.30, 1.06), (0.30, 1.06), (0.30, 1.22), (-0.30, 1.14)]], (1, 0, 0), 0.76, A)
    m.box(-0.36, 1.06, -0.30, 0.36, 1.095, -0.26, A)
    m.plate([(-0.30, y, z) for z, y in [(-0.20, 1.10), (0.0, 1.135), (0.0, 1.17), (-0.20, 1.14)]], (1, 0, 0), 0.3, TR)
    m.plate([(0.0, y, z) for z, y in [(0.0, 1.135), (0.2, 1.11), (0.2, 1.15), (0.0, 1.17)]], (1, 0, 0), 0.3, TR)
    m.box(-0.18, 1.13, 0.22, 0.18, 1.58, 0.30, A, chamfer=0.012)                   # back board
    m.box(-0.22, 1.56, 0.20, 0.22, 1.62, 0.32, A, chamfer=0.01)
    return [("Mesh", m, None)]


def npc():
    m = Model("npc")
    m.loft(
        [dict(y=0.0, rx=0.34, rz=0.26), dict(y=0.20, rx=0.30, rz=0.22), dict(y=0.62, rx=0.24, rz=0.18), dict(y=0.92, rx=0.27, rz=0.19), dict(y=1.02, rx=0.18, rz=0.14)],
        W, sides=12, power=2.4,
    )
    m.box(-0.30, 0.52, 0.12, 0.30, 0.62, 0.22, A, chamfer=0.01)                     # belt
    m.box(-0.26, 0.56, 0.18, -0.04, 0.80, 0.30, W, chamfer=0.02)                     # folded arms
    m.box(0.04, 0.56, 0.18, 0.26, 0.80, 0.30, W, chamfer=0.02)
    m.sphere(0.0, 1.17, 0.0, 0.20, A, sides=10, rings=5, ry=0.23)                    # hood
    m.box(-0.11, 1.08, 0.11, 0.11, 1.24, 0.20, DI, chamfer=0.01)                     # shadowed face
    m.sphere(0.0, 1.62, 0.0, 0.11, ORB, sides=8, rings=4)
    return [("Mesh", m, None)]


def loot_pickup():
    m = Model("loot_pickup")
    m.loft(
        [dict(y=0.12, rx=0.15, rz=0.15), dict(y=0.24, rx=0.25, rz=0.25), dict(y=0.40, rx=0.26, rz=0.26), dict(y=0.54, rx=0.17, rz=0.17), dict(y=0.62, rx=0.08, rz=0.08)],
        TR, sides=10, power=2.2,
    )
    m.cylinder(0.0, 0.56, 0.0, 0.10, 0.62, A, sides=10)
    m.box(-0.04, 0.62, -0.04, 0.04, 0.72, 0.04, A, chamfer=0.006)
    m.pyramid(-0.085, -0.085, 0.085, 0.085, 0.82, 0.96, GLOW)
    m.pyramid(-0.085, -0.085, 0.085, 0.085, 0.82, 0.68, GLOW)
    return [("Mesh", m, None)]


def cannon():
    m = Model("cannon")
    m.box(-0.90, 0.0, -0.70, 0.90, 0.35, 0.70, W, chamfer=0.04)
    m.box(-0.78, 0.35, -0.55, 0.78, 0.42, 0.55, A, chamfer=0.02)
    for sx in (-1, 1):
        m.box(sx * 0.46 - 0.07, 0.42, -0.45, sx * 0.46 + 0.07, 0.86, 0.30, T, chamfer=0.015)   # cheeks
    m.tube((0.0, 0.72, -0.40), (0.0, 0.72, 0.95), 0.27, 0.21, A, sides=10)
    m.tube((0.0, 0.72, 0.95), (0.0, 0.72, 1.04), 0.26, 0.26, I, sides=10)
    m.sphere(0.0, 0.72, -0.42, 0.26, A, sides=10, rings=4)
    for z in (-0.1, 0.35, 0.72):
        m.tube((0.0, 0.72, z - 0.03), (0.0, 0.72, z + 0.03), 0.30 - z * 0.06, 0.30 - z * 0.06, I, sides=10)
    m.tube((-0.46, 0.66, 0.0), (0.46, 0.66, 0.0), 0.05, 0.05, I, sides=6)           # axle
    for i in range(3):
        x = -0.35 + 0.35 * i
        m.pyramid(x - 0.06, -0.31, x + 0.06, -0.19, 0.42, 0.74, CRYSTAL)
        m.pyramid(x - 0.06, -0.31, x + 0.06, -0.19, 0.42, 0.46, CRYSTAL)
    return [("Mesh", m, None)]


def falling_block():
    m = Model("falling_block")
    m.box(-0.95, -0.725, -0.95, 0.95, 0.725, 0.95, W, chamfer=0.07)
    for y in (0.68, -0.80):
        m.box(-0.975, y, -0.975, 0.975, y + 0.12, 0.975, A, chamfer=0.03)
    for zs in (-1, 1):
        m.box(-0.70, 0.24, zs * 0.96 - 0.04 + (0.02 if zs > 0 else -0.02), 0.70, 0.37, zs * 0.96 + 0.04 + (0.02 if zs > 0 else -0.02), A, chamfer=0.01)
        m.box(-0.70, -0.37, zs * 0.96 - 0.04 + (0.02 if zs > 0 else -0.02), 0.70, -0.24, zs * 0.96 + 0.04 + (0.02 if zs > 0 else -0.02), A, chamfer=0.01)
        m.box(-0.065, -0.275, zs * 0.96 - 0.04 + (0.03 if zs > 0 else -0.03), 0.065, 0.275, zs * 0.96 + 0.04 + (0.03 if zs > 0 else -0.03), A, chamfer=0.01)
        for sx in (-0.45, 0.45):
            m.pyramid(sx - 0.10, zs * 0.95 - 0.02, sx + 0.10, zs * 0.95 + 0.02, -0.12, 0.12, DI, apex=(sx, zs * 0.95 + zs * 0.07))
    for sx in (-1, 1):
        m.box(sx * 0.96 - 0.03, -0.5, -0.5, sx * 0.96 + 0.03, 0.5, 0.5, DI, chamfer=0.008)
    return [("Mesh", m, None)]


def crystal_pillar():
    m = Model("crystal_pillar")
    m.loft(
        [dict(y=0.0, rx=0.22, rz=0.22), dict(y=0.35, rx=0.21, rz=0.21), dict(y=0.95, rx=0.17, rz=0.17), dict(y=1.22, rx=0.15, rz=0.15)],
        CRYSTAL, sides=6, power=2.0, top_mat=CRYSTAL,
    )
    m.cone(0.0, 1.22, 0.0, 0.15, 1.72, CRYSTAL, sides=6)
    for i, (a, h, r) in enumerate([(0.3, 0.62, 0.09), (1.5, 0.52, 0.08), (2.7, 0.70, 0.085), (4.1, 0.48, 0.07), (5.3, 0.58, 0.08)]):
        bx, bz = math.cos(a) * 0.20, math.sin(a) * 0.20
        tip = (math.cos(a) * 0.36, h, math.sin(a) * 0.36)
        m.tube((bx, 0.0, bz), (tip[0] * 0.92, h * 0.78, tip[2] * 0.92), r, r * 0.8, CRYSTAL, sides=5)
        m.tube((tip[0] * 0.92, h * 0.78, tip[2] * 0.92), tip, r * 0.8, 0.008, CRYSTAL, sides=5)
    return [("Mesh", m, None)]


def spikes():
    base = Model("Base")
    base.box(-1.4, -0.02, -1.4, 1.4, 0.10, 1.4, W, chamfer=0.03)
    for e in (-1, 1):
        base.box(-1.4, 0.10, e * 1.25 - 0.03, 1.4, 0.14, e * 1.25 + 0.03, WARN)
        base.box(e * 1.25 - 0.03, 0.10, -1.4, e * 1.25 + 0.03, 0.14, 1.4, WARN)
    for x in range(4):
        for z in range(4):
            px, pz = -0.9 + x * 0.6, -0.9 + z * 0.6
            base.cylinder(px, 0.10, pz, 0.19, 0.145, I, sides=8, r_top=0.17)
    sp = Model("Spikes")
    for x in range(4):
        for z in range(4):
            px, pz = -0.9 + x * 0.6, -0.9 + z * 0.6
            sp.cylinder(px, 0.10, pz, 0.135, 0.52, ST, sides=6, r_top=0.11)
            sp.cone(px, 0.52, pz, 0.11, 0.78, ST, sides=6)
    return [("Base", base, None), ("Spikes", sp, None)]


def locked_door():
    m = Model("locked_door")
    hw = DOOR_W / 2
    jx = hw + 0.15
    for sx in (-1, 1):
        m.box(sx * jx - 0.15, 0.0, -0.15, sx * jx + 0.15, DOOR_H, 0.15, W, chamfer=0.02)
        m.box(sx * jx - 0.19, 0.0, -0.19, sx * jx + 0.19, 0.30, 0.19, W, chamfer=0.02)
        m.box(sx * jx - 0.19, DOOR_H - 0.30, -0.19, sx * jx + 0.19, DOOR_H, 0.19, A, chamfer=0.02)
    m.box(-jx - 0.22, DOOR_H, -0.17, jx + 0.22, DOOR_H + 0.3, 0.17, W, chamfer=0.03)
    m.box(-jx, DOOR_H + 0.3, -0.12, jx, DOOR_H + 0.36, 0.12, A, chamfer=0.01)
    for side in (-1, 1):
        lx = side * DOOR_W * 0.25
        half = hw - 0.035
        m.box(lx - half / 2, 0.04, -0.11, lx + half / 2, DOOR_H - 0.04, 0.11, T, chamfer=0.012)
        for k in range(1, 5):
            gx = lx - half / 2 + half * k / 5
            for face in (-1, 1):
                m.box(gx - 0.006, 0.08, face * 0.11 - 0.003 + (0.003 if face > 0 else 0), gx + 0.006, DOOR_H - 0.08, face * 0.11 + 0.008 * face, TR)
        for face in (-1, 1):
            zc = face * 0.13
            for by in (0.55, DOOR_H - 0.55):
                m.box(lx - (hw - 0.12) / 2, by - 0.055, zc - 0.0175, lx + (hw - 0.12) / 2, by + 0.055, zc + 0.0175, I, chamfer=0.006)
            sx = lx + side * hw * 0.4
            m.box(sx - 0.05, 0.12, zc - 0.02, sx + 0.05, DOOR_H - 0.13, zc + 0.02, I, chamfer=0.006)
            for by in (0.55, DOOR_H - 0.55):
                m.sphere(lx - side * hw * 0.35, by, zc + face * 0.02, 0.03, ST, sides=6, rings=3)
    for face in (-1, 1):
        cy = DOOR_H * 0.65
        z = face * 0.16
        m.box(-0.36, cy - 0.39, z - 0.0275, 0.36, cy + 0.39, z + 0.0275, I, chamfer=0.008)
        m.box(-0.28, cy - 0.31, face * 0.2 - 0.03, 0.28, cy + 0.31, face * 0.2 + 0.03, TINT, chamfer=0.006)
        m.box(-0.045, cy - 0.15, face * 0.24 - 0.0325, 0.045, cy + 0.15, face * 0.24 + 0.0325, I)
        m.box(-0.10, cy - 0.06, face * 0.24 - 0.0325, 0.10, cy + 0.03, face * 0.24 + 0.0325, I)
    return [("Mesh", m, None)]


def boss_door_frame():
    m = Model("boss_door_frame")
    for sx in (-1, 1):
        x = sx * 2.6
        m.box(x - 0.45, 0.0, -0.45, x + 0.45, 0.45, 0.45, W, chamfer=0.04)
        m.loft(
            [dict(y=0.45, cx=x, cz=0, rx=0.26, rz=0.26), dict(y=1.6, cx=x, cz=0, rx=0.22, rz=0.22), dict(y=3.5, cx=x, cz=0, rx=0.22, rz=0.22), dict(y=3.85, cx=x, cz=0, rx=0.27, rz=0.27)],
            W, sides=8, power=2.4, cap_bottom=False, cap_top=False,
        )
        m.box(x - 0.34, 3.85, -0.34, x + 0.34, 4.2, 0.34, A, chamfer=0.03)
        for y in (1.2, 2.4, 3.3):
            m.box(x - 0.27, y, -0.27, x + 0.27, y + 0.09, 0.27, A, chamfer=0.01)
        # Torch holder
        m.box(x - 0.05, 2.35, 0.20, x + 0.05, 2.45, 0.50, I, chamfer=0.008)
        m.cylinder(x, 2.40, 0.42, 0.11, 2.52, I, sides=8, r_top=0.14)
        m.cone(x, 2.52, 0.42, 0.11, 2.80, FLAME, sides=6)
    m.box(-3.1, 4.2, -0.30, 3.1, 4.56, 0.30, W, chamfer=0.04)
    m.box(-2.85, 4.56, -0.22, 2.85, 4.66, 0.22, A, chamfer=0.02)
    m.pyramid(-0.45, -0.18, 0.45, 0.18, 4.66, 5.05, A)
    m.box(-2.4, 2.1 - 0.075, -0.175, 2.4, 2.1 + 0.075, -0.025, A, chamfer=0.01)
    return [("Mesh", m, None)]


def sigil():
    m = Model("sigil")
    m.plate([(0.0, 0.26, 0.05), (-0.26, 0.0, 0.05), (0.0, -0.26, 0.05), (0.26, 0.0, 0.05)], (0, 0, -1), 0.10, "sigil")
    m.plate([(0.0, 0.14, 0.055), (-0.14, 0.0, 0.055), (0.0, -0.14, 0.055), (0.14, 0.0, 0.055)], (0, 0, -1), 0.012, DI)
    return [("Mesh", m, None)]


def key_icon():
    m = Model("key_icon")
    m.box(-0.15, -0.15, -0.05, 0.15, 0.15, 0.05, TINT, chamfer=0.012)
    m.box(-0.022, -0.09, 0.05, 0.022, 0.02, 0.058, DI)
    m.box(-0.06, 0.0, 0.05, 0.06, 0.05, 0.058, DI)
    return [("Mesh", m, None)]


def doorway_frame():
    m = Model("DoorwayFrame")
    hw = DOOR_W / 2
    jx = hw + 0.2
    for sx in (-1, 1):
        m.box(sx * jx - 0.2, 0.0, -0.2, sx * jx + 0.2, DOOR_H, 0.2, W, chamfer=0.025)
        m.box(sx * jx - 0.26, 0.0, -0.26, sx * jx + 0.26, 0.36, 0.26, W, chamfer=0.025)
        m.box(sx * jx - 0.24, DOOR_H - 0.22, -0.24, sx * jx + 0.24, DOOR_H, 0.24, A, chamfer=0.02)
    m.box(-jx - 0.26, DOOR_H, -0.22, jx + 0.26, DOOR_H + 0.4, 0.22, W, chamfer=0.03)
    m.box(-0.28, DOOR_H + 0.05, -0.27, 0.28, DOOR_H + 0.45, 0.27, A, chamfer=0.03)
    for sx in (-1, 1):
        m.pyramid(sx * 0.55 - 0.12, -0.18, sx * 0.55 + 0.12, 0.18, DOOR_H + 0.4, DOOR_H + 0.52, A)
    th = Model("Threshold")
    th.box(-hw, 0.0, -0.25, hw, 0.06, 0.25, "floor", chamfer=0.008)
    return [("Mesh", m, None), ("Threshold", th, None)]


BUILDERS = {
    "chest": chest, "lever": lever, "bonfire": bonfire, "lectern": lectern, "npc": npc,
    "loot_pickup": loot_pickup, "cannon": cannon, "falling_block": falling_block,
    "crystal_pillar": crystal_pillar, "spikes": spikes, "locked_door": locked_door,
    "boss_door_frame": boss_door_frame, "sigil": sigil, "key_icon": key_icon, "doorway_frame": doorway_frame,
}
