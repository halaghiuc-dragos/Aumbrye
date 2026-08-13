#!/usr/bin/env python3
"""Bring oversized VFX/HUD textures back to true pixel-art resolution with a real alpha channel.

Two defects are corrected here.

First, these textures were fully opaque: the "transparency" around each sprite was a light grey
checkerboard painted into the pixels. Godot has no way to know that, so a blood decal rendered as
an opaque white square with a splat in the middle, and the lock-on reticle covered the HUD with a
white block. The background is keyed out by flood-filling near-neutral light pixels inward from the
border, which removes the checkerboard without touching light pixels enclosed by the artwork.

Second, they shipped at 1024-1536 px with interpolated edges, imitating pixel art rather than being
it. At the sizes they are actually drawn -- HUD pips at 14x8 px, decals at 0.28-0.42 world units on
a pixel-snapped grid -- that reads as blur next to the genuine 1-4 KB pixel atlases, and costs
~7.5 MB of repository and PCK weight.

Each texture is rewritten at the resolution its consumer expects: key the background, crop to the
remaining artwork, resample down, then harden the alpha edge so the result stays crisp under
nearest-neighbour filtering. Colours come from the source art, so the art direction is preserved --
only the sampling grid and the alpha channel change.

Usage:
    python tools/normalize_pixel_textures.py [--check]

--check reports what would change and exits non-zero if anything is out of date.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "apps" / "game" / "client" / "assets"

# Alpha below this is treated as background when locating the real artwork, which discards the
# faint halo the upscaler left across the whole canvas.
CONTENT_ALPHA = 32

# Edge hardening threshold. Anything at or above becomes fully opaque, anything below fully clear.
EDGE_ALPHA = 110

# A pixel counts as background only if it is both light and near-neutral, which matches the white
# and the two checkerboard greys without matching the cream of the dust puff.
BACKGROUND_MIN_LUMA = 214
BACKGROUND_MAX_CHROMA = 12

# Luminance spread that identifies the alternating checkerboard rather than a flat highlight.
CHECKER_LUMA_SPREAD = 6


@dataclass(frozen=True)
class Target:
    path: str
    width: int
    height: int
    #: Split the source into this many equal columns and fit each into its own output cell.
    #: Used by sprite strips whose cells are addressed individually by an atlas manifest.
    cells: int = 1
    #: Keep the soft alpha gradient (for smoke/dust puffs, where a hard edge looks wrong).
    soft_alpha: bool = False
    note: str = ""


TARGETS: list[Target] = [
    # combat_hud.gd draws each pip at exactly 14x8 px, and content/ui/hud_atlas.json addresses
    # them as two 14x8 regions side by side, so the sheet is 28x8.
    Target("ui/hud_pips.png", 28, 8, cells=2, note="two 14x8 pips: filled, empty"),
    Target("ui/hud_reticle.png", 32, 32, note="lock-on reticle"),
    Target("ui/hud_objective.png", 16, 16, note="objective chevron"),
    Target("textures/vfx/blood_large.png", 48, 48),
    Target("textures/vfx/blood_small.png", 32, 32),
    Target("textures/vfx/dust_ring.png", 32, 32, soft_alpha=True, note="dust puff keeps a gradient"),
    Target("textures/vfx/impact_scorch.png", 32, 32),
    Target("textures/vfx/impact_small.png", 24, 24),
]


def key_background(image: Image.Image) -> Image.Image:
    """Replace the painted checkerboard/white background with real transparency.

    A region is background when it is light, near-neutral, and either reaches the image border or
    carries the checkerboard's alternating greys. The second rule matters for shapes that enclose
    background — the lock-on reticle's centre must be see-through, or it covers the enemy it is
    pointing at. A uniformly coloured light region enclosed by artwork is a highlight and is kept.
    """
    width, height = image.size
    pixels = image.load()

    def is_background_colour(x: int, y: int) -> bool:
        r, g, b, a = pixels[x, y]
        if a == 0:
            return True
        return (
            min(r, g, b) >= BACKGROUND_MIN_LUMA
            and (max(r, g, b) - min(r, g, b)) <= BACKGROUND_MAX_CHROMA
        )

    visited = [[False] * width for _ in range(height)]
    cleared = [[False] * width for _ in range(height)]

    for seed_y in range(height):
        for seed_x in range(width):
            if visited[seed_y][seed_x] or not is_background_colour(seed_x, seed_y):
                continue

            component: list[tuple[int, int]] = []
            lumas: set[int] = set()
            touches_border = False
            stack = [(seed_x, seed_y)]
            visited[seed_y][seed_x] = True

            while stack:
                x, y = stack.pop()
                component.append((x, y))
                if x == 0 or y == 0 or x == width - 1 or y == height - 1:
                    touches_border = True
                lumas.add(pixels[x, y][1])
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < width and 0 <= ny < height and not visited[ny][nx]:
                        if is_background_colour(nx, ny):
                            visited[ny][nx] = True
                            stack.append((nx, ny))

            # Two or more distinct greys means the checkerboard, not a flat highlight.
            banded = (max(lumas) - min(lumas)) >= CHECKER_LUMA_SPREAD
            if touches_border or banded:
                for x, y in component:
                    cleared[y][x] = True

    out = image.copy()
    out_pixels = out.load()
    for y in range(height):
        row = cleared[y]
        for x in range(width):
            if row[x]:
                r, g, b, _ = out_pixels[x, y]
                out_pixels[x, y] = (r, g, b, 0)
    return out


def content_box(image: Image.Image) -> tuple[int, int, int, int]:
    """Bounding box of pixels above CONTENT_ALPHA, or the whole image when nothing qualifies."""
    alpha = image.getchannel("A").point(lambda v: 255 if v >= CONTENT_ALPHA else 0)
    return alpha.getbbox() or (0, 0, image.width, image.height)


def harden(image: Image.Image) -> Image.Image:
    """Snap the alpha edge so the sprite stays crisp when sampled nearest-neighbour."""
    r, g, b, a = image.split()
    return Image.merge("RGBA", (r, g, b, a.point(lambda v: 255 if v >= EDGE_ALPHA else 0)))


def fit_cell(source: Image.Image, width: int, height: int, soft_alpha: bool) -> Image.Image:
    cropped = source.crop(content_box(source))
    resized = cropped.resize((width, height), Image.LANCZOS)
    return resized if soft_alpha else harden(resized)


def build(target: Target) -> Image.Image:
    source = key_background(Image.open(ASSETS / target.path).convert("RGBA"))
    if target.cells == 1:
        return fit_cell(source, target.width, target.height, target.soft_alpha)

    cell_w = target.width // target.cells
    out = Image.new("RGBA", (target.width, target.height), (0, 0, 0, 0))
    slice_w = source.width // target.cells
    for index in range(target.cells):
        piece = source.crop((index * slice_w, 0, (index + 1) * slice_w, source.height))
        out.paste(
            fit_cell(piece, cell_w, target.height, target.soft_alpha),
            (index * cell_w, 0),
        )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report drift instead of rewriting")
    args = parser.parse_args()

    stale = 0
    for target in TARGETS:
        path = ASSETS / target.path
        if not path.exists():
            print(f"MISSING {target.path}")
            stale += 1
            continue

        current = Image.open(path)
        if current.size == (target.width, target.height):
            print(f"OK      {target.path} ({target.width}x{target.height})")
            continue

        stale += 1
        before_kb = path.stat().st_size / 1024
        if args.check:
            print(
                f"STALE   {target.path} is {current.width}x{current.height}, "
                f"expected {target.width}x{target.height}"
            )
            continue

        build(target).save(path, optimize=True)
        after_kb = path.stat().st_size / 1024
        detail = f" — {target.note}" if target.note else ""
        print(
            f"REWROTE {target.path}: {current.width}x{current.height} ({before_kb:.0f} KB) -> "
            f"{target.width}x{target.height} ({after_kb:.1f} KB){detail}"
        )

    if args.check and stale:
        print(f"\n{stale} texture(s) are not at native resolution.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
