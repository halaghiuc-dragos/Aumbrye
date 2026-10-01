"""Blender builders for the village terrain around the tower: houses, trees, fences, wells, crops,
hedges, streets, mountains and the distant horizon ruins.

Roles are the skyline's own material names: daub/stone (walls), tile/thatch (roofing), timber,
foot (stone footing), window, leaf, leaf_warm, grass, grass_pale, crop, dirt, cobble, rock_far,
rock_pale, snow. Roofing and walling are swapped in code (`wall`, `roof`), so the roles below are
stand-ins the skyline re-skins per block.
"""

from __future__ import annotations

import math
import random

from bl_lib import Model

WALL, ROOF, TIM, FOOT, WIN = "wall", "roof", "timber", "foot", "window"
LEAF, LEAFW, GRASS, GRASSP = "leaf", "leaf_warm", "grass", "grass_pale"
CROP, DIRT, COBBLE = "crop", "dirt", "cobble"
ROCK, SCREE, SNOW = "rock_far", "rock_pale", "snow"
STONE, STONED = "stone", "stone_dark"

UNIT_W, UNIT_D = 6.4, 8.0
EAVE_1, EAVE_2 = 5.6, 8.0


def _lump(m, cx, cy, cz, rx, ry, rz, mat, sides=8, rings=4):
    m.sphere(cx, cy, cz, rx, mat, sides=sides, rings=rings, ry=ry, rz=rz)


# -- houses ---------------------------------------------------------------------------------
def _roof(m, w, d, y, peak, detail):
    """Gabled roof with the ridge along x (the street), slopes falling to the front and back walls
    and gable ends at the two sides of the unit."""
    eave = 0.35
    hl, hd = w / 2 + eave, d / 2 + eave
    for zs in (-1, 1):
        pts = [(-hl, y - 0.1, zs * hd), (hl, y - 0.1, zs * hd), (hl, y + peak, 0.0), (-hl, y + peak, 0.0)]
        m.plate(pts, (0, 0.22, 0), 0.22, ROOF)
        if detail:
            m.box(-hl - 0.04, y - 0.26, zs * hd - 0.1, hl + 0.04, y - 0.1, zs * hd + 0.1, TIM, chamfer=0.03)
    m.box(-hl, y + peak - 0.06, -0.16, hl, y + peak + 0.2, 0.16, TIM, chamfer=0.04)
    for xs in (-1, 1):
        xg = xs * (w / 2 - 0.05)
        m.plate([(xg, y, -d / 2 + 0.05), (xg, y, d / 2 - 0.05), (xg, y + peak * 0.9, 0.0)], (xs, 0, 0), 0.28, WALL)
        if detail:
            m.box(xg + xs * 0.26, y, -0.05, xg + xs * 0.3, y + peak * 0.9, 0.05, TIM)


def _window(m, x, y, z, facing):
    w, h = 0.78, 0.95
    m.box(x - w / 2 - 0.1, y - h / 2 - 0.1, z - 0.02, x + w / 2 + 0.1, y + h / 2 + 0.1, z + 0.12, TIM, chamfer=0.02)
    m.box(x - w / 2, y - h / 2, z + 0.1, x + w / 2, y + h / 2, z + 0.16, WIN)
    m.box(x - 0.03, y - h / 2, z + 0.15, x + 0.03, y + h / 2, z + 0.19, TIM)
    m.box(x - w / 2, y - 0.03, z + 0.15, x + w / 2, y + 0.03, z + 0.19, TIM)
    m.box(x - w / 2 - 0.14, y - h / 2 - 0.22, z + 0.05, x + w / 2 + 0.14, y - h / 2 - 0.1, z + 0.3, TIM, chamfer=0.02)


