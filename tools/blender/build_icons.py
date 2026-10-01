"""Rasterise the icon models to 16 x 16 glyph rows.

    Blender/blender -b -P tools/blender/build_icons.py

Writes tools/icon-gen/glyphs.json: for each shape, sixteen strings in the atlas glyph alphabet
(`.` clear, `o` outline, `d m l h` metal tones, `a b c` accent tones). Each model is fitted to a
12 x 12 pixel box, so the outline ring lands inside a one-pixel margin.
"""

from __future__ import annotations

import json
import math
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import bl_lib  # noqa: E402
from icons import EMBLEMS, ICONS, STATUS_ICONS  # noqa: E402

CELL = 16
SS = 8
FIT = 12.0
LIGHT = (-0.5, 0.7, 0.55)
_l = math.sqrt(sum(c * c for c in LIGHT))
LIGHT = tuple(c / _l for c in LIGHT)


def _faces(icon):
    bm = icon.m.bm
    out = []
    for f in bm.faces:
        tag = icon.m._mats[f.material_index]
        mat, part = tag.split("#")
        pts = [(v.co.x, v.co.z, -v.co.y) for v in f.verts]  # back to the model's own frame
        out.append((mat, int(part), pts))
    return out


def _normal(pts):
    nx = ny = nz = 0.0
    for i, (x0, y0, z0) in enumerate(pts):
        x1, y1, z1 = pts[(i + 1) % len(pts)]
        nx += (y0 - y1) * (z0 + z1)
        ny += (z0 - z1) * (x0 + x1)
        nz += (x0 - x1) * (y0 + y1)
    ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return nx / ln, ny / ln, nz / ln


def _tone(mat, dot, main_only=False):
    if main_only and mat == "a":
        mat = "m"
    if mat == "x":
        return "d"
    if mat == "a":
        return "c" if dot > 0.62 else ("b" if dot > 0.2 else "a")
    return "h" if dot > 0.8 else ("l" if dot > 0.5 else ("m" if dot > 0.15 else "d"))


def render(icon, main_only=False, cell=CELL, ss=SS, fit=FIT):
    faces = _faces(icon)
    xs = [p[0] for _, _, pts in faces for p in pts]
    ys = [p[1] for _, _, pts in faces for p in pts]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    scale = fit / max(w, h)
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    size = cell * ss
    zbuf = [[-1e9] * size for _ in range(size)]
    samples = [[None] * size for _ in range(size)]
    for mat, part, pts in faces:
        n = _normal(pts)
        if n[2] <= 1e-3:
            continue
        tone = _tone(mat, n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2], main_only)
        proj = [((p[0] - cx) * scale, (p[1] - cy) * scale, p[2] * scale) for p in pts]
        for k in range(1, len(proj) - 1):
            _tri(proj[0], proj[k], proj[k + 1], zbuf, samples, (mat, part, tone), cell, ss)
    # Downsample: a pixel is filled when enough of its samples are.
    grid = [["." for _ in range(cell)] for _ in range(cell)]
    for py in range(cell):
        for px in range(cell):
            seen = []
            for sy in range(ss):
                for sx in range(ss):
                    sample = samples[py * ss + sy][px * ss + sx]
                    if sample is not None:
                        seen.append(sample)
            if len(seen) >= ss * ss * 0.34:
                grid[py][px] = Counter(t[2] for t in seen).most_common(1)[0][0]
    out = [row[:] for row in grid]
    for y in range(cell):
        for x in range(cell):
            if grid[y][x] != ".":
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < cell and 0 <= ny < cell and grid[ny][nx] != ".":
                    out[y][x] = "o"
                    break
    return ["".join(r) for r in out]


def _tri(a, b, c, zbuf, samples, payload, cell, ss):
    size = cell * ss
    half = cell / 2

    def to_px(p):
        return ((p[0] + half) * ss, (half - p[1]) * ss, p[2])

    pa, pb, pc = to_px(a), to_px(b), to_px(c)
    min_x = max(0, int(math.floor(min(pa[0], pb[0], pc[0]))))
    max_x = min(size - 1, int(math.ceil(max(pa[0], pb[0], pc[0]))))
    min_y = max(0, int(math.floor(min(pa[1], pb[1], pc[1]))))
    max_y = min(size - 1, int(math.ceil(max(pa[1], pb[1], pc[1]))))
    den = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
    if abs(den) < 1e-9:
        return
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            sx, sy = x + 0.5, y + 0.5
            w0 = ((pb[1] - pc[1]) * (sx - pc[0]) + (pc[0] - pb[0]) * (sy - pc[1])) / den
            w1 = ((pc[1] - pa[1]) * (sx - pc[0]) + (pa[0] - pc[0]) * (sy - pc[1])) / den
            w2 = 1.0 - w0 - w1
            if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
                continue
            z = w0 * pa[2] + w1 * pb[2] + w2 * pc[2]
            if z > zbuf[y][x]:
                zbuf[y][x] = z
                samples[y][x] = payload


def main():
    glyphs = {}
    for name, build in ICONS.items():
        bl_lib.reset_scene()
        glyphs[name] = render(build())
        print("icon", name)
    for name, build in STATUS_ICONS.items():
        bl_lib.reset_scene()
        glyphs[name] = render(build(), main_only=True)
        print("icon", name)
    emblems = {}
    for name, build in EMBLEMS.items():
        bl_lib.reset_scene()
        emblems[name] = render(build(), cell=64, ss=4, fit=46.0)
        print("emblem", name)
    for filename, data in (("glyphs.json", glyphs), ("emblems.json", emblems)):
        with open(os.path.join(ROOT, "tools", "icon-gen", filename), "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=1, sort_keys=True)
            fh.write("\n")


if __name__ == "__main__":
    main()
