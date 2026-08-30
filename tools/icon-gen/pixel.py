"""Shared drawing rules for every generated icon sheet.

One construction rule across the whole UI: a hard dark outline the whole way round, flat tones
inside, highlight up and to the left, and at least one transparent pixel of margin in the cell.
Sheets differ in cell size and subject, never in how a shape is built.

Glyph legend used by the hand-authored row strings:

    .  transparent   o  outline   d  dark   m  mid   l  light   h  highlight
    a  accent-dark   b  accent    c  accent-light
"""

from __future__ import annotations

TONE_KEYS = "odmlh"
ACCENT_KEYS = "abc"


def lut_for(ramp) -> dict:
    """Map glyph characters onto a ramp.

    Ramps are (outline, dark, mid, light, highlight) and optionally three accent tones. Sheets
    that have no accents reuse the main ramp for them so a shape never draws a missing colour.
    """
    table = {
        "o": ramp[0], "d": ramp[1], "m": ramp[2], "l": ramp[3], "h": ramp[4],
    }
    if len(ramp) >= 8:
        table.update({"a": ramp[5], "b": ramp[6], "c": ramp[7]})
    else:
        table.update({"a": ramp[1], "b": ramp[2], "c": ramp[3]})
    return table


def validate(name: str, rows, cell: int) -> None:
    """A shape off the grid misaligns against every other cell on the sheet, so refuse it."""
    if len(rows) != cell:
        raise SystemExit("%s: %d rows, expected %d" % (name, len(rows), cell))
    for y, line in enumerate(rows):
        if len(line) != cell:
            raise SystemExit(
                "%s: row %d is %d wide, expected %d" % (name, y, len(line), cell)
            )
        for x, ch in enumerate(line):
            if ch != "." and ch not in TONE_KEYS and ch not in ACCENT_KEYS:
                raise SystemExit("%s: unknown glyph %r at %d,%d" % (name, ch, x, y))


def margins(rows, cell: int) -> tuple[int, int, int, int]:
    """(left, top, right, bottom) transparent margin, for the alignment report."""
    filled = [(x, y) for y, line in enumerate(rows) for x, ch in enumerate(line) if ch != "."]
    if not filled:
        return (cell, cell, cell, cell)
    xs = [x for x, _ in filled]
    ys = [y for _, y in filled]
    return (min(xs), min(ys), cell - 1 - max(xs), cell - 1 - max(ys))


def blit(px, rows, ramp, col, row, cell: int) -> None:
    table = lut_for(ramp)
    for y, line in enumerate(rows):
        for x, ch in enumerate(line):
            if ch == ".":
                continue
            r, g, b = table[ch]
            px[col * cell + x, row * cell + y] = (r, g, b, 255)


