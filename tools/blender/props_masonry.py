"""Blender builders for the dungeon's own structure: wall masonry, flagstone floors and stairs, in
six biome styles.

Masonry faces +z (into the room once the game turns it) and is 2 m wide and 2 m tall, origin at
the bottom centre of the wall face. Floor tiles are 4 x 4 m with their top at y = 0, discs are unit
radius and scaled to the room, steps are one 4.0 x 0.5 x 0.8 m tread. Roles are the biome's own
`wall`, `floor` and `accent`, plus `crystal`, `iron`, `darkiron` and `steel` where a style needs them.
"""

from __future__ import annotations

import math
import random

from bl_lib import Model

W, F, A = "wall", "floor", "accent"
CRYSTAL, IRON, DARK, STEEL = "crystal", "iron", "darkiron", "steel"
STYLES = ["castle", "crystal", "swamp", "frozen", "vault", "cathedral"]
L = 2.0


def _newell(pts):
    nx = ny = nz = 0.0
    for i, (x0, y0, z0) in enumerate(pts):
        x1, y1, z1 = pts[(i + 1) % len(pts)]
        nx += (y0 - y1) * (z0 + z1)
        ny += (z0 - z1) * (x0 + x1)
        nz += (x0 - x1) * (y0 + y1)
    return nx, ny, nz


def _face_out(m, pts, hint, mat):
    """Add a face whose winding is flipped if needed so it faces along `hint`."""
    n = _newell(pts)
    if n[0] * hint[0] + n[1] * hint[1] + n[2] * hint[2] < 0:
        pts = list(reversed(pts))
    m.face(pts, mat)


def block(m, x0, y0, x1, y1, depth, bevel, mat):
    """A wall block seen from the front: a face at z = depth inside a bevel, sides sunk into the wall."""
    b = min(bevel, (x1 - x0) * 0.4, (y1 - y0) * 0.4)
    outer = [(x0, y0, 0.0), (x1, y0, 0.0), (x1, y1, 0.0), (x0, y1, 0.0)]
    inner = [(x0 + b, y0 + b, depth), (x1 - b, y0 + b, depth), (x1 - b, y1 - b, depth), (x0 + b, y1 - b, depth)]
    hints = [(0, -1, 0.6), (1, 0, 0.6), (0, 1, 0.6), (-1, 0, 0.6)]
    for k in range(4):
        k2 = (k + 1) % 4
        _face_out(m, [outer[k], outer[k2], inner[k2], inner[k]], hints[k], mat)
    _face_out(m, inner, (0, 0, 1), mat)


def _courses(m, rng, heights, widths, depth, bevel, mats, gap=0.04, stagger=True):
    """Fill the 2 x 2 face with courses of blocks. Heights and widths are (min, max) or fixed."""
    y = 0.0
    row = 0
    while y < L - 1e-3:
        h = heights if isinstance(heights, float) else rng.uniform(*heights)
        h = min(h, L - y)
        if L - y - h < 0.12:
            h = L - y
        x = -L / 2
        if stagger and row % 2:
            x -= rng.uniform(0.15, 0.4)
        while x < L / 2 - 1e-3:
            w = widths if isinstance(widths, float) else rng.uniform(*widths)
            x1 = x + w
            cx0, cx1 = max(x, -L / 2), min(x1, L / 2)
            if cx1 - cx0 > 0.12:
                mat = mats[rng.randrange(len(mats))]
                block(m, cx0 + gap / 2, y + gap / 2, cx1 - gap / 2, y + h - gap / 2, rng.uniform(*depth), bevel, mat)
            x = x1
        y += h
        row += 1


