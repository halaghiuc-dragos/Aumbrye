#!/usr/bin/env python3
"""Generate status and item icon atlases plus manifest JSON for Aumbrye."""

from __future__ import annotations

import hashlib
import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "apps" / "game" / "client"
ASSETS_UI = CLIENT / "assets" / "ui"
CONTENT_UI = ROOT / "content" / "ui"
CATALOG = ROOT / "content" / "items" / "catalog.json"

CELL = 16

STATUS_GLYPHS = {
    "burn": (255, 115, 26),
    "poison": (89, 230, 64),
    "freeze": (140, 217, 255),
    "stun": (255, 235, 51),
    "bleed": (217, 31, 31),
}

SLOT_KEYS = {
    "slot/helmet": (180, 180, 200),
    "slot/chest": (160, 170, 190),
    "slot/gloves": (150, 160, 180),
    "slot/boots": (140, 150, 170),
    "slot/weapon": (200, 180, 120),
    "slot/secondary": (170, 160, 140),
    "slot/ring": (220, 200, 80),
    "slot/amulet": (180, 140, 220),
    "slot/relic": (120, 200, 200),
}

TYPE_HUES = {
    "weapon": 30,
    "armor": 210,
    "accessory": 280,
    "consumable": 120,
    "material": 45,
    "key": 50,
    "relic": 300,
}


