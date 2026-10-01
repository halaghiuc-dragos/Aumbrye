"""Blender builders for the remaining one-off structure and effect pieces: stair ramps, the boss dais,
the secret-cue plaque, obstacle blocks, debris, ambient motes, fountain droplets and the waves
objective marker.

Structure pieces use the biome roles (`wall`, `floor`, `accent`); effect pieces are bare meshes whose
role name is `mesh`, because the game skins them with its own glowing or translucent materials.
"""

from __future__ import annotations

import math
import random

from bl_lib import Model
from props_masonry import STYLES, _face_out

W, F, A, M = "wall", "floor", "accent", "mesh"


# -- structure ------------------------------------------------------------------------------
def ramp():
    """A 4 x 12 m stair ramp, 0.4 thick, centred on the origin, long axis z, with non-slip cleats and curbs."""
    m = Model("ramp")
    m.box(-2.0, -0.2, -6.0, 2.0, 0.2, 6.0, F, chamfer=0.04)
    for k in range(16):
        z = -5.6 + k * 0.75
        m.box(-1.75, 0.2, z, 1.75, 0.27, z + 0.16, W, chamfer=0.02)
    for s in (-1, 1):
        m.box(s * 1.85 - 0.15, 0.2, -6.0, s * 1.85 + 0.15, 0.55, 6.0, W, chamfer=0.03)
        for k in range(6):
            z = -5.0 + k * 2.0
            m.box(s * 1.85 - 0.19, 0.2, z - 0.1, s * 1.85 + 0.19, 0.62, z + 0.1, F, chamfer=0.02)
    return [("Mesh", m, None)]


def _ngon(r, n, phase=0.0):
    return [(math.sin(phase + math.tau * i / n) * r, math.cos(phase + math.tau * i / n) * r) for i in range(n)]


def dais():
    """The boss dais: two octagonal tiers on a 10 m footprint, origin at the floor, top at 0.6 m."""
    m = Model("dais")
    for r, y0, y1, mat in ((5.2, 0.0, 0.3, F), (4.3, 0.3, 0.6, W)):
        pts = _ngon(r, 8, math.pi / 8)
        lo = [(x, y0, z) for x, z in pts]
        hi = [(x, y1, z) for x, z in pts]
        for k in range(8):
            k2 = (k + 1) % 8
            ex, ez = (pts[k][0] + pts[k2][0]) / 2, (pts[k][1] + pts[k2][1]) / 2
            _face_out(m, [lo[k], lo[k2], hi[k2], hi[k]], (ex, 0, ez), mat)
        _face_out(m, hi, (0, 1, 0), mat)
    ring_o, ring_i = _ngon(3.3, 16), _ngon(3.0, 16)
    for k in range(16):
        k2 = (k + 1) % 16
        pts = [ring_o[k], ring_o[k2], ring_i[k2], ring_i[k]]
        _face_out(m, [(x, 0.61, z) for x, z in pts], (0, 1, 0), A)
    for k in range(8):
        a = math.tau * k / 8 + math.pi / 8
        m.box(math.sin(a) * 4.7 - 0.12, 0.3, math.cos(a) * 4.7 - 0.12, math.sin(a) * 4.7 + 0.12, 0.42, math.cos(a) * 4.7 + 0.12, A, chamfer=0.02)
    return [("Mesh", m, None)]


def cue_panel():
    """A carved plaque, 0.4 thick (x) by 2.5 by 2.5, facing +x, with a rune cut into its face."""
    m = Model("cue")
    m.box(-0.2, -1.25, -1.25, 0.2, 1.25, 1.25, W, chamfer=0.05)
    m.box(0.2, -1.05, -1.05, 0.26, 1.05, 1.05, F, chamfer=0.02)
    m.tube((0.29, -0.7, 0.0), (0.29, 0.7, 0.0), 0.06, 0.06, A, sides=5)
    m.tube((0.29, 0.0, -0.6), (0.29, 0.0, 0.6), 0.06, 0.06, A, sides=5)
    for k in range(6):
        a = math.tau * k / 6
        m.tube((0.29, math.cos(a) * 0.45, math.sin(a) * 0.45), (0.29, math.cos(a + 1.0) * 0.45, math.sin(a + 1.0) * 0.45), 0.04, 0.04, A, sides=4)
    return [("Mesh", m, None)]


