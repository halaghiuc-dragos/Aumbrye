"""Blender builders for the Vigil (waves mode): the cresset, the summoner's portal and spawn markers."""

from __future__ import annotations

import math

from bl_lib import Model

W, A, I, DI, ST = "wall", "accent", "iron", "darkiron", "steel"


def cresset_body():
    m = Model("cresset")
    m.box(-1.3, 0.0, -1.3, 1.3, 0.22, 1.3, W, chamfer=0.04)
    m.box(-1.0, 0.22, -1.0, 1.0, 0.42, 1.0, W, chamfer=0.04)
    m.box(-0.75, 0.42, -0.75, 0.75, 0.56, 0.75, I, chamfer=0.03)
    for k in range(8):
        a = math.tau * k / 8
        m.box(math.cos(a) * 1.15 - 0.06, 0.42, math.sin(a) * 1.15 - 0.06, math.cos(a) * 1.15 + 0.06, 0.52, math.sin(a) * 1.15 + 0.06, A, chamfer=0.008)
    m.tube((0, 0.56, 0), (0, 1.62, 0), 0.15, 0.12, I, sides=8)
    for i in range(3):
        a = math.tau * i / 3
        m.tube((math.cos(a) * 0.5, 0.56, math.sin(a) * 0.5), (math.cos(a) * 0.2, 1.4, math.sin(a) * 0.2), 0.05, 0.04, I, sides=5)
    m.loft([dict(y=1.55, rx=0.2, rz=0.2), dict(y=1.72, rx=0.5, rz=0.5), dict(y=1.9, rx=0.56, rz=0.56)], I, sides=12, power=2.0, cap_top=False)
    m.loft([dict(y=1.86, rx=0.6, rz=0.6), dict(y=1.96, rx=0.6, rz=0.6)], A, sides=12, power=2.0, cap_bottom=False, cap_top=False)
    for k in range(8):
        a = math.tau * k / 8
        m.box(math.cos(a) * 0.58 - 0.05, 1.9, math.sin(a) * 0.58 - 0.05, math.cos(a) * 0.58 + 0.05, 2.1, math.sin(a) * 0.58 + 0.05, I, chamfer=0.008)
    return [("Mesh", m, None)]


def cresset_flame():
    """Origin at the bowl rim: embers, then three tongues of flame of growing heat."""
    m = Model("flame")
    m.cylinder(0, -0.05, 0, 0.3, 0.12, "cresset_ember", sides=10)
    m.cone(0, 0.0, 0, 0.27, 0.46, "cresset_core", sides=7)
    m.cone(0.06, 0.25, -0.03, 0.17, 0.78, "cresset_core", sides=6)
    m.cone(-0.04, 0.5, 0.04, 0.1, 0.96, "cresset_tip", sides=5)
    for k in range(4):
        a = math.tau * k / 4 + 0.5
        m.cone(math.cos(a) * 0.18, 0.05, math.sin(a) * 0.18, 0.07, 0.3 + 0.06 * k, "cresset_ember", sides=4)
    return [("Mesh", m, None)]


def summoner_arch():
    m = Model("arch")
    m.box(-1.7, 0.0, -0.7, 1.7, 0.3, 0.7, W, chamfer=0.04)
    m.box(-1.45, 0.3, -0.55, 1.45, 0.42, 0.55, A, chamfer=0.02)
    for sx in (-1, 1):
        x = sx * 1.35
        m.box(x - 0.25, 0.42, -0.35, x + 0.25, 3.7, 0.35, W, chamfer=0.04)
        for y in (1.1, 2.2, 3.1):
            m.box(x - 0.3, y, -0.4, x + 0.3, y + 0.12, 0.4, A, chamfer=0.015)
        m.box(x - 0.15, 1.4, 0.35, x + 0.15, 2.0, 0.39, A, chamfer=0.008)
        m.pyramid(x - 0.3, -0.4, x + 0.3, 0.4, 3.7, 4.05, A)
    m.box(-1.6, 3.65, -0.35, 1.6, 4.15, 0.35, W, chamfer=0.04)
    m.box(-0.4, 4.15, -0.3, 0.4, 4.45, 0.3, A, chamfer=0.03)
    m.pyramid(-0.3, -0.25, 0.3, 0.25, 4.45, 4.75, A)
    return [("Mesh", m, None)]


