"""Icon models for the 16 x 16 item atlas.

Each shape is a small relief seen from the front (x right, y up, z toward the camera), about 12 units
tall so one unit is one pixel. Parts are bevelled plates: the bevel is what catches the light, so a
flat silhouette still reads as solid. Materials: `M` metal or stone (four tones), `A` accent such as
leather, gold or a liquid (three tones) and `X`, a flat dark used for slits and sockets.
"""

from __future__ import annotations

import math

from bl_lib import Model
from props_masonry import _face_out

M, A, X = "m", "a", "x"


def _area(pts):
    return sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) / 2


def _inset(pts, d):
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]

        def nrm(a, b):
            dx, dy = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dy) or 1.0
            return (-dy / ln, dx / ln)

        n1, n2 = nrm(p0, p1), nrm(p1, p2)
        k = 1.0 + n1[0] * n2[0] + n1[1] * n2[1]
        k = max(k, 0.35)
        out.append((p1[0] + (n1[0] + n2[0]) / k * d, p1[1] + (n1[1] + n2[1]) / k * d))
    return out


# A placement applied to every point an icon builder emits, so one builder can be reused for a part of a
# bigger composition (two axes crossed, say): (angle in degrees, mirrored, dx, dy).
XF = (0.0, False, 0.0, 0.0)


def _xf(p):
    angle, mirror, dx, dy = XF
    x, y = (-p[0] if mirror else p[0]), p[1]
    a = math.radians(angle)
    return (x * math.cos(a) - y * math.sin(a) + dx, x * math.sin(a) + y * math.cos(a) + dy)


class Icon:
    active = None

    def __new__(cls, name):
        # While an emblem is being composed every builder draws into the same icon.
        if cls.active is not None:
            return cls.active
        return super().__new__(cls)

    def __init__(self, name):
        if getattr(self, "m", None) is not None:
            return
        self.m = Model(name)
        self.z = 0.0
        self.parts = 0

    def poly(self, pts, mat=M, bevel=0.8, depth=1.0):
        """A bevelled plate over the polygon `pts` (x, y), drawn in front of everything added before it."""
        pts = [_xf(p) for p in pts]
        if _area(pts) < 0:
            pts.reverse()
        inner = _inset(pts, min(bevel, _min_width(pts) * 0.45))
        z0 = self.z
        z1 = z0 + depth
        self.parts += 1
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            quad = [(pts[i][0], pts[i][1], z0), (pts[j][0], pts[j][1], z0), (inner[j][0], inner[j][1], z1), (inner[i][0], inner[i][1], z1)]
            mx = (pts[i][0] + pts[j][0]) / 2 - sum(p[0] for p in pts) / n
            my = (pts[i][1] + pts[j][1]) / 2 - sum(p[1] for p in pts) / n
            _face_out(self.m, quad, (mx, my, 1.0), self._tag(mat))
        _face_out(self.m, [(x, y, z1) for x, y in inner], (0, 0, 1), self._tag(mat))
        self.z += 0.45

    def _tag(self, mat):
        # Faces carry `<material>#<part>` so the rasteriser can draw keylines between parts.
        return "%s#%d" % (mat, self.parts)

    def rect(self, x0, y0, x1, y1, mat=M, bevel=0.6, depth=1.0):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], mat, bevel, depth)

    def disc(self, cx, cy, r, mat=M, n=14, bevel=0.9, depth=1.2, ry=None):
        ry = r if ry is None else ry
        self.poly([(cx + math.cos(math.tau * i / n) * r, cy + math.sin(math.tau * i / n) * ry) for i in range(n)], mat, bevel, depth)

    def line(self, p0, p1, w, mat=M, bevel=0.45):
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln * w / 2, dx / ln * w / 2
        self.poly([(p0[0] + nx, p0[1] + ny), (p1[0] + nx, p1[1] + ny), (p1[0] - nx, p1[1] - ny), (p0[0] - nx, p0[1] - ny)], mat, bevel)

    def arc(self, cx, cy, r, a0, a1, w, mat=M, steps=8):
        for i in range(steps):
            t0, t1 = a0 + (a1 - a0) * i / steps, a0 + (a1 - a0) * (i + 1) / steps
            self.line((cx + math.cos(t0) * r, cy + math.sin(t0) * r), (cx + math.cos(t1) * r, cy + math.sin(t1) * r), w, mat, 0.35)