def obstacle_block(style):
    """A solid 1 x 1 x 1 block (origin at the centre of its base) faced with courses of stone on four
    sides under a capstone; the game scales it to a platform, a low wall or a pillar."""
    rng = random.Random("block/" + style)
    m = Model("block")
    m.box(-0.5, 0.0, -0.5, 0.5, 1.0, 0.5, W)
    courses = 4
    for face in range(4):
        yaw = face * math.pi / 2
        c, s = math.cos(yaw), math.sin(yaw)
        for row in range(courses):
            y0 = row / courses
            y1 = (row + 1) / courses
            cols = 2 if (row + face) % 2 else 3
            shift = rng.uniform(0.0, 0.15) if cols == 3 else 0.0
            for col in range(cols):
                x0 = -0.5 + col / cols + shift * (col > 0)
                x1 = -0.5 + (col + 1) / cols
                if x1 - x0 < 0.05:
                    continue
                # Build the block on the +z face, then turn it to this side of the cube.
                depth = rng.uniform(0.012, 0.03)
                b = min(0.012, (x1 - x0) * 0.3, (y1 - y0) * 0.3)
                g = 0.008
                ox0, ox1, oy0, oy1 = x0 + g, x1 - g, y0 + g, y1 - g

                def p(x, y, z):
                    # rotate about y by yaw, then push the face out to the cube surface
                    zz = z + 0.5
                    return (x * c + zz * s, y, -x * s + zz * c)

                outer = [p(ox0, oy0, 0.0), p(ox1, oy0, 0.0), p(ox1, oy1, 0.0), p(ox0, oy1, 0.0)]
                inner = [p(ox0 + b, oy0 + b, depth), p(ox1 - b, oy0 + b, depth), p(ox1 - b, oy1 - b, depth), p(ox0 + b, oy1 - b, depth)]
                nx, nz = s, c
                mid = [sum(q[i] for q in inner) / 4 for i in range(3)]
                for k in range(4):
                    k2 = (k + 1) % 4
                    quad = [outer[k], outer[k2], inner[k2], inner[k]]
                    hint = tuple(sum(q[i] for q in quad) / 4 - mid[i] for i in range(3))
                    _face_out(m, quad, hint, F if rng.random() < 0.25 else W)
                _face_out(m, inner, (nx, 0, nz), F if rng.random() < 0.25 else W)
    m.box(-0.53, 0.94, -0.53, 0.53, 1.0, 0.53, F, chamfer=0.015)
    return [("Mesh", m, None)]


# -- effects --------------------------------------------------------------------------------
def debris(variant):
    """A faceted chunk about one unit across; the game scales it to a chip of masonry or ice."""
    rng = random.Random("debris%d" % variant)
    m = Model("debris")
    top = [(rng.uniform(-0.45, 0.45), rng.uniform(0.3, 0.5), rng.uniform(-0.45, 0.45)) for _ in range(3)]
    ring = []
    for k in range(5):
        a = math.tau * k / 5 + rng.uniform(-0.25, 0.25)
        ring.append((math.cos(a) * rng.uniform(0.35, 0.55), rng.uniform(-0.05, 0.1), math.sin(a) * rng.uniform(0.35, 0.55)))
    base = [(x * 0.8, -0.5, z * 0.8) for x, _, z in ring]
    apex = (0.0, 0.5, 0.0)
    for k in range(5):
        k2 = (k + 1) % 5
        cx = sum(p[0] for p in (ring[k], ring[k2])) / 2
        cz = sum(p[2] for p in (ring[k], ring[k2])) / 2
        _face_out(m, [base[k], base[k2], ring[k2], ring[k]], (cx, 0, cz), M)
        _face_out(m, [ring[k], ring[k2], apex], (cx, 0.6, cz), M)
    _face_out(m, base, (0, -1, 0), M)
    return [("Mesh", m, None)]


def mote():
    """An octahedron 0.12 across, for drifting dust and embers."""
    m = Model("mote")
    r = 0.06
    top, bot = (0, r * 1.3, 0), (0, -r * 1.3, 0)
    ring = [(r, 0, 0), (0, 0, r), (-r, 0, 0), (0, 0, -r)]
    for k in range(4):
        k2 = (k + 1) % 4
        cx, cz = (ring[k][0] + ring[k2][0]) / 2, (ring[k][2] + ring[k2][2]) / 2
        _face_out(m, [ring[k], ring[k2], top], (cx, 1, cz), M)
        _face_out(m, [ring[k2], ring[k], bot], (cx, -1, cz), M)
    return [("Mesh", m, None)]


def droplet():
    """A water droplet, unit radius, pointed at the top."""
    m = Model("droplet")
    m.loft([dict(y=-1.0, rx=0.001, rz=0.001), dict(y=-0.55, rx=0.75, rz=0.75), dict(y=0.0, rx=1.0, rz=1.0), dict(y=0.6, rx=0.6, rz=0.6), dict(y=1.5, rx=0.001, rz=0.001)], M, sides=6, power=2.0, cap_bottom=False, cap_top=False)
    return [("Mesh", m, None)]