def summoner_sheet():
    m = Model("sheet")
    m.box(-1.15, 0.3, -0.07, 1.15, 3.6, 0.07, "portal_sheet", chamfer=0.05)
    return [("Sheet", m, None)]


def summoner():
    m = Model("summoner")
    m.loft(
        [dict(y=0.0, rx=0.42, rz=0.34), dict(y=0.3, rx=0.36, rz=0.3), dict(y=0.85, rx=0.28, rz=0.24), dict(y=1.15, rx=0.3, rz=0.24), dict(y=1.22, rx=0.2, rz=0.17)],
        "robe", sides=12, power=2.4,
    )
    m.box(-0.3, 0.72, 0.18, 0.3, 0.8, 0.26, A, chamfer=0.01)
    m.sphere(0.0, 1.38, 0.0, 0.25, "robe", sides=10, rings=5, ry=0.26)
    m.box(-0.15, 1.3, 0.17, 0.15, 1.45, 0.26, DI, chamfer=0.01)
    for sx in (-1, 1):
        m.box(sx * 0.3 - 0.07, 0.75, 0.12, sx * 0.3 + 0.07, 1.1, 0.26, "robe", chamfer=0.02)
    m.tube((0.42, 0.0, 0.0), (0.42, 1.95, 0.0), 0.05, 0.04, "staff", sides=6)
    for k in range(4):
        a = math.tau * k / 4 + math.pi / 4
        m.tube((0.42 + math.cos(a) * 0.05, 1.8, math.sin(a) * 0.05), (0.42 + math.cos(a) * 0.13, 2.05, math.sin(a) * 0.13), 0.02, 0.015, "staff", sides=4)
    m.pyramid(0.42 - 0.12, -0.12, 0.42 + 0.12, 0.12, 1.95, 2.12, "staff_light")
    m.pyramid(0.42 - 0.12, -0.12, 0.42 + 0.12, 0.12, 1.95, 1.8, "staff_light")
    return [("Mesh", m, None)]


# ------------------------------------------------------------------------ spawn markers

def marker_ring():
    """A flat rune ring, inner radius 0.75 and outer 1.35, studded with notches."""
    m = Model("ring")
    n = 32
    for y0, y1, r0, r1 in ((0.0, 0.05, 0.75, 1.35),):
        outer = [m.ring_points(0, 0, r1, r1, y0, n, 2.0), m.ring_points(0, 0, r1, r1, y1, n, 2.0)]
        inner = [m.ring_points(0, 0, r0, r0, y0, n, 2.0), m.ring_points(0, 0, r0, r0, y1, n, 2.0)]
        m._bridge(outer, "ring")
        m._bridge(list(reversed(inner)), "ring")
        for k in range(n):
            k2 = (k + 1) % n
            m.face([outer[1][k], outer[1][k2], inner[1][k2], inner[1][k]], "ring")
    for k in range(12):
        a = math.tau * k / 12
        r = 1.05
        m.box(math.cos(a) * r - 0.06, 0.05, math.sin(a) * r - 0.06, math.cos(a) * r + 0.06, 0.1, math.sin(a) * r + 0.06, "ring")
    for k in range(4):
        a = math.tau * k / 4
        m.pyramid(math.cos(a) * 1.4 - 0.1, math.sin(a) * 1.4 - 0.1, math.cos(a) * 1.4 + 0.1, math.sin(a) * 1.4 + 0.1, 0.0, 0.14, "ring")
    return [("Ring", m, None)]


def marker_melee():
    m = Model("icon")
    m.loft([dict(y=-0.4, rx=0.02, rz=0.02), dict(y=-0.3, rx=0.14, rz=0.06), dict(y=0.3, rx=0.16, rz=0.06), dict(y=0.42, rx=0.1, rz=0.05)], "icon", sides=4, power=1.3)
    m.box(-0.3, -0.42, -0.06, 0.3, -0.34, 0.06, "icon", chamfer=0.01)
    m.tube((0, -0.34, 0), (0, -0.56, 0), 0.05, 0.05, "icon", sides=4)
    return [("Icon", m, None)]


