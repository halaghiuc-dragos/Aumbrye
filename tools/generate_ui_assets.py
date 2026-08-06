#!/usr/bin/env python3
"""Generate status/item icon PNGs and character voxel JSON for Aumbrye."""

from __future__ import annotations

import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "apps" / "game" / "client"
ASSETS_UI = CLIENT / "assets" / "ui"
ASSETS_CHARS = CLIENT / "assets" / "characters"
CONTENT_UI = ROOT / "content" / "ui"
CONTENT_CHARS = ROOT / "content" / "characters"
VOXEL_EDGE = 0.04

STATUS_IDS = ["burn", "poison", "freeze", "stun", "bleed"]
STATUS_COLORS = {
    "burn": (255, 115, 26),
    "poison": (89, 230, 64),
    "freeze": (140, 217, 255),
    "stun": (255, 235, 51),
    "bleed": (217, 31, 31),
    "unknown": (128, 128, 128),
}

ITEM_ICON_IDS = [
    "health_potion",
    "mana_potion",
    "stamina_potion",
    "iron_scrap",
    "castle_sword",
    "castle_crown",
    "castle_chalice",
    "leather_cap",
    "iron_helm",
    "leather_vest",
    "iron_chest",
    "leather_gloves",
    "iron_gauntlets",
    "leather_boots",
    "iron_greaves",
    "ring_of_vigor",
    "amulet_of_ward",
    "elixir_might",
    "elixir_vigor",
    "dungeon_key",
]


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = b""
    stride = width * 4
    for y in range(height):
        raw += b"\x00" + rgba[y * stride : (y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(raw, 9)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", idat)
        + _png_chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def _draw_status_glyph(
    rgba: bytearray,
    w: int,
    h: int,
    col: int,
    row: int,
    cell: int,
    color: tuple[int, int, int],
    shape: str,
) -> None:
    ox, oy = col * cell, row * cell
    for y in range(cell):
        for x in range(cell):
            px, py = ox + x, oy + y
            if px >= w or py >= h:
                continue
            dx, dy = x - cell // 2, y - cell // 2
            on = False
            if shape == "circle":
                on = dx * dx + dy * dy <= (cell * 0.38) ** 2
            elif shape == "diamond":
                on = abs(dx) + abs(dy) <= cell * 0.42
            elif shape == "bolt":
                on = abs(dx) <= 2 and abs(dy) <= cell * 0.4 and (dy < 0 or abs(dx) <= 1)
            elif shape == "ring":
                d2 = dx * dx + dy * dy
                on = (cell * 0.22) ** 2 <= d2 <= (cell * 0.4) ** 2
            else:
                on = dx * dx + dy * dy <= (cell * 0.35) ** 2
            if on:
                i = (py * w + px) * 4
                rgba[i : i + 4] = bytes([color[0], color[1], color[2], 255])


def generate_status_atlas(path: Path, cb: bool = False) -> None:
    cols, rows, cell = 8, 6, 16
    w, h = cols * cell, rows * cell
    rgba = bytearray(w * h * 4)
    shapes = {
        "burn": "circle",
        "poison": "ring",
        "freeze": "diamond",
        "stun": "bolt",
        "bleed": "circle",
        "unknown": "circle",
    }
    for i, sid in enumerate(STATUS_IDS):
        color = STATUS_COLORS[sid]
        if cb:
            color = tuple(int(c * (0.6 + (i % 3) * 0.15)) for c in color)
        _draw_status_glyph(rgba, w, h, i, 0, cell, color, shapes[sid])
    _draw_status_glyph(rgba, w, h, 7, 5, cell, STATUS_COLORS["unknown"], "circle")
    write_png(path, w, h, bytes(rgba))


def generate_item_atlas(path: Path) -> None:
    cols, cell = 16, 16
    rows = (len(ITEM_ICON_IDS) + cols - 1) // cols
    w, h = cols * cell, max(rows, 16) * cell
    rgba = bytearray(w * h * 4)
    for idx, item_id in enumerate(ITEM_ICON_IDS):
        col, row = idx % cols, idx // cols
        hue = (hash(item_id) % 360) / 360.0
        r = int(80 + 120 * ((hue * 3) % 1))
        g = int(80 + 120 * ((hue * 5 + 0.3) % 1))
        b = int(80 + 120 * ((hue * 7 + 0.6) % 1))
        ox, oy = col * cell, row * cell
        for y in range(2, cell - 2):
            for x in range(2, cell - 2):
                px, py = ox + x, oy + y
                i = (py * w + px) * 4
                rgba[i : i + 4] = bytes([r, g, b, 255])
    write_png(path, w, h, bytes(rgba))


def _voxels_from_size(size_m: tuple[float, float, float], color: list[float]) -> dict:
    sx = max(1, round(size_m[0] / VOXEL_EDGE))
    sy = max(1, round(size_m[1] / VOXEL_EDGE))
    sz = max(1, round(size_m[2] / VOXEL_EDGE))
    cells = []
    for x in range(int(sx)):
        for y in range(int(sy)):
            for z in range(int(sz)):
                cells.append([x, y, z])
    return {"edge": VOXEL_EDGE, "size": [int(sx), int(sy), int(sz)], "color": color, "cells": cells}


PROFILES = {
    "player_warden": {
        "profile": "biped",
        "parts": {
            "LegL": {"size": (0.24, 0.48, 0.24), "joint": [-3, 12, 0]},
            "LegR": {"size": (0.24, 0.48, 0.24), "joint": [3, 12, 0]},
            "Torso": {"size": (0.48, 0.64, 0.32), "joint": [0, 12, 0]},
            "Head": {"size": (0.32, 0.32, 0.32), "joint": [0, 16, 0], "parent": "Torso"},
            "ArmL": {"size": (0.20, 0.52, 0.20), "joint": [-7, 14, 0], "parent": "Torso"},
            "ArmR": {"size": (0.20, 0.52, 0.20), "joint": [7, 14, 0], "parent": "Torso"},
        },
    },
    "enemy_melee": {
        "profile": "biped",
        "parts": {
            "LegL": {"size": (0.24, 0.48, 0.28), "joint": [-3, 12, 0]},
            "LegR": {"size": (0.24, 0.48, 0.28), "joint": [3, 12, 0]},
            "Torso": {"size": (0.56, 0.64, 0.40), "joint": [0, 12, 0]},
            "Head": {"size": (0.36, 0.36, 0.36), "joint": [0, 16, 0], "parent": "Torso"},
            "ArmL": {"size": (0.24, 0.56, 0.24), "joint": [-8, 14, 0], "parent": "Torso"},
            "ArmR": {"size": (0.24, 0.56, 0.24), "joint": [8, 14, 0], "parent": "Torso"},
        },
    },
    "enemy_ranged": {
        "profile": "biped",
        "parts": {
            "LegL": {"size": (0.20, 0.44, 0.24), "joint": [-3, 11, 0]},
            "LegR": {"size": (0.20, 0.44, 0.24), "joint": [3, 11, 0]},
            "Torso": {"size": (0.44, 0.56, 0.32), "joint": [0, 11, 0]},
            "Head": {"size": (0.28, 0.28, 0.28), "joint": [0, 14, 0], "parent": "Torso"},
            "ArmL": {"size": (0.16, 0.48, 0.16), "joint": [-6, 13, 0], "parent": "Torso"},
            "ArmR": {"size": (0.16, 0.48, 0.16), "joint": [6, 13, 0], "parent": "Torso"},
        },
    },
    "enemy_brute": {
        "profile": "biped",
        "parts": {
            "LegL": {"size": (0.32, 0.52, 0.32), "joint": [-4, 13, 0]},
            "LegR": {"size": (0.32, 0.52, 0.32), "joint": [4, 13, 0]},
            "Torso": {"size": (0.80, 0.84, 0.52), "joint": [0, 13, 0]},
            "Head": {"size": (0.44, 0.44, 0.44), "joint": [0, 21, 0], "parent": "Torso"},
            "ArmL": {"size": (0.32, 0.68, 0.32), "joint": [-11, 18, 0], "parent": "Torso"},
            "ArmR": {"size": (0.32, 0.68, 0.32), "joint": [11, 18, 0], "parent": "Torso"},
        },
    },
}


def generate_character_assets() -> None:
    CONTENT_CHARS.mkdir(parents=True, exist_ok=True)
    for archetype, spec in PROFILES.items():
        out_dir = ASSETS_CHARS / archetype
        out_dir.mkdir(parents=True, exist_ok=True)
        manifest = {
            "id": archetype,
            "grid": VOXEL_EDGE,
            "profile": spec["profile"],
            "parts": {},
        }
        for part_name, part in spec["parts"].items():
            fname = part_name.lower() + ".voxels.json"
            rel_mesh = f"res://assets/characters/{archetype}/{fname}"
            color = [0.55, 0.58, 0.62] if "enemy" in archetype else [0.42, 0.48, 0.55]
            vox = _voxels_from_size(part["size"], color)
            (out_dir / fname).write_text(json.dumps(vox, indent=2), encoding="utf-8")
            entry = {"mesh": rel_mesh, "joint": part["joint"]}
            if "parent" in part:
                entry["parent"] = part["parent"]
            if part_name == "ArmL":
                entry["mount"] = "ShieldMount"
            if part_name == "ArmR":
                entry["mount"] = "WeaponMount"
            manifest["parts"][part_name] = entry
        (CONTENT_CHARS / f"{archetype}.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def write_manifests() -> None:
    CONTENT_UI.mkdir(parents=True, exist_ok=True)
    status_cells = {sid: {"col": i, "row": 0} for i, sid in enumerate(STATUS_IDS)}
    status_cells["unknown"] = {"col": 7, "row": 5}
    (CONTENT_UI / "status_icon_atlas.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "texture": "res://assets/ui/status_icons.png",
                "textureColorblind": "res://assets/ui/status_icons_cb.png",
                "cellSize": 16,
                "columns": 8,
                "rows": 6,
                "cells": status_cells,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    item_cells = {item_id: {"col": i % 16, "row": i // 16} for i, item_id in enumerate(ITEM_ICON_IDS)}
    (CONTENT_UI / "item_icon_atlas.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "texture": "res://assets/ui/item_icons.png",
                "cellSize": 16,
                "columns": 16,
                "rows": 16,
                "cells": item_cells,
            },
            indent=2,
        ),
        encoding="utf-8",
    )


def main() -> None:
    ASSETS_UI.mkdir(parents=True, exist_ok=True)
    generate_status_atlas(ASSETS_UI / "status_icons.png", cb=False)
    generate_status_atlas(ASSETS_UI / "status_icons_cb.png", cb=True)
    generate_item_atlas(ASSETS_UI / "item_icons.png")
    write_manifests()
    generate_character_assets()
    print("Generated UI and character assets.")


if __name__ == "__main__":
    main()
