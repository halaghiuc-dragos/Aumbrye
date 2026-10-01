"""Blender builders for the player's customisable appearance: hair, faces and class garments.

Frames match what the runtime (`DioramaCharacterSkin`) expects:
  hair     modelled inside the head's own box; the runtime centres it and scales it to the head.
  face     a plate about 6 x 4 voxels; the runtime seats it on the front of the head.
  garment  y = 0 sits SKIRT_DROP voxels below the torso's base; the runtime centres it on x and z.
Hair and face are tinted at runtime by a shader parameter, so they use literal near-white and
near-black colours that survive the multiply.
"""

from __future__ import annotations

import math

import characters as ch
from bl_lib import ACCENT, BASE, LEATHER, Model, literal, slot

E = ch.EDGE
SKIRT_DROP = 6

HAIR_LIGHT = literal((1.0, 1.0, 1.0))
HAIR_DARK = literal((0.80, 0.80, 0.80))
FACE_SKIN = literal((1.0, 1.0, 1.0))
FACE_SHADE = literal((0.90, 0.90, 0.90))
FACE_MARK = literal((0.18, 0.15, 0.16))

# Mirrors HAIR_RECIPES in the retired voxel sculptor so every style keeps its silhouette.
HAIR_RECIPES = {
    "shaven": dict(cap=1),
    "short": dict(cap=2),
    "crop": dict(cap=2, fringe=1),
    "bowl": dict(cap=2, fringe=1, sides=(2, 1), back=(2, 1)),
    "tied": dict(cap=2, tail=(3, 2)),
    "topknot": dict(cap=2, crest="topknot", tail=(3, 2)),
    "ponytail": dict(cap=2, tail=(6, 2)),
    "braided": dict(cap=2, sides=(5, 1)),
    "twin_falls": dict(cap=2, sides=(7, 1)),
    "long": dict(cap=2, back=(6, 1)),
    "flowing": dict(cap=2, back=(8, 1), sides=(4, 1)),
    "mane": dict(cap=3, back=(7, 0), sides=(5, 0)),
    "wild": dict(cap=3, crest="spikes"),
    "windswept": dict(cap=2, crest="spikes", back=(3, 1)),
    "mohawk": dict(cap=1, crest="mohawk"),
    "crest": dict(cap=1, crest="mohawk", back=(4, 2)),
    "tonsure": dict(cap=1, sides=(2, 0)),
    "widow": dict(cap=2, fringe=2),
    "shag": dict(cap=2, fringe=1, sides=(3, 1), crest="spikes"),
    "bob": dict(cap=2, sides=(3, 0), back=(3, 0), fringe=1),
    "cropped_tail": dict(cap=1, tail=(4, 1)),
    "warrior": dict(cap=2, crest="mohawk", tail=(5, 2)),
    "loose": dict(cap=2, back=(4, 1), fringe=1),
    "shorn_sides": dict(cap=2, crest="mohawk", fringe=1),
    "veiled": dict(cap=2, back=(9, 0), sides=(6, 0)),
}

FACE_MASKS = {
    "open": ("......", ".#..#.", "......", "..##.."),
    "stern": ("##..##", ".#..#.", "......", "..##.."),
    "kind": (".#..#.", "##..##", "......", "#.##.#"),
    "weary": ("......", ".#..#.", ".#..#.", "..##.."),
    "scarred": ("....##", ".#..#.", "...#..", "..##.."),
    "hollow": ("......", "##..##", "#....#", "..##.."),
    "grim": ("##..##", "##..##", "......", ".####."),
    "watchful": (".#..#.", "#.##.#", "......", "..##.."),
    "hardened": ("#....#", "##..##", "#....#", ".####."),
    "gaunt": ("......", "#....#", "#....#", "..##.."),
    "wry": ("......", ".#..#.", "......", "#..##."),
    "grave": ("##..##", ".#..#.", "......", ".####."),
    "young": ("......", ".#..#.", "......", "...#.."),
    "seamed": ("#....#", ".#..#.", "#....#", "..##.."),
    "burned": ("###...", ".#..#.", "##....", "..##.."),
    "veteran": ("##...#", ".#..#.", "....#.", ".####."),
    "sleepless": ("......", ".#..#.", "##..##", "..##.."),
    "resolute": (".####.", ".#..#.", "......", ".####."),
    "wolfish": ("#....#", ".#..#.", "......", "#.##.#"),
    "sunken": (".#..#.", "##..##", ".#..#.", "..##.."),
    "brand": ("..##..", ".#..#.", "......", "..##.."),
    "split": ("...##.", ".#..#.", "...#..", "..##.."),
    "patient": ("......", ".#..#.", "......", ".####."),
    "cold": ("##..##", "#....#", "......", "..##.."),
    "ruined": ("##.###", "##..#.", "#...#.", ".###.."),
}