def _write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    raw_rows = []
    stride = width * 4
    for y in range(height):
        row = b"\x00" + rgba[y * stride : (y + 1) * stride]
        raw_rows.append(row)
    compressed = zlib.compress(b"".join(raw_rows), 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", compressed)
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def _hsv_to_rgb(h: float, s: float, v: float) -> tuple[int, int, int]:
    i = int(h * 6.0)
    f = h * 6.0 - i
    p = int(255 * v * (1.0 - s))
    q = int(255 * v * (1.0 - f * s))
    t = int(255 * v * (1.0 - (1.0 - f) * s))
    v255 = int(255 * v)
    i %= 6
    if i == 0:
        return v255, t, p
    if i == 1:
        return q, v255, p
    if i == 2:
        return p, v255, t
    if i == 3:
        return p, q, v255
    if i == 4:
        return t, p, v255
    return v255, p, q


def _item_color(item_id: str, item_type: str) -> tuple[int, int, int]:
    digest = hashlib.md5(item_id.encode()).digest()
    hue = (TYPE_HUES.get(item_type, 200) + digest[0]) % 360 / 360.0
    sat = 0.55 + (digest[1] / 255.0) * 0.35
    val = 0.65 + (digest[2] / 255.0) * 0.3
    return _hsv_to_rgb(hue, sat, val)


def _fill_circle(buf: bytearray, ox: int, oy: int, size: int, rgb: tuple[int, int, int]) -> None:
    cx = ox + size // 2
    cy = oy + size // 2
    r = size * 0.38
    r2 = r * r
    for y in range(size):
        for x in range(size):
            dx = x + 0.5 - (cx - ox)
            dy = y + 0.5 - (cy - oy)
            if dx * dx + dy * dy <= r2:
                idx = ((oy + y) * (buf_width) + (ox + x)) * 4
                buf[idx : idx + 3] = bytes([rgb[0], rgb[1], rgb[2], 255])


def _fill_diamond(buf: bytearray, ox: int, oy: int, size: int, rgb: tuple[int, int, int]) -> None:
    cx = size / 2.0
    cy = size / 2.0
    r = size * 0.42
    for y in range(size):
        for x in range(size):
            if abs(x + 0.5 - cx) / r + abs(y + 0.5 - cy) / r <= 1.0:
                idx = ((oy + y) * buf_width + (ox + x)) * 4
                buf[idx : idx + 3] = bytes([rgb[0], rgb[1], rgb[2], 255])


def _fill_checker(buf: bytearray, ox: int, oy: int, size: int) -> None:
    for y in range(size):
        for x in range(size):
            c = 255 if ((x // 4) + (y // 4)) % 2 == 0 else 0
            idx = ((oy + y) * buf_width + (ox + x)) * 4
            if c:
                buf[idx : idx + 3] = bytes([255, 0, 255, 255])
            else:
                buf[idx : idx + 3] = bytes([0, 0, 0, 255])


def _draw_item_glyph(buf: bytearray, ox: int, oy: int, item_id: str, item_type: str) -> None:
    rgb = _item_color(item_id, item_type)
    digest = hashlib.md5(item_id.encode()).digest()
    variant = digest[3] % 4
    if item_type == "weapon":
        for y in range(4, 13):
            for x in range(7, 9):
                idx = ((oy + y) * buf_width + (ox + x)) * 4
                buf[idx : idx + 3] = bytes([rgb[0], rgb[1], rgb[2], 255])
        for y in range(2, 6):
            for x in range(5, 11):
                idx = ((oy + y) * buf_width + (ox + x)) * 4
                buf[idx : idx + 3] = bytes([min(255, rgb[0] + 30), min(255, rgb[1] + 30), min(255, rgb[2] + 30), 255])
    elif item_type == "consumable":
        _fill_circle(buf, ox + 2, oy + 2, 12, rgb)
    elif item_type == "material":
        _fill_diamond(buf, ox + 2, oy + 2, 12, rgb)
    elif variant == 0:
        _fill_circle(buf, ox + 1, oy + 1, 14, rgb)
    elif variant == 1:
        _fill_diamond(buf, ox + 1, oy + 1, 14, rgb)
    else:
        for y in range(3, 13):
            for x in range(3, 13):
                if (x + y) % 3 != 0:
                    idx = ((oy + y) * buf_width + (ox + x)) * 4
                    buf[idx : idx + 3] = bytes([rgb[0], rgb[1], rgb[2], 255])


def _load_item_types() -> dict[str, str]:
    types: dict[str, str] = {}
    for category in ("equipment", "consumables", "materials", "relics"):
        for item_id in json.loads(CATALOG.read_text(encoding="utf-8")).get(category, []):
            rel = f"content/items/{category}/{item_id}.json"
            path = ROOT / rel.replace("/", "\\") if False else ROOT / rel
            if not path.exists() and category == "equipment":
                path = ROOT / "content" / "items" / "equipment" / f"{item_id}.json"
            if not path.exists() and category == "relics":
                path = ROOT / "content" / "items" / "relics" / f"{item_id}.json"
            if path.exists():
                data = json.loads(path.read_text(encoding="utf-8"))
                types[item_id] = data.get("itemType", category.rstrip("s"))
            else:
                types[item_id] = category.rstrip("s")
    return types


def generate_status_atlas() -> None:
    global buf_width
    cols, rows = 8, 6
    buf_width = cols * CELL
    buf_height = rows * CELL
    buf = bytearray(buf_width * buf_height * 4)

    cells: dict[str, dict[str, int]] = {}
    col = 0
    for status_id, rgb in STATUS_GLYPHS.items():
        ox, oy = col * CELL, 0
        if status_id == "freeze":
            _fill_diamond(buf, ox, oy, CELL, rgb)
        elif status_id == "stun":
            for y in range(CELL):
                for x in range(CELL):
                    if x >= 7 and x <= 8 and y >= 2:
                        idx = (oy + y) * buf_width + (ox + x)
                        buf[idx * 4 : idx * 4 + 3] = bytes([rgb[0], rgb[1], rgb[2], 255])
        else:
            _fill_circle(buf, ox, oy, CELL, rgb)
        cells[status_id] = {"col": col, "row": 0}
        col += 1

    unknown_col, unknown_row = 7, 5
    _fill_checker(buf, unknown_col * CELL, unknown_row * CELL, CELL)
    cells["unknown"] = {"col": unknown_col, "row": unknown_row}

    tex_path = ASSETS_UI / "status_icons.png"
    _write_png(tex_path, buf_width, buf_height, bytes(buf))

    manifest = {
        "schemaVersion": 1,
        "texture": "res://assets/ui/status_icons.png",
        "cellSize": CELL,
        "columns": cols,
        "rows": rows,
        "unknown": {"col": unknown_col, "row": unknown_row},
        "cells": cells,
    }
    CONTENT_UI.mkdir(parents=True, exist_ok=True)
    (CONTENT_UI / "status_icon_atlas.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )


def generate_item_atlas() -> None:
    global buf_width
    cols, rows = 16, 16
    buf_width = cols * CELL
    buf_height = rows * CELL
    buf = bytearray(buf_width * buf_height * 4)

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    item_types = _load_item_types()
    cells: dict[str, dict[str, int]] = {}
    index = 0

    def place(key: str, item_id: str, item_type: str) -> None:
        nonlocal index
        col = index % cols
        row = index // cols
        _draw_item_glyph(buf, col * CELL, row * CELL, item_id, item_type)
        cells[key] = {"col": col, "row": row}
        index += 1

    for category in ("equipment", "consumables", "materials", "relics"):
        for item_id in catalog.get(category, []):
            place(item_id, item_id, item_types.get(item_id, "material"))

    for slot_key, rgb in SLOT_KEYS.items():
        col = index % cols
        row = index // cols
        _fill_diamond(buf, col * CELL, row * CELL, CELL, rgb)
        cells[slot_key] = {"col": col, "row": row}
        index += 1

    unknown_col, unknown_row = 15, 15
    _fill_checker(buf, unknown_col * CELL, unknown_row * CELL, CELL)
    cells["unknown"] = {"col": unknown_col, "row": unknown_row}

    tex_path = ASSETS_UI / "item_icons.png"
    _write_png(tex_path, buf_width, buf_height, bytes(buf))

    manifest = {
        "schemaVersion": 1,
        "texture": "res://assets/ui/item_icons.png",
        "cellSize": CELL,
        "columns": cols,
        "rows": rows,
        "unknown": {"col": unknown_col, "row": unknown_row},
        "cells": cells,
    }
    (CONTENT_UI / "item_icon_atlas.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )


def main() -> None:
    generate_status_atlas()
    generate_item_atlas()
    print("Generated status_icons.png, item_icons.png, and manifests.")


if __name__ == "__main__":
    main()
