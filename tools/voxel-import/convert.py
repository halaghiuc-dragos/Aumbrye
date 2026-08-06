#!/usr/bin/env python3
"""Convert art-source .vox files to Godot mesh JSON intermediates."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from archetypes import (
    ARCHETYPES,
    EQUIPMENT_VISUALS,
    PART_FILE_NAMES,
    PART_NODE_NAMES,
    ArchetypeSpec,
    PartSpec,
    _palette_colours,
)
from mesh_builder import mesh_model, validate_mesh_on_grid
from palette import snap_colour
from vox_io import build_box_model, read_vox, write_vox

ROOT = Path(__file__).resolve().parents[2]
ART_SOURCE = ROOT / "art-source" / "characters"
MESH_JSON_DIR = ROOT / "apps" / "game" / "client" / "assets" / "characters" / "_intermediate"
CONTENT_DIR = ROOT / "content" / "characters"
MAX_TRIANGLES = 400


def _mesh_to_dict(mesh) -> dict:
    return {
        "vertices": [list(v) for v in mesh.vertices],
        "normals": [list(n) for n in mesh.normals],
        "colors": [list(c) for c in mesh.colors],
        "indices": mesh.indices,
    }


def _write_mesh_json(path: Path, mesh) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(_mesh_to_dict(mesh), separators=(",", ":"), sort_keys=True) + "\n", encoding="utf-8")


def _part_vox_name(part: PartSpec) -> str:
    return PART_FILE_NAMES.get(part.name, part.name.lower())


def _iter_manifest_parts(spec: ArchetypeSpec) -> list[PartSpec]:
    return [part for part in spec.parts if not part.skip_manifest and part.size != (0, 0, 0)]


def generate_sources(force: bool = False) -> None:
    for spec in ARCHETYPES:
        body, accent = _palette_colours(spec.theme_index)
        out_dir = ART_SOURCE / spec.id
        out_dir.mkdir(parents=True, exist_ok=True)
        for part in spec.parts:
            if part.size == (0, 0, 0):
                continue
            file_name = _part_vox_name(part)
            vox_path = out_dir / f"{file_name}.vox"
            if vox_path.exists() and not force:
                continue
            model = build_box_model(part.size, body, accent if part.accent_band else None)
            write_vox(vox_path, model)

    equip_dir = ART_SOURCE / "equipment"
    equip_dir.mkdir(parents=True, exist_ok=True)
    for item_id, visual in EQUIPMENT_VISUALS.items():
        vox_path = equip_dir / f"{item_id}.vox"
        if vox_path.exists() and not force:
            continue
        body, accent = _palette_colours(visual["theme"])
        model = build_box_model(tuple(visual["size"]), body, accent)
        write_vox(vox_path, model)


def convert_all(check_only: bool = False) -> int:
    errors: list[str] = []
    changed = 0

    for spec in ARCHETYPES:
        manifest_parts: dict[str, dict] = {}
        for part in _iter_manifest_parts(spec):
            file_name = _part_vox_name(part)
            vox_path = ART_SOURCE / spec.id / f"{file_name}.vox"
            if not vox_path.exists():
                errors.append(f"missing source {vox_path}")
                continue
            model = read_vox(vox_path)
            mesh = mesh_model(model)
            validate_mesh_on_grid(mesh)
            if mesh.triangle_count() > MAX_TRIANGLES:
                errors.append(f"{vox_path}: {mesh.triangle_count()} triangles exceeds {MAX_TRIANGLES}")
            for colour in mesh.colors:
                snap_colour(colour)
            json_path = MESH_JSON_DIR / spec.id / f"{file_name}.mesh.json"
            if check_only:
                if not json_path.exists():
                    errors.append(f"missing committed mesh json {json_path}")
                    continue
                existing = json_path.read_text(encoding="utf-8")
                fresh = json.dumps(_mesh_to_dict(mesh), separators=(",", ":"), sort_keys=True) + "\n"
                if existing != fresh:
                    errors.append(f"stale mesh json {json_path}")
            else:
                _write_mesh_json(json_path, mesh)
                changed += 1
            node_name = PART_NODE_NAMES.get(part.name, part.name)
            entry = {
                "mesh": f"res://assets/characters/{spec.id}/{file_name}.mesh",
                "joint": list(part.joint),
            }
            if part.parent not in ("", "Root"):
                entry["parent"] = part.parent
            if part.mount:
                entry["mount"] = part.mount
            manifest_parts[node_name] = entry

        if not check_only and manifest_parts:
            manifest = {
                "id": spec.id,
                "grid": 0.04,
                "profile": spec.profile,
                "parts": manifest_parts,
            }
            if spec.animation_library:
                manifest["animationLibrary"] = spec.animation_library
            if spec.profile == "biped":
                manifest["slots"] = {
                    "head": "Head",
                    "chest": "Torso",
                    "hands": ["ArmL", "ArmR"],
                    "feet": ["LegL", "LegR"],
                }
            CONTENT_DIR.mkdir(parents=True, exist_ok=True)
            (CONTENT_DIR / f"{spec.id}.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    for item_id, visual in EQUIPMENT_VISUALS.items():
        vox_path = ART_SOURCE / "equipment" / f"{item_id}.vox"
        if not vox_path.exists():
            errors.append(f"missing equipment source {vox_path}")
            continue
        model = read_vox(vox_path)
        mesh = mesh_model(model)
        validate_mesh_on_grid(mesh)
        json_path = MESH_JSON_DIR / "equipment" / f"{item_id}.mesh.json"
        if check_only:
            if not json_path.exists():
                errors.append(f"missing equipment mesh json {json_path}")
        else:
            _write_mesh_json(json_path, mesh)
            changed += 1

    if errors:
        for err in errors:
            print(err, file=sys.stderr)
        return 1
    print(f"convert ok ({changed} mesh json files)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Voxel character import pipeline")
    parser.add_argument("--generate-sources", action="store_true", help="Write art-source .vox files")
    parser.add_argument("--force-sources", action="store_true", help="Overwrite existing .vox sources")
    parser.add_argument("--check", action="store_true", help="Verify committed intermediates match sources")
    args = parser.parse_args()

    if args.generate_sources:
        generate_sources(force=args.force_sources)
    return convert_all(check_only=args.check)


if __name__ == "__main__":
    raise SystemExit(main())
