"""Blender builders for the village landmarks behind the hub: castle, church, windmill and market.

Built at the sizes the skyline places them (castle x1.0, church x1.15). Roles are the skyline's own
material names: stone, stone_dark, tile_grey, thatch, timber, canvas, canvas_red, iron and window.
"""

from __future__ import annotations

import math

from bl_lib import Model

S, SD, ROOF, THATCH, TIM = "stone", "stone_dark", "tile_grey", "thatch", "timber"
CANVAS, RED, IRON, WIN = "canvas", "canvas_red", "iron", "window"


def _gable_roof(m, x0, z0, x1, z1, y, peak, mat, gable_mat, overhang=0.35, ridge_along_x=True):
    """A simple gabled roof over a rectangle, with stone gable ends and a ridge beam."""
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    if ridge_along_x:
        hl, hw = (x1 - x0) / 2 + overhang, (z1 - z0) / 2 + overhang
        # two slopes as slabs
        for zs in (-1, 1):
            pts = [(cx - hl, y, cz + zs * hw), (cx + hl, y, cz + zs * hw), (cx + hl, y + peak, cz), (cx - hl, y + peak, cz)]
            m.plate(pts, (0, 0.22, 0), 0.22, mat)
        m.box(cx - hl, y + peak - 0.08, cz - 0.12, cx + hl, y + peak + 0.16, cz + 0.12, TIM, chamfer=0.03)
        for xs in (-1, 1):
            xg = cx + xs * (hl - overhang)
            m.plate([(xg, y, cz - hw + overhang), (xg, y, cz + hw - overhang), (xg, y + peak * 0.92, cz)], (xs, 0, 0), 0.3, gable_mat)
    else:
        hl, hw = (z1 - z0) / 2 + overhang, (x1 - x0) / 2 + overhang
        for xs in (-1, 1):
            pts = [(cx + xs * hw, y, cz - hl), (cx + xs * hw, y, cz + hl), (cx, y + peak, cz + hl), (cx, y + peak, cz - hl)]
            m.plate(pts, (0, 0.22, 0), 0.22, mat)
        m.box(cx - 0.12, y + peak - 0.08, cz - hl, cx + 0.12, y + peak + 0.16, cz + hl, TIM, chamfer=0.03)
        for zs in (-1, 1):
            zg = cz + zs * (hl - overhang)
            m.plate([(cx - hw + overhang, y, zg), (cx + hw - overhang, y, zg), (cx, y + peak * 0.92, zg)], (0, 0, zs), 0.3, gable_mat)


def _pyramid_roof(m, cx, cz, half, y, peak, mat, sides=4):
    m.cone(cx, y, cz, half * 1.32, y + peak, mat, sides=sides)


def _crenel(m, x0, z0, x1, z1, y, mat, count_x, count_z, h=0.9, w=0.8):
    for i in range(count_x):
        x = x0 + (x1 - x0) * (i + 0.5) / count_x
        for z in (z0, z1):
            m.box(x - w / 2, y, z - 0.4, x + w / 2, y + h, z + 0.4, mat, chamfer=0.05)
    for j in range(count_z):
        z = z0 + (z1 - z0) * (j + 0.5) / count_z
        for x in (x0, x1):
            m.box(x - 0.4, y, z - w / 2, x + 0.4, y + h, z + w / 2, mat, chamfer=0.05)


