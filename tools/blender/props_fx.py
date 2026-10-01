"""Blender builders for small effect geometry: projectiles, beams, shrines, gates and trap parts.

These are bare meshes: the game puts its own (often animated or translucent) material on them, so
the surface role names here do not matter. Unit meshes are scaled to size in code.
"""

from __future__ import annotations

import math

from bl_lib import Model

M = "mesh"


def bolt_orb():
    m = Model("orb")
    m.sphere(0, 0, 0, 0.18, M, sides=10, rings=5)
    m.loft([dict(y=-0.015, rx=0.26, rz=0.26), dict(y=0.015, rx=0.26, rz=0.26)], M, sides=12, power=2.0, cap_bottom=False, cap_top=False)
    return [("Mesh", m, None)]


def arrow_shaft():
    m = Model("shaft")
    m.tube((0, 0, -0.25), (0, 0, 0.37), 0.022, 0.022, M, sides=6)
    return [("Mesh", m, None)]


def arrow_head():
    m = Model("head")
    m.tube((0, 0, -0.23), (0, 0, -0.09), 0.001, 0.05, M, sides=5)
    m.tube((0, 0, -0.09), (0, 0, 0.0), 0.05, 0.035, M, sides=5)
    return [("Mesh", m, None)]


def arrow_fletch():
    m = Model("fletch")
    for k in range(3):
        a = math.tau * k / 3
        m.plate([(0, 0, -0.06), (math.cos(a) * 0.09, math.sin(a) * 0.09, -0.08), (math.cos(a) * 0.09, math.sin(a) * 0.09, 0.05), (0, 0, 0.08)], (math.sin(a) * 0.01, -math.cos(a) * 0.01, 0.0), 0.012, M)
    return [("Mesh", m, None)]


def flask():
    """A round-bellied fire flask with a short neck and a fuse."""
    m = Model("flask")
    m.loft([dict(y=-0.26, rx=0.05, rz=0.05), dict(y=-0.15, rx=0.22, rz=0.22), dict(y=0.05, rx=0.27, rz=0.27), dict(y=0.17, rx=0.17, rz=0.17), dict(y=0.26, rx=0.08, rz=0.08), dict(y=0.34, rx=0.09, rz=0.09)], M, sides=10, power=2.0)
    m.tube((0, 0.34, 0), (0.05, 0.46, 0), 0.015, 0.008, M, sides=4)
    return [("Mesh", m, None)]


def lure_ring():
    m = Model("lure")
    n = 20
    outer = [m.ring_points(0, 0, 0.3, 0.3, -0.05, n, 2.0), m.ring_points(0, 0, 0.3, 0.3, 0.05, n, 2.0)]
    inner = [m.ring_points(0, 0, 0.15, 0.15, -0.05, n, 2.0), m.ring_points(0, 0, 0.15, 0.15, 0.05, n, 2.0)]
    m._bridge(outer, M)
    m._bridge(list(reversed(inner)), M)
    for k in range(n):
        k2 = (k + 1) % n
        m.face([outer[1][k], outer[1][k2], inner[1][k2], inner[1][k]], M)
        m.face([outer[0][k2], outer[0][k], inner[0][k], inner[0][k2]], M)
    return [("Mesh", m, None)]


def beam():
    """Unit beam: bottom radius 1, top radius 0.375, height 1, eight sides."""
    m = Model("beam")
    m.loft([dict(y=0.0, rx=1.0, rz=1.0), dict(y=0.5, rx=0.65, rz=0.65), dict(y=1.0, rx=0.375, rz=0.375)], M, sides=8, power=2.0)
    return [("Mesh", m, None)]


def pact_base():
    m = Model("base")
    m.box(-0.525, 0.0, -0.525, 0.525, 0.6, 0.525, M, chamfer=0.04)
    m.box(-0.56, 0.08, -0.56, 0.56, 0.16, 0.56, M, chamfer=0.02)
    m.box(-0.56, 0.44, -0.56, 0.56, 0.52, 0.56, M, chamfer=0.02)
    return [("Mesh", m, None)]


