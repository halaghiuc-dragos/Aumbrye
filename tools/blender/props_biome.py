"""The biome prop kit: pillars, statues, altars, banners, debris, rubble and sconces, in six styles.

The ten biomes share six styles (castle, crystal, swamp, frozen, vault, cathedral); the biome's own
palette colours each model at load, so a mire pillar and a swamp pillar share a model and differ in
colour. Sizes follow the footprints the dressing and layout code already assume.
"""

from __future__ import annotations

import math
import random

from bl_lib import Model

W, A, T, TR, I, DI, ST = "wall", "accent", "timber", "trim", "iron", "darkiron", "steel"
GLOW, CRYSTAL, FLAME, EMBER = "glow", "crystal", "flame", "ember"
STYLES = ["castle", "crystal", "swamp", "frozen", "vault", "cathedral"]


def _rng(style, kind):
    return random.Random(f"{style}/{kind}")


def _shards(m, rng, cx, cz, n, rmin, rmax, hmin, hmax, mat, y0=0.0, spread=0.0):
    """A cluster of leaning crystal/ice shards."""
    for i in range(n):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, spread)
        bx, bz = cx + math.cos(a) * d, cz + math.sin(a) * d
        h = rng.uniform(hmin, hmax)
        r = rng.uniform(rmin, rmax)
        lean = rng.uniform(0.05, 0.22)
        la = rng.uniform(0, math.tau)
        top = (bx + math.cos(la) * lean * h, y0 + h, bz + math.sin(la) * lean * h)
        mid = (bx + math.cos(la) * lean * h * 0.7, y0 + h * 0.72, bz + math.sin(la) * lean * h * 0.7)
        m.tube((bx, y0, bz), mid, r, r * 0.85, mat, sides=5)
        m.tube(mid, top, r * 0.85, r * 0.04, mat, sides=5)


def _chunk(m, rng, cx, cz, size, mat, y0=0.0, tilt=True):
    """A rough rock: a squashed low-poly sphere or a chamfered block."""
    sx, sy, sz = size
    if rng.random() < 0.5:
        m.sphere(cx, y0 + sy / 2, cz, sx / 2, mat, sides=6, rings=3, ry=sy / 2, rz=sz / 2)
    else:
        m.box(cx - sx / 2, y0, cz - sz / 2, cx + sx / 2, y0 + sy, cz + sz / 2, mat, chamfer=min(sx, sy, sz) * 0.16)


# --------------------------------------------------------------------------------------- pillar

