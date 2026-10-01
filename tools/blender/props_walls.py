"""Blender builders for wall relief: base trim, cornices, pilasters and capitals, in six biome styles.

Modules face +z (the room's interior once the game turns them) and are 2 m long. The base sits on
the floor (origin at its bottom), the cornice hangs from the wall top (origin at its top edge), the
pilaster shaft is one metre tall and scaled to the wall, and the capital caps it.
"""

from __future__ import annotations

import math
import random

from bl_lib import Model

W, A, T, TR, I, DI, ST = "wall", "accent", "timber", "trim", "iron", "darkiron", "steel"
GLOW, CRYSTAL, FLAME = "glow", "crystal", "flame"
STYLES = ["castle", "crystal", "swamp", "frozen", "vault", "cathedral"]
L = 2.0  # module length


def base(style):
    m = Model("base")
    m.box(-L / 2, 0.0, -0.02, L / 2, 0.30, 0.14, W, chamfer=0.03)
    m.box(-L / 2, 0.30, -0.02, L / 2, 0.38, 0.10, A, chamfer=0.02)
    rng = random.Random("base/" + style)
    if style == "vault":
        m.box(-L / 2, 0.05, 0.14, L / 2, 0.25, 0.17, I, chamfer=0.01)
        for k in range(6):
            m.sphere(-0.85 + k * 0.34, 0.15, 0.175, 0.025, ST, sides=5, rings=2)
    elif style == "crystal":
        for k in range(4):
            x = -0.8 + k * 0.5 + rng.uniform(-0.1, 0.1)
            m.tube((x, 0.3, 0.05), (x + 0.03, 0.3 + rng.uniform(0.15, 0.3), 0.08), 0.045, 0.006, CRYSTAL, sides=4)
    elif style == "swamp":
        for k in range(6):
            x = -0.9 + k * 0.36
            m.sphere(x, 0.30, 0.08, 0.1, A, sides=6, rings=3, ry=0.07)
    elif style == "frozen":
        for k in range(5):
            x = -0.85 + k * 0.42
            m.pyramid(x - 0.06, 0.02, x + 0.06, 0.13, 0.30, 0.42, CRYSTAL)
    elif style == "cathedral":
        for k in range(8):
            x = -0.9 + k * 0.26
            m.box(x - 0.05, 0.05, 0.14, x + 0.05, 0.27, 0.17, A, chamfer=0.006)
    else:
        for k in range(4):
            x = -0.75 + k * 0.5
            m.box(x - 0.2, 0.04, 0.14, x + 0.2, 0.26, 0.16, A, chamfer=0.01)
    return [("Mesh", m, None)]


def cornice(style):
    m = Model("cornice")
    m.box(-L / 2, -0.36, -0.02, L / 2, -0.24, 0.14, W, chamfer=0.02)
    m.box(-L / 2, -0.24, -0.02, L / 2, -0.10, 0.22, A, chamfer=0.03)
    m.box(-L / 2, -0.10, -0.02, L / 2, 0.0, 0.26, W, chamfer=0.03)
    rng = random.Random("cornice/" + style)
    if style == "vault":
        m.tube((-L / 2, -0.30, 0.19), (L / 2, -0.30, 0.19), 0.045, 0.045, I, sides=6)
        for x in (-0.9, 0.0, 0.9):
            m.box(x - 0.05, -0.34, 0.14, x + 0.05, -0.26, 0.24, ST, chamfer=0.01)
    elif style == "cathedral":
        for k in range(10):
            x = -0.9 + k * 0.2
            m.box(x - 0.045, -0.24, 0.22, x + 0.045, -0.12, 0.29, A, chamfer=0.008)
    elif style in ("frozen",):
        for k in range(12):
            x = -0.92 + k * 0.167 + rng.uniform(-0.02, 0.02)
            ln = rng.uniform(0.18, 0.5)
            m.tube((x, -0.36, 0.08), (x + 0.01, -0.36 - ln, 0.09), 0.03, 0.004, CRYSTAL, sides=4)
    elif style == "swamp":
        for k in range(9):
            x = -0.9 + k * 0.225
            ln = rng.uniform(0.2, 0.7)
            m.tube((x, -0.36, 0.1), (x + rng.uniform(-0.04, 0.04), -0.36 - ln, 0.12), 0.02, 0.008, A, sides=4)
    elif style == "crystal":
        for k in range(6):
            x = -0.83 + k * 0.33
            m.pyramid(x - 0.07, 0.02, x + 0.07, 0.16, -0.36, -0.52, CRYSTAL)
    else:
        for k in range(5):
            x = -0.8 + k * 0.4
            m.box(x - 0.09, -0.36, 0.06, x + 0.09, -0.24, 0.2, A, chamfer=0.012)
    return [("Mesh", m, None)]