def masonry(style):
    rng = random.Random("masonry/" + style)
    m = Model("masonry")
    if style == "castle":
        _courses(m, rng, 0.5, (0.6, 1.1), (0.03, 0.07), 0.03, [W, W, W, F])
    elif style == "cathedral":
        _courses(m, rng, 0.25, (0.5, 0.72), (0.025, 0.05), 0.02, [W, W, W, F])
        for k in range(2):
            x = -0.5 + k * 1.0
            m.tube((x, 0.0, 0.06), (x, L, 0.06), 0.02, 0.02, A, sides=4)
    elif style == "crystal":
        _courses(m, rng, 1.0, 1.0, (0.08, 0.13), 0.05, [W], gap=0.1, stagger=True)
        for _ in range(5):
            x, y = rng.uniform(-0.9, 0.9), rng.uniform(0.15, 1.85)
            h = rng.uniform(0.18, 0.4)
            m.tube((x, y, 0.06), (x + rng.uniform(-0.05, 0.05), y + h, 0.14), 0.05, 0.006, CRYSTAL, sides=4)
    elif style == "swamp":
        _courses(m, rng, (0.36, 0.6), (0.4, 0.9), (0.03, 0.12), 0.04, [W, W, F])
        for _ in range(4):
            x = rng.uniform(-0.9, 0.9)
            y = rng.uniform(0.6, 1.9)
            m.tube((x, y, 0.08), (x + rng.uniform(-0.04, 0.04), y - rng.uniform(0.25, 0.6), 0.1), 0.03, 0.008, A, sides=4)
    elif style == "frozen":
        _courses(m, rng, 0.66, (0.66, 1.0), (0.06, 0.1), 0.05, [W, W, CRYSTAL])
        for k in range(4):
            x = -0.8 + k * 0.55 + rng.uniform(-0.1, 0.1)
            m.tube((x, 0.0, 0.05), (x, -0.0 + rng.uniform(0.15, 0.4), 0.09), 0.03, 0.005, CRYSTAL, sides=4)
    else:  # vault
        for ix in range(2):
            for iy in range(2):
                x0, y0 = -1.0 + ix * 1.0, iy * 1.0
                block(m, x0 + 0.03, y0 + 0.03, x0 + 0.97, y0 + 0.97, 0.05, 0.03, W)
                for dx in (0.12, 0.88):
                    for dy in (0.12, 0.88):
                        m.sphere(x0 + dx, y0 + dy, 0.07, 0.03, STEEL, sides=5, rings=2)
        for y in (0.0, 1.0, 2.0):
            m.box(-L / 2, max(y - 0.03, 0.0), 0.0, L / 2, min(y + 0.03, L), 0.06, DARK)
    return [("Mesh", m, None)]


# -- floors ---------------------------------------------------------------------------------
def _stone(m, pts, y0, top, bevel, mat):
    """A floor stone: a polygon (x, z) raised to `top`, bevelled at its upper edge."""
    cx = sum(p[0] for p in pts) / len(pts)
    cz = sum(p[1] for p in pts) / len(pts)

    def inset(d):
        out = []
        for x, z in pts:
            dx, dz = x - cx, z - cz
            ln = math.hypot(dx, dz) or 1.0
            k = max(0.0, (ln - d) / ln)
            out.append((cx + dx * k, cz + dz * k))
        return out

    lo = [(x, y0, z) for x, z in pts]
    mid = [(x, top - bevel, z) for x, z in pts]
    hi = [(x, top, z) for x, z in inset(bevel)]
    n = len(pts)
    for k in range(n):
        k2 = (k + 1) % n
        ex, ez = (pts[k][0] + pts[k2][0]) / 2 - cx, (pts[k][1] + pts[k2][1]) / 2 - cz
        _face_out(m, [lo[k], lo[k2], mid[k2], mid[k]], (ex, 0, ez), mat)
        _face_out(m, [mid[k], mid[k2], hi[k2], hi[k]], (ex * 0.5, 0.6, ez * 0.5), mat)
    _face_out(m, hi, (0, 1, 0), mat)


def _shrink(pts, d):
    cx = sum(p[0] for p in pts) / len(pts)
    cz = sum(p[1] for p in pts) / len(pts)
    out = []
    for x, z in pts:
        dx, dz = x - cx, z - cz
        ln = math.hypot(dx, dz) or 1.0
        k = max(0.0, (ln - d) / ln)
        out.append((cx + dx * k, cz + dz * k))
    return out


