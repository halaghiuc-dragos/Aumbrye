"""Blender builders for the hub's service tents and their interiors.

Tent sizes are read from `SERVICE_TENTS` in `hub_diorama.gd`, so a size change in the game needs
only a rebuild here. Models are built in the tent's own frame: origin at the centre of the floor,
the entrance on +z. Roles are hub material names (canvas, canvas_dark, wood, accent, roof, floor_alt,
wall, paper, forge, hub_iron ...).
"""

from __future__ import annotations

import math
import os
import re

from bl_lib import Model

HERE = os.path.dirname(os.path.abspath(__file__))
HUB_DIORAMA = os.path.join(HERE, "..", "..", "apps", "game", "client", "scripts", "hub", "hub_diorama.gd")

CANVAS, CANVAS_DARK, WOOD, ACCENT, ROOF, FLOOR_ALT, WALL = "canvas", "canvas_dark", "wood", "accent", "roof", "floor_alt", "wall"
PAPER, FORGE, IRON, FLOOR = "paper", "forge", "hub_iron", "floor"


def tent_sizes():
    text = open(HUB_DIORAMA, encoding="utf-8").read()
    sizes = {}
    for name, w, d, wh, en, pk in re.findall(
        r'"(\w+)":\s*\{"width": ([\d.]+), "depth": ([\d.]+), "wall_height": ([\d.]+), "entrance": ([\d.]+), "roof_peak": ([\d.]+)\}', text
    ):
        sizes[name] = dict(width=float(w), depth=float(d), wall_height=float(wh), entrance=float(en), roof_peak=float(pk))
    assert len(sizes) == 4, sizes
    return sizes


def tent_id(cfg):
    return "hub/tent_%d_%d_%d_%d" % tuple(round(cfg[k] * 100) for k in ("width", "depth", "wall_height", "roof_peak"))


def _roof_side(m, sx, hw, wh, peak, depth, mat, stripe_mat):
    """One sloped canvas panel with a slight sag, plus darker stripes and underside battens."""
    eave = (sx * (hw + 0.12), wh - 0.02)
    ridge = (0.0, wh + peak)
    n = 5
    top = []
    for i in range(n + 1):
        t = i / n
        x = eave[0] + (ridge[0] - eave[0]) * t
        y = eave[1] + (ridge[1] - eave[1]) * t - 0.07 * math.sin(math.pi * t)
        top.append((x, y))
    thick = 0.09
    pts = [(x, y, -depth / 2 - 0.25) for x, y in top] + [(x, y - thick, -depth / 2 - 0.25) for x, y in reversed(top)]
    m.plate(pts, (0, 0, 1), depth + 0.5, mat)
    stripes = max(2, int((depth + 0.5) / 1.15))
    for i in range(stripes):
        z = -(depth + 0.5) / 2 + (depth + 0.5) * (i + 0.5) / stripes
        sp = [(x, y + 0.01, z - 0.17) for x, y in top] + [(x, y + 0.05, z - 0.17) for x, y in reversed(top)]
        m.plate(sp, (0, 0, 1), 0.34, stripe_mat)
    batt = max(2, round((depth + 0.5) / 0.95) - 1)
    for i in range(batt):
        z = -(depth + 0.5) / 2 + (depth + 0.5) * (i + 1) / (batt + 1)
        bp = [(x, y - thick - 0.0, z - 0.045) for x, y in top] + [(x, y - thick - 0.07, z - 0.045) for x, y in reversed(top)]
        m.plate(bp, (0, 0, 1), 0.09, WOOD)