def castle():
    m = Model("castle")
    bailey, wall_h = 20.0, 6.5
    hb = bailey / 2
    for side in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        sx, sz = side
        if sz:
            m.box(-hb, 0.0, sz * hb - 0.9, hb, wall_h, sz * hb + 0.9, SD, chamfer=0.08)
            _crenel(m, -hb + 0.5, sz * hb, hb - 0.5, sz * hb, wall_h, SD, 11, 0)
        else:
            m.box(sx * hb - 0.9, 0.0, -hb, sx * hb + 0.9, wall_h, hb, SD, chamfer=0.08)
            _crenel(m, sx * hb, -hb + 0.5, sx * hb, hb - 0.5, wall_h, SD, 0, 11)
    # Gatehouse arch in the +z wall.
    m.box(-2.2, 0.0, hb - 1.4, 2.2, 7.5, hb + 1.4, S, chamfer=0.08)
    m.box(-1.3, 0.0, hb + 1.3, 1.3, 4.0, hb + 1.45, "iron", chamfer=0.04)
    for cx, cz in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        x, z = cx * hb, cz * hb
        t_h = wall_h * 1.7
        m.tapered_box((x - 2.2, z - 2.2, x + 2.2, z + 2.2), (x - 2.0, z - 2.0, x + 2.0, z + 2.0), 0.0, t_h, SD, chamfer=0.1)
        m.box(x - 2.5, t_h, z - 2.5, x + 2.5, t_h + 0.5, z + 2.5, S, chamfer=0.05)
        _pyramid_roof(m, x, z, 2.0, t_h + 0.5, 5.0, ROOF, sides=8)
        for y in (t_h * 0.45, t_h * 0.75):
            for sx in (-1, 1):
                m.box(x - 0.2, y, z + sx * 2.05, x + 0.2, y + 1.1, z + sx * 2.12, "window")
    keep = 11.0
    kh = 24.0
    m.box(-(keep + 2) / 2, 0.0, -(keep + 2) / 2, (keep + 2) / 2, 2.4, (keep + 2) / 2, S, chamfer=0.08)
    m.tapered_box((-keep / 2, -keep / 2, keep / 2, keep / 2), (-keep / 2 + 0.2, -keep / 2 + 0.2, keep / 2 - 0.2, keep / 2 - 0.2), 2.4, kh, SD, chamfer=0.1)
    for storey in range(3):
        y = kh * (0.3 + storey * 0.22)
        m.box(-keep / 2 - 0.3, y, -keep / 2 - 0.3, keep / 2 + 0.3, y + 0.4, keep / 2 + 0.3, S, chamfer=0.04)
        for pane in range(2):
            x = (pane - 0.5) * keep * 0.44
            m.box(x - 0.45, y + 1.3, keep / 2 - 0.05, x + 0.45, y + 3.1, keep / 2 + 0.12, "window", chamfer=0.03)
            m.pyramid(x - 0.6, keep / 2 + 0.0, x + 0.6, keep / 2 + 0.3, y + 3.1, y + 3.6, S)
    m.box(-(keep + 1.6) / 2, kh, -(keep + 1.6) / 2, (keep + 1.6) / 2, kh + 1.0, (keep + 1.6) / 2, S, chamfer=0.05)
    _crenel(m, -keep / 2, -keep / 2, keep / 2, keep / 2, kh + 1.0, SD, 5, 5, h=1.0, w=1.0)
    for cx, cz in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        x, z = cx * keep * 0.44, cz * keep * 0.44
        m.tapered_box((x - 1.3, z - 1.3, x + 1.3, z + 1.3), (x - 1.15, z - 1.15, x + 1.15, z + 1.15), kh + 1.0, kh + 6.0, SD, chamfer=0.06)
        _pyramid_roof(m, x, z, 1.2, kh + 6.0, 3.4, ROOF, sides=6)
    # Great hall against the north wall.
    hall_z = -bailey * 0.28
    m.box(-bailey * 0.35, 0.0, hall_z - 3.5, bailey * 0.35, wall_h * 1.3, hall_z + 3.5, S, chamfer=0.08)
    _gable_roof(m, -bailey * 0.35, hall_z - 3.5, bailey * 0.35, hall_z + 3.5, wall_h * 1.3, 4.0, ROOF, S, ridge_along_x=True)
    for k in range(5):
        x = -bailey * 0.3 + k * bailey * 0.15
        m.box(x - 0.45, 2.0, hall_z + 3.4, x + 0.45, 6.0, hall_z + 3.55, "window", chamfer=0.03)
        m.pyramid(x - 0.6, hall_z + 3.4, x + 0.6, hall_z + 3.8, 6.0, 6.7, S)
    return [("Mesh", m, None)]