def house(storeys, detail=True, seed=1):
    """One terrace unit, 6.4 wide (x) and 8 deep (z); +z is the street front. Scaled by the skyline."""
    rng = random.Random("house%d%d" % (storeys, seed))
    m = Model("house")
    w, d = UNIT_W, UNIT_D
    eave = EAVE_2 if storeys == 2 else EAVE_1
    peak = d * 0.47
    m.box(-w / 2, 0.0, -d / 2 - 0.15, w / 2, 0.6, d / 2 + 0.15, FOOT, chamfer=0.06)
    m.box(-w / 2 + 0.09, 0.6, -d / 2 + 0.09, w / 2 - 0.09, eave, d / 2 - 0.09, WALL, chamfer=0.04)
    if detail:
        m.box(-w / 2, eave - 0.24, -d / 2 - 0.06, w / 2, eave, d / 2 + 0.06, TIM, chamfer=0.03)
        if storeys == 2:
            m.box(-w / 2 - 0.08, eave * 0.52 - 0.11, -d / 2 - 0.1, w / 2 + 0.08, eave * 0.52 + 0.11, d / 2 + 0.1, TIM, chamfer=0.03)
        for px in (-1, 1):
            for pz in (-1, 1):
                m.box(px * (w / 2 - 0.13) - 0.13, 0.6, pz * (d / 2 - 0.13) - 0.13, px * (w / 2 - 0.13) + 0.13, eave, pz * (d / 2 - 0.13) + 0.13, TIM, chamfer=0.02)
        # half-timber braces on the front
        for k in (-1, 1):
            m.tube((k * w * 0.36, eave * 0.52 if storeys == 2 else 0.7, d / 2 + 0.03), (k * w * 0.12, eave - 0.3, d / 2 + 0.03), 0.07, 0.07, TIM, sides=4)
        # door
        m.box(-0.62, 0.6, d / 2 - 0.04, 0.62, 2.5, d / 2 + 0.14, TIM, chamfer=0.04)
        m.box(-0.5, 0.6, d / 2 + 0.12, 0.5, 2.4, d / 2 + 0.17, FOOT)
        m.box(-0.78, 0.6, d / 2, -0.62, 2.62, d / 2 + 0.2, TIM)
        m.box(0.62, 0.6, d / 2, 0.78, 2.62, d / 2 + 0.2, TIM)
        m.box(-0.78, 2.5, d / 2, 0.78, 2.66, d / 2 + 0.2, TIM)
        m.box(-1.0, 0.6, d / 2 + 0.05, 1.0, 0.72, d / 2 + 0.9, FOOT, chamfer=0.03)
        rows = [eave * 0.33] if storeys == 1 else [eave * 0.22, eave * 0.7]
        for ri, y in enumerate(rows):
            for xs in (-1, 1):
                _window(m, xs * w * 0.3 if ri == 0 else xs * w * 0.27, y + (0.4 if ri == 0 else 0.0), d / 2 - 0.02, 1)
        if storeys == 2:
            # jetty shadow beams and a hanging sign
            m.tube((w / 2 + 0.2, eave * 0.66, d / 2 - 0.3), (w / 2 + 1.0, eave * 0.66, d / 2 - 0.3), 0.05, 0.05, TIM, sides=4)
            m.box(w / 2 + 0.5, eave * 0.52, d / 2 - 0.36, w / 2 + 1.05, eave * 0.62, d / 2 - 0.3, "canvas_red" if rng.random() < 0.5 else TIM)
    else:
        for xs in (-0.22, 0.22):
            m.box(xs * w - 0.3, eave * 0.3, d / 2 - 0.04, xs * w + 0.3, eave * 0.3 + 0.8, d / 2 + 0.05, WIN)
    _roof(m, w, d, eave, peak, detail)
    if detail:
        stack = peak + 1.5
        m.box(w * 0.22, eave, -d * 0.12, w * 0.22 + 0.8, eave + stack, -d * 0.12 + 0.8, FOOT, chamfer=0.05)
        m.box(w * 0.22 - 0.1, eave + stack, -d * 0.12 - 0.1, w * 0.22 + 0.9, eave + stack + 0.2, -d * 0.12 + 0.9, STONED, chamfer=0.03)
    return [("Mesh", m, None)]