def _split(rng, rect, min_side, depth=0):
    x0, z0, x1, z1 = rect
    w, d = x1 - x0, z1 - z0
    if (w < min_side * 1.8 and d < min_side * 1.8) or depth > 4 or (w < 1.4 and d < 1.4 and rng.random() < 0.6):
        return [rect]
    if w >= d:
        cut = x0 + w * rng.uniform(0.35, 0.65)
        return _split(rng, (x0, z0, cut, z1), min_side, depth + 1) + _split(rng, (cut, z0, x1, z1), min_side, depth + 1)
    cut = z0 + d * rng.uniform(0.35, 0.65)
    return _split(rng, (x0, z0, x1, cut), min_side, depth + 1) + _split(rng, (x0, cut, x1, z1), min_side, depth + 1)


def _rect_pts(r):
    x0, z0, x1, z1 = r
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def floor_tile(style):
    rng = random.Random("floor/" + style)
    m = Model("floor")
    half = 2.0
    m.box(-half, -0.5, -half, half, -0.07, half, F)
    if style == "cathedral":
        for ix in range(4):
            for iz in range(4):
                mat = W if (ix + iz) % 2 else F
                x0, z0 = -half + ix, -half + iz
                _stone(m, _shrink(_rect_pts((x0, z0, x0 + 1, z0 + 1)), 0.02), -0.09, 0.0, 0.012, mat)
        m.box(-0.12, 0.0, -0.12, 0.12, 0.012, 0.12, W)
    elif style == "vault":
        for ix in range(2):
            for iz in range(2):
                x0, z0 = -half + ix * 2, -half + iz * 2
                _stone(m, _shrink(_rect_pts((x0, z0, x0 + 2, z0 + 2)), 0.025), -0.09, 0.0, 0.02, F)
                for dx in (0.25, 1.75):
                    for dz in (0.25, 1.75):
                        m.sphere(x0 + dx, 0.0, z0 + dz, 0.05, STEEL, sides=5, rings=2, ry=0.03)
                for k in range(5):
                    m.box(x0 + 0.5 + k * 0.25, 0.0, z0 + 0.95, x0 + 0.58 + k * 0.25, 0.012, z0 + 1.05, DARK)
    elif style == "swamp":
        cells = 6
        step = 4.0 / cells
        grid = [[(-half + i * step + rng.uniform(-0.12, 0.12) * (0 < i < cells), -half + j * step + rng.uniform(-0.12, 0.12) * (0 < j < cells)) for j in range(cells + 1)] for i in range(cells + 1)]
        for i in range(cells):
            for j in range(cells):
                quad = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                top = -rng.uniform(0.0, 0.035)
                _stone(m, _shrink(quad, 0.04), -0.1, top, 0.02, W if rng.random() < 0.22 else F)
    elif style in ("frozen", "crystal"):
        rects = _split(rng, (-half, -half, half, half), 1.0)
        for r in rects:
            top = -rng.uniform(0.0, 0.02)
            _stone(m, _shrink(_rect_pts(r), 0.035), -0.09, top, 0.03, CRYSTAL if rng.random() < 0.05 else F)
        for _ in range(3):
            x, z = rng.uniform(-1.6, 1.6), rng.uniform(-1.6, 1.6)
            m.tube((x, 0.0, z), (x + 0.03, rng.uniform(0.15, 0.3), z + 0.03), 0.05, 0.006, CRYSTAL, sides=4)
    else:  # castle
        rects = _split(rng, (-half, -half, half, half), 0.9)
        for r in rects:
            top = -rng.uniform(0.0, 0.025)
            _stone(m, _shrink(_rect_pts(r), 0.03), -0.09, top, 0.02, W if rng.random() < 0.12 else F)
    return [("Mesh", m, None)]