def tent(cfg):
    w, d, wh, peak = cfg["width"], cfg["depth"], cfg["wall_height"], cfg["roof_peak"]
    hw, hd = w / 2, d / 2
    ridge_y = wh + peak
    m = Model("tent")
    m.box(-(w + 0.45) / 2, 0.0, -(d + 0.45) / 2, (w + 0.45) / 2, 0.12, (d + 0.45) / 2, FLOOR_ALT, chamfer=0.02)
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * (hw - 0.08), sz * (hd - 0.08)
            m.tube((x, 0.12, z), (x, wh, z), 0.085, 0.075, WOOD, sides=6)
            m.box(x - 0.14, 0.12, z - 0.14, x + 0.14, 0.3, z + 0.14, WOOD, chamfer=0.02)
    for sx in (-1, 1):
        m.box(sx * hw - 0.07, wh - 0.02, -(d + 0.3) / 2, sx * hw + 0.07, wh + 0.12, (d + 0.3) / 2, WOOD, chamfer=0.015)
    for sz in (-1, 1):
        m.tube((0.0, 0.12, sz * (hd - 0.1)), (0.0, ridge_y, sz * (hd - 0.1)), 0.1, 0.085, WOOD, sides=6)
    m.box(-0.08, ridge_y - 0.08, -(d + 0.55) / 2, 0.08, ridge_y + 0.08, (d + 0.55) / 2, WOOD, chamfer=0.012)
    for sx in (-1, 1):
        _roof_side(m, sx, hw, wh, peak, d, CANVAS, CANVAS_DARK)
    # Walls: canvas panels with seams and a stitched hem.
    thick = 0.16
    for sx in (-1, 1):
        m.box(sx * hw - thick / 2, 0.12, -hd, sx * hw + thick / 2, wh, hd, CANVAS, chamfer=0.01)
        seams = max(2, int(d / 1.15))
        for i in range(seams):
            z = -hd + d * (i + 0.5) / seams
            m.box(sx * hw - thick / 2 - 0.025, 0.14, z - 0.05, sx * hw + thick / 2 + 0.025, wh - 0.02, z + 0.05, CANVAS_DARK)
        m.box(sx * hw - thick / 2 - 0.035, 0.12, -hd, sx * hw + thick / 2 + 0.035, 0.24, hd, CANVAS_DARK)
    m.box(-hw, 0.12, -hd - thick / 2, hw, wh, -hd + thick / 2, CANVAS, chamfer=0.01)
    back_seams = max(2, int(w / 1.15))
    for i in range(back_seams):
        x = -hw + w * (i + 0.5) / back_seams
        m.box(x - 0.05, 0.14, -hd - thick / 2 - 0.025, x + 0.05, wh - 0.02, -hd + thick / 2 + 0.025, CANVAS_DARK)
    # Stepped gable above the back wall.
    steps = 5
    seg = peak / steps
    for i in range(steps):
        sw = w * (1 - i / steps) * 0.96
        if sw > 0.05:
            m.box(-sw / 2, wh + seg * i, -hd - thick / 2, sw / 2, wh + seg * (i + 1), -hd + thick / 2, CANVAS_DARK)
    slope = math.atan2(peak, hw)
    slope_len = math.hypot(hw, peak)
    for sx in (-1, 1):
        # Barge boards along the front gable edge.
        a = (sx * (hw + 0.1), wh + 0.0, hd + 0.26)
        b = (0.0, ridge_y + 0.06, hd + 0.26)
        m.tube(a, b, 0.08, 0.07, ACCENT, sides=4)
    scallops = max(3, int(w / 0.62))
    for i in range(scallops):
        t = (i + 0.5) / scallops
        x = -hw + w * t
        drop = 0.16 + 0.12 * math.sin(t * math.pi)
        sw = w / scallops * 0.86
        m.plate([(x - sw / 2, wh + 0.06, hd + 0.2), (x + sw / 2, wh + 0.06, hd + 0.2), (x + sw / 2, wh + 0.06 - drop * 0.6, hd + 0.2), (x, wh + 0.06 - drop, hd + 0.2), (x - sw / 2, wh + 0.06 - drop * 0.6, hd + 0.2)], (0, 0, 1), 0.08, ACCENT)
    for sx in (-1, 1):
        m.box(sx * (hw - 0.32) - 0.25, 0.12, hd - 0.16, sx * (hw - 0.32) + 0.25, wh * 0.82, hd - 0.04, CANVAS, chamfer=0.01)
        m.box(sx * (hw - 0.12) - 0.1, wh * 0.56 - 0.05, hd - 0.12, sx * (hw - 0.12) + 0.1, wh * 0.56 + 0.05, hd - 0.0, WOOD, chamfer=0.01)
    # Guy ropes and pegs.
    def rope(p0, p1):
        m.tube(p0, p1, 0.03, 0.03, WOOD, sides=4)
        peg = (p1[0], p1[1] + 0.3, p1[2])
        m.tube((p1[0], p1[1] - 0.05, p1[2]), peg, 0.05, 0.04, WOOD, sides=4)

    for side in (-1, 1):
        for i in range(2):
            z = -hd * 0.62 + i * hd * 0.78
            rope((side * hw, wh - 0.1, z), (side * (hw + 0.95), 0.02, z))
        rope((side * hw * 0.62, wh + peak * 0.5, -hd), (side * hw * 0.62, 0.02, -hd - 0.95))
    for side in (-1, 1):
        m.box(side * (hw + 0.12) - 0.08, wh - 0.09, -(d + 0.5) / 2, side * (hw + 0.12) + 0.08, wh + 0.05, (d + 0.5) / 2, ROOF, chamfer=0.01)
    for sz in (-1, 1):
        m.tube((0.0, ridge_y + 0.0, sz * (hd + 0.24)), (0.0, ridge_y + 0.45, sz * (hd + 0.24)), 0.08, 0.04, ROOF, sides=4)
        m.pyramid(-0.1, sz * (hd + 0.24) - 0.1, 0.1, sz * (hd + 0.24) + 0.1, ridge_y + 0.35, ridge_y + 0.55, ROOF)
    return [("Mesh", m, None)]