def barn():
    """A big barn, 8.2 wide and 8 deep, with a hay loft and double doors."""
    m = Model("barn")
    w, d, eave = 8.2, UNIT_D, 5.2
    peak = d * 0.5
    m.box(-w / 2, 0.0, -d / 2 - 0.1, w / 2, 0.5, d / 2 + 0.1, FOOT, chamfer=0.06)
    m.box(-w / 2 + 0.06, 0.5, -d / 2 + 0.06, w / 2 - 0.06, eave, d / 2 - 0.06, WALL, chamfer=0.04)
    for k in range(-3, 4):
        m.box(k * w * 0.14 - 0.08, 0.5, d / 2, k * w * 0.14 + 0.08, eave, d / 2 + 0.07, TIM)
    for k in (-1, 1):
        m.box(k * w / 2 - 0.15, 0.5, d / 2 - 0.15, k * w / 2 + 0.15, eave, d / 2 + 0.15, TIM, chamfer=0.02)
    m.box(-1.6, 0.5, d / 2 - 0.02, 1.6, 3.6, d / 2 + 0.16, TIM, chamfer=0.04)
    m.box(-0.04, 0.5, d / 2 + 0.14, 0.04, 3.6, d / 2 + 0.2, FOOT)
    m.tube((-1.5, 0.7, d / 2 + 0.22), (-0.06, 3.5, d / 2 + 0.22), 0.07, 0.07, TIM, sides=4)
    m.tube((1.5, 0.7, d / 2 + 0.22), (0.06, 3.5, d / 2 + 0.22), 0.07, 0.07, TIM, sides=4)
    m.box(-0.5, eave - 1.2, d / 2 - 0.02, 0.5, eave - 0.2, d / 2 + 0.18, TIM)
    _roof(m, w, d, eave, peak, True)
    return [("Mesh", m, None)]


def far_house():
    """A rooftop silhouette for the outskirts: body and roof, no frame."""
    return house(1, detail=False)


# -- trees and cover ------------------------------------------------------------------------
def oak(variant):
    """A broad field oak: a trunk, a few boughs and a crown of leaf clumps. About 4 m across."""
    rng = random.Random("oak%d" % variant)
    m = Model("oak")
    th = rng.uniform(2.4, 3.4)
    m.loft(
        [dict(y=0.0, cx=0, cz=0, rx=0.55, rz=0.5), dict(y=0.4, cx=0, cz=0, rx=0.38, rz=0.36), dict(y=th, cx=0.05, cz=0.0, rx=0.3, rz=0.3)],
        TIM, sides=7,
    )
    for k in range(3):
        a = k * math.tau / 3 + rng.uniform(-0.3, 0.3)
        m.tube((0.0, th * 0.72, 0.0), (math.cos(a) * 0.9, th * 1.08, math.sin(a) * 0.9), 0.17, 0.09, TIM, sides=5)
        m.tube((0.0, 0.0, 0.0), (math.cos(a) * 0.55, 0.05, math.sin(a) * 0.55), 0.14, 0.04, TIM, sides=4)
    crown = rng.uniform(1.9, 2.4)
    clumps = [(0, th + crown * 0.42, 0, crown, crown * 0.78)]
    for k in range(5):
        a = k * math.tau / 5 + rng.uniform(-0.3, 0.3)
        clumps.append((math.cos(a) * crown * 0.62, th + crown * rng.uniform(0.15, 0.5), math.sin(a) * crown * 0.62, crown * rng.uniform(0.55, 0.72), crown * 0.5))
    clumps.append((0.0, th + crown * 0.98, 0.0, crown * 0.55, crown * 0.42))
    for i, (x, y, z, rx, ry) in enumerate(clumps):
        _lump(m, x, y, z, rx, ry, rx * rng.uniform(0.9, 1.05), LEAFW if i % 4 == 3 else LEAF, sides=9, rings=4)
    return [("Mesh", m, None)]


def pine(variant):
    rng = random.Random("pine%d" % variant)
    m = Model("pine")
    h = rng.uniform(5.0, 6.4)
    m.loft([dict(y=0.0, cx=0, cz=0, rx=0.4, rz=0.4), dict(y=h * 0.5, cx=0, cz=0, rx=0.2, rz=0.2)], TIM, sides=6)
    tiers = 5
    for t in range(tiers):
        y = 1.2 + t * (h - 1.6) / tiers
        r = 1.9 * (1.0 - t / (tiers + 0.6))
        m.cone(0.0, y, 0.0, r, y + 1.6, LEAF if t % 2 == 0 else LEAFW, sides=8)
    return [("Mesh", m, None)]


