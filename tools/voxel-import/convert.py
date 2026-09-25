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
    ArchetypeSpec,
    PartSpec,
    _palette_colours,
)
from mesh_builder import mesh_model, validate_mesh_on_grid
from palette import snap_colour
from vox_io import build_box_model, encode_vox, read_vox
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from generated_manifest import write_generated_bytes_set  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ART_SOURCE = ROOT / "art-source" / "characters"
MESH_JSON_DIR = ROOT / "apps" / "game" / "client" / "assets" / "characters" / "_intermediate"
MAX_TRIANGLES = 400


def _mesh_to_dict(mesh) -> dict:
    return {
        "vertices": [list(v) for v in mesh.vertices],
        "normals": [list(n) for n in mesh.normals],
        "colors": [list(c) for c in mesh.colors],
        "indices": mesh.indices,
    }


def _part_vox_name(part: PartSpec) -> str:
    return PART_FILE_NAMES.get(part.name, part.name.lower())


def _iter_manifest_parts(spec: ArchetypeSpec) -> list[PartSpec]:
    return [part for part in spec.parts if not part.skip_manifest and part.size != (0, 0, 0)]


def generate_sources(force: bool = False, dry_run: bool = False) -> None:
    outputs: list[tuple[Path, bytes]] = []
    for spec in ARCHETYPES:
        body, accent = _palette_colours(spec.theme_index)
        out_dir = ART_SOURCE / spec.id
        for part in spec.parts:
            if part.size == (0, 0, 0):
                continue
            file_name = _part_vox_name(part)
            vox_path = out_dir / f"{file_name}.vox"
            if vox_path.exists() and not force:
                continue
            model = build_box_model(part.size, body, accent if part.accent_band else None)
            outputs.append((vox_path, encode_vox(model)))

    equip_dir = ART_SOURCE / "equipment"
    for item_id, visual in EQUIPMENT_VISUALS.items():
        vox_path = equip_dir / f"{item_id}.vox"
        if vox_path.exists() and not force:
            continue
        body, accent = _palette_colours(visual["theme"])
        model = build_box_model(tuple(visual["size"]), body, accent)
        outputs.append((vox_path, encode_vox(model)))
    if outputs:
        write_generated_bytes_set(
            outputs,
            generator=Path(__file__).resolve(),
            sources=[Path(__file__).resolve(), Path(__file__).with_name("archetypes.py").resolve()],
            force=force,
            dry_run=dry_run,
        )


def convert_all(check_only: bool = False, dry_run: bool = False, force: bool = False) -> int:
    errors: list[str] = []
    outputs: list[tuple[Path, bytes]] = []
    source_paths: set[Path] = set()

    for spec in ARCHETYPES:
        for part in _iter_manifest_parts(spec):
            file_name = _part_vox_name(part)
            vox_path = ART_SOURCE / spec.id / f"{file_name}.vox"
            if not vox_path.exists():
                errors.append(f"missing source {vox_path}")
                continue
            model = read_vox(vox_path)
            source_paths.add(vox_path)
            mesh = mesh_model(model)
            validate_mesh_on_grid(mesh)
            if mesh.triangle_count() > MAX_TRIANGLES:
                errors.append(f"{vox_path}: {mesh.triangle_count()} triangles exceeds {MAX_TRIANGLES}")
            for colour in mesh.colors:
                snap_colour(colour)
            json_path = MESH_JSON_DIR / spec.id / f"{file_name}.mesh.json"
            fresh = json.dumps(_mesh_to_dict(mesh), separators=(",", ":"), sort_keys=True) + "\n"
            if check_only:
                if not json_path.exists() or json_path.read_text(encoding="utf-8") != fresh:
                    errors.append(f"missing or stale mesh json {json_path}")
            else:
                outputs.append((json_path, fresh.encode("utf-8")))

    for item_id, visual in EQUIPMENT_VISUALS.items():
        vox_path = ART_SOURCE / "equipment" / f"{item_id}.vox"
        if not vox_path.exists():
            errors.append(f"missing equipment source {vox_path}")
            continue
        model = read_vox(vox_path)
        source_paths.add(vox_path)
        mesh = mesh_model(model)
        validate_mesh_on_grid(mesh)
        json_path = MESH_JSON_DIR / "equipment" / f"{item_id}.mesh.json"
        fresh = json.dumps(_mesh_to_dict(mesh), separators=(",", ":"), sort_keys=True) + "\n"
        if check_only:
            if not json_path.exists() or json_path.read_text(encoding="utf-8") != fresh:
                errors.append(f"missing or stale equipment mesh json {json_path}")
        else:
            outputs.append((json_path, fresh.encode("utf-8")))

    if errors:
        for err in errors:
            print(err, file=sys.stderr)
        return 1
    written: list[Path] = []
    if not check_only:
        written = write_generated_bytes_set(
            outputs,
            generator=Path(__file__).resolve(),
            sources=sorted(source_paths),
            force=force,
            dry_run=dry_run,
        )
    print(
        f"convert ok ({len(outputs)} mesh json candidates, {len(written)} file(s) written; "
        "character content manifests remain owned by generate_character_voxels.py)"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Voxel character import pipeline")
    parser.add_argument("--generate-sources", action="store_true", help="Write art-source .vox files")
    parser.add_argument("--force-sources", action="store_true", help="Overwrite existing .vox sources")
    parser.add_argument("--check", action="store_true", help="Verify committed intermediates match sources")
    parser.add_argument("--dry-run", action="store_true", help="Validate ownership and generated intermediates without writing")
    parser.add_argument("--force", action="store_true", help="Explicitly replace unowned/manual mesh intermediates")
    args = parser.parse_args()

    if args.generate_sources:
        generate_sources(force=args.force_sources, dry_run=args.dry_run)
    return convert_all(check_only=args.check, dry_run=args.dry_run, force=args.force)


if __name__ == "__main__":
    raise SystemExit(main())
