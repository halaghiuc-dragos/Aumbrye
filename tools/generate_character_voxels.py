#!/usr/bin/env python3
"""Generate .voxels.json character assets and rig manifests for the Godot client."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "voxel-import"))
sys.path.insert(0, str(ROOT / "tools"))

from voxel_sculpt import sculpt_for_part  # noqa: E402

from archetypes import (  # noqa: E402
    ArchetypeSpec,
    ExtraSpec,
    PartSpec,
    all_archetypes,
    theme_colours,
)

VOXEL_EDGE = 0.04
CLIENT_ASSETS = ROOT / "apps" / "game" / "client" / "assets" / "characters"
CONTENT_CHARS = ROOT / "content" / "characters"

# Height variants reuse standard meshes; only joint offsets differ.
HEIGHT_VARIANT_MANIFESTS = {
    "player_warden_compact": {
        "base_meshes": "player_warden",
        "joint_delta": -2,
    },
    "player_warden_tall": {
        "base_meshes": "player_warden",
        "joint_delta": 2,
    },
}

# Lean and heavy builds have their own part dimensions, so they cannot reuse the standard rig's
# meshes the way the height variants do. They used to be pre-baked to binary .mesh files and
# skipped here entirely — which meant the voxel sculptor never saw them, and six of the nine body
# shapes a player can pick were still solid boxes after every other rig had been shaped. They are
# generated from source like everything else now.
SKIP_MESH_ARCHETYPE_SUFFIXES: tuple[str, ...] = ()


def _part_file_name(part_name: str) -> str:
    return part_name.lower()


def _voxels_from_size(
    size_voxels: tuple[int, int, int],
    color: tuple[float, float, float],
    part_name: str = "",
) -> dict:
    """Sculpt a part instead of filling its bounding box.

    This used to emit every cell in the box, so each of the eight parts of every rig was a solid
    rectangular prism and the whole cast read as stacked crates. The format always allowed an
    arbitrary `cells` list and the runtime mesher is a greedy mesher that handles sparse occupancy
    happily — nothing but this function needed to change.
    """
    sculpt = sculpt_for_part(part_name, size_voxels)
    cells = sculpt.normalised_cells()
    if not cells:
        # A profile should never erase a part outright, but shipping an empty mesh would be worse
        # than shipping the old box.
        sx, sy, sz = size_voxels
        cells = [[x, y, z] for x in range(sx) for y in range(sy) for z in range(sz)]
    span = [max(c[i] for c in cells) + 1 for i in range(3)]
    return {
        "edge": VOXEL_EDGE,
        "size": span,
        "color": [round(c, 4) for c in color],
        "cells": cells,
    }


def _part_color(spec: ArchetypeSpec, part: PartSpec) -> tuple[float, float, float]:
    body, accent = theme_colours(spec.theme_index)
    return accent if part.accent_band else body


def _should_generate_meshes(spec: ArchetypeSpec) -> bool:
    archetype_id = spec.id
    if archetype_id in HEIGHT_VARIANT_MANIFESTS:
        return False
    for suffix in SKIP_MESH_ARCHETYPE_SUFFIXES:
        if archetype_id.endswith(suffix):
            return False
    return True


def _write_voxels(
    out_dir: Path,
    name: str,
    size: tuple[int, int, int],
    color: tuple[float, float, float],
) -> None:
    if size == (0, 0, 0):
        return
    fname = _part_file_name(name) + ".voxels.json"
    payload = _voxels_from_size(size, color, name)
    (out_dir / fname).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def _write_part_voxels(out_dir: Path, part: PartSpec, color: tuple[float, float, float]) -> None:
    _write_voxels(out_dir, part.name, part.size, color)


def _extra_color(spec: ArchetypeSpec, extra: ExtraSpec) -> tuple[float, float, float]:
    body, accent = theme_colours(spec.theme_index)
    return accent if extra.accent else body


def _extras_manifest(spec: ArchetypeSpec, mesh_archetype: str) -> dict:
    extras: dict = {}
    for extra in spec.extras:
        extras[extra.name] = {
            "mesh": (
                f"res://assets/characters/{mesh_archetype}/{_part_file_name(extra.name)}.voxels.json"
            ),
            "parent": extra.parent,
            "offset": list(extra.offset),
        }
    return extras


def _manifest_entry(spec: ArchetypeSpec, part: PartSpec, mesh_archetype: str) -> dict:
    fname = _part_file_name(part.name) + ".voxels.json"
    entry: dict = {
        "mesh": f"res://assets/characters/{mesh_archetype}/{fname}",
        "joint": list(part.joint),
    }
    if part.parent not in ("", "Root"):
        entry["parent"] = part.parent
    if part.mount:
        entry["mount"] = part.mount
    if part.mesh_offset != (0, 0, 0):
        entry["meshOffset"] = list(part.mesh_offset)
    return entry


def _write_manifest(
    spec: ArchetypeSpec,
    mesh_archetype: str,
    *,
    manifest_id: str | None = None,
    joint_delta: int = 0,
) -> None:
    parts: dict = {}
    for part in spec.parts:
        if part.skip_manifest or part.size == (0, 0, 0):
            continue
        entry = _manifest_entry(spec, part, mesh_archetype)
        if joint_delta:
            joint = entry["joint"]
            entry["joint"] = [joint[0], joint[1] + joint_delta, joint[2]]
        parts[part.name] = entry
    manifest = {
        "id": manifest_id or spec.id,
        "grid": VOXEL_EDGE,
        "profile": spec.profile,
        "parts": parts,
    }
    if spec.animation_library:
        manifest["animationLibrary"] = spec.animation_library
    extras_manifest = _extras_manifest(spec, mesh_archetype)
    if extras_manifest:
        manifest["extras"] = extras_manifest
    if spec.profile == "biped":
        manifest["slots"] = {
            "head": "Head",
            "chest": "Torso",
            "hands": ["ArmL", "ArmR"],
            "feet": ["LegL", "LegR"],
        }
    path = CONTENT_CHARS / f"{manifest_id or spec.id}.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def generate_all() -> None:
    CONTENT_CHARS.mkdir(parents=True, exist_ok=True)
    specs = {spec.id: spec for spec in all_archetypes()}
    generated_mesh_ids: set[str] = set()

    for spec in all_archetypes():
        if not _should_generate_meshes(spec):
            continue
        out_dir = CLIENT_ASSETS / spec.id
        out_dir.mkdir(parents=True, exist_ok=True)
        for part in spec.parts:
            color = _part_color(spec, part)
            _write_part_voxels(out_dir, part, color)
        for extra in spec.extras:
            _write_voxels(out_dir, extra.name, extra.size, _extra_color(spec, extra))
        generated_mesh_ids.add(spec.id)

    for spec in all_archetypes():
        if spec.id in HEIGHT_VARIANT_MANIFESTS:
            continue
        mesh_archetype = spec.id if spec.id in generated_mesh_ids else "player_warden"
        _write_manifest(spec, mesh_archetype)

    base_player = specs.get("player_warden")
    if base_player is not None:
        for variant_id, cfg in HEIGHT_VARIANT_MANIFESTS.items():
            _write_manifest(
                base_player,
                cfg["base_meshes"],
                manifest_id=variant_id,
                joint_delta=cfg["joint_delta"],
            )

    print(f"Generated character voxels under {CLIENT_ASSETS}")
    print(f"Wrote manifests under {CONTENT_CHARS}")


def main() -> int:
    generate_all()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