def pact_rune():
    m = Model("rune")
    m.loft([dict(y=-0.775, rx=0.52, rz=0.52), dict(y=-0.3, rx=0.44, rz=0.44), dict(y=0.4, rx=0.38, rz=0.38), dict(y=0.775, rx=0.34, rz=0.34)], M, sides=4, power=1.8, top_mat=M)
    for y in (-0.35, 0.05, 0.45):
        m.loft([dict(y=y, rx=0.46 - y * 0.12, rz=0.46 - y * 0.12), dict(y=y + 0.05, rx=0.46 - y * 0.12, rz=0.46 - y * 0.12)], M, sides=4, power=1.8, cap_bottom=False, cap_top=False)
    return [("Mesh", m, None)]


def pact_shard():
    m = Model("shard")
    m.tube((0, -0.15, 0), (0, 0.04, 0), 0.1, 0.07, M, sides=4)
    m.tube((0, 0.04, 0), (0, 0.15, 0), 0.07, 0.008, M, sides=4)
    return [("Mesh", m, None)]


def clue_bowl():
    m = Model("bowl")
    m.loft([dict(y=-0.17, rx=0.12, rz=0.12), dict(y=-0.05, rx=0.22, rz=0.22), dict(y=0.17, rx=0.26, rz=0.26)], M, sides=10, power=2.0, cap_top=False)
    m.loft([dict(y=0.15, rx=0.27, rz=0.27), dict(y=0.2, rx=0.27, rz=0.27)], M, sides=10, power=2.0, cap_bottom=False, cap_top=False)
    return [("Mesh", m, None)]


def gate_portcullis():
    """Unit cube: a lattice of iron bars between a header and a sill."""
    m = Model("gate")
    m.box(-0.5, 0.44, -0.5, 0.5, 0.5, 0.5, M, chamfer=0.02)
    m.box(-0.5, -0.5, -0.5, 0.5, -0.44, 0.5, M, chamfer=0.02)
    n = 9
    for k in range(n):
        x = -0.44 + 0.88 * k / (n - 1)
        m.tube((x, -0.44, 0.0), (x, 0.44, 0.0), 0.03, 0.03, M, sides=4)
    for y in (-0.25, 0.0, 0.25):
        m.box(-0.5, y - 0.025, -0.3, 0.5, y + 0.025, 0.3, M, chamfer=0.008)
    return [("Mesh", m, None)]


def gate_rune_door():
    m = Model("door")
    m.box(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, M, chamfer=0.03)
    m.box(-0.44, -0.44, -0.6, 0.44, 0.44, 0.6, M, chamfer=0.02)
    for k in range(3):
        y = -0.3 + 0.3 * k
        m.box(-0.3, y - 0.05, 0.5, 0.3, y + 0.05, 0.56, M)
        m.box(-0.3, y - 0.05, -0.56, 0.3, y + 0.05, -0.5, M)
    return [("Mesh", m, None)]


def slab():
    m = Model("slab")
    m.box(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, M, chamfer=0.03)
    return [("Mesh", m, None)]


def disc():
    """Unit disc: radius 1, height 1, centred; a faceted rim and a raised lip."""
    m = Model("disc")
    m.loft([dict(y=-0.5, rx=0.96, rz=0.96), dict(y=-0.4, rx=1.0, rz=1.0), dict(y=0.4, rx=1.0, rz=1.0), dict(y=0.5, rx=0.94, rz=0.94)], M, sides=12, power=2.0, top_mat=M)
    return [("Mesh", m, None)]


def spike():
    """Unit spike: base radius 1, height 1, centred, with a collar."""
    m = Model("spike")
    m.loft([dict(y=-0.5, rx=1.0, rz=1.0), dict(y=-0.36, rx=0.92, rz=0.92)], M, sides=6, power=2.0, cap_top=False)
    m.tube((0, -0.36, 0), (0, 0.5, 0), 0.92, 0.0, M, sides=6, caps=(False, False))
    return [("Mesh", m, None)]


def ember_chunk():
    """A tiny faceted spark, unit size 0.05 cube-equivalent (scaled in code)."""
    m = Model("ember")
    m.pyramid(-0.025, -0.025, 0.025, 0.025, 0.0, 0.035, M)
    m.pyramid(-0.025, -0.025, 0.025, 0.025, 0.0, -0.035, M)
    return [("Mesh", m, None)]


def rain_drop():
    m = Model("drop")
    m.tube((0, -0.15, 0), (0, 0.1, 0), 0.007, 0.011, M, sides=4)
    m.tube((0, 0.1, 0), (0, 0.15, 0), 0.011, 0.001, M, sides=4)
    return [("Mesh", m, None)]