# ------------------------------------------------------------------------------------------
# Hair
# ------------------------------------------------------------------------------------------

def hair(style, head_size):
    r = HAIR_RECIPES.get(style, HAIR_RECIPES["short"])
    sx, sy, sz = head_size
    w, h, d = sx * E, sy * E, sz * E
    m = Model("hair")
    cap = int(r.get("cap", 2))
    grow = E * 0.55
    y_low = h - cap * E
    stops = ch.HEAD_STOPS
    rings = []
    ts = [t for t, *_ in stops if t * h >= y_low - 1e-6] or [1.0]
    samples = sorted(set([y_low / h] + ts + [1.0]))
    for t in samples:
        fw = ch._profile([(s[0], s[1]) for s in stops], t)
        fd = ch._profile([(s[0], s[2]) for s in stops], t)
        rings.append(dict(y=t * h, cx=w / 2, cz=d / 2, rx=w / 2 * fw + grow, rz=d / 2 * fd + grow))
    m.loft(
        rings, HAIR_LIGHT, sides=16, power=3.4, cap_bottom=False, top_mat=HAIR_LIGHT,
        mat_fn=lambda i, k, n: HAIR_DARK if (i + k) % 5 == 0 else HAIR_LIGHT,
    )
    back = -grow * 0.3  # z toward the back of the head is 0

    length, inset = r.get("back", (0, 1))
    if length:
        m.box(inset * E, h - (length + 1) * E, back, w - inset * E, h - E, back + E * (2 if inset == 0 else 1.2), HAIR_LIGHT, chamfer=0.004)
    length, inset = r.get("sides", (0, 1))
    if length:
        for x0 in (inset * E, w - inset * E - E):
            m.box(x0 - grow * 0.5, h - (length + 1) * E, back, x0 + E + grow * 0.5, h - E, back + 2 * E, HAIR_DARK, chamfer=0.004)
    length, width = r.get("tail", (0, 0))
    if length:
        wd = max(1, width) * E
        m.tapered_box(
            (w / 2 - wd / 2, back - E, w / 2 + wd / 2, back + E),
            (w / 2 - wd / 3, back - E * 0.6, w / 2 + wd / 3, back + E * 0.6),
            h - (length + 2) * E, h - 2 * E, HAIR_LIGHT, chamfer=0.003,
        )
    crest = r.get("crest", "none")
    if crest == "spikes":
        for ix in range(0, sx, 2):
            for iz in range(0, sz, 2):
                px, pz = (ix + 0.5) * E, (iz + 0.5) * E
                # Only where the crown actually is.
                if abs(px - w / 2) < w * 0.42 and abs(pz - d / 2) < d * 0.42:
                    m.cone(px, h - 0.004, pz, E * 0.55, h + 0.026, HAIR_LIGHT, sides=5)
    elif crest == "mohawk":
        m.tapered_box(
            (w / 2 - E, 0.0 + E * 0.5, w / 2 + E, d - E * 0.5),
            (w / 2 - E * 0.6, 0.0 + E * 1.2, w / 2 + E * 0.6, d - E * 1.2),
            h - E, h + 0.036, HAIR_LIGHT, chamfer=0.004,
        )
    elif crest == "topknot":
        m.cylinder(w / 2, h - 0.004, back + E * 1.4, E * 1.3, h + 0.034, HAIR_LIGHT, sides=8, r_top=E * 1.0)
    for row in range(int(r.get("fringe", 0))):
        y = h - cap * E - row * E
        m.box(E, y, d - E * 0.4, w - E, y + E, d + grow, HAIR_DARK, chamfer=0.003)
    return m


# ------------------------------------------------------------------------------------------
# Face plates
# ------------------------------------------------------------------------------------------

def face(style, width=6, height=4, depth=1):
    rows = FACE_MASKS.get(style, FACE_MASKS["open"])
    w, h, d = width * E, height * E, depth * E
    m = Model("face")
    m.box(0, 0, 0, w, h, d, FACE_SKIN, chamfer=0.003)
    # Marks: raised dark tiles that read as brow, eye, scar and mouth at pixel scale.
    for ri, row in enumerate(rows[:height]):
        y0 = h - (ri + 1) * E
        run = None
        for xi in range(width + 1):
            marked = xi < width and xi < len(row) and row[xi] == "#"
            if marked and run is None:
                run = xi
            elif not marked and run is not None:
                m.box(run * E + 0.002, y0 + 0.003, d - 0.002, xi * E - 0.002, y0 + E - 0.003, d + 0.006, FACE_MARK, chamfer=0.002)
                run = None
    # A nose, so a plate has a profile from the side too.
    m.box(w / 2 - E * 0.5, E * 1.2, d - 0.002, w / 2 + E * 0.5, E * 2.6, d + E * 0.7, FACE_SHADE, chamfer=0.004)
    return m