def orchard_tree():
    m = Model("orchard")
    m.loft([dict(y=0.0, cx=0, cz=0, rx=0.3, rz=0.3), dict(y=1.6, cx=0, cz=0, rx=0.2, rz=0.2)], TIM, sides=6)
    for k in range(3):
        a = k * math.tau / 3
        m.tube((0.0, 1.3, 0.0), (math.cos(a) * 0.5, 1.9, math.sin(a) * 0.5), 0.1, 0.05, TIM, sides=4)
    _lump(m, 0.0, 2.45, 0.0, 1.25, 0.95, 1.25, LEAF, sides=9, rings=4)
    _lump(m, 0.5, 2.15, 0.3, 0.7, 0.6, 0.7, LEAFW, sides=7, rings=3)
    _lump(m, -0.45, 2.3, -0.35, 0.65, 0.55, 0.65, LEAFW, sides=7, rings=3)
    return [("Mesh", m, None)]


def shrub(variant):
    rng = random.Random("shrub%d" % variant)
    m = Model("shrub")
    for k in range(4):
        a = k * math.tau / 4 + rng.uniform(-0.4, 0.4)
        d = rng.uniform(0.15, 0.4)
        r = rng.uniform(0.3, 0.5)
        _lump(m, math.cos(a) * d, r * 0.65, math.sin(a) * d, r, r * 0.8, r, LEAF if k % 2 == 0 else LEAFW, sides=7, rings=3)
    return [("Mesh", m, None)]


def grass_clump(variant):
    rng = random.Random("clump%d" % variant)
    m = Model("clump")
    for i in range(rng.randint(7, 10)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.0, 0.5)
        x, z = math.cos(a) * d, math.sin(a) * d
        h = rng.uniform(0.4, 1.0)
        lean = (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2))
        mat = GRASS if rng.random() > 0.4 else GRASSP
        m.tube((x, 0.0, z), (x + lean[0] * 0.5, h * 0.6, z + lean[1] * 0.5), 0.07, 0.05, mat, sides=4)
        m.tube((x + lean[0] * 0.5, h * 0.6, z + lean[1] * 0.5), (x + lean[0], h, z + lean[1]), 0.05, 0.005, mat, sides=4)
    return [("Mesh", m, None)]


def fence():
    """One 1.8 m bay of post-and-rail fence, posts at the ends, along x."""
    m = Model("fence")
    for x in (-0.9, 0.9):
        m.box(x - 0.08, 0.0, -0.08, x + 0.08, 1.1, 0.08, TIM, chamfer=0.02)
        m.box(x - 0.11, 1.1, -0.11, x + 0.11, 1.16, 0.11, TIM)
    for y in (0.5, 0.85):
        m.box(-0.9, y - 0.05, -0.04, 0.9, y + 0.05, 0.04, TIM, chamfer=0.015)
    return [("Mesh", m, None)]


def hedge():
    """A 4 m hedgerow section along x, 1.4 high and 1.1 through."""
    rng = random.Random("hedge")
    m = Model("hedge")
    for k in range(5):
        x = -1.6 + k * 0.8
        _lump(m, x, 0.7, rng.uniform(-0.1, 0.1), 0.62, 0.66, 0.55, LEAF if k % 2 == 0 else LEAFW, sides=8, rings=3)
    m.box(-2.0, 0.0, -0.3, 2.0, 0.35, 0.3, TIM, chamfer=0.04)
    return [("Mesh", m, None)]