def _min_width(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(max(xs) - min(xs), max(ys) - min(ys))


# -- weapons --------------------------------------------------------------------------------
def _sword(name, w, top, guard, grip_top=-1.8, tip=1.6):
    i = Icon(name)
    i.line((0, -5.2), (0, -2.0), 1.3, A)
    i.poly([(-w, grip_top + 0.9), (w, grip_top + 0.9), (w, top - tip), (0, top), (-w, top - tip)], M)
    i.rect(-guard, grip_top, guard, grip_top + 0.9, A, 0.4)
    i.disc(0, -5.3, 0.95, A, 8, 0.4)
    return i


def sword():
    return _sword("sword", 1.15, 6.0, 2.7)


def greatsword():
    i = _sword("greatsword", 1.6, 6.3, 3.3, grip_top=-2.2, tip=2.2)
    return i


def dagger():
    i = Icon("dagger")
    i.line((0, -5.6), (0, -2.6), 1.3, A)
    i.poly([(-1.05, -1.6), (1.05, -1.6), (1.05, 3.4), (0, 5.8), (-1.05, 3.4)], M)
    i.rect(-2.0, -2.6, 2.0, -1.6, A, 0.4)
    i.disc(0, -5.6, 0.9, A, 8, 0.4)
    return i


def shortsword():
    return _sword("shortsword", 1.25, 4.8, 2.6, grip_top=-2.2, tip=1.4)


def rapier():
    i = Icon("rapier")
    i.line((0, -5.6), (0, -3.0), 1.2, A)
    i.poly([(-0.65, -2.0), (0.65, -2.0), (0.65, 5.0), (0, 6.2), (-0.65, 5.0)], M)
    i.disc(0, -2.5, 2.3, A, 10, 0.6, ry=0.9)
    i.disc(0, -5.6, 0.9, A, 8, 0.4)
    return i


def axe():
    i = Icon("axe")
    i.line((-1.0, -6.0), (0.4, 5.4), 1.3, A)
    i.poly([(0.6, 5.8), (5.8, 4.2), (6.0, -2.0), (1.8, 0.2), (0.0, 0.0)], M)
    i.rect(-1.2, 0.2, 1.2, 1.1, A, 0.3)
    return i


def hammer():
    i = Icon("hammer")
    i.line((0, -6.0), (0, 2.0), 1.4, A)
    i.rect(-3.8, 1.8, 3.8, 5.6, M, 0.8)
    i.rect(-4.2, 2.3, -3.4, 5.1, A, 0.3)
    return i


def spear():
    i = Icon("spear")
    i.line((0, -6.2), (0, 3.0), 1.2, A)
    i.poly([(-2.3, 1.6), (0, 6.4), (2.3, 1.6), (0, 2.8)], M)
    i.rect(-1.0, 2.0, 1.0, 2.9, A, 0.3)
    return i


def halberd():
    i = Icon("halberd")
    i.line((0, -6.2), (0, 4.0), 1.2, A)
    i.poly([(0.4, 4.6), (4.6, 4.2), (4.8, 0.4), (0.4, 1.6)], M)
    i.poly([(-0.9, 4.0), (0, 6.3), (0.9, 4.0)], M)
    return i


def staff():
    i = Icon("staff")
    i.line((0, -6.2), (0, 2.6), 1.3, A)
    i.disc(0, 4.2, 1.9, M, 10, 0.8)
    i.disc(0, 4.2, 0.8, A, 8, 0.3)
    i.poly([(-2.4, 2.4), (0, 1.6), (2.4, 2.4), (0, 3.0)], A, 0.3)
    return i


def bow_recurve():
    i = Icon("bow")
    i.arc(-2.4, 0, 6.2, -1.15, 1.15, 1.3, A, 10)
    i.line((2.3, -5.2), (2.3, 5.2), 0.45, M, 0.15)
    i.rect(-0.9, -0.9, 0.3, 0.9, M, 0.3)
    return i


# -- armour ---------------------------------------------------------------------------------
def helm():
    i = Icon("helm")
    i.poly([(-4.2, -5), (4.2, -5), (4.6, 0), (3.3, 3.8), (0, 5.8), (-3.3, 3.8), (-4.6, 0)], M)
    i.rect(-3.2, -1.6, 3.2, 0.0, X, 0.2)
    i.rect(-0.5, -5, 0.5, 0.0, X, 0.15)
    i.poly([(-0.9, 5.4), (0.9, 5.4), (1.6, 7.0), (-1.6, 7.0)], A, 0.3)
    return i


def cuirass():
    i = Icon("cuirass")
    i.poly([(-4.8, 4.6), (-2.0, 5.6), (2.0, 5.6), (4.8, 4.6), (5.6, 2.2), (3.4, 1.2), (3.6, -5.4), (-3.6, -5.4), (-3.4, 1.2), (-5.6, 2.2)], M)
    i.rect(-3.6, -2.6, 3.6, -1.4, A, 0.3)
    i.disc(0, 2.0, 1.2, A, 8, 0.4)
    return i


def glove():
    i = Icon("glove")
    i.poly([(-3.2, -2.4), (3.2, -2.4), (3.6, 1.8), (-3.6, 1.8)], M)
    for k, (x, h) in enumerate(((-2.7, 5.2), (-0.9, 6.0), (0.9, 5.6), (2.7, 4.6))):
        i.rect(x - 0.75, 1.4, x + 0.75, h, M, 0.35)
    i.poly([(-3.4, -0.4), (-5.6, 1.6), (-4.6, 2.8), (-2.8, 1.0)], M, 0.4)
    i.rect(-3.6, -5.6, 3.6, -2.2, A, 0.5)
    return i


def boot():
    i = Icon("boot")
    i.poly([(-2.8, 6.0), (1.6, 6.0), (1.6, -0.4), (5.8, -2.0), (5.8, -5.4), (-3.4, -5.4)], M)
    i.rect(-3.4, -5.6, 5.8, -4.2, A, 0.3)
    i.rect(-3.0, 4.2, 1.8, 6.0, A, 0.3)
    return i


def shield():
    i = Icon("shield")
    i.poly([(-4.8, 5.4), (4.8, 5.4), (4.8, 0.4), (3.2, -3.2), (0, -6.0), (-3.2, -3.2), (-4.8, 0.4)], M)
    i.poly([(-0.9, 4.2), (0.9, 4.2), (0.9, -3.6), (-0.9, -3.6)], A, 0.3)
    i.poly([(-3.2, 1.0), (3.2, 1.0), (3.2, 2.2), (-3.2, 2.2)], A, 0.3)
    return i


def buckler():
    i = Icon("buckler")
    i.disc(0, 0, 5.2, M, 16, 0.9, 1.0)
    i.disc(0, 0, 1.9, A, 10, 0.6, 1.2)
    return i


def towershield():
    i = Icon("towershield")
    i.poly([(-3.8, 6.0), (3.8, 6.0), (3.8, -1.0), (2.6, -4.4), (0, -6.2), (-2.6, -4.4), (-3.8, -1.0)], M)
    i.rect(-0.7, 5.0, 0.7, -4.4, A, 0.25)
    i.rect(-3.0, 1.6, 3.0, 2.6, A, 0.25)
    return i


def crown():
    i = Icon("crown")
    i.poly([(-5.2, -3.6), (5.2, -3.6), (5.6, 2.4), (3.0, 0.2), (2.0, 5.0), (0, 1.0), (-2.0, 5.0), (-3.0, 0.2), (-5.6, 2.4)], M)
    i.rect(-5.0, -3.6, 5.0, -2.0, A, 0.3)
    i.disc(0, -0.8, 0.8, A, 6, 0.3)
    return i


def cloak():
    i = Icon("cloak")
    i.poly([(-2.4, 5.8), (2.4, 5.8), (3.4, 2.0), (5.8, -5.6), (-5.8, -5.6), (-3.4, 2.0)], A)
    i.rect(-2.8, 4.4, 2.8, 5.8, M, 0.3)
    i.disc(0, 4.8, 0.9, M, 8, 0.3)
    return i


def veil():
    i = Icon("veil")
    i.poly([(-5.2, 4.6), (5.2, 4.6), (4.6, -1.0), (5.4, -5.4), (2.6, -4.2), (0, -5.8), (-2.6, -4.2), (-5.4, -5.4), (-4.6, -1.0)], A)
    i.rect(-5.2, 3.6, 5.2, 4.8, M, 0.3)
    return i


# -- jewellery ------------------------------------------------------------------------------
def amulet():
    i = Icon("amulet")
    i.arc(0, 1.4, 4.6, math.radians(200), math.radians(340), 0.9, A, 8)
    i.line((-4.3, 0.2), (-1.4, 5.8), 0.9, A, 0.25)
    i.line((4.3, 0.2), (1.4, 5.8), 0.9, A, 0.25)
    i.poly([(0, -1.2), (2.4, -3.0), (2.0, -5.6), (0, -6.4), (-2.0, -5.6), (-2.4, -3.0)], M)
    i.disc(0, -3.6, 0.9, A, 6, 0.3)
    return i


def ring():
    i = Icon("ring")
    i.arc(0, -0.8, 3.6, 0, math.tau, 2.0, A, 14)
    i.poly([(0, 5.6), (2.0, 3.6), (0, 1.8), (-2.0, 3.6)], M, 0.6)
    return i


def charm():
    i = Icon("charm")
    i.arc(0, 4.0, 2.0, 0, math.tau, 0.9, A, 10)
    i.line((0, 2.0), (0, -0.6), 0.8, A, 0.2)
    i.disc(0, -3.2, 2.8, M, 10, 0.8)
    i.disc(0, -3.2, 1.0, A, 6, 0.3)
    return i


def medallion():
    i = Icon("medallion")
    i.line((-2.6, 6.0), (0, 2.6), 0.9, A, 0.2)
    i.line((2.6, 6.0), (0, 2.6), 0.9, A, 0.2)
    i.disc(0, -1.4, 4.4, A, 14, 0.8, 1.0)
    i.disc(0, -1.4, 2.4, M, 10, 0.6, 1.2)
    return i


def token():
    i = Icon("token")
    i.disc(0, 0, 5.4, M, 16, 0.9, 1.0)
    i.disc(0, 0, 3.2, A, 12, 0.6, 1.2)
    i.disc(0, 0, 1.2, M, 6, 0.3, 1.4)
    return i


# -- consumables and curios -----------------------------------------------------------------
def flask():
    i = Icon("flask")
    i.poly([(-1.3, 6.0), (1.3, 6.0), (1.3, 2.4), (4.6, -2.6), (3.4, -5.6), (-3.4, -5.6), (-4.6, -2.6), (-1.3, 2.4)], M)
    i.poly([(-3.6, -2.6), (3.6, -2.6), (3.0, -4.8), (-3.0, -4.8)], A, 0.4)
    i.rect(-1.6, 5.4, 1.6, 6.8, A, 0.3)
    return i


def oil():
    i = Icon("oil")
    i.poly([(-1.5, 4.6), (1.5, 4.6), (1.5, 2.6), (3.6, 1.2), (3.6, -5.4), (-3.6, -5.4), (-3.6, 1.2), (-1.5, 2.6)], M)
    i.rect(-3.0, -4.6, 3.0, -0.2, A, 0.4)
    i.rect(-1.0, 4.4, 1.0, 5.6, A, 0.3)
    i.poly([(0, 7.0), (1.2, 5.6), (0, 4.6), (-1.2, 5.6)], A, 0.25)
    return i


def bomb():
    i = Icon("bomb")
    i.disc(0, -1.6, 4.6, M, 14, 1.0, 1.4)
    i.rect(-1.1, 2.6, 1.1, 4.0, A, 0.3)
    i.line((0.4, 3.8), (2.4, 5.6), 0.7, A, 0.2)
    i.poly([(2.4, 6.6), (3.4, 5.6), (2.4, 4.8), (1.6, 5.6)], A, 0.2)
    return i


def caltrops():
    i = Icon("caltrops")
    i.poly([(-5.4, -3.6), (-0.6, -0.6), (-0.6, -4.2)], M, 0.4)
    i.poly([(5.4, -3.6), (0.6, -0.6), (0.6, -4.2)], M, 0.4)
    i.poly([(-0.9, -0.6), (0.9, -0.6), (0, 5.8)], M, 0.4)
    i.disc(0, -2.0, 1.5, A, 8, 0.4)
    return i


def scroll():
    i = Icon("scroll")
    i.rect(-3.8, -4.4, 3.8, 4.4, A, 0.5)
    i.rect(-4.8, 3.6, 4.8, 5.4, M, 0.5)
    i.rect(-4.8, -5.4, 4.8, -3.6, M, 0.5)
    for y in (-1.6, 0.2, 2.0):
        i.rect(-2.6, y - 0.25, 2.6, y + 0.25, X, 0.12)
    return i


def key():
    i = Icon("key")
    i.arc(0, 3.6, 2.3, 0, math.tau, 1.6, A, 12)
    i.line((0, 1.4), (0, -5.6), 1.4, A, 0.3)
    i.rect(0.4, -5.6, 2.6, -4.4, A, 0.3)
    i.rect(0.4, -3.4, 2.0, -2.2, A, 0.3)
    return i


def torch():
    i = Icon("torch")
    i.line((0, -6.2), (0, 0.6), 1.6, A, 0.4)
    i.poly([(-1.6, 0.4), (1.6, 0.4), (2.0, 2.4), (-2.0, 2.4)], M, 0.35)
    i.poly([(0, 6.8), (2.6, 3.8), (1.6, 2.2), (-1.6, 2.2), (-2.6, 3.8)], A, 0.6)
    return i


def pouch():
    i = Icon("pouch")
    i.poly([(-1.8, 3.6), (1.8, 3.6), (4.6, 0.0), (4.4, -4.4), (2.0, -5.6), (-2.0, -5.6), (-4.4, -4.4), (-4.6, 0.0)], A)
    i.rect(-2.4, 3.0, 2.4, 4.2, M, 0.3)
    i.rect(-1.0, 4.0, 1.0, 5.8, M, 0.3)
    return i


def whetstone():
    i = Icon("whetstone")
    i.poly([(-5.6, -1.6), (4.6, -3.2), (5.6, 0.6), (-4.6, 2.4)], M)
    i.poly([(-3.6, -0.2), (2.6, -1.0), (2.8, 0.2), (-3.4, 1.0)], X, 0.15)
    return i


def ingot_bar():
    i = Icon("ingot")
    i.poly([(-5.4, -4.6), (5.4, -4.6), (4.2, -0.4), (-4.2, -0.4)], M)
    i.poly([(-4.4, 0.2), (0.2, 0.2), (-0.4, 4.4), (-3.4, 4.4)], M)
    i.poly([(0.6, 0.2), (5.2, 0.2), (4.2, 4.4), (1.4, 4.4)], A)
    return i


def scrap():
    i = Icon("scrap")
    i.poly([(-5.2, -3.2), (-1.2, -4.6), (0.4, -1.0), (-3.4, 0.8)], M)
    i.poly([(0.2, -1.6), (4.6, -2.6), (5.0, 1.6), (1.6, 2.6)], A)
    i.poly([(-2.2, 1.6), (1.6, 3.0), (0.4, 5.6), (-3.4, 4.4)], M)
    return i


def chalice():
    i = Icon("chalice")
    i.poly([(-4.4, 5.6), (4.4, 5.6), (3.6, 0.4), (1.0, -1.2), (-1.0, -1.2), (-3.6, 0.4)], A)
    i.poly([(-0.9, -1.0), (0.9, -1.0), (0.9, -4.4), (-0.9, -4.4)], A, 0.3)
    i.poly([(-3.6, -6.0), (3.6, -6.0), (2.4, -4.2), (-2.4, -4.2)], A, 0.4)
    i.rect(-3.4, 4.0, 3.4, 4.8, M, 0.25)
    return i


def banner():
    i = Icon("banner")
    i.line((-3.6, -6.2), (-3.6, 6.2), 1.1, A, 0.3)
    i.poly([(-3.0, 5.4), (4.8, 5.4), (4.8, -2.4), (0.9, -4.6), (-3.0, -2.4)], M)
    i.disc(0.9, 0.6, 1.8, A, 8, 0.5)
    return i


def runestone():
    i = Icon("runestone")
    i.poly([(-3.6, -5.4), (3.6, -5.4), (4.6, 2.2), (1.6, 6.0), (-2.6, 5.6), (-4.6, 1.6)], M)
    i.line((0, 3.2), (0, -3.6), 1.1, A, 0.3)
    i.line((-2.0, 0.8), (2.0, -0.4), 1.0, A, 0.3)
    return i


def orb():
    i = Icon("orb")
    i.disc(0, 1.0, 4.8, M, 16, 1.1, 1.6)
    i.disc(-1.2, 2.2, 1.6, A, 8, 0.4, 1.8)
    i.poly([(-3.2, -4.0), (3.2, -4.0), (2.0, -6.0), (-2.0, -6.0)], A, 0.4)
    return i


def heart():
    i = Icon("heart")
    i.poly([(0, -5.6), (-4.0, -1.4), (-5.2, 2.0), (-3.8, 4.6), (-1.6, 4.8), (0, 3.0), (1.6, 4.8), (3.8, 4.6), (5.2, 2.0), (4.0, -1.4)], A, 1.0)
    return i


def gem():
    i = Icon("gem")
    i.poly([(-3.0, 4.6), (3.0, 4.6), (5.6, 1.0), (0, -5.6), (-5.6, 1.0)], M, 1.0)
    i.poly([(-1.8, 3.6), (1.8, 3.6), (0.6, 0.2), (-0.6, 0.2)], A, 0.4, 0.6)
    return i


def shard():
    i = Icon("shard")
    i.poly([(-1.8, -5.6), (1.6, -5.6), (3.4, 0.0), (0.4, 6.4), (-2.4, 1.0)], M, 0.9)
    i.poly([(-0.6, -2.0), (0.6, -2.0), (0.8, 1.6), (0.0, 3.6)], A, 0.3, 0.6)
    return i


ICONS = {
    "sword": sword, "greatsword": greatsword, "dagger": dagger, "shortsword": shortsword, "rapier": rapier,
    "axe": axe, "hammer": hammer, "spear": spear, "halberd": halberd, "staff": staff, "bow_recurve": bow_recurve,
    "helm": helm, "cuirass": cuirass, "glove": glove, "boot": boot, "shield": shield, "buckler": buckler,
    "towershield": towershield, "crown": crown, "cloak": cloak, "veil": veil,
    "amulet": amulet, "ring": ring, "charm": charm, "medallion": medallion, "token": token,
    "flask": flask, "oil": oil, "bomb": bomb, "caltrops": caltrops, "scroll": scroll, "key": key,
    "torch": torch, "pouch": pouch, "whetstone": whetstone, "ingot_bar": ingot_bar, "scrap": scrap,
    "chalice": chalice, "banner": banner, "runestone": runestone, "orb": orb, "heart": heart,
    "gem": gem, "shard": shard,
}


# -- status effects -------------------------------------------------------------------------
# These sheets have five tones and no accent, so they are drawn in the main material only.
def st_bleed():
    i = Icon("bleed")
    i.poly([(0, 6.4), (2.2, 2.8), (3.6, 0), (3.4, -2.8), (1.9, -5.0), (0, -5.8), (-1.9, -5.0), (-3.4, -2.8), (-3.6, 0), (-2.2, 2.8)], M, 1.0, 1.2)
    i.poly([(-1.6, -0.4), (-0.6, -0.4), (-0.6, -3.4), (-1.6, -3.0)], M, 0.2, 0.6)
    return i


def st_burn():
    i = Icon("burn")
    i.poly([(0.6, 6.6), (3.2, 2.8), (4.8, -0.6), (3.6, -4.6), (0, -6.0), (-3.6, -4.6), (-4.8, -0.6), (-3.0, 1.6), (-1.8, 4.0)], M, 1.0, 1.0)
    i.poly([(0.2, 2.0), (2.2, -1.0), (1.6, -3.8), (0, -4.6), (-1.6, -3.8), (-2.0, -1.0)], X, 0.6, 0.8)
    i.poly([(0.1, -0.6), (1.0, -2.6), (0, -3.8), (-1.0, -2.6)], M, 0.3, 0.8)
    return i


def st_freeze():
    i = Icon("freeze")
    for k in range(3):
        a = math.pi * k / 3
        i.line((-math.cos(a) * 5.8, -math.sin(a) * 5.8), (math.cos(a) * 5.8, math.sin(a) * 5.8), 1.5, M, 0.4)
    i.disc(0, 0, 2.0, M, 6, 0.6, 1.4)
    for k in range(6):
        a = math.tau * k / 6
        i.disc(math.cos(a) * 5.0, math.sin(a) * 5.0, 1.0, M, 4, 0.3, 1.0)
    return i


def st_poison():
    i = Icon("poison")
    i.poly([(0, 6.2), (2.4, 2.4), (3.8, -1.0), (2.8, -4.4), (0, -5.8), (-2.8, -4.4), (-3.8, -1.0), (-2.4, 2.4)], M, 1.0, 1.2)
    i.disc(-1.0, -1.6, 1.0, X, 6, 0.3, 1.6)
    i.disc(1.2, -3.2, 0.7, X, 6, 0.2, 1.6)
    i.disc(0.9, 0.4, 0.6, X, 6, 0.2, 1.6)
    return i


def st_stun():
    i = Icon("stun")
    i.poly([(0, 6.4), (1.3, 1.3), (6.4, 0), (1.3, -1.3), (0, -6.4), (-1.3, -1.3), (-6.4, 0), (-1.3, 1.3)], M, 0.8, 1.2)
    i.poly([(-4.6, 4.8), (-4.0, 3.4), (-2.6, 2.8), (-4.0, 2.2)], M, 0.2, 0.8)
    i.poly([(4.4, -3.0), (5.0, -4.4), (6.4, -5.0), (5.0, -5.6)], M, 0.2, 0.8)
    return i


def st_focus():
    i = Icon("focus")
    i.poly([(-6.0, 0), (-3.0, 3.4), (0, 4.4), (3.0, 3.4), (6.0, 0), (3.0, -3.4), (0, -4.4), (-3.0, -3.4)], M, 0.9, 1.0)
    i.disc(0, 0, 2.6, X, 10, 0.5, 1.2)
    i.disc(0, 0, 1.2, M, 8, 0.3, 1.5)
    return i


def st_resolve():
    i = Icon("resolve")
    i.poly([(0, 6.2), (5.6, 0.4), (5.6, -2.0), (0, 3.2), (-5.6, -2.0), (-5.6, 0.4)], M, 0.8, 1.0)
    i.poly([(0, 1.0), (5.0, -4.0), (5.0, -6.0), (0, -1.6), (-5.0, -6.0), (-5.0, -4.0)], M, 0.8, 1.0)
    return i


def st_stoneskin():
    i = Icon("stoneskin")
    i.poly([(-5.8, -1.0), (-4.4, 3.2), (-0.8, 4.0), (1.2, 0.8), (0.8, -4.6), (-3.4, -5.6)], M, 1.0, 1.2)
    i.poly([(-0.6, 2.4), (2.6, 5.8), (5.8, 3.0), (5.6, -2.8), (2.2, -5.8), (1.0, -1.6)], M, 1.0, 1.2)
    return i


def st_swiftness():
    i = Icon("swiftness")
    for dx in (-3.6, 0.8):
        i.poly([(dx - 1.6, 5.4), (dx + 1.2, 5.4), (dx + 4.6, 0), (dx + 1.2, -5.4), (dx - 1.6, -5.4), (dx + 1.8, 0)], M, 0.7, 1.0)
    return i


def st_torpor():
    i = Icon("torpor")
    pts = []
    for k in range(13):
        a = math.radians(50 + 260 * k / 12)
        pts.append((math.cos(a) * 5.6, math.sin(a) * 5.6))
    for k in range(13):
        a = math.radians(310 - 260 * k / 12)
        pts.append((2.7 + math.cos(a) * 4.6, math.sin(a) * 4.6))
    i.poly(pts, M, 0.9, 1.0)
    return i


STATUS_ICONS = {
    "status/bleed": st_bleed, "status/burn": st_burn, "status/freeze": st_freeze, "status/poison": st_poison,
    "status/stun": st_stun, "status/focus": st_focus, "status/resolve": st_resolve,
    "status/stoneskin": st_stoneskin, "status/swiftness": st_swiftness, "status/torpor": st_torpor,
}


# -- class emblems --------------------------------------------------------------------------
def arrow():
    i = Icon("arrow")
    i.line((-5.6, 0.0), (5.0, 0.0), 0.9, A, 0.25)
    i.poly([(5.0, -1.3), (6.6, 0.0), (5.0, 1.3)], M, 0.3)
    i.poly([(-5.8, 0.0), (-4.2, 1.6), (-3.6, 1.6), (-4.6, 0.0), (-3.6, -1.6), (-4.2, -1.6)], A, 0.25)
    return i


def _compose(name, placements):
    global XF
    icon = Icon(name)
    Icon.active = icon
    try:
        for build, angle, mirror, dx, dy in placements:
            XF = (angle, mirror, dx, dy)
            build()
    finally:
        Icon.active = None
        XF = (0.0, False, 0.0, 0.0)
    return icon


EMBLEMS = {
    "berserker": lambda: _compose("berserker", [(axe, -24, False, 2.6, 0), (axe, 24, True, -2.6, 0)]),
    "knight": lambda: _compose("knight", [(shield, 0, False, 0, 0)]),
    "rogue": lambda: _compose("rogue", [(dagger, 38, False, -1.0, 0), (dagger, -38, True, 1.0, 0)]),
    "scholar": lambda: _compose("scholar", [(staff, -18, False, 0, 0)]),
    "sentinel": lambda: _compose("sentinel", [(spear, 12, False, 4.6, 0), (towershield, 0, False, -1.0, 0)]),
    "hunter": lambda: _compose("hunter", [(bow_recurve, 0, False, -1.5, 0), (arrow, 0, False, 0.0, 0)]),
    "herald": lambda: _compose("herald", [(banner, 0, False, 0, 0)]),
}