def church():
    sc = 1.15
    m = Model("church")
    nave_w, nave_l, nave_h = 8.0 * sc, 20.0 * sc, 9.0 * sc
    m.box(-nave_l / 2, 0.0, -(nave_w + 1) / 2, nave_l / 2, 1.0, (nave_w + 1) / 2, S, chamfer=0.06)
    m.box(-nave_l / 2, 1.0, -nave_w / 2, nave_l / 2, nave_h, nave_w / 2, S, chamfer=0.08)
    _gable_roof(m, -nave_l / 2, -nave_w / 2, nave_l / 2, nave_w / 2, nave_h, nave_w * 0.45, ROOF, S, ridge_along_x=True)
    for sz in (-1, 1):
        aisle_h = nave_h * 0.55
        zc = sz * (nave_w * 0.5 + 2.0 * sc)
        m.box(-nave_l * 0.43, 0.0, zc - 2.0 * sc, nave_l * 0.43, aisle_h, zc + 2.0 * sc, S, chamfer=0.06)
        _gable_roof(m, -nave_l * 0.43, zc - 2.0 * sc, nave_l * 0.43, zc + 2.0 * sc, aisle_h, 1.5 * sc, ROOF, S, ridge_along_x=True)
    for bay in range(5):
        x = ((bay + 0.5) / 5 - 0.5) * nave_l
        for sz in (-1, 1):
            zb = sz * (nave_w * 0.5 + 4.4 * sc)
            m.box(x - 0.5 * sc, 0.0, zb - 0.7 * sc, x + 0.5 * sc, nave_h * 0.8, zb + 0.7 * sc, S, chamfer=0.05)
            m.tube((x, nave_h * 0.75, zb - sz * 0.0), (x, nave_h * 0.55, zb - sz * 2.2 * sc), 0.25 * sc, 0.2 * sc, S, sides=4)
            # Tall windows between buttresses.
            m.box(x - 0.6 * sc, 2.4, sz * (nave_w / 2) - 0.05 + (0.05 if sz > 0 else 0), x + 0.6 * sc, 6.8, sz * (nave_w / 2) + 0.1 * sz, "window")
    tower_w = 6.5 * sc
    tower_h = nave_h * 2.1
    tx = -nave_l * 0.5 - tower_w * 0.4
    m.tapered_box((tx - tower_w / 2, -tower_w / 2, tx + tower_w / 2, tower_w / 2), (tx - tower_w / 2 + 0.25, -tower_w / 2 + 0.25, tx + tower_w / 2 - 0.25, tower_w / 2 - 0.25), 0.0, tower_h, S, chamfer=0.08)
    for y in (tower_h * 0.35, tower_h * 0.6):
        m.box(tx - tower_w / 2 - 0.15, y, -tower_w / 2 - 0.15, tx + tower_w / 2 + 0.15, y + 0.4, tower_w / 2 + 0.15, S, chamfer=0.03)
    for sz in (-1, 1):
        m.box(tx - 0.8 * sc, tower_h * 0.74, sz * tower_w / 2 - 0.1, tx + 0.8 * sc, tower_h * 0.92, sz * tower_w / 2 + 0.1, "stone_dark", chamfer=0.03)
        m.box(tx + sz * tower_w / 2 - 0.1, tower_h * 0.74, -0.8 * sc, tx + sz * tower_w / 2 + 0.1, tower_h * 0.92, 0.8 * sc, "stone_dark", chamfer=0.03)
    m.box(tx - tower_w / 2 - 0.5, tower_h, -tower_w / 2 - 0.5, tx + tower_w / 2 + 0.5, tower_h + 0.7 * sc, tower_w / 2 + 0.5, S, chamfer=0.05)
    for cx, cz in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        x, z = tx + cx * tower_w * 0.42, cz * tower_w * 0.42
        m.box(x - 0.5 * sc, tower_h + 0.7 * sc, z - 0.5 * sc, x + 0.5 * sc, tower_h + 2.3 * sc, z + 0.5 * sc, S, chamfer=0.04)
        m.cone(x, tower_h + 2.3 * sc, z, 0.5 * sc, tower_h + 3.4 * sc, ROOF, sides=4)
    spire_h = tower_h * 0.75
    m.cone(tx, tower_h + 1.0 * sc, 0.0, tower_w * 0.5, tower_h + 1.0 * sc + spire_h, ROOF, sides=8)
    m.tube((tx, tower_h + spire_h + 1.0 * sc, 0), (tx, tower_h + spire_h + 3.0 * sc, 0), 0.12, 0.08, IRON, sides=4)
    m.box(tx - 0.55, tower_h + spire_h + 2.2 * sc, -0.05, tx + 0.55, tower_h + spire_h + 2.45 * sc, 0.05, IRON)
    return [("Mesh", m, None)]


