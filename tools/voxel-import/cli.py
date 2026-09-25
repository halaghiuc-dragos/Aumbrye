"""Convert art-source .vox files to Godot ArrayMesh assets and rig manifests."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

from archetypes import (
    PART_FILE_NAMES,
    ArchetypeSpec,
    all_archetypes,
    equipment_archetypes,
    theme_colours,
)
from godot_mesh_writer import mesh_resource_path, write_mesh
from mesh_builder import EDGE, mesh_model, validate_mesh_on_grid
from palette import snap_colour
from vox_io import build_box_model, write_vox
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from generated_manifest import write_generated_bytes_set  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ART_SOURCE = REPO_ROOT / "art-source" / "characters"
CLIENT_ASSETS = REPO_ROOT / "apps" / "game" / "client" / "assets" / "characters"
CONTENT_CHARS = REPO_ROOT / "content" / "characters"


def _part_file_name(part_name: str) -> str:
    # C-37: this used to bypass PART_FILE_NAMES entirely, which is how the two conventions drifted.
    return PART_FILE_NAMES.get(part_name, part_name.lower())


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
    raise SystemExit(
        "legacy per-archetype voxel publishing is retired; use tools/generate_character_voxels.py"
    )


def generate_equipment(spec: ArchetypeSpec, write_vox_files: bool = True) -> None:
    raise SystemExit(
        "legacy equipment voxel publishing is retired; use tools/generate_character_voxels.py"
    )


def generate_all(write_vox_files: bool = True) -> None:
    raise SystemExit(
        "generate-all is retired: tools/generate_character_voxels.py owns character meshes and manifests"
    )


def convert_vox_tree(
    source_root: Path, output_root: Path, *, force: bool = False, dry_run: bool = False
) -> None:
    outputs: list[tuple[Path, bytes]] = []
    sources: list[Path] = []
    from vox_io import read_vox

    with tempfile.TemporaryDirectory(prefix="aumbrye-voxel-cli-stage-") as temp_dir:
        stage_root = Path(temp_dir)
        for vox_path in sorted(source_root.rglob("*.vox")):
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
            staged_path = stage_root / rel.with_suffix(".tres")
            write_mesh(staged_path, mesh)
            outputs.append((output_root / rel.with_suffix(".tres"), staged_path.read_bytes()))
            sources.append(vox_path)
    if not outputs:
        raise ValueError(f"No .vox inputs found under {source_root}")
    write_generated_bytes_set(
        outputs,
        generator=Path(__file__).resolve(),
        sources=sources,
        force=force,
        dry_run=dry_run,
    )


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
    parser.add_argument("--dry-run", action="store_true", help="validate conversions without publishing")
    parser.add_argument("--force", action="store_true", help="adopt or replace unowned output explicitly")
    args = parser.parse_args(argv)

    if args.command == "generate-all":
        generate_all(write_vox_files=not args.no_vox)
        print(f"Generated archetypes under {CLIENT_ASSETS}")
        return 0

    convert_vox_tree(args.source, args.output, force=args.force, dry_run=args.dry_run)
    print(f"Converted vox tree {args.source} -> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
