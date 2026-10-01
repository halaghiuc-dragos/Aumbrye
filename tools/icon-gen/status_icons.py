"""16x16 status icons for the buff bar, rendered from Blender models.

The shipped status_icons.png was placeholder noise: seven of the ten statuses were diagonal colour
smears rather than shapes, and both polarity frames were empty. These are drawn to the same rules
the item atlas already follows -- a dark outline the whole way round, two or three flat tones
inside, and the highlight up and to the left -- so the buff bar reads as part of the same set.

Glyph legend per row string:
    .  transparent      o  outline        d  dark tone
    m  mid tone         l  light tone     h  highlight
"""

import json
from pathlib import Path

from PIL import Image

CELL = 16
COLS, ROWS = 8, 6

# Ramps are (outline, dark, mid, light, highlight).
RAMPS = {
    "blood":  ((0x2a, 0x07, 0x0d), (0x6d, 0x11, 0x1c), (0xa8, 0x1d, 0x2a), (0xd6, 0x3a, 0x42), (0xf2, 0x86, 0x83)),
    "ember":  ((0x33, 0x16, 0x05), (0x8a, 0x33, 0x08), (0xd1, 0x5f, 0x0d), (0xf2, 0x99, 0x22), (0xff, 0xd9, 0x7a)),
    "frost":  ((0x11, 0x2b, 0x3d), (0x25, 0x5c, 0x82), (0x49, 0x92, 0xba), (0x8a, 0xcd, 0xe4), (0xdf, 0xf5, 0xff)),
    "venom":  ((0x14, 0x2c, 0x11), (0x2f, 0x5e, 0x1f), (0x55, 0x94, 0x2c), (0x86, 0xc2, 0x44), (0xc9, 0xef, 0x8d)),
    "gold":   ((0x35, 0x25, 0x08), (0x7d, 0x58, 0x14), (0xc0, 0x8c, 0x22), (0xe8, 0xbb, 0x45), (0xff, 0xe9, 0xa8)),
    "arcane": ((0x22, 0x14, 0x38), (0x4a, 0x2c, 0x74), (0x76, 0x4c, 0xaf), (0xa8, 0x83, 0xd8), (0xe0, 0xcd, 0xf7)),
    "stone":  ((0x1d, 0x20, 0x24), (0x40, 0x46, 0x4e), (0x67, 0x6f, 0x79), (0x93, 0x9c, 0xa6), (0xc9, 0xd1, 0xd8)),
    "wind":   ((0x11, 0x2f, 0x2c), (0x1f, 0x60, 0x59), (0x33, 0x99, 0x8c), (0x63, 0xc9, 0xba), (0xbd, 0xf2, 0xe8)),
    "umbral": ((0x18, 0x12, 0x24), (0x33, 0x27, 0x4c), (0x55, 0x44, 0x77), (0x83, 0x70, 0xa6), (0xc4, 0xb6, 0xdc)),
}

_GLYPHS = json.loads(Path(__file__).with_name("glyphs.json").read_text(encoding="utf-8"))
# The glyphs are rendered from tools/blender/icons.py by tools/blender/build_icons.py.
BLEED = _GLYPHS["status/bleed"]
BURN = _GLYPHS["status/burn"]
FREEZE = _GLYPHS["status/freeze"]
POISON = _GLYPHS["status/poison"]
STUN = _GLYPHS["status/stun"]
FOCUS = _GLYPHS["status/focus"]
RESOLVE = _GLYPHS["status/resolve"]
STONESKIN = _GLYPHS["status/stoneskin"]
SWIFTNESS = _GLYPHS["status/swiftness"]
TORPOR = _GLYPHS["status/torpor"]


# Polarity frames: a corner-bracket ring the pip sits inside.
def frame(_ramp):
    rows = []
    for y in range(CELL):
        row = ""
        for x in range(CELL):
            edge = x in (0, CELL - 1) or y in (0, CELL - 1)
            near = x in (1, CELL - 2) or y in (1, CELL - 2)
            corner = (x < 5 or x > CELL - 6) and (y < 5 or y > CELL - 6)
            if edge and corner:
                row += "o"
            elif near and corner:
                row += "h"
            else:
                row += "."
        rows.append(row)
    return rows


ICONS = {
    "burn": (BURN, "ember", (0, 0)),
    "poison": (POISON, "venom", (1, 0)),
    "freeze": (FREEZE, "frost", (2, 0)),
    "stun": (STUN, "gold", (3, 0)),
    "bleed": (BLEED, "blood", (4, 0)),
    "focus": (FOCUS, "arcane", (5, 0)),
    "resolve": (RESOLVE, "gold", (6, 0)),
    "stoneskin": (STONESKIN, "stone", (7, 0)),
    "swiftness": (SWIFTNESS, "wind", (0, 1)),
    "torpor": (TORPOR, "umbral", (1, 1)),
    "frame_buff": (frame(None), "gold", (7, 4)),
    "frame_debuff": (frame(None), "blood", (6, 5)),
}

# The fallback stays a loud checker so a missing mapping is obvious in play.
UNKNOWN_CELL = (7, 5)


def build_image() -> Image.Image:
    img = Image.new("RGBA", (COLS * CELL, ROWS * CELL), (0, 0, 0, 0))
    px = img.load()
    for name, (rows, ramp_name, (col, row)) in ICONS.items():
        ramp = RAMPS[ramp_name]
        lut = {"o": ramp[0], "d": ramp[1], "m": ramp[2], "l": ramp[3], "h": ramp[4]}
        if len(rows) != CELL:
            raise SystemExit(f"{name}: {len(rows)} rows, expected {CELL}")
        for y, line in enumerate(rows):
            if len(line) != CELL:
                raise SystemExit(f"{name}: row {y} is {len(line)} wide, expected {CELL}")
            for x, ch in enumerate(line):
                if ch == ".":
                    continue
                if ch not in lut:
                    raise SystemExit(f"{name}: unknown glyph {ch!r}")
                r, g, b = lut[ch]
                px[col * CELL + x, row * CELL + y] = (r, g, b, 255)
    ux, uy = UNKNOWN_CELL
    for y in range(CELL):
        for x in range(CELL):
            on = ((x // 4) + (y // 4)) % 2 == 0
            px[ux * CELL + x, uy * CELL + y] = (255, 0, 255, 255) if on else (0, 0, 0, 255)
    return img


if __name__ == "__main__":
    raise SystemExit(
        "Direct publication is retired; use tools/icon-gen/atlas_build.py "
        "(--dry-run/--force supported) to publish the complete owned atlas set."
    )