def well():
    m = Model("well")
    m.cylinder(0.0, 0.0, 0.0, 0.85, 0.85, STONE, sides=10)
    m.cylinder(0.0, 0.85, 0.0, 0.7, 0.9, STONED, sides=10)
    for s in (-1, 1):
        m.box(s * 0.75 - 0.11, 0.0, -0.11, s * 0.75 + 0.11, 2.1, 0.11, TIM, chamfer=0.02)
    m.tube((-0.75, 2.0, 0.0), (0.75, 2.0, 0.0), 0.06, 0.06, TIM, sides=5)
    m.plate([(-1.15, 2.05, -1.0), (-1.15, 2.05, 1.0), (0.0, 2.8, 1.0), (0.0, 2.8, -1.0)], (0, 0.2, 0), 0.2, "thatch")
    m.plate([(1.15, 2.05, -1.0), (1.15, 2.05, 1.0), (0.0, 2.8, 1.0), (0.0, 2.8, -1.0)], (0, 0.2, 0), 0.2, "thatch")
    m.tube((0.0, 2.0, 0.0), (0.0, 1.0, 0.0), 0.02, 0.02, TIM, sides=3)
    m.cylinder(0.0, 0.85, 0.0, 0.2, 1.1, TIM, sides=6, r_top=0.23)
    return [("Mesh", m, None)]


def crop_row():
    """A 2 m run of one furrow: a mound with staggered stalks and heads of grain."""
    rng = random.Random("crop")
    m = Model("crop")
    m.box(-1.0, 0.0, -0.3, 1.0, 0.18, 0.3, DIRT, chamfer=0.06)
    for k in range(9):
        x = -0.9 + k * 0.225
        z = rng.uniform(-0.12, 0.12)
        h = rng.uniform(0.6, 0.85)
        lean = rng.uniform(-0.08, 0.08)
        m.tube((x, 0.1, z), (x + lean, h, z), 0.035, 0.022, CROP, sides=4)
        m.tube((x + lean, h, z), (x + lean * 1.6, h + 0.22, z), 0.05, 0.01, CROP, sides=4)
    return [("Mesh", m, None)]


def grazing():
    """A 4 x 4 patch of meadow with tufts, tiled over a paddock."""
    rng = random.Random("graze")
    m = Model("graze")
    m.box(-2.0, 0.0, -2.0, 2.0, 0.22, 2.0, GRASS, chamfer=0.05)
    for k in range(10):
        x, z = rng.uniform(-1.8, 1.8), rng.uniform(-1.8, 1.8)
        m.tube((x, 0.2, z), (x + 0.05, 0.6, z), 0.05, 0.004, GRASSP, sides=4)
    return [("Mesh", m, None)]


# -- streets --------------------------------------------------------------------------------
def road(kind):
    """A 4 m length of street, 1 m wide (scaled to the street). The slab hangs 0.6 below its top, so
    two streets crossing interpenetrate instead of z-fighting."""
    rng = random.Random("road" + kind)
    m = Model("road")
    m.box(-2.0, -0.6, -0.5, 2.0, 0.0, 0.5, COBBLE if kind == "cobble" else DIRT)
    if kind == "cobble":
        for r in range(9):
            for c in range(3):
                x = -1.9 + r * 0.44 + (0.12 if c % 2 else 0.0)
                z = -0.33 + c * 0.33
                hgt = rng.uniform(0.04, 0.085)
                m.box(x - 0.2, 0.0, z - 0.15, x + 0.2, hgt, z + 0.15, COBBLE if rng.random() > 0.3 else STONED, chamfer=0.025)
    else:
        for z in (-0.25, 0.25):
            m.box(-2.0, -0.02, z - 0.06, 2.0, 0.0, z + 0.06, "timber")
        for k in range(10):
            x, z = rng.uniform(-1.9, 1.9), rng.uniform(-0.45, 0.45)
            m.box(x - 0.06, 0.0, z - 0.05, x + 0.06, rng.uniform(0.03, 0.06), z + 0.05, COBBLE, chamfer=0.01)
    return [("Mesh", m, None)]


def road_joint(kind):
    """A 1 x 1 patch for street corners."""
    rng = random.Random("joint" + kind)
    m = Model("joint")
    m.box(-0.5, -0.6, -0.5, 0.5, 0.0, 0.5, COBBLE if kind == "cobble" else DIRT)
    if kind == "cobble":
        for r in range(2):
            for c in range(2):
                x, z = -0.25 + r * 0.5, -0.25 + c * 0.5
                m.box(x - 0.22, 0.0, z - 0.22, x + 0.22, rng.uniform(0.04, 0.085), z + 0.22, COBBLE, chamfer=0.025)
    return [("Mesh", m, None)]