def pillar(style):
    m = Model("pillar")
    rng = _rng(style, "pillar")
    m.box(-0.56, 0.0, -0.56, 0.56, 0.22, 0.56, W, chamfer=0.04)
    if style == "vault":
        m.loft([dict(y=0.22, rx=0.40, rz=0.40), dict(y=2.78, rx=0.40, rz=0.40)], I, sides=8, power=2.0, cap_bottom=False, cap_top=False)
        for y in (0.38, 1.5, 2.6):
            m.box(-0.50, y - 0.065, -0.50, 0.50, y + 0.065, 0.50, ST, chamfer=0.02)
        for s in (-1, 1):
            m.box(s * 0.47 - 0.08, 0.3, -0.08, s * 0.47 + 0.08, 2.7, 0.08, DI, chamfer=0.01)
            m.box(-0.08, 0.3, s * 0.47 - 0.08, 0.08, 2.7, s * 0.47 + 0.08, DI, chamfer=0.01)
        for y in (0.7, 1.1, 1.9, 2.3):
            for k in range(8):
                a = math.tau * k / 8
                m.sphere(math.cos(a) * 0.41, y, math.sin(a) * 0.41, 0.028, ST, sides=5, rings=2)
        m.box(-0.45, 2.78, -0.45, 0.45, 3.0, 0.45, I, chamfer=0.03)
        m.cylinder(0.0, 3.0, 0.0, 0.16, 3.1, GLOW, sides=8)
        return m
    if style == "cathedral":
        rings = [dict(y=0.22, rx=0.36, rz=0.36), dict(y=0.6, rx=0.30, rz=0.30), dict(y=2.5, rx=0.27, rz=0.27), dict(y=2.78, rx=0.34, rz=0.34)]
        m.loft(rings, W, sides=12, power=2.0, cap_bottom=False, cap_top=False, mat_fn=lambda i, k, n: A if k % 3 == 0 else W)
        for k in range(8):
            a = math.tau * k / 8
            m.tube((math.cos(a) * 0.32, 0.3, math.sin(a) * 0.32), (math.cos(a) * 0.27, 2.55, math.sin(a) * 0.27), 0.035, 0.03, W, sides=5)
        m.box(-0.48, 2.76, -0.48, 0.48, 2.98, 0.48, A, chamfer=0.03)
        for s in (-1, 1):
            m.cone(s * 0.40, 2.98, 0.0, 0.085, 3.55, A, sides=5)
        m.cone(0.0, 2.98, 0.0, 0.10, 3.45, GLOW, sides=5)
        return m
    if style == "crystal":
        m.loft([dict(y=0.22, rx=0.40, rz=0.40), dict(y=1.5, rx=0.36, rz=0.36), dict(y=2.78, rx=0.40, rz=0.40)], A, sides=10, power=2.6, cap_bottom=False, cap_top=False)
        m.box(-0.5, 2.78, -0.5, 0.5, 3.0, 0.5, W, chamfer=0.03)
        _shards(m, rng, 0, 0, 5, 0.06, 0.11, 0.55, 0.95, CRYSTAL, y0=0.05, spread=0.56)
        _shards(m, rng, 0, 0, 5, 0.07, 0.12, 0.5, 0.75, CRYSTAL, y0=2.98, spread=0.35)
        return m
    if style == "swamp":
        m.loft([dict(y=0.22, rx=0.44, rz=0.44), dict(y=0.9, rx=0.38, rz=0.38), dict(y=2.0, rx=0.35, rz=0.35), dict(y=2.78, rx=0.42, rz=0.42)], W, sides=9, power=2.3, cap_bottom=False, cap_top=False, mat_fn=lambda i, k, n: A if (i + k) % 4 == 0 else W)
        m.box(-0.5, 2.78, -0.5, 0.5, 3.0, 0.5, W, chamfer=0.05)
        for k in range(6):
            a = math.tau * k / 6 + 0.3
            m.tube((math.cos(a) * 0.62, 0.0, math.sin(a) * 0.62), (math.cos(a) * 0.36, 0.7, math.sin(a) * 0.36), 0.07, 0.04, A, sides=5)
            top = 1.6 + 0.3 * (k % 3)
            m.tube((math.cos(a) * 0.36, 0.7, math.sin(a) * 0.36), (math.cos(a) * 0.38, top, math.sin(a) * 0.38), 0.035, 0.02, A, sides=4)
        for k in range(5):
            a = math.tau * k / 5
            m.tube((math.cos(a) * 0.43, 2.95, math.sin(a) * 0.43), (math.cos(a) * 0.46, 2.15 - 0.15 * (k % 3), math.sin(a) * 0.46), 0.02, 0.012, A, sides=4)
        return m
    if style == "frozen":
        m.loft([dict(y=0.22, rx=0.42, rz=0.42), dict(y=1.5, rx=0.37, rz=0.37), dict(y=2.78, rx=0.41, rz=0.41)], W, sides=8, power=2.4, cap_bottom=False, cap_top=False)
        m.box(-0.50, 2.78, -0.50, 0.50, 3.0, 0.50, A, chamfer=0.04)
        for k in range(10):
            a = math.tau * k / 10
            ln = 0.25 + 0.2 * ((k * 7) % 3)
            m.tube((math.cos(a) * 0.44, 2.78, math.sin(a) * 0.44), (math.cos(a) * 0.45, 2.78 - ln, math.sin(a) * 0.45), 0.035, 0.004, CRYSTAL, sides=4)
        _shards(m, rng, 0, 0, 4, 0.06, 0.1, 0.4, 0.8, CRYSTAL, y0=0.05, spread=0.55)
        return m
    # castle
    m.loft([dict(y=0.22, rx=0.44, rz=0.44), dict(y=1.5, rx=0.40, rz=0.40), dict(y=2.78, rx=0.44, rz=0.44)], W, sides=12, power=2.2, cap_bottom=False, cap_top=False, mat_fn=lambda i, k, n: A if k % 6 == 0 else W)
    for y in (0.45, 1.55, 2.65):
        m.box(-0.47, y, -0.47, 0.47, y + 0.14, 0.47, A, chamfer=0.02)
    m.box(-0.52, 2.78, -0.52, 0.52, 3.0, 0.52, W, chamfer=0.04)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box(sx * 0.40 - 0.08, 3.0, sz * 0.40 - 0.08, sx * 0.40 + 0.08, 3.16, sz * 0.40 + 0.08, W, chamfer=0.015)
    m.box(-0.06, 1.65, 0.41, 0.06, 2.05, 0.47, A, chamfer=0.01)
    return m


