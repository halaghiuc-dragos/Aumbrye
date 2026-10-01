"""Blender builders for the distant villagers: one unit shape per body part.

Every shape fits the unit cube centred on the origin; the crowd scales each copy to its part's size
and swings the limbs about their tops. Materials are the crowd's own (cloth, skin, iron ...), so the
surface role is irrelevant here.
"""

from __future__ import annotations

import math

from bl_lib import Model

M = "mesh"


def _unit(name, build):
    m = Model(name)
    build(m)
    return [("Mesh", m, None)]


def box(m):
    m.box(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, M, chamfer=0.08)


def torso(m):
    m.loft([dict(y=-0.5, rx=0.42, rz=0.45), dict(y=-0.2, rx=0.46, rz=0.48), dict(y=0.2, rx=0.5, rz=0.5), dict(y=0.5, rx=0.4, rz=0.42)], M, sides=8, power=3.0)


def head(m):
    m.loft([dict(y=-0.5, rx=0.3, rz=0.32), dict(y=-0.2, rx=0.46, rz=0.46), dict(y=0.25, rx=0.5, rz=0.5), dict(y=0.5, rx=0.32, rz=0.34)], M, sides=8, power=2.6)
    m.box(-0.06, -0.18, 0.4, 0.06, 0.05, 0.56, M)


def arm(m):
    m.loft([dict(y=-0.5, rx=0.4, rz=0.42), dict(y=-0.3, rx=0.34, rz=0.36), dict(y=0.1, rx=0.46, rz=0.46), dict(y=0.5, rx=0.5, rz=0.5)], M, sides=6, power=2.6)


def leg(m):
    m.loft([dict(y=-0.5, rx=0.5, rz=0.62), dict(y=-0.4, rx=0.46, rz=0.5), dict(y=-0.1, rx=0.36, rz=0.4), dict(y=0.5, rx=0.5, rz=0.5)], M, sides=6, power=2.6)


def bundle(m):
    m.sphere(0, 0, 0, 0.5, M, sides=8, rings=4, ry=0.45, rz=0.5)
    m.box(-0.12, 0.3, -0.12, 0.12, 0.5, 0.12, M)


def helm(m):
    m.loft([dict(y=-0.5, rx=0.5, rz=0.5), dict(y=-0.1, rx=0.42, rz=0.42), dict(y=0.3, rx=0.3, rz=0.3), dict(y=0.5, rx=0.06, rz=0.06)], M, sides=8, power=2.0)


def pole(m):
    m.tube((0, -0.5, 0), (0, 0.5, 0), 0.5, 0.42, M, sides=6)


def spearhead(m):
    m.tube((0, -0.5, 0), (0, -0.1, 0), 0.5, 0.5, M, sides=4)
    m.tube((0, -0.1, 0), (0, 0.5, 0), 0.5, 0.0, M, sides=4)


def horse_body(m):
    layers = []
    for t, fw, fh in [(-0.5, 0.6, 0.6), (-0.35, 0.9, 0.9), (0.0, 1.0, 1.0), (0.35, 0.92, 0.92), (0.5, 0.7, 0.72)]:
        ring = m.ring_points(0, 0, 0.5 * fw, 0.5 * fh, 0.0, 10, 2.4)
        layers.append([(x, z, t) for (x, _y, z) in ring])
    m._bridge(layers, M)
    m.face(list(reversed(layers[0])), M)
    m.face(layers[-1], M)


def horse_neck(m):
    m.loft([dict(y=-0.5, rx=0.5, rz=0.5), dict(y=0.0, rx=0.42, rz=0.42), dict(y=0.5, rx=0.34, rz=0.38)], M, sides=8, power=2.4)


def horse_head(m):
    m.box(-0.36, -0.5, -0.5, 0.36, 0.45, 0.5, M, chamfer=0.1)
    m.pyramid(-0.3, -0.05, -0.1, 0.1, 0.45, 0.7, M)
    m.pyramid(0.1, -0.05, 0.3, 0.1, 0.45, 0.7, M)


def horse_tail(m):
    m.tube((0, 0.5, 0), (0, -0.5, 0), 0.4, 0.22, M, sides=5)


def wagon(m):
    m.box(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, M, chamfer=0.04)
    for k in range(4):
        z = -0.36 + 0.24 * k
        m.box(-0.52, -0.5, z - 0.02, 0.52, 0.5, z + 0.02, M)


def wheel(m):
    n = 12
    layers = []
    for x in (-0.5, 0.5):
        ring = m.ring_points(0, 0, 0.5, 0.5, 0.0, n, 2.0)
        layers.append([(x, y_, z_) for (z_, _y, y_) in [(p[0], p[1], p[2]) for p in ring]])
    m._bridge(layers, M)
    m.face(list(reversed(layers[0])), M)
    m.face(layers[1], M)
    for k in range(4):
        a = math.pi * k / 4
        m.tube((0, -0.5 * math.cos(a), -0.5 * math.sin(a)), (0, 0.5 * math.cos(a), 0.5 * math.sin(a)), 0.05, 0.05, M, sides=4)


def load_heap(m):
    m.sphere(0, -0.2, 0, 0.5, M, sides=8, rings=4, ry=0.7, rz=0.5)
    m.box(-0.5, -0.5, -0.5, 0.5, -0.2, 0.5, M, chamfer=0.06)


def dog_body(m):
    m.box(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, M, chamfer=0.22)


def dog_head(m):
    m.box(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, M, chamfer=0.2)
    m.box(-0.3, -0.4, 0.3, 0.3, 0.1, 0.6, M, chamfer=0.05)


def dog_tail(m):
    m.tube((0, 0, -0.5), (0, 0.3, 0.5), 0.5, 0.25, M, sides=4)


SHAPES = {
    "box": box, "torso": torso, "head": head, "arm": arm, "leg": leg, "bundle": bundle, "helm": helm,
    "pole": pole, "spearhead": spearhead, "horse_body": horse_body, "horse_neck": horse_neck,
    "horse_head": horse_head, "horse_tail": horse_tail, "wagon": wagon, "wheel": wheel, "load_heap": load_heap,
    "dog_body": dog_body, "dog_head": dog_head, "dog_tail": dog_tail,
}

BUILDERS = {"crowd/" + name: (lambda n=name, f=fn: _unit(n, f)) for name, fn in SHAPES.items()}