def splash_chip():
    m = Model("splash")
    m.pyramid(-0.045, -0.045, 0.045, 0.045, 0.0, 0.03, M)
    return [("Mesh", m, None)]


def marker_gem():
    """The weak-point gem, radius 0.5."""
    m = Model("gem")
    m.sphere(0, 0, 0, 0.5, M, sides=8, rings=4)
    return [("Mesh", m, None)]


def elite_crown():
    m = Model("crown")
    m.loft([dict(y=-0.09, rx=0.27, rz=0.27), dict(y=0.0, rx=0.22, rz=0.22), dict(y=0.04, rx=0.2, rz=0.2)], M, sides=8, power=2.0, cap_top=False)
    for k in range(5):
        a = math.tau * k / 5
        m.tube((math.cos(a) * 0.19, 0.03, math.sin(a) * 0.19), (math.cos(a) * 0.16, 0.16 if k == 0 else 0.13, math.sin(a) * 0.16), 0.045, 0.008, M, sides=4)
    return [("Mesh", m, None)]


def boss_shard():
    m = Model("shard")
    m.tube((0, -0.19, 0), (0, 0.04, 0), 0.13, 0.09, M, sides=4)
    m.tube((0, 0.04, 0), (0, 0.19, 0), 0.09, 0.008, M, sides=4)
    return [("Mesh", m, None)]


def charge_core():
    m = Model("core")
    m.sphere(0, 0, 0, 0.14, M, sides=8, rings=4)
    return [("Mesh", m, None)]


def fp_arm():
    """A first-person sleeve: 0.16 wide and deep, 0.46 long, hanging from y = 0."""
    m = Model("arm")
    m.loft([dict(y=-0.46, rx=0.072, rz=0.072), dict(y=-0.36, rx=0.08, rz=0.078), dict(y=-0.2, rx=0.078, rz=0.08), dict(y=-0.05, rx=0.086, rz=0.086), dict(y=0.0, rx=0.07, rz=0.07)], M, sides=10, power=2.6)
    m.loft([dict(y=-0.44, rx=0.088, rz=0.088), dict(y=-0.36, rx=0.092, rz=0.092)], M, sides=10, power=2.6, cap_bottom=False, cap_top=False)
    return [("Mesh", m, None)]


def fp_glove():
    """A gauntleted fist, centred, about 0.18 wide."""
    m = Model("glove")
    m.box(-0.095, -0.06, -0.095, 0.095, 0.06, 0.095, M, chamfer=0.02)
    m.box(-0.085, 0.04, -0.105, 0.085, 0.085, 0.105, M, chamfer=0.012)
    for k in range(4):
        x = -0.06 + k * 0.04
        m.box(x - 0.016, -0.05, 0.095, x + 0.016, 0.03, 0.12, M, chamfer=0.006)
    return [("Mesh", m, None)]


def smoke_puff():
    """A lumpy cloud within the unit cube, so a column of puffs reads as smoke and not as boxes."""
    m = Model("puff")
    for cx, cy, cz, r in [(0.0, 0.0, 0.0, 0.34), (0.22, 0.08, 0.1, 0.24), (-0.2, -0.06, 0.12, 0.26), (0.05, 0.22, -0.16, 0.22), (-0.1, 0.12, -0.2, 0.2)]:
        m.sphere(cx, cy, cz, r, M, sides=7, rings=4)
    return [("Mesh", m, None)]


BUILDERS = {
    "fx/smoke_puff": smoke_puff,
    "fx/ember_chunk": ember_chunk, "fx/rain_drop": rain_drop, "fx/splash_chip": splash_chip,
    "fx/marker_gem": marker_gem, "fx/elite_crown": elite_crown, "fx/boss_shard": boss_shard,
    "fx/charge_core": charge_core, "fx/fp_arm": fp_arm, "fx/fp_glove": fp_glove,
    "fx/bolt_orb": bolt_orb, "fx/arrow_shaft": arrow_shaft, "fx/arrow_head": arrow_head, "fx/arrow_fletch": arrow_fletch,
    "fx/flask": flask, "fx/lure_ring": lure_ring, "fx/beam": beam,
    "fx/pact_base": pact_base, "fx/pact_rune": pact_rune, "fx/pact_shard": pact_shard, "fx/clue_bowl": clue_bowl,
    "fx/gate_portcullis": gate_portcullis, "fx/gate_rune_door": gate_rune_door,
    "fx/slab": slab, "fx/disc": disc, "fx/spike": spike,
}