# ---------------------------------------------------------------------------------------- statue

def statue(style):
    m = Model("statue")
    rng = _rng(style, "statue")
    m.box(-0.5, 0.0, -0.5, 0.5, 0.28, 0.5, W, chamfer=0.04)
    m.box(-0.42, 0.28, -0.42, 0.42, 0.44, 0.42, A, chamfer=0.02)
    if style == "castle":
        for s in (-1, 1):
            m.box(s * 0.12 - 0.09, 0.44, -0.10, s * 0.12 + 0.09, 1.2, 0.10, W, chamfer=0.02)
        m.box(-0.30, 1.2, -0.15, 0.30, 1.9, 0.15, W, chamfer=0.04)
        m.box(-0.34, 1.72, -0.18, 0.34, 1.92, 0.18, A, chamfer=0.03)
        for s in (-1, 1):
            m.box(s * 0.38 - 0.07, 1.25, -0.08, s * 0.38 + 0.07, 1.85, 0.08, W, chamfer=0.02)
        m.sphere(0.0, 2.08, 0.0, 0.17, W, sides=8, rings=4, ry=0.2)
        m.box(-0.18, 1.98, 0.10, 0.18, 2.06, 0.20, DI)
        m.cone(0.0, 2.25, 0.0, 0.05, 2.5, A, sides=5)
        m.plate([(0.0, y, z) for z, y in [(0.22, 1.8), (0.42, 1.65), (0.42, 1.05), (0.22, 0.85)]], (1, 0, 0), 0.12, A)
        m.tube((0.40, 1.2, 0.0), (0.40, 0.46, 0.0), 0.035, 0.03, ST, sides=4)
        return m
    if style == "crystal":
        for s in (-1, 1):
            m.tube((s * 0.12, 0.44, 0.0), (s * 0.16, 1.25, 0.0), 0.09, 0.07, CRYSTAL, sides=5)
        m.loft([dict(y=1.2, rx=0.22, rz=0.14), dict(y=1.55, rx=0.30, rz=0.16), dict(y=1.95, rx=0.26, rz=0.13)], CRYSTAL, sides=6, power=2.0)
        m.sphere(0.0, 2.15, 0.0, 0.15, CRYSTAL, sides=6, rings=3, ry=0.2)
        _shards(m, rng, 0, 0, 6, 0.05, 0.08, 0.4, 0.8, CRYSTAL, y0=0.44, spread=0.35)
        return m
    if style == "swamp":
        m.loft([dict(y=0.44, rx=0.30, rz=0.28), dict(y=0.9, rx=0.20, rz=0.2), dict(y=1.4, rx=0.27, rz=0.22), dict(y=1.9, rx=0.16, rz=0.16)], W, sides=8, power=2.2, mat_fn=lambda i, k, n: A if (i + k) % 3 == 0 else W)
        m.sphere(0.0, 2.1, 0.0, 0.2, W, sides=8, rings=4, ry=0.22)
        for s in (-1, 1):
            m.box(s * 0.09 - 0.045, 2.08, 0.15, s * 0.09 + 0.045, 2.16, 0.22, GLOW)
        for k in range(6):
            a = math.tau * k / 6
            m.tube((math.cos(a) * 0.4, 0.3, math.sin(a) * 0.4), (math.cos(a) * 0.2, 1.3 + 0.12 * k, math.sin(a) * 0.2), 0.05, 0.03, A, sides=5)
        return m
    if style == "frozen":
        m.box(-0.42, 0.44, -0.42, 0.42, 2.6, 0.42, CRYSTAL, chamfer=0.06)
        for s in (-1, 1):
            m.box(s * 0.12 - 0.09, 0.46, -0.10, s * 0.12 + 0.09, 1.2, 0.10, W, chamfer=0.02)
        m.box(-0.26, 1.2, -0.13, 0.26, 1.85, 0.13, W, chamfer=0.03)
        m.sphere(0.0, 2.0, 0.0, 0.15, W, sides=8, rings=4)
        m.box(-0.06, 1.3, 0.14, 0.06, 1.75, 0.22, A)
        _shards(m, rng, 0, 0, 5, 0.05, 0.09, 0.3, 0.6, CRYSTAL, y0=2.6, spread=0.3)
        return m
    if style == "vault":
        for s in (-1, 1):
            m.box(s * 0.16 - 0.10, 0.44, -0.12, s * 0.16 + 0.10, 1.25, 0.12, I, chamfer=0.02)
            m.box(s * 0.16 - 0.12, 0.44, -0.16, s * 0.16 + 0.12, 0.6, 0.22, DI, chamfer=0.02)
        m.box(-0.36, 1.25, -0.22, 0.36, 2.0, 0.22, I, chamfer=0.04)
        m.box(-0.22, 1.5, 0.21, 0.22, 1.75, 0.27, GLOW)
        for s in (-1, 1):
            m.box(s * 0.50 - 0.08, 1.3, -0.10, s * 0.50 + 0.08, 1.95, 0.10, ST, chamfer=0.015)
        m.box(-0.22, 2.0, -0.2, 0.22, 2.4, 0.2, I, chamfer=0.03)
        m.box(-0.14, 2.14, 0.19, 0.14, 2.24, 0.24, GLOW)
        m.tube((0.0, 2.4, 0.0), (0.0, 2.75, 0.0), 0.02, 0.02, ST, sides=4)
        m.sphere(0.0, 2.78, 0.0, 0.05, GLOW, sides=6, rings=3)
        return m
    # cathedral: a praying figure with folded wings
    m.loft([dict(y=0.44, rx=0.32, rz=0.26), dict(y=0.9, rx=0.26, rz=0.2), dict(y=1.7, rx=0.30, rz=0.18), dict(y=1.9, rx=0.16, rz=0.14)], W, sides=10, power=2.3, mat_fn=lambda i, k, n: A if k % 5 == 0 else W)
    m.sphere(0.0, 2.05, 0.02, 0.15, W, sides=8, rings=4, ry=0.18)
    m.box(-0.12, 1.55, 0.16, 0.12, 1.8, 0.26, W, chamfer=0.03)
    for s in (-1, 1):
        m.plate([(s * 0.25, y, z) for z, y in [(-0.18, 1.85), (-0.30, 2.6), (-0.42, 2.2), (-0.40, 1.3), (-0.25, 0.9)]], (s, 0, 0), 0.05, W)
    m.cylinder(0.0, 2.24, 0.0, 0.17, 2.255, GLOW, sides=12)
    return m


