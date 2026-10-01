"""Blender builders for distant landmarks: the boss spire, the silhouette and the orientation spire.

Shafts are modelled 10 m tall and 1 m half-width and scaled to each landmark's hint in the game;
their glowing caps are separate models so they keep their proportions.
"""

from __future__ import annotations

import math

from bl_lib import Model

W, A, T, TR, I, DI, ST = "wall", "accent", "timber", "trim", "iron", "darkiron", "steel"
GLOW, TORCHFIRE = "glow", "torchfire"


def boss_spire_shaft():
    """Five tapering tiers, each with a flared collar and buttress fins, like a broken watchtower."""
    m = Model("shaft")
    tiers = 5
    h = 10.0 / tiers
    for i in range(tiers):
        t = i / tiers
        w0 = 1.0 + 0.0 - 0.75 * t
        w1 = 1.0 - 0.75 * (t + 1 / tiers)
        y0, y1 = i * h, (i + 1) * h
        m.tapered_box((-w0, -w0, w0, w0), (-w1 * 1.02, -w1 * 1.02, w1 * 1.02, w1 * 1.02), y0, y1 - 0.12, W, chamfer=0.05)
        m.box(-w1 * 1.12, y1 - 0.12, -w1 * 1.12, w1 * 1.12, y1 + 0.02, w1 * 1.12, A, chamfer=0.03)
        for sx in (-1, 1):
            m.box(sx * w0 - 0.06, y0, -0.12, sx * w0 + 0.06, y0 + h * 0.55, 0.12, W, chamfer=0.01)
            m.box(-0.12, y0, sx * w0 - 0.06, 0.12, y0 + h * 0.55, sx * w0 + 0.06, W, chamfer=0.01)
        for k in range(2):
            wy = y0 + h * (0.3 + 0.35 * k)
            m.box(-0.08, wy, w0 * 0.98 - 0.02, 0.08, wy + 0.3, w0 * 1.02 + 0.02, DI)
    return [("Shaft", m, None)]


def spire_beacon():
    m = Model("beacon")
    m.pyramid(-0.5, -0.5, 0.5, 0.5, 0.0, 0.5, "torchfire")
    m.pyramid(-0.5, -0.5, 0.5, 0.5, 0.0, -0.5, "torchfire")
    return [("Beacon", m, None)]


def boss_silhouette():
    """A hanging chain with a torn banner: 10 m tall, 1 m half-width."""
    m = Model("silhouette")
    links = 18
    for i in range(links):
        y = 0.55 * i + 0.25
        (m.box(-0.1, y, -0.05, 0.1, y + 0.4, 0.05, TR, chamfer=0.02) if i % 2 == 0 else m.box(-0.05, y, -0.1, 0.05, y + 0.4, 0.1, TR, chamfer=0.02))
    cloth = [(-0.42, 10.0), (0.42, 10.0), (0.42, 6.4), (0.2, 6.9), (0.0, 6.0), (-0.2, 6.8), (-0.42, 6.3)]
    m.plate([(x, y, 0.0) for x, y in cloth], (0, 0, 1), 0.06, A)
    m.box(-0.6, 9.9, -0.08, 0.6, 10.1, 0.14, TR, chamfer=0.02)
    return [("Mesh", m, None)]


def orientation_spire_shaft():
    m = Model("shaft")
    m.box(-1.3, 0.0, -1.3, 1.3, 0.5, 1.3, W, chamfer=0.04)
    m.tapered_box((-1.0, -1.0, 1.0, 1.0), (-0.8, -0.8, 0.8, 0.8), 0.5, 9.4, W, chamfer=0.05)
    for y in (3.0, 6.0):
        m.box(-0.95, y, -0.95, 0.95, y + 0.25, 0.95, A, chamfer=0.03)
    m.box(-1.3, 9.4, -1.3, 1.3, 10.0, 1.3, TR, chamfer=0.04)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.tube((sx * 1.05, 9.4, sz * 1.05), (sx * 1.05, 10.7, sz * 1.05), 0.06, 0.06, TR, sides=4)
    return [("Shaft", m, None)]


def spire_lantern():
    m = Model("lantern")
    m.box(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, "torchfire", chamfer=0.05)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.tube((sx * 0.52, -0.5, sz * 0.52), (sx * 0.52, 0.5, sz * 0.52), 0.05, 0.05, TR, sides=4)
    return [("Lantern", m, None)]


def torch_pole():
    m = Model("pole")
    m.tube((0.0, 0.0, 0.18), (0.0, 1.05, 0.18), 0.06, 0.05, TR, sides=6)
    m.box(-0.10, 0.0, 0.08, 0.10, 0.06, 0.28, TR, chamfer=0.01)
    return [("Pole", m, None)]


BUILDERS = {
    "torch_pole": torch_pole,
    "boss_spire_shaft": boss_spire_shaft, "spire_beacon": spire_beacon, "boss_silhouette": boss_silhouette,
    "orientation_spire_shaft": orientation_spire_shaft, "spire_lantern": spire_lantern,
}