# ------------------------------------------------------------------------------------------
# Class garments
# ------------------------------------------------------------------------------------------

GARMENT_PALETTES = {
    "knight": [(0.20, 0.34, 0.62), (0.86, 0.88, 0.92), (0.28, 0.22, 0.18), (0.13, 0.23, 0.44)],
    "sentinel": [(0.30, 0.33, 0.38), (0.94, 0.70, 0.22), (0.24, 0.20, 0.17), (0.20, 0.22, 0.26)],
    "berserker": [(0.62, 0.20, 0.16), (0.82, 0.62, 0.34), (0.34, 0.24, 0.16), (0.42, 0.13, 0.11)],
    "rogue": [(0.11, 0.12, 0.15), (0.42, 0.52, 0.30), (0.20, 0.16, 0.13), (0.07, 0.08, 0.10)],
    "hunter": [(0.20, 0.42, 0.24), (0.78, 0.64, 0.36), (0.30, 0.22, 0.15), (0.13, 0.29, 0.16)],
    "scholar": [(0.34, 0.20, 0.52), (0.92, 0.78, 0.32), (0.24, 0.18, 0.26), (0.23, 0.13, 0.37)],
    "herald": [(0.90, 0.90, 0.92), (0.74, 0.14, 0.20), (0.28, 0.24, 0.22), (0.72, 0.72, 0.76)],
}


class _Body:
    """The torso's ring profile, used to wrap clothing around it."""

    def __init__(self, torso_size):
        self.w, self.h, self.d = ch._dims(torso_size)
        self.base = SKIRT_DROP * E

    def half(self, t):
        fw = ch._profile([(s[0], s[1]) for s in ch.TORSO_STOPS], t)
        fd = ch._profile([(s[0], s[2]) for s in ch.TORSO_STOPS], t)
        return self.w / 2 * fw, self.d / 2 * fd

    def ring(self, t, grow):
        rx, rz = self.half(t)
        return dict(y=self.base + self.h * t, cx=self.w / 2, cz=self.d / 2, rx=rx + grow, rz=rz + grow)

    def shell(self, m, t0, t1, mat, grow=E, mat_fn=None, steps=None):
        ts = sorted(set([t0, t1] + [s[0] for s in ch.TORSO_STOPS if t0 < s[0] < t1]))
        m.loft([self.ring(t, grow) for t in ts], mat, sides=16, power=4.0, cap_bottom=False, cap_top=False, mat_fn=mat_fn)

    def skirt(self, m, y_top_t, y_bottom, mat, flare=1.25, grow=E, fold_mat=None):
        top = self.ring(y_top_t, grow)
        rings = [top]
        n = 4
        for i in range(1, n + 1):
            f = i / n
            y = top["y"] + (y_bottom - top["y"]) * f
            k = 1.0 + (flare - 1.0) * f
            rings.append(dict(y=y, cx=top["cx"], cz=top["cz"], rx=top["rx"] * k, rz=top["rz"] * (1 + (k - 1) * 0.6)))
        m.loft(
            list(reversed(rings)), mat, sides=16, power=4.0, cap_bottom=False, cap_top=False,
            mat_fn=(lambda i, k, n_: fold_mat if fold_mat and k % 3 == 0 else mat),
        )

    def front_z(self, t, grow=E):
        return self.d / 2 + self.half(t)[1] + grow

    def stripe(self, m, t0, t1, x0, x1, mat, grow=E):
        zf = self.front_z((t0 + t1) / 2, grow)
        y0, y1 = self.base + self.h * t0, self.base + self.h * t1
        m.box(self.w / 2 + x0, y0, zf - 0.006, self.w / 2 + x1, y1, zf + 0.008, mat, chamfer=0.002)

    def sash(self, m, t0, t1, mat, grow=E, width=E * 1.4, flip=False):
        """A strap running corner to corner across the chest."""
        zf = self.front_z((t0 + t1) / 2, grow) - 0.002
        x_lo, x_hi = -self.w * 0.40, self.w * 0.40
        if flip:
            x_lo, x_hi = x_hi, x_lo
        y0, y1 = self.base + self.h * t0, self.base + self.h * t1
        cx = self.w / 2
        pts = [
            (cx + x_lo, y1, zf), (cx + x_lo + width, y1, zf),
            (cx + x_hi + width, y0, zf), (cx + x_hi, y0, zf),
        ]
        if flip:
            pts = list(reversed(pts))
        m.plate(pts, (0, 0, 1), 0.010, mat)