# ----------------------------------------------------------------------------------------- altar

def altar(style):
    m = Model("altar")
    rng = _rng(style, "altar")
    m.box(-0.70, 0.0, -0.70, 0.70, 0.16, 0.70, W, chamfer=0.04)
    if style == "vault":
        m.box(-0.62, 0.16, -0.50, 0.62, 0.86, 0.50, I, chamfer=0.04)
        m.box(-0.52, 0.86, -0.42, 0.52, 1.0, 0.42, DI, chamfer=0.03)
        m.box(-0.40, 1.0, -0.06, 0.40, 1.30, 0.22, I, chamfer=0.02)
        m.box(-0.32, 1.06, 0.20, 0.32, 1.24, 0.25, GLOW)
        for s in (-1, 1):
            m.tube((s * 0.66, 0.3, -0.3), (s * 0.66, 0.9, 0.3), 0.06, 0.06, ST, sides=6)
        m.sphere(0.0, 1.08, -0.2, 0.12, GLOW, sides=8, rings=4)
        return m
    if style == "cathedral":
        m.box(-0.60, 0.16, -0.46, 0.60, 0.92, 0.46, W, chamfer=0.03)
        m.box(-0.66, 0.92, -0.52, 0.66, 1.0, 0.52, A, chamfer=0.02)
        m.plate([(-0.56, y, z) for z, y in [(-0.46, 1.0), (0.46, 1.0), (0.54, 0.72), (-0.54, 0.72)]], (1, 0, 0), 1.12, A)
        for s in (-1, 1):
            m.cylinder(s * 0.45, 1.0, -0.28, 0.035, 1.3, W, sides=6)
            m.cone(s * 0.45, 1.3, -0.28, 0.03, 1.4, FLAME, sides=5)
        m.box(-0.05, 1.0, -0.42, 0.05, 1.72, -0.36, A)
        m.box(-0.22, 1.42, -0.42, 0.22, 1.5, -0.36, A)
        return m
    if style == "crystal":
        m.box(-0.58, 0.16, -0.58, 0.58, 0.86, 0.58, W, chamfer=0.05)
        m.box(-0.66, 0.86, -0.66, 0.66, 1.0, 0.66, A, chamfer=0.03)
        _shards(m, rng, 0, 0, 7, 0.06, 0.11, 0.35, 0.75, CRYSTAL, y0=1.0, spread=0.35)
        return m
    if style == "swamp":
        m.box(-0.60, 0.16, -0.5, 0.60, 0.9, 0.5, W, chamfer=0.07)
        m.box(-0.66, 0.9, -0.56, 0.66, 1.0, 0.56, A, chamfer=0.05)
        for k in range(8):
            a = math.tau * k / 8
            m.tube((math.cos(a) * 0.9, 0.0, math.sin(a) * 0.72), (math.cos(a) * 0.45, 1.0, math.sin(a) * 0.36), 0.06, 0.03, A, sides=5)
        m.sphere(0.0, 1.1, 0.0, 0.15, GLOW, sides=8, rings=4)
        return m
    if style == "frozen":
        m.box(-0.62, 0.16, -0.50, 0.62, 0.9, 0.50, CRYSTAL, chamfer=0.08)
        m.box(-0.68, 0.9, -0.56, 0.68, 1.0, 0.56, W, chamfer=0.04)
        _shards(m, rng, 0, 0, 5, 0.05, 0.1, 0.25, 0.55, CRYSTAL, y0=1.0, spread=0.4)
        return m
    m.box(-0.62, 0.16, -0.50, 0.62, 0.9, 0.50, W, chamfer=0.04)
    m.box(-0.70, 0.9, -0.58, 0.70, 1.0, 0.58, A, chamfer=0.03)
    m.cylinder(0.0, 1.0, 0.0, 0.28, 1.12, A, sides=10, r_top=0.32)
    m.cone(0.0, 1.12, 0.0, 0.16, 1.4, FLAME, sides=6)
    return m


