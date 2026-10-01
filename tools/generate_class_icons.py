#!/usr/bin/env python3
"""Build the class-select portrait atlas from Blender-rendered emblems.

Each of the seven cells shipped as a single flat colour, so the character-creation list read as a
column of blank swatches. This keeps the established per-class colour identity and draws a legible
emblem in it: a weapon or symbol that says what the class does at a glance.

Everything is authored on the 64x64 cell grid the manifest declares
(content/ui/class_icon_atlas.json), with hard edges so it stays crisp under nearest filtering.

"""

from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asset_io import write_bytes_set  # noqa: E402

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


# Emblems are rendered from Blender models (tools/blender/icons.py) by tools/blender/build_icons.py into
# emblems.json: sixty-four rows of tone letters per class. `d m l h` are the main metal, `a b c` the
# accent, `o` the outline.
_EMBLEMS = json.loads((Path(__file__).resolve().parent / "icon-gen" / "emblems.json").read_text(encoding="utf-8"))

#: (main material, accent material) per class emblem.
MATERIALS = {
    "berserker": (STEEL, WOOD),
    "knight": (STEEL, GOLD),
    "rogue": (STEEL, WOOD),
    "scholar": (GOLD, WOOD),
    "sentinel": (STEEL, STEEL_DARK),
    "hunter": (STEEL, WOOD),
    "herald": (GOLD, WOOD),
}


def _ramp(colour):
    return {
        "d": shade(colour, 0.5), "m": shade(colour, 0.72), "l": colour, "h": shade(colour, 1.18),
        "a": shade(colour, 0.6), "b": colour, "c": shade(colour, 1.25),
    }


def paint_emblem(cell: Image.Image, class_id: str) -> None:
    main, accent = MATERIALS[class_id]
    table = {"o": INK}
    for key in "dmlh":
        table[key] = _ramp(main)[key]
    for key in "abc":
        table[key] = _ramp(accent)[key]
    px = cell.load()
    for y, row in enumerate(_EMBLEMS[class_id]):
        for x, ch in enumerate(row):
            if ch != ".":
                px[x, y] = table[ch] + (255,)


def build() -> Image.Image:
    atlas = Image.new("RGBA", (CELL * len(ORDER), CELL), (0, 0, 0, 0))
    for index, class_id in enumerate(ORDER):
        cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        draw = ImageDraw.Draw(cell)
        backdrop(draw, BASE[class_id])
        paint_emblem(cell, class_id)
        atlas.paste(cell, (index * CELL, 0))
    return atlas


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report whether the atlas is flat art")
    parser.add_argument("--dry-run", action="store_true", help="report what would change without writing")
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

    buffer = io.BytesIO()
    build().save(buffer, format="PNG", optimize=True)
    written = bool(write_bytes_set([(ATLAS, buffer.getvalue())], dry_run=args.dry_run))
    print(
        f"{'validated' if args.dry_run else 'published'} {ATLAS.relative_to(ROOT)} "
        f"({len(ORDER)} cells at {CELL}x{CELL}; {'would write' if args.dry_run else 'written'}={written})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