def _sized(name):
    return tent_sizes()[name]


# -------------------------------------------------------------------------------- interiors

def dressing_blacksmith():
    cfg = _sized("Blacksmith")
    back = -cfg["depth"] / 2 + 0.9
    m = Model("dressing")
    f = Model("Forge")
    f.box(1.3 - 0.55, 0.0, back - 0.5, 1.3 + 0.55, 0.9, back + 0.5, FORGE, chamfer=0.04)
    f.box(1.3 - 0.4, 0.88, back - 0.4, 1.3 + 0.4, 0.98, back + 0.4, FORGE, chamfer=0.03)
    m.box(1.3 - 0.225, 0.9, back - 0.225, 1.3 + 0.225, 1.95, back + 0.225, WALL, chamfer=0.03)
    m.box(1.3 - 0.32, 0.0, back - 0.56, 1.3 + 0.32, 0.12, back + 0.56, WALL, chamfer=0.02)
    m.box(-0.75, 0.0, back + 0.1, -0.05, 0.12, back + 0.6, WALL, chamfer=0.02)
    # Anvil: waisted body, horn and face.
    m.box(-0.62, 0.12, back + 0.2, -0.18, 0.36, back + 0.5, WALL, chamfer=0.02)
    m.box(-0.74, 0.36, back + 0.17, -0.05, 0.72, back + 0.53, ACCENT, chamfer=0.02)
    m.tube((-0.74, 0.6, back + 0.35), (-1.0, 0.6, back + 0.35), 0.1, 0.03, ACCENT, sides=4)
    m.box(-2.0, 0.0, back - 0.8, -0.2, 0.85, back - 0.2, WOOD, chamfer=0.03)
    m.box(-2.05, 0.85, back - 0.85, -0.15, 0.93, back - 0.15, ROOF, chamfer=0.02)
    for x in (-1.75, -1.25, -0.75):
        m.box(x - 0.1, 0.93, back - 0.6, x + 0.1, 1.05, back - 0.4, WALL, chamfer=0.01)
    m.box(-2.02, 0.0, back - 0.52, -1.78, 1.25, back - 0.28, ACCENT, chamfer=0.02)
    for k in range(3):
        m.tube((-1.9, 0.95 + 0.14 * k, back - 0.28), (-1.9 - 0.15, 0.85 + 0.14 * k, back - 0.28), 0.018, 0.018, WALL, sides=4)
    return [("Mesh", m, None), ("Forge", f, None)]


