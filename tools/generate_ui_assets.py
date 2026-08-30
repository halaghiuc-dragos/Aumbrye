#!/usr/bin/env python3
"""Generate character voxel JSON for Aumbrye.

This used to generate the status and item icon sheets too, from a table of twenty item ids and
five status ids, as flat colour blobs. It was the reason half the colourblind status sheet was
empty and the item atlas had a placeholder era baked into it -- running it overwrote the authored
artwork. Those sheets now come from tools/icon-gen/atlas_build.py, which draws all of them to one
set of rules; nothing about icons is generated here any more.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "apps" / "game" / "client"
ASSETS_CHARS = CLIENT / "assets" / "characters"
CONTENT_CHARS = ROOT / "content" / "characters"
VOXEL_EDGE = 0.04


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


def main() -> None:
    generate_character_assets()
    print("Generated character assets.")


if __name__ == "__main__":
    main()