# -- mountains and horizon ------------------------------------------------------------------
def mountain(snow_line, seed):
    """A faceted peak 100 wide (x) and deep (z), 100 high. Rock below, scree, then snow above
    `snow_line` of the height. Scaled by the skyline to anything from a hill to a summit."""
    rng = random.Random("mountain%d" % seed)
    m = Model("mountain")
    segs, rings = 14, 8
    phase = [rng.uniform(0, math.tau) for _ in range(3)]
    ridge = [rng.uniform(0.05, 0.12) for _ in range(3)]
    drift = (rng.uniform(-0.12, 0.12), rng.uniform(-0.1, 0.1))

    def point(ring, seg):
        t = ring / rings
        a = math.tau * seg / segs
        wob = 1.0 + sum(ridge[i] * math.sin(a * (i + 2) + phase[i]) for i in range(3)) * (1.0 - t)
        r = (1.0 - t) ** 0.9 * wob
        y = t ** 0.85 * (1.0 + 0.04 * math.sin(a * 5 + phase[0]) * (1.0 - t))
        ridge_bump = 0.05 * math.sin(a * 4 + phase[1]) * t * (1 - t) * 4
        x = 50.0 * r * math.cos(a) + drift[0] * 100 * t
        z = 37.0 * r * math.sin(a) + drift[1] * 100 * t
        return (x, (y + ridge_bump) * 100.0, z)

    def mat_at(t):
        if t >= snow_line:
            return SNOW
        if t >= snow_line - 0.14:
            return SCREE
        return ROCK

    for ring in range(rings):
        for seg in range(segs):
            a = point(ring, seg)
            b = point(ring, (seg + 1) % segs)
            c = point(ring + 1, (seg + 1) % segs)
            d = point(ring + 1, seg)
            t = (ring + 0.5) / rings
            mat = mat_at(t)
            if ring + 1 == rings:
                m.face([c, b, a], mat)
            else:
                m.face([a, b, c, d][::-1], mat)
    base = [point(0, s) for s in range(segs)]
    m.face(base, ROCK)
    return [("Mesh", m, None)]


def horizon_keep():
    """A ruined curtain wall with towers, 100 wide (x), for the far horizon ring."""
    rng = random.Random("keep")
    m = Model("keep")
    w, h, dpt = 80.0, 20.0, 22.0
    m.box(-w / 2, 0.0, -dpt / 2, w / 2, h, dpt / 2, STONED, chamfer=0.4)
    for k in range(16):
        x = -w / 2 + 2.5 + k * (w - 5) / 15
        if k % 3 == 1:
            continue
        m.box(x - 1.3, h, dpt / 2 - 1.4, x + 1.3, h + 2.6, dpt / 2, STONED, chamfer=0.12)
    for tx in (-w * 0.42, -w * 0.1, w * 0.3):
        th = h * rng.uniform(1.2, 1.7)
        m.tapered_box((tx - 5.5, -5.5, tx + 5.5, 5.5), (tx - 4.6, -4.6, tx + 4.6, 4.6), 0.0, th, STONED, chamfer=0.3)
        m.box(tx - 6.0, th, -6.0, tx + 6.0, th + 1.0, 6.0, STONE, chamfer=0.2)
        m.cone(tx, th + 1.0, 0.0, 6.8, th + 9.5, "tile_grey", sides=8)
    return [("Mesh", m, None)]


def horizon_hill():
    """A terraced rocky hill with a ruined tower, 100 wide."""
    rng = random.Random("hill")
    m = Model("hill")
    total, base_w = 40.0, 100.0
    steps = 5
    for s in range(steps):
        t = s / steps
        w = base_w * (1.0 - t * 0.78)
        d = base_w * 0.6 * (1.0 - t * 0.7)
        ox = rng.uniform(-4, 4)
        m.tapered_box((ox - w / 2, -d / 2, ox + w / 2, d / 2), (ox - w * 0.42, -d * 0.42, ox + w * 0.42, d * 0.42), total * t, total * (t + 1.0 / steps), STONED, chamfer=0.5)
    m.box(-5.0, total, -5.0, 5.0, total + 14.0, 5.0, STONED, chamfer=0.3)
    m.cone(0.0, total + 14.0, 0.0, 6.6, total + 24.0, "tile_grey", sides=8)
    return [("Mesh", m, None)]


