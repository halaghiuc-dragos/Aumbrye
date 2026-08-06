#!/usr/bin/env python3
"""Generate aumbrye_pixel.ttf and paperdoll_silhouette.png for game UI skin."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI_DIR = ROOT / "apps" / "game" / "client" / "assets" / "ui"
FONT_DIR = UI_DIR / "fonts"
FONT_PATH = FONT_DIR / "aumbrye_pixel.ttf"
PNG_PATH = UI_DIR / "paperdoll_silhouette.png"

SILHOUETTE_RGBA = (36, 33, 43, 140)  # ~Color(0.14, 0.13, 0.17, 0.55)


def write_png(path: Path, width: int, height: int, pixels: list[tuple[int, int, int, int]]) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixels[y * width + x])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def make_paperdoll_png() -> None:
    w, h = 96, 160
    pixels = [(0, 0, 0, 0)] * (w * h)

    def fill_rect(x0: int, y0: int, x1: int, y1: int) -> None:
        for y in range(max(0, y0), min(h, y1)):
            for x in range(max(0, x0), min(w, x1)):
                pixels[y * w + x] = SILHOUETTE_RGBA

    cx = w // 2
    fill_rect(cx - 10, 12, cx + 10, 32)  # head
    fill_rect(cx - 16, 32, cx + 16, 78)  # torso
    fill_rect(cx - 28, 36, cx - 14, 72)  # left arm
    fill_rect(cx + 14, 36, cx + 28, 72)  # right arm
    fill_rect(cx - 14, 78, cx - 2, 132)  # left leg
    fill_rect(cx + 2, 78, cx + 14, 132)  # right leg
    write_png(PNG_PATH, w, h, pixels)
    print(f"wrote {PNG_PATH}")


def make_pixel_ttf() -> None:
    import urllib.request

    # OFL-licensed pixel font (Press Start 2P) — renamed for the project skin.
    url = (
        "https://github.com/google/fonts/raw/main/ofl/pressstart2p/"
        "PressStart2P-Regular.ttf"
    )
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=60) as response:
        FONT_PATH.write_bytes(response.read())
    print(f"wrote {FONT_PATH}")


def main() -> None:
    make_paperdoll_png()
    make_pixel_ttf()


if __name__ == "__main__":
    main()
