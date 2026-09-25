#!/usr/bin/env python3
"""Generate aumbrye_pixel.ttf and paperdoll_silhouette.png for game UI skin."""

from __future__ import annotations

import struct
import zlib
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from generated_manifest import load_manifest, record_write, write_generated_bytes_set

UI_DIR = ROOT / "apps" / "game" / "client" / "assets" / "ui"
FONT_DIR = UI_DIR / "fonts"
FONT_PATH = FONT_DIR / "aumbrye_pixel.ttf"
PNG_PATH = UI_DIR / "paperdoll_silhouette.png"

SILHOUETTE_RGBA = (36, 33, 43, 140)  # ~Color(0.14, 0.13, 0.17, 0.55)


def encode_png(width: int, height: int, pixels: list[tuple[int, int, int, int]]) -> bytes:
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
    return png


def make_paperdoll_png() -> bytes:
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
    return encode_png(w, h, pixels)


def validate_png(data: bytes, width: int, height: int) -> None:
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Generated paperdoll is not a PNG")
    if data[12:16] != b"IHDR" or struct.unpack(">II", data[16:24]) != (width, height):
        raise ValueError(f"Generated paperdoll must be {width}x{height}")
    offset = 8
    saw_end = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunk_type = data[offset + 4:offset + 8]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("Generated paperdoll has a truncated PNG chunk")
        chunk_data = data[offset + 8:offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length:end])[0]
        if zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF != expected_crc:
            raise ValueError("Generated paperdoll has a bad PNG chunk checksum")
        offset = end
        if chunk_type == b"IEND":
            saw_end = True
            break
    if not saw_end or offset != len(data):
        raise ValueError("Generated paperdoll has no terminal IEND chunk")


def generate(
    *, font_source: Path | None, force: bool, dry_run: bool, adopt_identical: bool = False
) -> list[Path]:
    paperdoll = make_paperdoll_png()
    validate_png(paperdoll, 96, 160)
    outputs: list[tuple[Path, bytes]] = [(PNG_PATH, paperdoll)]
    sources: list[Path] = []
    if font_source is not None:
        if not font_source.is_file():
            raise FileNotFoundError(f"Pixel font source does not exist: {font_source}")
        font_data = font_source.read_bytes()
        if not font_data.startswith(b"\x00\x01\x00\x00"):
            raise ValueError(f"Pixel font source is not a TrueType font: {font_source}")
        outputs.append((FONT_PATH, font_data))
        sources.append(font_source)
    written = write_generated_bytes_set(
        outputs,
        generator=Path(__file__).resolve(),
        sources=sources,
        force=force,
        dry_run=dry_run,
    )
    if adopt_identical and not dry_run:
        manifest = load_manifest()
        for path, content in outputs:
            key = path.resolve().relative_to(ROOT).as_posix()
            if path.is_file() and path.read_bytes() == content and key not in manifest:
                record_write(path, content, generator=Path(__file__).resolve(), sources=sources)
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font-source", type=Path, help="existing in-repository licensed TTF source to stage as the UI font")
    parser.add_argument("--force", action="store_true", help="allow replacing outputs that differ from their registered generator owner")
    parser.add_argument("--dry-run", action="store_true", help="preflight without publishing outputs")
    parser.add_argument("--adopt-identical", action="store_true", help="register an existing byte-identical output without rewriting it")
    args = parser.parse_args()
    written = generate(
        font_source=args.font_source,
        force=args.force,
        dry_run=args.dry_run,
        adopt_identical=args.adopt_identical,
    )
    print(f"UI-skin candidates: 2" if args.font_source else "UI-skin candidates: 1")
    print(f"published: {len(written)}")
    if args.font_source is None:
        print("font unchanged; pass --font-source with an in-repository licensed TTF to publish it")


if __name__ == "__main__":
    main()