# ---------------------------------------------------------------------------------------- banner

def banner(style):
    m = Model("banner")
    m.box(-0.36, 0.0, -0.10, 0.36, 0.10, 0.10, W, chamfer=0.02)
    m.tube((-0.30, 0.1, 0.0), (-0.30, 2.25, 0.0), 0.04, 0.035, TR if style != "crystal" else A, sides=6)
    m.tube((0.30, 0.1, 0.0), (0.30, 2.25, 0.0), 0.04, 0.035, TR if style != "crystal" else A, sides=6)
    m.box(-0.36, 2.2, -0.05, 0.36, 2.3, 0.05, TR, chamfer=0.015)
    cloth = [(-0.28, 2.2), (0.28, 2.2), (0.28, 0.75), (0.14, 0.92), (0.0, 0.62), (-0.14, 0.92), (-0.28, 0.75)]
    m.plate([(x, y, 0.0) for x, y in cloth], (0, 0, 1), 0.02, A)
    m.plate([(x * 0.55, y * 0.62 + 0.85, -0.001) for x, y in [(-0.28, 1.7), (0.28, 1.7), (0.28, 0.5), (0.0, 0.25), (-0.28, 0.5)]], (0, 0, 1), 0.03, W) if style != "vault" else None
    m.sphere(-0.30, 2.3, 0.0, 0.05, ST, sides=6, rings=3)
    m.sphere(0.30, 2.3, 0.0, 0.05, ST, sides=6, rings=3)
    return m


# ------------------------------------------------------------------------------------- debris