def _edge_radius(a, n):
    seg = math.tau / n
    return math.cos(seg / 2) / math.cos((a % seg) - seg / 2)


def floor_disc(style, n):
    """A unit-radius n-gon floor matching the game's CylinderMesh (vertices at multiples of tau/n)."""
    rng = random.Random("disc/%s/%d" % (style, n))
    m = Model("disc")

    def at(r, a):
        k = r * _edge_radius(a, n)
        return (math.sin(a) * k, math.cos(a) * k)

    base = [at(1.0, math.tau * i / n) for i in range(n)]
    lo = [(x, -0.5, z) for x, z in base]
    hi = [(x, -0.07, z) for x, z in base]
    for k in range(n):
        k2 = (k + 1) % n
        ex, ez = (base[k][0] + base[k2][0]) / 2, (base[k][1] + base[k2][1]) / 2
        _face_out(m, [lo[k], lo[k2], hi[k2], hi[k]], (ex, 0, ez), F)
    _face_out(m, hi, (0, 1, 0), F)
    rings = [(0.0, 0.3), (0.3, 0.64), (0.64, 1.0)]
    counts = [n, n * 2, n * 3] if n <= 8 else [n, n, n * 2]
    d = 0.022
    for ri, (r0, r1) in enumerate(rings):
        cnt = counts[ri]
        for k in range(cnt):
            a0 = math.tau * k / cnt + (0.0 if ri % 2 == 0 else math.tau / cnt * 0.5)
            a1 = a0 + math.tau / cnt
            sub = 6
            arc_out = [at(r1, a0 + (a1 - a0) * s / sub) for s in range(sub + 1)]
            arc_in = [at(r0, a0 + (a1 - a0) * s / sub) for s in range(sub + 1)] if r0 > 0 else [(0.0, 0.0)]
            pts = arc_out + list(reversed(arc_in))
            top = -rng.uniform(0.0, 0.02)
            mat = W if (ri == 0 or (k + ri) % 2) else F
            if style == "swamp" and rng.random() < 0.2:
                mat = A
            if style in ("frozen", "crystal") and rng.random() < 0.1:
                mat = CRYSTAL
            _stone(m, _shrink(pts, d), -0.09, top, 0.014, mat)
    return [("Mesh", m, None)]


# -- stairs ---------------------------------------------------------------------------------
def step(style):
    """One tread, 4.0 wide (x), 0.5 high, 0.8 deep (z), origin at the bottom centre; the game scales it."""
    m = Model("step")
    w, h, d = 4.0, 0.5, 0.8
    m.box(-w / 2, 0.0, -d / 2, w / 2, h, d / 2, F, chamfer=0.05)
    m.box(-w / 2 + 0.15, h, -d / 2 + 0.12, w / 2 - 0.15, h + 0.01, d / 2 - 0.12, W)
    # the nosing and a worn groove along the tread
    m.box(-w / 2, h - 0.12, d / 2 - 0.02, w / 2, h, d / 2 + 0.05, W, chamfer=0.03)
    if style in ("crystal", "frozen"):
        for k in range(3):
            x = -1.2 + k * 1.2
            m.tube((x, h, 0.0), (x + 0.02, h + 0.14, 0.02), 0.03, 0.004, CRYSTAL, sides=4)
    elif style == "vault":
        for k in range(6):
            m.sphere(-1.6 + k * 0.64, h, d / 2 - 0.08, 0.03, STEEL, sides=5, rings=2)
    return [("Mesh", m, None)]


BUILDERS = {}
for _s in STYLES:
    BUILDERS["walls/masonry_" + _s] = (lambda s=_s: masonry(s))
    BUILDERS["walls/floor_" + _s] = (lambda s=_s: floor_tile(s))
    BUILDERS["walls/disc24_" + _s] = (lambda s=_s: floor_disc(s, 24))
    BUILDERS["walls/disc8_" + _s] = (lambda s=_s: floor_disc(s, 8))
    BUILDERS["walls/step_" + _s] = (lambda s=_s: step(s))