def marker_ranged():
    m = Model("icon")
    m.sphere(0, 0, 0, 0.3, "icon", sides=8, rings=4)
    m.loft([dict(y=-0.04, rx=0.45, rz=0.45), dict(y=0.04, rx=0.45, rz=0.45)], "icon", sides=12, power=2.0, cap_bottom=False, cap_top=False)
    return [("Icon", m, None)]


def marker_fast():
    m = Model("icon")
    m.pyramid(-0.3, -0.22, 0.3, 0.22, -0.4, 0.4, "icon")
    m.pyramid(-0.3, -0.22, 0.3, 0.22, -0.4, -0.55, "icon")
    return [("Icon", m, None)]


def marker_control():
    m = Model("icon")
    outline = [(-0.34, 0.3), (0.34, 0.3), (0.34, -0.05), (0.0, -0.36), (-0.34, -0.05)]
    m.plate([(x, y, -0.12) for x, y in outline], (0, 0, 1), 0.24, "icon")
    return [("Icon", m, None)]


def marker_boss():
    m = Model("icon")
    m.loft([dict(y=-0.3, rx=0.4, rz=0.3), dict(y=-0.1, rx=0.42, rz=0.3)], "icon", sides=5, power=2.0)
    for k in range(5):
        x = -0.36 + 0.18 * k
        h = 0.3 if k % 2 == 0 else 0.46
        m.pyramid(x - 0.07, -0.07, x + 0.07, 0.07, -0.1, -0.1 + h + 0.3, "icon")
    return [("Icon", m, None)]


def pyre():
    """A ring pyre: stone foot, iron pole and bowl. Unit scale; the flame is a separate model."""
    m = Model("pyre")
    m.box(-0.7, 0.0, -0.7, 0.7, 0.3, 0.7, "pyre_stone", chamfer=0.04)
    m.box(-0.5, 0.3, -0.5, 0.5, 0.46, 0.5, "pyre_stone", chamfer=0.03)
    m.tube((0, 0.46, 0), (0, 2.25, 0), 0.22, 0.17, I, sides=6)
    for y in (0.9, 1.5):
        m.box(-0.26, y, -0.26, 0.26, y + 0.1, 0.26, I, chamfer=0.015)
    m.loft([dict(y=2.15, rx=0.25, rz=0.25), dict(y=2.3, rx=0.52, rz=0.52), dict(y=2.52, rx=0.58, rz=0.58)], I, sides=10, power=2.0, cap_top=False)
    for k in range(8):
        a = math.tau * k / 8
        m.box(math.cos(a) * 0.56 - 0.05, 2.45, math.sin(a) * 0.56 - 0.05, math.cos(a) * 0.56 + 0.05, 2.7, math.sin(a) * 0.56 + 0.05, I, chamfer=0.01)
    return [("Mesh", m, None)]


def pyre_flame():
    m = Model("flame")
    m.cone(0, 0.0, 0, 0.36, 0.62, "pyre_flame", sides=7)
    m.cone(0.04, 0.5, 0.0, 0.2, 0.98, "pyre_flame", sides=6)
    for k in range(4):
        a = math.tau * k / 4 + 0.4
        m.cone(math.cos(a) * 0.24, 0.0, math.sin(a) * 0.24, 0.1, 0.4 + 0.07 * k, "pyre_flame", sides=4)
    return [("Mesh", m, None)]


BUILDERS = {
    "waves/pyre": pyre, "waves/pyre_flame": pyre_flame,
    "waves/cresset_body": cresset_body, "waves/cresset_flame": cresset_flame,
    "waves/summoner_arch": summoner_arch, "waves/summoner_sheet": summoner_sheet, "waves/summoner": summoner,
    "waves/marker_ring": marker_ring, "waves/marker_melee": marker_melee, "waves/marker_ranged": marker_ranged,
    "waves/marker_fast": marker_fast, "waves/marker_control": marker_control, "waves/marker_boss": marker_boss,
}