def energy_pillar():
    """A faceted crystal column, unit radius (x, z) and unit height, pointed tip; scaled to the pillar."""
    m = Model("pillar")
    m.loft([dict(y=0.0, rx=1.0, rz=1.0), dict(y=0.12, rx=0.78, rz=0.78), dict(y=0.85, rx=0.55, rz=0.55), dict(y=1.0, rx=0.12, rz=0.12)], M, sides=6, power=2.0)
    for k in range(3):
        a = math.tau * k / 3 + 0.4
        m.tube((math.cos(a) * 0.75, 0.05, math.sin(a) * 0.75), (math.cos(a) * 0.55, 0.55, math.sin(a) * 0.55), 0.22, 0.02, M, sides=4)
    return [("Mesh", m, None)]


def recovery_ring():
    """A ring of linked stone-and-rune segments, mean radius 2.85, 0.14 high."""
    m = Model("recovery")
    n = 16
    for k in range(n):
        a0 = math.tau * k / n + 0.03
        a1 = math.tau * (k + 1) / n - 0.03
        pts = [(math.sin(a) * r, math.cos(a) * r) for a, r in ((a0, 3.1), (a1, 3.1), (a1, 2.6), (a0, 2.6))]
        _face_out(m, [(x, 0.0, z) for x, z in pts], (0, 1, 0), M)
        for i in range(4):
            i2 = (i + 1) % 4
            lo = [(pts[i][0], 0.0, pts[i][1]), (pts[i2][0], 0.0, pts[i2][1])]
            hi = [(pts[i2][0], 0.14, pts[i2][1]), (pts[i][0], 0.14, pts[i][1])]
            ex = (pts[i][0] + pts[i2][0]) / 2
            ez = (pts[i][1] + pts[i2][1]) / 2
            _face_out(m, lo + hi, (ex, 0, ez), M)
        _face_out(m, [(x, 0.14, z) for x, z in pts], (0, 1, 0), M)
    for k in range(8):
        a = math.tau * k / 8
        m.tube((math.sin(a) * 3.15, 0.0, math.cos(a) * 3.15), (math.sin(a) * 3.15, 0.5, math.cos(a) * 3.15), 0.1, 0.01, M, sides=4)
    return [("Mesh", m, None)]


def beacon():
    """A crystal spire 0.8 wide and 2 high, origin at its middle, with two orbiting shards."""
    m = Model("beacon")
    m.loft([dict(y=-1.0, rx=0.001, rz=0.001), dict(y=-0.45, rx=0.4, rz=0.4), dict(y=0.35, rx=0.4, rz=0.4), dict(y=1.0, rx=0.001, rz=0.001)], M, sides=4, power=2.0, cap_bottom=False, cap_top=False)
    for k in range(2):
        a = math.pi * k
        m.tube((math.sin(a) * 0.65, -0.1 + k * 0.4, math.cos(a) * 0.65), (math.sin(a) * 0.65, 0.3 + k * 0.4, math.cos(a) * 0.65), 0.09, 0.005, M, sides=4)
    return [("Mesh", m, None)]


def wing():
    """A swept feather blade pointing along +x: unit long, unit wide, unit thick, origin at its root."""
    m = Model("wing")
    outline = [(0.0, -0.22), (0.25, -0.5), (0.72, -0.34), (1.0, 0.04), (0.64, 0.5), (0.22, 0.4), (0.0, 0.2)]
    n = len(outline)
    lo = [(x - 0.5, -0.3, z) for x, z in outline]
    hi = [(x - 0.5, 0.3, z) for x, z in outline]
    cx = sum(p[0] for p in lo) / n
    cz = sum(p[2] for p in lo) / n
    for k in range(n):
        k2 = (k + 1) % n
        ex = (lo[k][0] + lo[k2][0]) / 2 - cx
        ez = (lo[k][2] + lo[k2][2]) / 2 - cz
        _face_out(m, [lo[k], lo[k2], hi[k2], hi[k]], (ex, 0, ez), M)
    _face_out(m, hi, (0, 1, 0), M)
    _face_out(m, lo, (0, -1, 0), M)
    return [("Mesh", m, None)]


BUILDERS = {
    "fx/wing": wing,
    "walls/ramp": ramp, "walls/dais": dais, "walls/cue_panel": cue_panel,
    "fx/debris_a": lambda: debris(0), "fx/debris_b": lambda: debris(1), "fx/debris_c": lambda: debris(2),
    "fx/mote": mote, "fx/droplet": droplet, "fx/energy_pillar": energy_pillar,
    "fx/recovery_ring": recovery_ring, "fx/beacon": beacon,
}
for _s in STYLES:
    BUILDERS["walls/block_" + _s] = (lambda s=_s: obstacle_block(s))