def dressing_merchant():
    cfg = _sized("Merchant")
    back = -cfg["depth"] / 2 + 0.6
    w = cfg["width"]
    m = Model("dressing")
    m.box(-1.5, 0.0, back - 0.3, 1.5, 0.95, back + 0.3, WOOD, chamfer=0.03)
    m.box(-1.56, 0.95, back - 0.36, 1.56, 1.02, back + 0.36, ROOF, chamfer=0.015)
    for i in range(4):
        x = -1.05 + i * 0.7
        mat = ACCENT if i % 2 == 0 else FLOOR
        if i % 2 == 0:
            m.cylinder(x, 1.02, back, 0.2, 1.24, mat, sides=8, r_top=0.14)
        else:
            m.box(x - 0.22, 1.02, back - 0.2, x + 0.22, 1.18, back + 0.2, mat, chamfer=0.02)
    for sx in (-1, 1):
        x = sx * 1.7
        z = back + (0.9 if sx < 0 else 1.0)
        m.box(x - 0.3, 0.0, z - 0.3, x + 0.3, 0.6, z + 0.3, ACCENT, chamfer=0.02)
        m.box(x - 0.32, 0.26, z - 0.32, x + 0.32, 0.34, z + 0.32, ROOF, chamfer=0.01)
    for sx in (-1, 1):
        x = sx * (w * 0.5 - 0.3)
        z0, z1 = back + 0.6 - 0.9, back + 0.6 + 0.9
        m.box(x - 0.14, 0.35, z0, x + 0.14, 1.65, z1, WOOD, chamfer=0.02)
        for y in (0.7, 1.05, 1.4):
            m.box(x - 0.17, y, z0 + 0.05, x + 0.17, y + 0.05, z1 - 0.05, ROOF, chamfer=0.01)
        for k in range(3):
            m.sphere(x, 0.78 + 0.35 * (k % 3), z0 + 0.3 + 0.3 * k, 0.07, ACCENT, sides=6, rings=3)
    return [("Mesh", m, None)]


def dressing_storage():
    cfg = _sized("Storage")
    back = -cfg["depth"] / 2 + 0.4
    m = Model("dressing")
    m.box(-1.7, 0.0, back - 0.15, 1.7, 1.8, back + 0.15, WOOD, chamfer=0.03)
    for y in (0.45, 0.95, 1.45):
        m.box(-1.75, y, back - 0.2, 1.75, y + 0.06, back + 0.3, ROOF, chamfer=0.01)
    for i in range(3):
        x = -1.05 + i * 1.05
        m.box(x - 0.4, 0.95 + 0.06, back + 0.02, x + 0.4, 1.45, back + 0.47, ACCENT, chamfer=0.02)
        m.box(x - 0.42, 1.15, back + 0.0, x + 0.42, 1.2, back + 0.49, ROOF)
    for sx in (-1, 1):
        x, z = sx * 1.9, back + 1.1
        m.loft(
            [dict(y=0.0, cx=x, cz=z, rx=0.3, rz=0.3), dict(y=0.3, cx=x, cz=z, rx=0.37, rz=0.37), dict(y=0.6, cx=x, cz=z, rx=0.38, rz=0.38), dict(y=0.9, cx=x, cz=z, rx=0.31, rz=0.31)],
            WOOD, sides=12, power=2.0, mat_fn=lambda i, k, n: ROOF if k % 3 == 0 else WOOD, top_mat=ROOF,
        )
        for y in (0.15, 0.45, 0.75):
            m.loft([dict(y=y - 0.03, cx=x, cz=z, rx=0.39, rz=0.39), dict(y=y + 0.03, cx=x, cz=z, rx=0.39, rz=0.39)], ACCENT, sides=12, power=2.0, cap_bottom=False, cap_top=False)
    m.box(-0.3, 0.0, back + 1.4, 0.3, 0.3, back + 1.8, ACCENT, chamfer=0.02)
    return [("Mesh", m, None)]