def garment(class_id, torso_size):
    pal = GARMENT_PALETTES[class_id]
    primary, trim, leather, fold = (literal(c) for c in pal)
    body = _Body(torso_size)
    m = Model("garment")
    waist, chest, top = 0.26, 0.66, 1.0
    if class_id == "knight":
        body.shell(m, waist, chest + 0.06, primary, mat_fn=lambda i, k, n: fold if k % 4 == 0 else primary)
        body.skirt(m, waist, body.base - 4 * E, primary, fold_mat=fold)
        body.shell(m, chest + 0.06, top, trim)
        body.stripe(m, 0.10, 0.72, -E * 1.2, E * 1.2, trim)
        body.shell(m, waist - 0.05, waist, leather, grow=E * 1.3)
    elif class_id == "sentinel":
        body.shell(m, waist, chest + 0.06, primary)
        body.shell(m, top - 0.08, top, trim, grow=E * 1.2)
        for i in range(3):
            y_hi = body.base - i * 2 * E
            m.loft(
                [
                    dict(y=y_hi - 2 * E, cx=body.w / 2, cz=body.d / 2, rx=body.w / 2 * (1.10 + 0.05 * i), rz=body.d / 2 * (1.0 + 0.04 * i)),
                    dict(y=y_hi, cx=body.w / 2, cz=body.d / 2, rx=body.w / 2 * (1.02 + 0.05 * i), rz=body.d / 2 * (0.96 + 0.04 * i)),
                ],
                trim if i % 2 else primary, sides=16, power=4.0, cap_bottom=False, cap_top=False,
            )
        body.shell(m, waist - 0.05, waist, leather, grow=E * 1.3)
    elif class_id == "berserker":
        body.shell(m, chest, top, trim, grow=E * 1.3, mat_fn=lambda i, k, n: primary if k % 5 == 0 else trim)
        for k in range(12):
            a = 2 * math.pi * k / 12
            x = body.w / 2 + math.cos(a) * body.half(chest)[0] * 1.15
            z = body.d / 2 + math.sin(a) * body.half(chest)[1] * 1.15
            m.cone(x, body.base + body.h * chest, z, E * 0.7, body.base + body.h * chest - E * 2.4, trim, sides=4)
        body.shell(m, waist - 0.08, waist, leather, grow=E * 1.3)
        body.sash(m, waist + 0.02, chest - 0.02, primary)
    elif class_id == "rogue":
        body.shell(m, waist, chest + 0.10, primary)
        body.shell(m, waist - 0.10, waist, leather, grow=E * 1.4)
        body.sash(m, waist + 0.04, chest + 0.10, trim, width=E * 1.6)
        body.shell(m, top - 0.08, top, primary, grow=E * 1.1)
    elif class_id == "hunter":
        body.shell(m, waist, chest + 0.06, primary)
        body.sash(m, waist + 0.04, chest + 0.06, leather, flip=True)
        # A short cape at the back: a slab hanging off the shoulder line.
        cape_top = body.base + body.h * (chest + 0.10)
        m.box(body.w * 0.12, body.base - 3 * E, -E * 1.1, body.w * 0.88, cape_top, -E * 0.1, trim, chamfer=0.004)
        body.shell(m, waist - 0.05, waist, leather, grow=E * 1.3)
    elif class_id == "scholar":
        body.shell(m, 0.0, chest + 0.06, primary, mat_fn=lambda i, k, n: fold if k % 4 == 0 else primary)
        body.skirt(m, 0.0, 0.0, primary, flare=1.14, fold_mat=fold)
        for sx in (-2 * E, 2 * E):
            body.stripe(m, 0.0, top, sx - E * 0.5, sx + E * 0.5, trim)
        body.shell(m, top - 0.08, top, trim, grow=E * 1.2)
        body.shell(m, waist - 0.02, waist + 0.02, leather, grow=E * 1.3)
    elif class_id == "herald":
        body.shell(m, waist, chest + 0.06, primary)
        body.skirt(m, waist, body.base - 4 * E, primary)
        # Party per pale: the right half of the front and the left half of the back in the trim.
        zf = body.front_z(0.5)
        y0, y1 = body.base - 4 * E, body.base + body.h * (chest + 0.06)
        cx = body.w / 2
        m.box(cx, y0, zf - 0.004, cx + body.w * 0.46, y1, zf + 0.010, trim, chamfer=0.002)
        zb = body.d / 2 - body.half(0.5)[1] - E
        m.box(cx - body.w * 0.46, y0, zb - 0.010, cx, y1, zb + 0.004, trim, chamfer=0.002)
        body.shell(m, top - 0.08, top, trim, grow=E * 1.2)
        body.shell(m, waist - 0.05, waist, leather, grow=E * 1.3)
    return m
