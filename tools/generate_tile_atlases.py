#!/usr/bin/env python3
"""Draw the per-biome floor and wall tile atlases.

All eleven atlases shipped as the same 666-byte file: a single flat colour, 256x256. Because the
pixel-diorama surface shader samples them for every floor and wall, that meant the entire world —
the hub, the training arena and all nine dungeon biomes — was rendered as untextured colour blocks,
which the shader's banding and dithering then turned into hard, garish fields.

Layout is fixed by assets/shared/pixel_diorama_surface.gdshader, which divides the atlas by 8 on
both axes and indexes it as `vec2(variant, tile_row) / 8.0`:

    row 0, columns 0-3  floor variants
    row 1, columns 0-3  wall variants

so each tile is 32x32 in a 256x256 sheet. The shader picks a variant per world cell from a hash,
so the four variants of a surface must read as the same material with different wear — not as four
different materials — or the floor turns into a checkerboard.

Tiles are drawn to wrap: the shader samples fract(uv), so anything crossing an edge is mirrored
onto the opposite edge.

Usage:
    python tools/generate_tile_atlases.py [--check]
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PALETTES = ROOT / "content" / "art" / "palettes.json"
TEXTURE_DIR = ROOT / "apps" / "game" / "client" / "assets" / "textures"

ATLAS = 256
TILE = 32
VARIANTS = 4
FLOOR_ROW = 0
WALL_ROW = 1

#: Surface character per theme. Keeps a biome's floor and wall recognisably its own material.
#:   flag    large stone flags, mortar joints          brick   coursed rectangular blocks
#:   facet   angular crystalline planes                ice     frozen slabs with fracture lines
#:   organic irregular mossy stone                     plate   riveted metal panels
STYLES = {
    "castle": ("flag", "brick"),
    "crystal": ("facet", "facet"),
    "swamp": ("organic", "organic"),
    "frozen": ("ice", "ice"),
    "cathedral": ("flag", "brick"),
    "vault": ("plate", "plate"),
    "prism": ("facet", "facet"),
    "mire": ("organic", "organic"),
    "hollow": ("ice", "ice"),
    "umbral": ("flag", "brick"),
    "hub": ("flag", "brick"),
}


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t: float):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(colour, factor: float):
    return tuple(max(0, min(255, int(round(c * factor)))) for c in colour)


def wrapped_line(d: ImageDraw.ImageDraw, points, colour) -> None:
    """Draws a run of pixels, wrapping coordinates so the tile stays seamless."""
    for x, y in points:
        d.point((x % TILE, y % TILE), fill=colour)


def speckle(d: ImageDraw.ImageDraw, rng: random.Random, colour, count: int) -> None:
    for _ in range(count):
        d.point((rng.randrange(TILE), rng.randrange(TILE)), fill=colour)


# ------------------------------------------------------------------------------------ surfaces


def draw_flag(base, dark, accent, rng: random.Random, variant: int) -> Image.Image:
    """Stone flags: two courses of large slabs with offset joints."""
    tile = Image.new("RGB", (TILE, TILE), base)
    d = ImageDraw.Draw(tile)
    joint = shade(dark, 0.78)
    for y in range(TILE):
        for x in range(TILE):
            if (x + y * 3) % 17 == 0:
                d.point((x, y), fill=mix(base, dark, 0.18))
    # Horizontal courses at y = 0 and 16, vertical joints offset per course.
    for y in (0, 16):
        d.line([(0, y), (TILE - 1, y)], fill=joint)
        d.line([(0, y + 1), (TILE - 1, y + 1)], fill=mix(base, joint, 0.45))
    offset = 8 if variant % 2 else 0
    for course, top in enumerate((0, 16)):
        seam = (offset + course * 16) % TILE
        d.line([(seam, top), (seam, top + 15)], fill=joint)
        d.line([((seam + 1) % TILE, top), ((seam + 1) % TILE, top + 15)],
               fill=mix(base, joint, 0.5))
    # Worn highlight along the top of each slab, chips along the bottom.
    for top in (2, 18):
        d.line([(2, top), (TILE - 3, top)], fill=mix(base, (255, 255, 255), 0.10))
    for _ in range(2 + variant):
        cx, cy = rng.randrange(TILE), rng.randrange(TILE)
        d.point((cx, cy), fill=shade(dark, 0.9))
        d.point(((cx + 1) % TILE, cy), fill=mix(base, dark, 0.5))
    speckle(d, rng, mix(base, dark, 0.35), 10 + variant * 4)
    if variant == 3:
        d.rectangle([12, 20, 15, 23], fill=mix(base, accent, 0.35))
    return tile


def draw_brick(base, dark, accent, rng: random.Random, variant: int) -> Image.Image:
    """Coursed masonry: four rows of running-bond blocks."""
    tile = Image.new("RGB", (TILE, TILE), base)
    d = ImageDraw.Draw(tile)
    mortar = shade(dark, 0.72)
    course_h = 8
    for row in range(TILE // course_h):
        y = row * course_h
        d.line([(0, y), (TILE - 1, y)], fill=mortar)
        stagger = (row % 2) * 8 + (variant * 4 if row % 2 == 0 else 0)
        for i in range(2):
            x = (stagger + i * 16) % TILE
            d.line([(x, y + 1), (x, y + course_h - 1)], fill=mortar)
        # Top-lit face of each block.
        d.line([(0, y + 1), (TILE - 1, y + 1)], fill=mix(base, (255, 255, 255), 0.09))
        d.line([(0, y + course_h - 1), (TILE - 1, y + course_h - 1)], fill=mix(base, dark, 0.35))
    speckle(d, rng, mix(base, dark, 0.4), 12 + variant * 5)
    if variant == 2:
        d.rectangle([20, 10, 23, 13], fill=mix(base, accent, 0.4))
    return tile


def draw_facet(base, dark, accent, rng: random.Random, variant: int) -> Image.Image:
    """Crystalline planes: angular shards catching light along one edge."""
    tile = Image.new("RGB", (TILE, TILE), base)
    d = ImageDraw.Draw(tile)
    rng2 = random.Random(variant * 977 + 13)
    for _ in range(5):
        cx, cy = rng2.randrange(TILE), rng2.randrange(TILE)
        size = rng2.randint(7, 13)
        pts = [
            (cx, cy - size),
            (cx + size // 2, cy),
            (cx, cy + size // 2),
            (cx - size // 2, cy),
        ]
        d.polygon(pts, fill=mix(base, dark, rng2.uniform(0.15, 0.55)))
        d.line([pts[0], pts[1]], fill=mix(base, accent, 0.5))
    for _ in range(3):
        x = rng2.randrange(TILE)
        d.line([(x, 0), ((x + 6) % TILE, TILE - 1)], fill=mix(base, accent, 0.25))
    speckle(d, rng, mix(base, (255, 255, 255), 0.4), 6 + variant * 3)
    return tile


def draw_ice(base, dark, accent, rng: random.Random, variant: int) -> Image.Image:
    """Frozen slabs: pale blocks with fracture lines and trapped bubbles."""
    tile = Image.new("RGB", (TILE, TILE), base)
    d = ImageDraw.Draw(tile)
    seam = mix(dark, (255, 255, 255), 0.12)
    d.line([(0, 15), (TILE - 1, 15)], fill=seam)
    x_seam = (6 + variant * 7) % TILE
    d.line([(x_seam, 0), (x_seam, 14)], fill=seam)
    d.line([((x_seam + 15) % TILE, 16), ((x_seam + 15) % TILE, TILE - 1)], fill=seam)
    rng2 = random.Random(variant * 613 + 7)
    for _ in range(3 + variant):
        x, y = rng2.randrange(TILE), rng2.randrange(TILE)
        pts = [(x + i, y + (i * (1 if i % 2 else -1)) // 2) for i in range(6)]
        wrapped_line(d, pts, mix(base, (255, 255, 255), 0.35))
    for _ in range(4):
        d.point((rng2.randrange(TILE), rng2.randrange(TILE)), fill=mix(base, accent, 0.55))
    speckle(d, rng, mix(base, dark, 0.3), 8)
    return tile


def draw_organic(base, dark, accent, rng: random.Random, variant: int) -> Image.Image:
    """Irregular wet stone with moss creeping through the joints."""
    tile = Image.new("RGB", (TILE, TILE), base)
    d = ImageDraw.Draw(tile)
    rng2 = random.Random(variant * 431 + 3)
    for _ in range(7):
        cx, cy = rng2.randrange(TILE), rng2.randrange(TILE)
        r = rng2.randint(3, 7)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=mix(base, dark, rng2.uniform(0.2, 0.5)))
    # Moss runs, wrapped so they continue across tiles.
    for _ in range(3 + variant):
        x, y = rng2.randrange(TILE), rng2.randrange(TILE)
        pts = [(x + i, y + rng2.randint(-1, 1)) for i in range(rng2.randint(6, 12))]
        wrapped_line(d, pts, mix(base, accent, 0.45))
    speckle(d, rng, mix(base, accent, 0.3), 12 + variant * 4)
    speckle(d, rng, shade(dark, 0.8), 10)
    return tile


def draw_plate(base, dark, accent, rng: random.Random, variant: int) -> Image.Image:
    """Riveted metal panels with a recessed seam cross."""
    tile = Image.new("RGB", (TILE, TILE), base)
    d = ImageDraw.Draw(tile)
    seam = shade(dark, 0.7)
    d.line([(0, 15), (TILE - 1, 15)], fill=seam)
    d.line([(0, 16), (TILE - 1, 16)], fill=mix(base, (255, 255, 255), 0.08))
    x = (7 + variant * 8) % TILE
    d.line([(x, 0), (x, TILE - 1)], fill=seam)
    d.line([((x + 1) % TILE, 0), ((x + 1) % TILE, TILE - 1)],
           fill=mix(base, (255, 255, 255), 0.08))
    for ry in (4, 20):
        for rx in range(4, TILE, 10):
            d.point(((rx + variant) % TILE, ry), fill=mix(base, accent, 0.55))
            d.point(((rx + variant) % TILE, ry + 1), fill=shade(dark, 0.75))
    speckle(d, rng, mix(base, dark, 0.35), 8 + variant * 3)
    return tile


DRAWERS = {
    "flag": draw_flag,
    "brick": draw_brick,
    "facet": draw_facet,
    "ice": draw_ice,
    "organic": draw_organic,
    "plate": draw_plate,
}


def build_atlas(theme: str, palette: dict) -> Image.Image:
    floor_base = hex_to_rgb(palette["floor_base"])
    floor_dark = hex_to_rgb(palette["floor_shadow"])
    wall_base = hex_to_rgb(palette["wall_base"])
    wall_dark = hex_to_rgb(palette["wall_shadow"])
    accent = hex_to_rgb(palette["accent"])

    atlas = Image.new("RGBA", (ATLAS, ATLAS), (*floor_base, 255))
    floor_style, wall_style = STYLES[theme]
    for variant in range(VARIANTS):
        rng = random.Random(f"{theme}-floor-{variant}")
        tile = DRAWERS[floor_style](floor_base, floor_dark, accent, rng, variant)
        atlas.paste(tile, (variant * TILE, FLOOR_ROW * TILE))
        rng = random.Random(f"{theme}-wall-{variant}")
        tile = DRAWERS[wall_style](wall_base, wall_dark, accent, rng, variant)
        atlas.paste(tile, (variant * TILE, WALL_ROW * TILE))
    return atlas


def load_palettes() -> dict:
    return json.loads(PALETTES.read_text(encoding="utf-8"))["palettes"]


def check(palettes: dict) -> int:
    problems: list[str] = []
    for theme in STYLES:
        path = TEXTURE_DIR / theme / "tiles.png"
        if not path.exists():
            problems.append("%s: missing %s" % (theme, path))
            continue
        image = Image.open(path).convert("RGB")
        if image.size != (ATLAS, ATLAS):
            problems.append("%s: expected %dx%d, found %s" % (theme, ATLAS, ATLAS, image.size))
            continue
        for row, label in ((FLOOR_ROW, "floor"), (WALL_ROW, "wall")):
            for variant in range(VARIANTS):
                box = (variant * TILE, row * TILE, (variant + 1) * TILE, (row + 1) * TILE)
                colours = image.crop(box).getcolors(TILE * TILE)
                if colours is not None and len(colours) <= 1:
                    problems.append(
                        "%s: %s variant %d is a flat colour" % (theme, label, variant)
                    )
    if problems:
        for problem in problems:
            print("FAIL %s" % problem)
        return 1
    print("OK %d tile atlases, %d floor + %d wall variants each"
          % (len(STYLES), VARIANTS, VARIANTS))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify every atlas has drawn tiles")
    args = parser.parse_args()
    palettes = load_palettes()
    if args.check:
        return check(palettes)
    for theme in STYLES:
        if theme not in palettes:
            print("WARN no palette for theme %s" % theme)
            continue
        out = TEXTURE_DIR / theme / "tiles.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        build_atlas(theme, palettes[theme]).save(out, optimize=True)
        print("Wrote %s" % out.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
