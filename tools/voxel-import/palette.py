"""Shared palette colours — keep in sync with PixelDioramaStyle.PALETTES."""

from __future__ import annotations

from typing import Iterable

RGB = tuple[float, float, float]

# Eight slots per theme row: floor_base, floor_shadow, wall_base, wall_shadow,
# accent, prop_wood, prop_metal, emissive.
PALETTES: list[list[RGB]] = [
    # castle
    [
        (0.35, 0.32, 0.38),
        (0.24, 0.22, 0.28),
        (0.22, 0.20, 0.28),
        (0.14, 0.12, 0.18),
        (0.55, 0.42, 0.28),
        (0.42, 0.30, 0.18),
        (0.48, 0.46, 0.50),
        (1.00, 0.62, 0.28),
    ],
    # crystal
    [
        (0.42, 0.55, 0.78),
        (0.28, 0.38, 0.58),
        (0.32, 0.48, 0.72),
        (0.18, 0.28, 0.45),
        (0.65, 0.82, 0.95),
        (0.35, 0.42, 0.55),
        (0.55, 0.62, 0.72),
        (0.55, 0.85, 1.00),
    ],
    # swamp
    [
        (0.28, 0.34, 0.20),
        (0.18, 0.24, 0.12),
        (0.20, 0.28, 0.16),
        (0.12, 0.16, 0.10),
        (0.45, 0.55, 0.22),
        (0.32, 0.24, 0.14),
        (0.40, 0.38, 0.34),
        (0.70, 0.90, 0.35),
    ],
    # frozen
    [
        (0.72, 0.80, 0.88),
        (0.55, 0.65, 0.78),
        (0.62, 0.72, 0.82),
        (0.42, 0.52, 0.65),
        (0.85, 0.92, 0.98),
        (0.48, 0.38, 0.28),
        (0.58, 0.62, 0.68),
        (0.75, 0.90, 1.00),
    ],
    # cathedral
    [
        (0.30, 0.28, 0.34),
        (0.18, 0.16, 0.22),
        (0.24, 0.22, 0.30),
        (0.12, 0.10, 0.16),
        (0.62, 0.48, 0.32),
        (0.38, 0.28, 0.18),
        (0.52, 0.50, 0.56),
        (0.95, 0.72, 0.35),
    ],
    # vault
    [
        (0.38, 0.36, 0.40),
        (0.24, 0.22, 0.26),
        (0.30, 0.28, 0.34),
        (0.16, 0.14, 0.18),
        (0.72, 0.55, 0.28),
        (0.45, 0.32, 0.18),
        (0.58, 0.56, 0.60),
        (1.00, 0.55, 0.20),
    ],
    # prism
    [
        (0.40, 0.32, 0.58),
        (0.26, 0.20, 0.42),
        (0.34, 0.26, 0.52),
        (0.18, 0.12, 0.32),
        (0.72, 0.55, 0.95),
        (0.42, 0.32, 0.55),
        (0.55, 0.48, 0.68),
        (0.65, 0.45, 1.00),
    ],
    # mire
    [
        (0.26, 0.32, 0.18),
        (0.16, 0.22, 0.10),
        (0.18, 0.26, 0.12),
        (0.10, 0.14, 0.08),
        (0.42, 0.52, 0.18),
        (0.28, 0.20, 0.12),
        (0.36, 0.34, 0.30),
        (0.75, 0.95, 0.35),
    ],
    # hollow
    [
        (0.55, 0.68, 0.78),
        (0.38, 0.50, 0.62),
        (0.48, 0.60, 0.72),
        (0.30, 0.40, 0.52),
        (0.78, 0.90, 0.98),
        (0.40, 0.32, 0.26),
        (0.50, 0.54, 0.58),
        (0.70, 0.88, 1.00),
    ],
    # umbral
    [
        (0.22, 0.18, 0.28),
        (0.12, 0.10, 0.16),
        (0.18, 0.14, 0.24),
        (0.08, 0.06, 0.12),
        (0.48, 0.32, 0.58),
        (0.28, 0.20, 0.32),
        (0.38, 0.34, 0.42),
        (0.85, 0.55, 0.95),
    ],
]

SLOT_NAMES = (
    "floor_base",
    "floor_shadow",
    "wall_base",
    "wall_shadow",
    "accent",
    "prop_wood",
    "prop_metal",
    "emissive",
)


def flatten_palette() -> list[RGB]:
    colours: list[RGB] = []
    for row in PALETTES:
        colours.extend(row)
    return colours


def nearest_palette_colour(rgb: RGB, palette: Iterable[RGB] | None = None) -> RGB:
    candidates = list(palette) if palette is not None else flatten_palette()
    best = candidates[0]
    best_dist = float("inf")
    for colour in candidates:
        dist = sum((rgb[i] - colour[i]) ** 2 for i in range(3))
        if dist < best_dist:
            best_dist = dist
            best = colour
    return best


def snap_colour(rgb: RGB, palette: Iterable[RGB] | None = None) -> RGB:
    candidates = list(palette) if palette is not None else flatten_palette()
    for colour in candidates:
        if all(abs(rgb[i] - colour[i]) < 1e-3 for i in range(3)):
            return colour
    return nearest_palette_colour(rgb, candidates)