def pilaster(style):
    """A one-metre shaft, 0.5 wide and 0.18 proud; the game scales it to the wall."""
    m = Model("pilaster")
    if style == "cathedral":
        for x in (-0.15, 0.0, 0.15):
            m.tube((x, 0.0, 0.11), (x, 1.0, 0.11), 0.06, 0.06, W, sides=8)
        m.box(-0.24, 0.0, 0.0, 0.24, 1.0, 0.06, W, chamfer=0.01)
    elif style == "vault":
        m.box(-0.22, 0.0, 0.0, 0.22, 1.0, 0.18, I, chamfer=0.015)
        for y in (0.15, 0.5, 0.85):
            m.box(-0.25, y - 0.03, 0.0, 0.25, y + 0.03, 0.2, ST, chamfer=0.01)
        for k in range(2):
            m.tube((-0.14 + 0.28 * k, 0.0, 0.2), (-0.14 + 0.28 * k, 1.0, 0.2), 0.03, 0.03, DI, sides=6)
    elif style == "crystal":
        m.box(-0.24, 0.0, 0.0, 0.24, 1.0, 0.16, W, chamfer=0.02)
        for k, (x, h) in enumerate([(-0.1, 0.55), (0.08, 0.8), (0.16, 0.4)]):
            m.tube((x, 0.0, 0.16), (x, h, 0.2), 0.045, 0.006, CRYSTAL, sides=4)
    elif style == "swamp":
        m.box(-0.23, 0.0, 0.0, 0.23, 1.0, 0.15, W, chamfer=0.03)
        for k in range(3):
            m.tube((-0.15 + 0.15 * k, 0.0, 0.16), (-0.1 + 0.1 * k, 1.0, 0.19), 0.03, 0.02, A, sides=5)
    elif style == "frozen":
        m.box(-0.24, 0.0, 0.0, 0.24, 1.0, 0.16, W, chamfer=0.02)
        for k in range(3):
            m.tube((-0.12 + 0.12 * k, 0.0, 0.16), (-0.12 + 0.12 * k, 0.5 + 0.15 * k, 0.2), 0.04, 0.005, CRYSTAL, sides=4)
    else:
        m.box(-0.25, 0.0, 0.0, 0.25, 1.0, 0.18, W, chamfer=0.025)
        for y in (0.25, 0.5, 0.75):
            m.box(-0.25, y, 0.0, 0.25, y + 0.03, 0.2, A, chamfer=0.01)
    return [("Mesh", m, None)]


def capital(style):
    """The top 0.3 m of a pilaster; origin at its bottom."""
    m = Model("capital")
    m.box(-0.29, 0.0, 0.0, 0.29, 0.14, 0.24, A, chamfer=0.02)
    m.box(-0.33, 0.14, 0.0, 0.33, 0.3, 0.3, W, chamfer=0.03)
    if style == "cathedral":
        m.pyramid(-0.2, 0.0, 0.2, 0.2, 0.3, 0.55, A)
    elif style == "vault":
        m.box(-0.2, 0.3, 0.0, 0.2, 0.34, 0.26, I, chamfer=0.01)
    elif style in ("crystal", "frozen"):
        m.tube((0.0, 0.3, 0.12), (0.02, 0.62, 0.14), 0.07, 0.006, CRYSTAL, sides=4)
    return [("Mesh", m, None)]


BUILDERS = {}
for _s in STYLES:
    BUILDERS["walls/base_" + _s] = (lambda s=_s: base(s))
    BUILDERS["walls/cornice_" + _s] = (lambda s=_s: cornice(s))
    BUILDERS["walls/pilaster_" + _s] = (lambda s=_s: pilaster(s))
    BUILDERS["walls/capital_" + _s] = (lambda s=_s: capital(s))