def dressing_questboard():
    cfg = _sized("QuestBoard")
    back = -cfg["depth"] / 2 + 0.2
    m = Model("dressing")
    m.box(-1.4, 0.4, back - 0.07, 1.4, 2.1, back + 0.07, WOOD, chamfer=0.02)
    for sx in (-1, 1):
        m.box(sx * 1.3 - 0.07, 0.0, back - 0.1, sx * 1.3 + 0.07, 2.2, back + 0.1, WOOD, chamfer=0.015)
    m.box(-1.25, 0.52, back + 0.07, 1.25, 1.98, back + 0.13, ACCENT, chamfer=0.01)
    for i in range(5):
        x = -0.96 + i * 0.48
        y = 1.16 + ((i * 5) % 3) * 0.2
        m.box(x - 0.21, y - 0.3, back + 0.13, x + 0.21, y + 0.3, back + 0.16, PAPER, chamfer=0.004)
        m.sphere(x, y + 0.24, back + 0.18, 0.025, IRON, sides=5, rings=2)
    m.box(1.5 - 0.22, 0.0, 0.5 - 0.22, 1.5 + 0.22, 0.45, 0.5 + 0.22, WOOD, chamfer=0.02)
    m.box(-1.45, 2.1, back - 0.12, 1.45, 2.18, back + 0.16, ROOF, chamfer=0.01)
    return [("Mesh", m, None)]


def porch_post():
    """A lantern post 3 m tall with an arm reaching toward +x; flipped in code for the other side."""
    m = Model("porch_post")
    m.tube((0.0, 0.0, 0.0), (0.0, 3.0, 0.0), 0.085, 0.07, WOOD, sides=6)
    m.box(-0.14, 0.0, -0.14, 0.14, 0.14, 0.14, WOOD, chamfer=0.02)
    m.box(-0.0, 2.9, -0.06, 0.46, 3.0, 0.06, WOOD, chamfer=0.01)
    m.tube((0.03, 2.75, 0.0), (0.28, 2.93, 0.0), 0.03, 0.03, WOOD, sides=4)
    return [("Mesh", m, None)]


def lantern():
    m = Model("lantern")
    m.box(-0.14, 0.15, -0.14, 0.14, 0.23, 0.14, ACCENT, chamfer=0.01)
    m.pyramid(-0.12, -0.12, 0.12, 0.12, 0.23, 0.31, ACCENT)
    m.box(-0.12, -0.15, -0.12, 0.12, 0.15, 0.12, "glass", chamfer=0.01)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.tube((sx * 0.125, -0.15, sz * 0.125), (sx * 0.125, 0.15, sz * 0.125), 0.012, 0.012, ACCENT, sides=4)
    m.box(-0.14, -0.2, -0.14, 0.14, -0.15, 0.14, ACCENT, chamfer=0.008)
    return [("Mesh", m, None)]


def ridge_sign():
    m = Model("ridge_sign")
    m.box(-0.06, -0.5, -0.06, 0.06, 0.0, 0.06, WOOD, chamfer=0.008)
    m.box(-0.625, -0.55, -0.07, 0.625, -0.45, 0.07, WOOD, chamfer=0.01)
    for sx in (-1, 1):
        m.box(sx * 0.42 - 0.035, -0.69, -0.035, sx * 0.42 + 0.035, -0.47, 0.035, WOOD)
    m.box(-0.525, -1.17, -0.05, 0.525, -0.55, 0.05, ACCENT, chamfer=0.015)
    m.box(-0.45, -1.1, 0.05, 0.45, -0.62, 0.07, WOOD, chamfer=0.01)
    m.box(-0.05, -1.0, 0.07, 0.05, -0.72, 0.085, ACCENT)
    m.box(-0.2, -0.92, 0.07, 0.2, -0.85, 0.085, ACCENT)
    return [("Mesh", m, None)]


def door_pad():
    """A paving slab 1 m wide and 1.2 deep, scaled to each tent's doorway."""
    m = Model("door_pad")
    m.box(-0.5, 0.0, -0.6, 0.5, 0.12, 0.6, FLOOR_ALT, chamfer=0.015)
    m.box(-0.03, 0.12, -0.6, 0.03, 0.125, 0.6, FLOOR)
    return [("Mesh", m, None)]


def _tent_builders():
    out = {}
    for name, cfg in tent_sizes().items():
        out[tent_id(cfg)] = (lambda c=cfg: tent(c))
    return out


BUILDERS = {
    "hub/dressing_blacksmith": dressing_blacksmith, "hub/dressing_merchant": dressing_merchant,
    "hub/dressing_storage": dressing_storage, "hub/dressing_questboard": dressing_questboard,
    "hub/porch_post": porch_post, "hub/lantern": lantern, "hub/ridge_sign": ridge_sign, "hub/door_pad": door_pad,
}
BUILDERS.update(_tent_builders())