def debris_pile(style):
    m = Model("debris_pile")
    rng = _rng(style, "debris")
    for _ in range(9):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, 0.6)
        s = rng.uniform(0.22, 0.45)
        _chunk(m, rng, math.cos(a) * d, math.sin(a) * d, (s, s * rng.uniform(0.3, 0.6), s * rng.uniform(0.7, 1.1)), W if rng.random() < 0.7 else A)
    if style in ("castle", "cathedral", "swamp"):
        for _ in range(4):
            a = rng.uniform(0, math.tau)
            d = rng.uniform(0.2, 0.6)
            m.tube((math.cos(a) * d, 0.08, math.sin(a) * d), (math.cos(a + 1) * d * 0.5, 0.2, math.sin(a + 1) * d * 0.5), 0.03, 0.03, T, sides=5)
    if style in ("crystal", "frozen"):
        _shards(m, rng, 0, 0, 5, 0.03, 0.06, 0.15, 0.35, CRYSTAL, spread=0.6)
    if style == "vault":
        for _ in range(4):
            a = rng.uniform(0, math.tau)
            d = rng.uniform(0.1, 0.6)
            m.sphere(math.cos(a) * d, 0.06, math.sin(a) * d, 0.06, ST, sides=6, rings=3)
    return m


def rubble_a(style):
    m = Model("rubble_a")
    rng = _rng(style, "rubble_a")
    m.box(-0.55, 0.0, -0.5, 0.55, 0.5, 0.5, W, chamfer=0.08)
    m.box(-0.50, 0.44, -0.45, 0.50, 0.50, 0.45, A, chamfer=0.04)
    m.box(0.12, 0.0, 0.04, 0.58, 0.4, 0.5, A, chamfer=0.06)
    _chunk(m, rng, -0.3, 0.42, (0.3, 0.2, 0.28), W)
    if style in ("crystal", "frozen"):
        _shards(m, rng, 0.0, 0.0, 4, 0.05, 0.09, 0.3, 0.6, CRYSTAL, y0=0.46, spread=0.35)
    if style == "swamp":
        for k in range(4):
            m.tube((-0.4 + 0.25 * k, 0.45, 0.0), (-0.4 + 0.25 * k + 0.03, 0.9 + 0.1 * (k % 2), 0.02), 0.022, 0.012, A, sides=4)
    if style == "vault":
        m.box(-0.40, 0.46, -0.05, 0.20, 0.54, 0.05, I, chamfer=0.01)
    return m


def rubble_b(style):
    m = Model("rubble_b")
    rng = _rng(style, "rubble_b")
    m.box(-0.4, 0.0, -0.65, 0.4, 0.44, 0.65, W, chamfer=0.07)
    m.box(-0.35, 0.40, -0.6, 0.35, 0.46, 0.6, A, chamfer=0.03)
    m.pyramid(-0.5, 0.05, -0.1, 0.42, 0.0, 0.3, A)
    _chunk(m, rng, 0.25, -0.4, (0.25, 0.22, 0.3), W)
    if style in ("crystal", "frozen"):
        _shards(m, rng, 0.0, 0.0, 3, 0.05, 0.08, 0.25, 0.5, CRYSTAL, y0=0.46, spread=0.3)
    return m


# ------------------------------------------------------------------------------------- sconce

def sconce(style):
    """A wall lamp that reads from every side: a cup on a bracket with a flame above it."""
    m = Model("sconce")
    if style == "crystal":
        m.box(-0.10, -0.08, -0.14, 0.10, 0.08, 0.14, W, chamfer=0.02)
        _shards(m, _rng(style, "sconce"), 0, 0.02, 3, 0.03, 0.05, 0.14, 0.26, CRYSTAL, y0=0.05, spread=0.06)
        m.pyramid(-0.07, -0.07, 0.07, 0.07, 0.12, 0.40, GLOW)
        return m
    m.box(-0.11, -0.08, -0.14, 0.11, 0.08, 0.14, I if style == "vault" else W, chamfer=0.02)
    m.cylinder(0.0, 0.08, 0.05, 0.10, 0.20, A if style != "vault" else ST, sides=8, r_top=0.14)
    m.cylinder(0.0, 0.20, 0.05, 0.12, 0.225, DI, sides=8)
    flame = GLOW if style == "frozen" else FLAME
    m.cone(0.0, 0.225, 0.05, 0.11, 0.52, flame, sides=6)
    m.cone(0.0, 0.27, 0.05, 0.06, 0.42, EMBER, sides=5)
    return m


BUILDERS = {}
for _style in STYLES:
    for _kind, _fn in (("pillar", pillar), ("statue", statue), ("altar", altar), ("banner", banner),
                       ("debris_pile", debris_pile), ("rubble_a", rubble_a), ("rubble_b", rubble_b), ("sconce", sconce)):
        BUILDERS[f"biome/{_style}_{_kind}"] = (lambda fn=_fn, st=_style: [("Mesh", fn(st), None)])