def windmill():
    m = Model("windmill")
    h = 11.0
    m.loft([dict(y=0.0, rx=2.75, rz=2.75), dict(y=h * 0.5, rx=2.15, rz=2.15), dict(y=h, rx=1.85, rz=1.85)], S, sides=8, power=2.2, cap_bottom=False)
    m.box(-0.6, 0.0, 2.3, 0.6, 2.4, 2.9, TIM, chamfer=0.05)
    m.cone(0.0, h, 0.0, 2.6, h + 3.4, THATCH, sides=8)
    m.box(-0.35, h * 0.86 - 0.35, 2.6, 0.35, h * 0.86 + 0.35, 3.6, TIM, chamfer=0.04)
    hub = (0.0, h * 0.86, 3.3)
    for k in range(4):
        a = math.tau * k / 4 + 0.4
        dx, dy = math.sin(a), math.cos(a)
        m.tube(hub, (hub[0] + dx * 9.0, hub[1] + dy * 9.0, hub[2]), 0.12, 0.1, TIM, sides=4)
        # A lattice sail: a wooden frame with cloth battens.
        px, py = -dy, dx
        for t in (0.2, 0.42, 0.64, 0.86):
            cx, cy = hub[0] + dx * 9.0 * t, hub[1] + dy * 9.0 * t
            m.box(cx + px * 0.05 - 0.04, cy + py * 0.05 - 0.04, hub[2] - 0.03, cx + px * 0.9 + 0.04, cy + py * 0.9 + 0.04, hub[2] + 0.03, TIM)
    return [("Mesh", m, None)]


def market_plaza():
    """The plaza monument: stepped plinth, a column and a canopy."""
    m = Model("plaza")
    m.box(-3.5, 0.0, -3.5, 3.5, 0.5, 3.5, S, chamfer=0.05)
    m.box(-2.8, 0.5, -2.8, 2.8, 1.4, 2.8, S, chamfer=0.05)
    m.box(-2.1, 1.4, -2.1, 2.1, 1.8, 2.1, SD, chamfer=0.04)
    m.loft([dict(y=1.8, rx=0.7, rz=0.7), dict(y=3.6, rx=0.55, rz=0.55), dict(y=4.0, rx=0.75, rz=0.75)], S, sides=8, power=2.0, cap_bottom=False)
    m.box(-1.1, 4.0, -1.1, 1.1, 4.5, 1.1, S, chamfer=0.04)
    m.pyramid(-0.9, -0.9, 0.9, 0.9, 4.5, 5.6, SD)
    return [("Mesh", m, None)]


def market_stall():
    """A market stall 4.4 wide and 3.8 deep (scaled in code), canvas roof over a counter."""
    m = Model("stall")
    w, d = 4.4, 3.8
    for cx in (-1, 1):
        for cz in (-1, 1):
            m.box(cx * w / 2 - 0.1, 0.0, cz * d / 2 - 0.1, cx * w / 2 + 0.1, 2.4, cz * d / 2 + 0.1, TIM, chamfer=0.02)
    m.box(-w / 2, 0.5, d * 0.15, w / 2, 1.3, d / 2, TIM, chamfer=0.04)
    m.box(-w / 2 - 0.05, 1.3, d * 0.15 - 0.05, w / 2 + 0.05, 1.38, d / 2 + 0.05, TIM, chamfer=0.02)
    _gable_roof(m, -w / 2, -d / 2, w / 2, d / 2, 2.4, d * 0.55, CANVAS, CANVAS, overhang=0.25, ridge_along_x=True)
    for k in range(3):
        x = -1.2 + k * 1.2
        m.box(x - 0.4, 0.0, -d * 0.3 - 0.4, x + 0.4, 0.8, -d * 0.3 + 0.4, TIM, chamfer=0.03)
    return [("Mesh", m, None)]


BUILDERS = {
    "skyline/castle": castle, "skyline/church": church, "skyline/windmill": windmill,
    "skyline/market_plaza": market_plaza, "skyline/market_stall": market_stall,
}
