"""Convert art-source .vox files to Godot ArrayMesh assets and rig manifests."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from archetypes import ArchetypeSpec, all_archetypes, equipment_archetypes, theme_colours
from godot_mesh_writer import mesh_resource_path, write_mesh
from mesh_builder import EDGE, mesh_model, validate_mesh_on_grid
from palette import snap_colour
from vox_io import build_box_model, write_vox

REPO_ROOT = Path(__file__).resolve().parents[2]
ART_SOURCE = REPO_ROOT / "art-source" / "characters"
CLIENT_ASSETS = REPO_ROOT / "apps" / "game" / "client" / "assets" / "characters"
CONTENT_CHARS = REPO_ROOT / "content" / "characters"


def _part_file_name(part_name: str) -> str:
    return part_name.lower()


def _build_part_model(spec_part, body_colour, accent_colour) -> object:
    body = snap_colour(body_colour)
    accent = snap_colour(accent_colour)
    accent_band = getattr(spec_part, "accent_band", False)
    model = build_box_model(spec_part.size, body, accent if accent_band else None)
    return model


def _build_extra_model(extra, body_colour, accent_colour) -> object:
    colour = accent_colour if extra.accent else body_colour
    return build_box_model(extra.size, snap_colour(colour))


def generate_archetype(spec: ArchetypeSpec, write_vox_files: bool = True) -> None:
    body_colour, accent_colour = theme_colours(spec.theme_index)
    parts_manifest: dict = {}
    extras_manifest: dict = {}

    for part in spec.parts:
        if part.size == (0, 0, 0):
            continue
        model = _build_part_model(part, body_colour, accent_colour)
        mesh = mesh_model(model)
        validate_mesh_on_grid(mesh)
        part_file = _part_file_name(part.name)
        if write_vox_files:
            vox_path = ART_SOURCE / spec.id / f"{part_file}.vox"
            write_vox(vox_path, model)
        mesh_path = CLIENT_ASSETS / spec.id / f"{part_file}.mesh"
        write_mesh(mesh_path, mesh)

        if part.skip_manifest:
            continue
        entry: dict = {
            "mesh": mesh_resource_path(spec.id, part_file),
            "joint": list(part.joint),
        }
        if part.parent != "Root":
            entry["parent"] = part.parent
        if part.mount:
            entry["mount"] = part.mount
        if part.mesh_offset != (0, 0, 0):
            entry["meshOffset"] = list(part.mesh_offset)
        parts_manifest[part.name] = entry

    for extra in spec.extras:
        model = _build_extra_model(extra, body_colour, accent_colour)
        mesh = mesh_model(model)
        validate_mesh_on_grid(mesh)
        extra_file = _part_file_name(extra.name)
        if write_vox_files:
            vox_path = ART_SOURCE / spec.id / f"{extra_file}.vox"
            write_vox(vox_path, model)
        mesh_path = CLIENT_ASSETS / spec.id / f"{extra_file}.mesh"
        write_mesh(mesh_path, mesh)
        extras_manifest[extra.name] = {
            "mesh": mesh_resource_path(spec.id, extra_file),
            "parent": extra.parent,
            "offset": list(extra.offset),
        }

    manifest = {
        "id": spec.id,
        "grid": EDGE,
        "profile": spec.profile,
        "parts": parts_manifest,
    }
    if spec.animation_library:
        manifest["animationLibrary"] = spec.animation_library
    if extras_manifest:
        manifest["extras"] = extras_manifest
    if spec.profile == "biped":
        manifest["slots"] = {
            "head": "Head",
            "chest": "Torso",
            "hands": ["ArmL", "ArmR"],
            "feet": ["LegL", "LegR"],
        }

    CONTENT_CHARS.mkdir(parents=True, exist_ok=True)
    manifest_path = CONTENT_CHARS / f"{spec.id}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def generate_equipment(spec: ArchetypeSpec, write_vox_files: bool = True) -> None:
    body_colour, accent_colour = theme_colours(spec.theme_index)
    item_id = spec.id.replace("equipment_", "")
    for part in spec.parts:
        model = _build_part_model(part, body_colour, accent_colour)
        mesh = mesh_model(model)
        validate_mesh_on_grid(mesh)
        if write_vox_files:
            vox_path = ART_SOURCE / "equipment" / f"{item_id}.vox"
            write_vox(vox_path, model)
        mesh_path = CLIENT_ASSETS / "equipment" / f"{item_id}.mesh"
        write_mesh(mesh_path, mesh)


def generate_all(write_vox_files: bool = True) -> None:
    for spec in all_archetypes():
        generate_archetype(spec, write_vox_files=write_vox_files)
    for spec in equipment_archetypes():
        generate_equipment(spec, write_vox_files=write_vox_files)


def convert_vox_tree(source_root: Path, output_root: Path) -> None:
    for vox_path in sorted(source_root.rglob("*.vox")):
        from vox_io import read_vox

        model = read_vox(vox_path)
        for index, colour in enumerate(model.palette):
            if index == 0:
                continue
            try:
                snap_colour(colour)
            except ValueError:
                pass
        mesh = mesh_model(model)
        validate_mesh_on_grid(mesh)
        rel = vox_path.relative_to(source_root)
        out_path = output_root / rel.with_suffix(".mesh")
        write_mesh(out_path, mesh)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Voxel character mesh pipeline")
    parser.add_argument(
        "command",
        choices=["generate-all", "convert-tree"],
        default="generate-all",
        nargs="?",
    )
    parser.add_argument("--source", type=Path, default=ART_SOURCE)
    parser.add_argument("--output", type=Path, default=CLIENT_ASSETS)
    parser.add_argument("--no-vox", action="store_true", help="Skip writing .vox source files")
    args = parser.parse_args(argv)

    if args.command == "generate-all":
        generate_all(write_vox_files=not args.no_vox)
        print(f"Generated archetypes under {CLIENT_ASSETS}")
        return 0

    convert_vox_tree(args.source, args.output)
    print(f"Converted vox tree {args.source} -> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