def horizon_tower():
    m = Model("tower")
    m.tapered_box((-7.0, -7.0, 7.0, 7.0), (-6.0, -6.0, 6.0, 6.0), 0.0, 26.0, STONED, chamfer=0.3)
    m.box(-7.0, 26.0, -7.0, 7.0, 27.4, 7.0, STONE, chamfer=0.2)
    m.cone(0.0, 27.4, 0.0, 8.0, 41.0, "tile_grey", sides=8)
    for y in (9.0, 17.0):
        for s in (-1, 1):
            m.box(-0.5, y, s * 6.5 - 0.1, 0.5, y + 2.6, s * 6.5 + 0.1, "window")
    return [("Mesh", m, None)]


def tower_cliff():
    """The rock column the tower stands on: a faceted shaft 40 across, 30 tall, stratified."""
    m = Model("cliff")
    segs = 40
    layers = 6
    for ly in range(layers):
        y0, y1 = ly * 30.0 / layers - 30.0, (ly + 1) * 30.0 / layers - 30.0

        def radius(y, s):
            a = math.tau * s / segs
            ridge = 0.035 * math.sin(a * 5 + y * 0.35) + 0.02 * math.sin(a * 11 - y * 0.2)
            return 40.0 * (1.0 + 0.18 * (1.0 - (y + 30.0) / 30.0)) * (1.0 + ridge)

        for s in range(segs):
            s2 = (s + 1) % segs
            a0, a1 = math.tau * s / segs, math.tau * s2 / segs
            mat = STONED if (ly + s // 4) % 3 == 0 else STONE
            r00, r01, r10, r11 = radius(y0, s), radius(y0, s2), radius(y1, s), radius(y1, s2)
            m.face([
                (math.cos(a0) * r00, y0, math.sin(a0) * r00), (math.cos(a1) * r01, y0, math.sin(a1) * r01),
                (math.cos(a1) * r11, y1, math.sin(a1) * r11), (math.cos(a0) * r10, y1, math.sin(a0) * r10),
            ][::-1], mat)
    return [("Mesh", m, None)]


BUILDERS = {
    "skyline/house_1": lambda: house(1, True, 1),
    "skyline/house_2": lambda: house(2, True, 2),
    "skyline/house_far": far_house,
    "skyline/barn": barn,
    "skyline/oak_a": lambda: oak(0), "skyline/oak_b": lambda: oak(1), "skyline/oak_c": lambda: oak(2),
    "skyline/pine_a": lambda: pine(0), "skyline/pine_b": lambda: pine(1),
    "skyline/orchard_tree": orchard_tree,
    "skyline/shrub_a": lambda: shrub(0), "skyline/shrub_b": lambda: shrub(1),
    "skyline/clump_a": lambda: grass_clump(0), "skyline/clump_b": lambda: grass_clump(1), "skyline/clump_c": lambda: grass_clump(2),
    "skyline/fence": fence, "skyline/hedge": hedge, "skyline/well": well,
    "skyline/crop_row": crop_row, "skyline/grazing": grazing,
    "skyline/road_cobble": lambda: road("cobble"), "skyline/road_dirt": lambda: road("dirt"),
    "skyline/joint_cobble": lambda: road_joint("cobble"), "skyline/joint_dirt": lambda: road_joint("dirt"),
    "skyline/mountain_bare": lambda: mountain(1.2, 1),
    "skyline/mountain_high": lambda: mountain(0.74, 2),
    "skyline/mountain_low": lambda: mountain(0.6, 3),
    "skyline/horizon_keep": horizon_keep, "skyline/horizon_hill": horizon_hill, "skyline/horizon_tower": horizon_tower,
    "skyline/tower_cliff": tower_cliff,
}
