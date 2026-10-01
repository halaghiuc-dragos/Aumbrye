"""Blender builders for the hub's birds, cats and dogs.

Roles: fur, dark (a shade under fur) and beak; the game supplies the tinted materials per animal.
Named objects (Body, Tail, Legs, WingL, WingR) are the nodes the animal scripts drive.
"""

from __future__ import annotations

from bl_lib import Model

FUR, DARK, BEAK = "fur", "dark", "beak"


def hub_bird():
    body = Model("Body")
    body.box(-0.1, -0.08, -0.19, 0.1, 0.08, 0.19, FUR, chamfer=0.03)
    body.box(-0.08, -0.015, 0.17, 0.08, 0.135, 0.32, FUR, chamfer=0.025)
    body.box(-0.03, 0.015, 0.3, 0.03, 0.065, 0.42, BEAK, chamfer=0.008)
    body.box(-0.07, -0.005, -0.38, 0.07, 0.045, -0.18, FUR, chamfer=0.01)
    objs = [("Body", body, None)]
    for side, name in ((-1, "WingL"), (1, "WingR")):
        w = Model(name)
        w.box(min(0.0, side * 0.36), -0.025, -0.11, max(0.0, side * 0.36), 0.025, 0.11, FUR, chamfer=0.01)
        w.box(min(side * 0.2, side * 0.36), -0.02, -0.14, max(side * 0.2, side * 0.36), 0.02, -0.06, DARK, chamfer=0.006)
        objs.append((name, w, (side * 0.09, 0.05, 0.0)))
    return objs


def hub_cat():
    body = Model("Body")
    body.box(-0.1, -0.09, -0.22, 0.1, 0.09, 0.22, FUR, chamfer=0.035)
    body.box(-0.1, 0.0, 0.19, 0.1, 0.2, 0.37, FUR, chamfer=0.035)
    body.box(-0.06, 0.06, 0.36, 0.06, 0.12, 0.4, DARK, chamfer=0.01)
    for sx in (-1, 1):
        body.pyramid(sx * 0.06 - 0.03, 0.26, sx * 0.06 + 0.03, 0.31, 0.2, 0.31, DARK)
        body.box(sx * 0.05 - 0.012, 0.11, 0.37, sx * 0.05 + 0.012, 0.15, 0.39, "eye")
    legs = Model("Legs")
    for x in (-0.07, 0.07):
        for z in (-0.15, 0.15):
            legs.box(x - 0.03, 0.0, z - 0.03, x + 0.03, 0.24, z + 0.03, DARK, chamfer=0.01)
    tail = Model("Tail")
    tail.tube((0, 0, 0), (0, 0.15, -0.05), 0.03, 0.028, FUR, sides=5)
    tail.tube((0, 0.15, -0.05), (0, 0.3, 0.0), 0.028, 0.022, FUR, sides=5)
    return [("Body", body, (0.0, 0.24, 0.0)), ("Legs", legs, None), ("Tail", tail, (0.0, 0.3, -0.22))]


def hub_dog():
    body = Model("Body")
    body.box(-0.14, -0.13, -0.3, 0.14, 0.13, 0.3, FUR, chamfer=0.045)
    body.box(-0.13, 0.0, 0.26, 0.13, 0.26, 0.5, FUR, chamfer=0.04)
    body.box(-0.075, -0.03, 0.46, 0.075, 0.1, 0.64, DARK, chamfer=0.02)
    body.box(-0.03, 0.05, 0.63, 0.03, 0.1, 0.66, "eye")
    for sx in (-1, 1):
        body.box(sx * 0.1 - 0.035, 0.12, 0.3, sx * 0.1 + 0.035, 0.3, 0.4, DARK, chamfer=0.012)
        body.box(sx * 0.07 - 0.015, 0.1, 0.49, sx * 0.07 + 0.015, 0.15, 0.51, "eye")
    legs = Model("Legs")
    for x in (-0.1, 0.1):
        for z in (-0.2, 0.2):
            legs.box(x - 0.045, 0.0, z - 0.045, x + 0.045, 0.38, z + 0.045, DARK, chamfer=0.012)
    tail = Model("Tail")
    tail.tube((0, 0, 0), (0, 0.13, -0.05), 0.04, 0.035, FUR, sides=5)
    tail.tube((0, 0.13, -0.05), (0, 0.27, -0.02), 0.035, 0.025, FUR, sides=5)
    return [("Body", body, (0.0, 0.38, 0.0)), ("Legs", legs, None), ("Tail", tail, (0.0, 0.48, -0.3))]


BUILDERS = {"fauna/bird": hub_bird, "fauna/cat": hub_cat, "fauna/dog": hub_dog}
