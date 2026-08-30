"""Authored 16x16 status icons for the buff bar.

The shipped status_icons.png was placeholder noise: seven of the ten statuses were diagonal colour
smears rather than shapes, and both polarity frames were empty. These are drawn to the same rules
the item atlas already follows -- a dark outline the whole way round, two or three flat tones
inside, and the highlight up and to the left -- so the buff bar reads as part of the same set.

Glyph legend per row string:
    .  transparent      o  outline        d  dark tone
    m  mid tone         l  light tone     h  highlight
"""

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

# A drop of blood, falling, with the wound-line behind it.
BLEED = [
    "................",
    ".......oo.......",
    "......ohho......",
    "......ohlo......",
    ".....oolmoo.....",
    ".....olmmdo.....",
    "....oolmmddo....",
    "....olmmmddo....",
    "...oolmmmdddo...",
    "...olmmmmdddo...",
    "...olmmmmdddo...",
    "...oolmmmddoo...",
    "....oodmmdoo....",
    "......oddo......",
    ".......oo.......",
    "................",
]

# A flame with a hot core.
BURN = [
    "................",
    ".......oo.......",
    "......ohdo......",
    "......ohdo......",
    ".....oohddo.....",
    ".....olhmdo.....",
    "....oolhmddo....",
    "...ooldhmdddo...",
    "...olmdhmmddo...",
    "..oolmmhlmdddo..",
    "..olmmmhllmddo..",
    "..olmmmlllmddo..",
    "..oolmmmlmmddo..",
    "...oolmmmmddo...",
    ".....ooooooo....",
    "................",
]

# A six-point ice star.
FREEZE = [
    "................",
    ".......oo.......",
    "......ohho......",
    "..o...ohho...o..",
    ".oho..ohho..oho.",
    "..ohooohhooooo..",
    "...ohhhhhhhho...",
    "..ooohhllhhoooo.",
    "..ooohhllhhoooo.",
    "...ohhhhhhhho...",
    "..ohoooohhoooo..",
    ".oho..ohho..oho.",
    "..o...ohho...o..",
    "......ohho......",
    ".......oo.......",
    "................",
]

# A dripping vial-drop with rising bubbles.
POISON = [
    "................",
    "................",
    ".......oo.......",
    "......ohho......",
    ".....oolhoo.....",
    "....oolmmhoo....",
    "...oolmmmmdoo...",
    "..oolmoomdddoo..",
    "..olmmoommdddo..",
    "..olmmmmoomddo..",
    "..olmmoommdddo..",
    "..oolmoomddddo..",
    "...oodmmmdddo...",
    "....ooddddoo....",
    "......oooo......",
    "................",
]

# An impact starburst.
# A watching eye.
FOCUS = [
    "................",
    "................",
    ".....oooooo.....",
    "...oohhhhhhoo...",
    "..ohhllllllhho..",
    ".ohhllooooollho.",
    ".ohlloommoolllo.",
    ".ollomodddomllo.",
    ".ollomodddomllo.",
    ".ohlloommoolllo.",
    ".ohhllooooollho.",
    "..ohhllllllhho..",
    "...oohhhhhhoo...",
    ".....oooooo.....",
    "................",
    "................",
]

# A steady upward chevron over a bar: the oath held.
RESOLVE = [
    "................",
    ".......oo.......",
    "......ohho......",
    ".....ohhhho.....",
    "....ohhllhho....",
    "...ohhlmmlhho...",
    "..ohhlmddmlhho..",
    ".ohhlmdoodmlhho.",
    ".ohlmdo..odmlho.",
    ".omdo......odmo.",
    ".omo........omo.",
    "................",
    "..oooooooooooo..",
    "..ohhhhhhhhhho..",
    "..oooooooooooo..",
    "................",
]

# A faceted block of stone.
STONESKIN = [
    "................",
    "................",
    "...oooooooooo...",
    "..ohhhhhhoddoo..",
    ".ohhllllhommddo.",
    ".ohllllhommmmdo.",
    ".ohlllhommmmmdo.",
    ".ohllhommmmdddo.",
    ".ohlhommmmddddo.",
    ".ohhommmmdddddo.",
    ".ohommmmddddddo.",
    ".ohommmdddddddo.",
    "..oommdddddddo..",
    "...oooooooooo...",
    "................",
    "................",
]

# Two swept chevrons: speed.
# An hourglass, running down.
TORPOR = [
    "................",
    "..oooooooooooo..",
    "..ohhhhhhhhhho..",
    "..oolllllllloo..",
    "...oldddddlo....",
    "....olddddlo....",
    ".....olddlo.....",
    "......ollo......",
    "......ollo......",
    ".....olmmlo.....",
    "....olmmmmlo....",
    "...olmmmmmmlo...",
    "..oollllllllooo.",
    "..ohhhhhhhhhho..",
    "..oooooooooooo..",
    "................",
]

def _blank():
    return [["." for _ in range(CELL)] for _ in range(CELL)]


def _put(grid, x, y, ch):
    if 0 <= x < CELL and 0 <= y < CELL:
        grid[y][x] = ch


def _chevron(grid, ox, oy, height, thickness=3):
    """A right-pointing ">" with its point on the vertical middle."""
    half = height // 2
    for i in range(half):
        for t in range(thickness):
            tone = "h" if t == 0 else ("l" if t == 1 else "m")
            _put(grid, ox + i + t, oy + i, tone)
            _put(grid, ox + i + t, oy + height - 1 - i, tone)
    # Outline the leading and trailing edges so the shape closes.
    for i in range(half):
        _put(grid, ox + i - 1, oy + i, "o")
        _put(grid, ox + i - 1, oy + height - 1 - i, "o")
        _put(grid, ox + i + thickness, oy + i, "o")
        _put(grid, ox + i + thickness, oy + height - 1 - i, "o")


def _star(grid, cx, cy, arm):
    """A four-point star: the classic 'seeing stars' mark."""
    _put(grid, cx, cy, "h")
    for d in range(1, arm + 1):
        tone = "h" if d <= arm - 1 else "l"
        for dx, dy in ((0, -d), (0, d), (-d, 0), (d, 0)):
            _put(grid, cx + dx, cy + dy, tone)
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        _put(grid, cx + dx, cy + dy, "l")
    # Ring the whole mark so it keeps the set's hard edge.
    for d in range(1, arm + 2):
        for dx, dy in ((0, -d), (0, d), (-d, 0), (d, 0)):
            x, y = cx + dx, cy + dy
            for ex, ey in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= ex < CELL and 0 <= ey < CELL and grid[ey][ex] == ".":
                    grid[ey][ex] = "o"


def _rows(grid):
    return ["".join(r) for r in grid]


def _build_stun():
    g = _blank()
    _star(g, 7, 7, 3)
    _star(g, 4, 4, 1)
    _star(g, 11, 10, 1)
    return _rows(g)


def _build_swiftness():
    g = _blank()
    _chevron(g, 3, 3, 10, 2)
    _chevron(g, 8, 3, 10, 2)
    return _rows(g)


STUN = _build_stun()
SWIFTNESS = _build_swiftness()


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


def render(path: str) -> None:
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
    img.save(path)
    print(f"wrote {path} ({img.width}x{img.height}, {len(ICONS)} icons)")


if __name__ == "__main__":
    import sys
    render(sys.argv[1] if len(sys.argv) > 1 else "status_icons.png")