def shade(mask, cell: int) -> list[str]:
    """Turn a filled boolean mask into an outlined, shaded glyph.

    Pixels facing up or left take the highlight, pixels facing down or right take the dark tone,
    everything enclosed takes the light tone, and the whole mark is ringed in the outline colour.
    That is the same light direction the hand-authored shapes use, so generated and authored
    glyphs sit on a sheet together without reading as two sets.
    """
    grid = [["." for _ in range(cell)] for _ in range(cell)]
    for y in range(cell):
        for x in range(cell):
            if not mask[y][x]:
                continue
            up = y > 0 and mask[y - 1][x]
            left = x > 0 and mask[y][x - 1]
            down = y < cell - 1 and mask[y + 1][x]
            right = x < cell - 1 and mask[y][x + 1]
            if not up or not left:
                grid[y][x] = "h"
            elif not down or not right:
                grid[y][x] = "d"
            else:
                grid[y][x] = "l"
    for y in range(cell):
        for x in range(cell):
            if mask[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                           (1, 1), (1, -1), (-1, 1), (-1, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < cell and 0 <= ny < cell and mask[ny][nx]:
                    grid[y][x] = "o"
                    break
    return ["".join(row) for row in grid]


def mask_from_spans(spans, cell: int):
    """Build a mask from (row, x_start, x_end) inclusive horizontal runs."""
    mask = [[False] * cell for _ in range(cell)]
    for y, x0, x1 in spans:
        for x in range(x0, x1 + 1):
            if 0 <= x < cell and 0 <= y < cell:
                mask[y][x] = True
    return mask


def mask_from_art(art, cell: int):
    """Build a mask from rows of '#' (filled) and '.' (empty)."""
    if len(art) != cell:
        raise SystemExit("mask art is %d rows, expected %d" % (len(art), cell))
    mask = [[False] * cell for _ in range(cell)]
    for y, line in enumerate(art):
        if len(line) != cell:
            raise SystemExit("mask art row %d is %d wide, expected %d" % (y, len(line), cell))
        for x, ch in enumerate(line):
            mask[y][x] = ch == "#"
    return mask


def shade_flat(mask, cell: int) -> list[str]:
    """Shade a mask without ringing it in outline.

    At eight pixels a keyline costs the shape more than it buys: the ring closes over the gaps
    that make a glyph readable and every mark collapses to a blob. The minimap draws its icons
    over its own dark room fill, which already separates them from the background, so there the
    mark is carried by a bright body with a dark lower-right edge instead.
    """
    grid = [["." for _ in range(cell)] for _ in range(cell)]
    for y in range(cell):
        for x in range(cell):
            if not mask[y][x]:
                continue
            down = y < cell - 1 and mask[y + 1][x]
            right = x < cell - 1 and mask[y][x + 1]
            up = y > 0 and mask[y - 1][x]
            left = x > 0 and mask[y][x - 1]
            if not up or not left:
                grid[y][x] = "h"
            elif not down or not right:
                grid[y][x] = "m"
            else:
                grid[y][x] = "l"
    return ["".join(row) for row in grid]


# ------------------------------------------------------------------- per-item accent variation
#
# Shape says what kind of thing an item is and the ramp says what it is made of, which is the right
# vocabulary -- but between them they only describe a *family*. Two swamp daggers resolved to the
# same shape and the same ramp and came out pixel for pixel identical, and across the atlas 195 of
# 284 items shared an icon with something else. A loot list that shows the same picture for the
# thing you are wearing and the thing you just found is not telling the player anything.
#
# The accent tones -- grips, bindings, gems, pommels -- are the part of a shape that is trim rather
# than substance, so they are where an item can differ without stopping looking like its family.
# The shift is derived from the item's own id, so it is stable: the same item is the same picture
# every time, on every machine, forever.
#
# Deliberately small. Rotating the trim hue a few degrees and nudging its value reads as "a
# different sword of the same make", which is what these are. A large shift would read as a
# different material and undo the thing the ramp is there to say.

ACCENT_HUE_STEPS = 7
ACCENT_HUE_RANGE = 0.055
ACCENT_VALUE_RANGE = 0.14


def _rgb_to_hsv(rgb):
    r, g, b = (channel / 255.0 for channel in rgb)
    high, low = max(r, g, b), min(r, g, b)
    value = high
    delta = high - low
    saturation = 0.0 if high == 0.0 else delta / high
    if delta == 0.0:
        hue = 0.0
    elif high == r:
        hue = ((g - b) / delta) % 6.0
    elif high == g:
        hue = (b - r) / delta + 2.0
    else:
        hue = (r - g) / delta + 4.0
    return hue / 6.0, saturation, value


def _hsv_to_rgb(hue, saturation, value):
    i = int(hue * 6.0) % 6
    f = hue * 6.0 - int(hue * 6.0)
    p = value * (1.0 - saturation)
    q = value * (1.0 - f * saturation)
    t = value * (1.0 - (1.0 - f) * saturation)
    r, g, b = [(value, t, p), (q, value, p), (p, value, t),
               (p, q, value), (t, p, value), (value, p, q)][i]
    return tuple(max(0, min(255, round(channel * 255.0))) for channel in (r, g, b))


#: Some silhouettes carry no trim at all -- a cuirass, a rune stone, a slab of plate is all body.
#: Varying nothing leaves those families pixel-identical, so their *body* is shifted instead, by a
#: smaller amount: the body is what says which material the item is, and it has to stay readable as
#: that material while still telling one piece from another.
#: Wide enough that two adjacent steps survive being rounded back to whole bytes -- at the first
#: values tried, neighbouring variants of a trimless shape rounded to the same colour and stayed
#: identical -- and still narrow enough to read as the same material.
BODY_HUE_RANGE = 0.026
BODY_VALUE_RANGE = 0.11


def accent_variant(ramp, key: str, glyph=None, ordinal: int | None = None):
    """Return `ramp` varied so this item does not look like its siblings.

    Where the shape has trim, the trim is what varies. Where it has none, the body is nudged
    instead -- less far, because the body is the material.

    `ordinal` is the item's position among the items that resolved to the same shape and ramp.
    Given one, the variant is spread across the available steps by position, which is what makes
    two members of a family *guaranteed* to differ: hashing the id alone left the choice to luck,
    and four pairs -- each a unique and the ordinary item it was modelled on -- happened to land on
    the same step and stayed identical. Without an ordinal it falls back to the id hash.
    """
    if len(ramp) < 5 or not key:
        return ramp
    has_accents = len(ramp) >= 8 and (
        glyph is None or any(ch in ACCENT_KEYS for row in glyph for ch in row)
    )
    # Stable across runs and platforms: Python's hash() is salted per process, so it cannot be
    # used for anything that ends up committed to disk.
    digest = 0
    for char in key:
        digest = (digest * 131 + ord(char)) & 0xFFFFFFFF
    slot = digest if ordinal is None else ordinal
    step = slot % ACCENT_HUE_STEPS
    # Centre the steps on zero so a family spreads either side of its authored trim rather than
    # always drifting one way.
    offset = (step / float(ACCENT_HUE_STEPS - 1)) * 2.0 - 1.0
    # Lightness moves with every step rather than only once the hue has been all the way round.
    # Some ramps -- the vault's iron trim among them -- carry accents that are almost grey, and a
    # hue shift does nothing at all to a colour with no saturation to rotate. Those families were
    # relying entirely on an axis that could not move them. The stride is coprime with the step
    # count so the two axes do not come back into phase.
    value_offset = ((slot * 3) % 5) / 4.0 * 2.0 - 1.0

    if has_accents:
        shifted = list(ramp[:5])
        for tone in ramp[5:8]:
            shifted.append(
                _shift(tone, offset * ACCENT_HUE_RANGE, value_offset * ACCENT_VALUE_RANGE)
            )
        return tuple(shifted)

    # No trim to vary: nudge the two tones that carry most of the shape's surface, and leave the
    # outline and highlight alone so the keyline and the light direction stay exactly as authored.
    hue_shift = offset * BODY_HUE_RANGE
    value_shift = value_offset * BODY_VALUE_RANGE
    shifted = [
        ramp[0],
        _shift(ramp[1], hue_shift, value_shift),
        _shift(ramp[2], hue_shift, value_shift),
        _shift(ramp[3], hue_shift, value_shift),
        ramp[4],
    ]
    return tuple(shifted) + tuple(ramp[5:])


def _shift(tone, hue_shift: float, value_shift: float):
    hue, saturation, value = _rgb_to_hsv(tone)
    hue = (hue + hue_shift) % 1.0
    value = max(0.04, min(1.0, value * (1.0 + value_shift)))
    return _hsv_to_rgb(hue, saturation, value)
