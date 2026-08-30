"""Room-kind glyphs for the minimap, on the 8x8 grid the minimap reads.

The shipped sheet was sixteen solid colour squares, so the map and its legend showed a block of
colour per room kind and nothing else -- the player had to memorise the legend to read the map at
all. These are marks: a chest is a chest, stairs are stairs.

Eight pixels is too little room for the keyline the rest of the UI uses -- the ring closes over
the gaps that make a mark readable -- so these are drawn as a bright body with a darker lower-right
edge, over the dark room fill the minimap already paints. Light still falls up and to the left,
which is what keeps them part of the same set. Colour separates the kinds; the shape is what makes
the map readable without the legend open, and what keeps it readable in colourblind modes.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import pixel  # noqa: E402

CELL = 8
COLUMNS = 8
ROWS = 2

# (outline, dark, mid, light, highlight)
RAMPS = {
    "steel":   ((0x14, 0x16, 0x1a), (0x45, 0x4a, 0x55), (0x6e, 0x75, 0x82), (0x9c, 0xa4, 0xb0), (0xd0, 0xd7, 0xe0)),
    "gold":    ((0x2c, 0x1f, 0x06), (0x74, 0x54, 0x12), (0xb4, 0x86, 0x1e), (0xe0, 0xb4, 0x3e), (0xff, 0xe6, 0x9c)),
    "green":   ((0x11, 0x28, 0x18), (0x24, 0x55, 0x33), (0x3c, 0x88, 0x52), (0x6c, 0xbb, 0x83), (0xb6, 0xe8, 0xc4)),
    "brass":   ((0x2e, 0x28, 0x08), (0x70, 0x63, 0x16), (0xac, 0x99, 0x24), (0xd8, 0xc6, 0x48), (0xf6, 0xef, 0xa4)),
    "violet":  ((0x1d, 0x14, 0x2e), (0x42, 0x2f, 0x68), (0x6c, 0x51, 0xa2), (0x9e, 0x85, 0xcc), (0xd8, 0xc9, 0xf0)),
    "teal":    ((0x0e, 0x28, 0x28), (0x1c, 0x57, 0x56), (0x2f, 0x8b, 0x89), (0x60, 0xbe, 0xba), (0xb4, 0xe8, 0xe4)),
    "amber":   ((0x30, 0x1a, 0x08), (0x77, 0x40, 0x14), (0xb6, 0x66, 0x22), (0xe0, 0x96, 0x44), (0xff, 0xcc, 0x92)),
    "bone":    ((0x2a, 0x26, 0x1c), (0x60, 0x59, 0x44), (0x94, 0x8b, 0x6c), (0xc2, 0xba, 0x9c), (0xee, 0xe8, 0xd2)),
    "crimson": ((0x2a, 0x0c, 0x10), (0x6a, 0x1c, 0x22), (0xa4, 0x30, 0x36), (0xd0, 0x60, 0x62), (0xf4, 0xa8, 0xa4)),
    "azure":   ((0x11, 0x1e, 0x38), (0x25, 0x42, 0x78), (0x3e, 0x6c, 0xb6), (0x76, 0x9e, 0xdc), (0xcc, 0xdf, 0xff)),
    "umber":   ((0x24, 0x18, 0x0e), (0x55, 0x39, 0x20), (0x84, 0x5b, 0x34), (0xb2, 0x88, 0x5c), (0xe0, 0xc0, 0x9a)),
    "slate":   ((0x14, 0x15, 0x19), (0x30, 0x33, 0x3c), (0x4e, 0x53, 0x5e), (0x74, 0x7b, 0x88), (0xa2, 0xaa, 0xb6)),
}

ART = {
    # Crossed blades.
    "combat": [
        "........",
        ".#....#.",
        "..#..#..",
        "...##...",
        "...##...",
        "..#..#..",
        ".#....#.",
        "........",
    ],
    # A banded chest.
    "treasure": [
        "........",
        "..####..",
        ".######.",
        ".##..##.",
        ".######.",
        ".######.",
        "........",
        "........",
    ],
    # A drawstring purse.
    "shop": [
        "........",
        "..#..#..",
        "..####..",
        ".######.",
        ".######.",
        ".######.",
        "..####..",
        "........",
    ],
    # A key: bow, ward, bit.
    "key": [
        "........",
        "..###...",
        "..#.#...",
        "..###...",
        "...#....",
        "...##...",
        "...#....",
        "........",
    ],
    # A warning triangle. Solid: at eight pixels a hollow one closes up into a blob.
    "hazard": [
        "........",
        "...##...",
        "...##...",
        "..####..",
        "..####..",
        ".######.",
        ".######.",
        "........",
    ],
    # Head and shoulders.
    "npc": [
        "........",
        "...##...",
        "..####..",
        "..####..",
        "...##...",
        ".######.",
        ".######.",
        "........",
    ],
    # A strongroom door with its dial.
    "vault": [
        "........",
        ".######.",
        ".#....#.",
        ".#.##.#.",
        ".#.##.#.",
        ".#....#.",
        ".######.",
        "........",
    ],
    # A written page.
    "lore": [
        "........",
        ".#####..",
        ".#...#..",
        ".#####..",
        ".#...#..",
        ".#####..",
        "........",
        "........",
    ],
    # A crown.
    "boss": [
        "........",
        ".#.##.#.",
        ".#.##.#.",
        ".######.",
        ".######.",
        ".######.",
        "........",
        "........",
    ],
    # An archway.
    "entrance": [
        "........",
        "..####..",
        ".######.",
        ".##..##.",
        ".##..##.",
        ".##..##.",
        ".##..##.",
        "........",
    ],
    # Steps going down.
    "stairs": [
        "........",
        ".....##.",
        ".....##.",
        "...####.",
        "...####.",
        ".######.",
        ".######.",
        "........",
    ],
    # An unread room: a plain marker.
    "unknown": [
        "........",
        "........",
        "...##...",
        "..####..",
        "..####..",
        "...##...",
        "........",
        "........",
    ],
    # A campfire: flame over a burning log, with the gap between them kept open so it cannot be
    # mistaken for the hazard triangle at this size.
    "rest": [
        "........",
        "...##...",
        "..####..",
        "..####..",
        "........",
        ".######.",
        ".######.",
        "........",
    ],
    # A cog.
    "puzzle": [
        "........",
        "..#..#..",
        ".######.",
        ".######.",
        ".######.",
        ".######.",
        "..#..#..",
        "........",
    ],
    # A watching eye, the same mark the focus status uses.
    "secret": [
        "........",
        "..####..",
        ".######.",
        ".##..##.",
        ".######.",
        "..####..",
        "........",
        "........",
    ],
}

#: Cells must match KIND_CELLS in scripts/ui/minimap.gd.
PLACEMENT = {
    "combat": (0, 0), "treasure": (1, 0), "shop": (2, 0), "key": (3, 0),
    "hazard": (4, 0), "npc": (5, 0), "vault": (6, 0), "lore": (7, 0),
    "boss": (0, 1), "entrance": (1, 1), "stairs": (2, 1), "unknown": (3, 1),
    "rest": (4, 1), "puzzle": (5, 1), "secret": (6, 1),
}

TINTS = {
    "combat": "steel", "treasure": "gold", "shop": "green", "key": "brass",
    "hazard": "amber", "npc": "teal", "vault": "violet", "lore": "bone",
    "boss": "crimson", "entrance": "azure", "stairs": "umber", "unknown": "slate",
    "rest": "amber", "puzzle": "violet", "secret": "bone",
}

ICONS = {
    name: (pixel.shade_flat(pixel.mask_from_art(art, CELL), CELL), TINTS[name], PLACEMENT[name])
    for name, art in ART.items()
}
