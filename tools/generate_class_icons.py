#!/usr/bin/env python3
"""Draw the class-select portrait atlas.

Each of the seven cells shipped as a single flat colour, so the character-creation list read as a
column of blank swatches. This keeps the established per-class colour identity and draws a legible
emblem in it: a weapon or symbol that says what the class does at a glance.

Everything is authored on the 64x64 cell grid the manifest declares
(content/ui/class_icon_atlas.json), with hard edges so it stays crisp under nearest filtering.

Usage:
    python tools/generate_class_icons.py [--check]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "apps" / "game" / "client" / "assets" / "ui" / "atlas" / "class_icons.png"

CELL = 64

#: Column order must match content/ui/class_icon_atlas.json.
ORDER = ["berserker", "knight", "rogue", "scholar", "sentinel", "hunter", "herald"]

#: Base colour per class, taken from the swatches these cells already used.
BASE = {
    "berserker": (180, 60, 50),
    "knight": (120, 130, 150),
    "rogue": (70, 120, 80),
    "scholar": (150, 110, 200),
    "sentinel": (90, 90, 110),
    "hunter": (122, 96, 58),
    "herald": (176, 158, 104),
}

STEEL = (214, 220, 232)
STEEL_DARK = (128, 138, 158)
WOOD = (110, 78, 46)
GOLD = (232, 194, 96)
INK = (26, 24, 32)


def rect(d: ImageDraw.ImageDraw, x0: int, y0: int, x1: int, y1: int, fill) -> None:
    """Rectangle that tolerates mirrored coordinates."""
    d.rectangle([min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)], fill=fill)


def shade(colour: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(channel * factor))) for channel in colour)


def backdrop(draw: ImageDraw.ImageDraw, base: tuple[int, int, int]) -> None:
    """Rounded plaque so every emblem sits on the same silhouette."""
    draw.rectangle([0, 0, CELL - 1, CELL - 1], fill=shade(base, 0.45))
    draw.rectangle([3, 3, CELL - 4, CELL - 4], fill=shade(base, 0.72))
    draw.rectangle([3, 3, CELL - 4, 6], fill=shade(base, 0.95))
    draw.rectangle([3, CELL - 8, CELL - 4, CELL - 4], fill=shade(base, 0.55))


def draw_berserker(d: ImageDraw.ImageDraw) -> None:
    """Crossed axes."""
    for flip in (False, True):
        x = lambda v: (CELL - 1 - v) if flip else v  # noqa: E731
        d.line([(x(18), 48), (x(44), 18)], fill=WOOD, width=4)
        d.polygon([(x(40), 12), (x(52), 20), (x(42), 28), (x(34), 20)], fill=STEEL)
        d.polygon([(x(42), 15), (x(48), 20), (x(42), 25)], fill=STEEL_DARK)


def draw_knight(d: ImageDraw.ImageDraw) -> None:
    """Kite shield with a cross."""
    d.polygon([(18, 12), (46, 12), (46, 38), (32, 52), (18, 38)], fill=STEEL)
    d.polygon([(22, 16), (42, 16), (42, 37), (32, 47), (22, 37)], fill=STEEL_DARK)
    d.rectangle([30, 19, 34, 43], fill=GOLD)
    d.rectangle([24, 25, 40, 29], fill=GOLD)


def draw_rogue(d: ImageDraw.ImageDraw) -> None:
    """Paired daggers."""
    for flip in (False, True):
        x = lambda v: (CELL - 1 - v) if flip else v  # noqa: E731
        d.polygon([(x(24), 14), (x(30), 20), (x(24), 44), (x(20), 44), (x(20), 20)], fill=STEEL)
        rect(d, x(18), 44, x(28), 48, GOLD)
        rect(d, x(21), 48, x(25), 54, WOOD)


def draw_scholar(d: ImageDraw.ImageDraw) -> None:
    """Open tome with an arcane spark."""
    d.polygon([(10, 24), (31, 20), (31, 46), (10, 44)], fill=STEEL)
    d.polygon([(33, 20), (54, 24), (54, 44), (33, 46)], fill=STEEL)
    d.polygon([(13, 27), (29, 24), (29, 42), (13, 41)], fill=STEEL_DARK)
    d.polygon([(35, 24), (51, 27), (51, 41), (35, 42)], fill=STEEL_DARK)
    d.rectangle([31, 20, 33, 46], fill=WOOD)
    d.polygon([(32, 6), (35, 14), (32, 18), (29, 14)], fill=GOLD)


def draw_sentinel(d: ImageDraw.ImageDraw) -> None:
    """Tower shield with a bar."""
    d.rectangle([18, 10, 46, 46], fill=STEEL)
    d.polygon([(18, 46), (46, 46), (32, 56)], fill=STEEL)
    d.rectangle([22, 14, 42, 43], fill=STEEL_DARK)
    d.rectangle([22, 24, 42, 30], fill=GOLD)


def draw_hunter(d: ImageDraw.ImageDraw) -> None:
    """Bow drawn with an arrow."""
    d.arc([16, 8, 48, 56], start=250, end=110, fill=WOOD, width=5)
    d.line([(22, 14), (22, 50)], fill=STEEL_DARK, width=2)
    d.line([(22, 32), (50, 32)], fill=STEEL, width=3)
    d.polygon([(48, 27), (58, 32), (48, 37)], fill=STEEL)


def draw_herald(d: ImageDraw.ImageDraw) -> None:
    """Banner on a staff."""
    d.rectangle([20, 8, 24, 56], fill=WOOD)
    d.polygon([(24, 12), (50, 16), (50, 36), (24, 32)], fill=GOLD)
    d.polygon([(24, 32), (50, 36), (42, 42), (24, 38)], fill=shade(GOLD, 0.7))
    d.rectangle([30, 20, 44, 24], fill=INK)
    d.rectangle([35, 16, 39, 30], fill=INK)


PAINTERS = {
    "berserker": draw_berserker,
    "knight": draw_knight,
    "rogue": draw_rogue,
    "scholar": draw_scholar,
    "sentinel": draw_sentinel,
    "hunter": draw_hunter,
    "herald": draw_herald,
}


def build() -> Image.Image:
    atlas = Image.new("RGBA", (CELL * len(ORDER), CELL), (0, 0, 0, 0))
    for index, class_id in enumerate(ORDER):
        cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        draw = ImageDraw.Draw(cell)
        backdrop(draw, BASE[class_id])
        PAINTERS[class_id](draw)
        atlas.paste(cell, (index * CELL, 0))
    return atlas


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report whether the atlas is flat art")
    args = parser.parse_args()

    if args.check:
        if not ATLAS.exists():
            print(f"MISSING {ATLAS}")
            return 1
        current = Image.open(ATLAS).convert("RGB")
        flat = [
            ORDER[i]
            for i in range(len(ORDER))
            if len(current.crop((i * CELL, 0, (i + 1) * CELL, CELL)).getcolors(4096) or []) <= 1
        ]
        if flat:
            print(f"FLAT class icons (placeholder swatches): {', '.join(flat)}")
            return 1
        print(f"OK {ATLAS.name}: {len(ORDER)} drawn cells")
        return 0

    ATLAS.parent.mkdir(parents=True, exist_ok=True)
    build().save(ATLAS, optimize=True)
    print(f"Wrote {ATLAS.relative_to(ROOT)} ({len(ORDER)} cells at {CELL}x{CELL})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
