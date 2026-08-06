#!/usr/bin/env python3
"""Regenerate biome mat_floor/wall/accent as pixel-diorama ShaderMaterials."""

from __future__ import annotations

import argparse
from pathlib import Path

from generated_manifest import prepare_write, record_write

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "apps" / "game" / "client"
SHADER = "res://assets/shared/pixel_diorama_surface.gdshader"

ACCENT_SURFACE_KIND = 3

ACCENT_HIGHLIGHTS = {
    "castle": (1.00, 0.62, 0.28),
    "crystal": (0.55, 0.85, 1.00),
    "swamp": (0.70, 0.90, 0.35),
    "frozen": (0.75, 0.90, 1.00),
    "cathedral": (0.95, 0.72, 0.35),
    "vault": (1.00, 0.55, 0.20),
    "prism": (0.65, 0.45, 1.00),
    "mire": (0.75, 0.95, 0.35),
    "hollow": (0.70, 0.88, 1.00),
    "umbral": (0.85, 0.55, 0.95),
}

BIOMES = [
    {
        "folder": "castle",
        "floor": (0.35, 0.32, 0.38),
        "floor_shadow": (0.24, 0.22, 0.28),
        "wall": (0.22, 0.20, 0.28),
        "wall_shadow": (0.14, 0.12, 0.18),
        "accent": (0.55, 0.42, 0.28),
    },
    {
        "folder": "crystal",
        "floor": (0.42, 0.55, 0.78),
        "floor_shadow": (0.28, 0.38, 0.58),
        "wall": (0.32, 0.48, 0.72),
        "wall_shadow": (0.18, 0.28, 0.45),
        "accent": (0.65, 0.82, 0.95),
    },
    {
        "folder": "swamp",
        "floor": (0.28, 0.34, 0.20),
        "floor_shadow": (0.18, 0.24, 0.12),
        "wall": (0.20, 0.28, 0.16),
        "wall_shadow": (0.12, 0.16, 0.10),
        "accent": (0.45, 0.55, 0.22),
    },
    {
        "folder": "frozen",
        "floor": (0.72, 0.80, 0.88),
        "floor_shadow": (0.55, 0.65, 0.78),
        "wall": (0.62, 0.72, 0.82),
        "wall_shadow": (0.42, 0.52, 0.65),
        "accent": (0.85, 0.92, 0.98),
    },
    {
        "folder": "cathedral",
        "floor": (0.20, 0.16, 0.28),
        "floor_shadow": (0.12, 0.10, 0.18),
        "wall": (0.16, 0.12, 0.22),
        "wall_shadow": (0.08, 0.06, 0.12),
        "accent": (0.62, 0.48, 0.28),
    },
    {
        "folder": "vault",
        "floor": (0.35, 0.32, 0.30),
        "floor_shadow": (0.22, 0.20, 0.18),
        "wall": (0.28, 0.26, 0.24),
        "wall_shadow": (0.16, 0.14, 0.12),
        "accent": (0.58, 0.50, 0.32),
    },
    {
        "folder": "prism",
        "floor": (0.55, 0.72, 0.92),
        "floor_shadow": (0.38, 0.52, 0.72),
        "wall": (0.42, 0.58, 0.82),
        "wall_shadow": (0.26, 0.38, 0.58),
        "accent": (0.78, 0.55, 0.95),
    },
    {
        "folder": "mire",
        "floor": (0.28, 0.42, 0.22),
        "floor_shadow": (0.18, 0.28, 0.14),
        "wall": (0.22, 0.34, 0.18),
        "wall_shadow": (0.12, 0.20, 0.10),
        "accent": (0.55, 0.72, 0.28),
    },
    {
        "folder": "hollow",
        "floor": (0.72, 0.80, 0.88),
        "floor_shadow": (0.55, 0.64, 0.74),
        "wall": (0.60, 0.70, 0.80),
        "wall_shadow": (0.40, 0.48, 0.58),
        "accent": (0.82, 0.90, 0.98),
    },
    {
        "folder": "umbral",
        "floor": (0.14, 0.10, 0.20),
        "floor_shadow": (0.08, 0.06, 0.12),
        "wall": (0.12, 0.08, 0.18),
        "wall_shadow": (0.06, 0.04, 0.10),
        "accent": (0.55, 0.38, 0.62),
    },
]


def color_str(rgb: tuple[float, float, float]) -> str:
    return f"Color({rgb[0]}, {rgb[1]}, {rgb[2]}, 1.0)"


def render_surface_material(
    surface_kind: int,
    color_base,
    color_shadow,
    color_accent,
) -> str:
    return f"""[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="{SHADER}" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
shader_parameter/color_base = {color_str(color_base)}
shader_parameter/color_shadow = {color_str(color_shadow)}
shader_parameter/color_accent = {color_str(color_accent)}
shader_parameter/pixel_scale = 8.0
shader_parameter/pattern_strength = 0.58
shader_parameter/stitch_strength = 0.28
shader_parameter/color_levels = 6.0
shader_parameter/edge_strength = 0.45
shader_parameter/shade_bands = 4.0
shader_parameter/shade_dither = 0.55
shader_parameter/light_wrap = 0.25
shader_parameter/rim_strength = 0.08
shader_parameter/surface_kind = {surface_kind}
texture_filter = 0
"""


def write_surface_material(
    path: Path,
    surface_kind: int,
    color_base,
    color_shadow,
    color_accent,
    *,
    force: bool,
    dry_run: bool,
) -> None:
    content = render_surface_material(surface_kind, color_base, color_shadow, color_accent)
    if not prepare_write(path, content, force=force, dry_run=dry_run):
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    record_write(path, content)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Print files that would be written")
    parser.add_argument("--force", action="store_true", help="Overwrite manually edited generated files")
    parser.add_argument(
        "--only",
        action="append",
        dest="only",
        metavar="folder",
        help="Limit to biome asset folder (repeatable)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    only = set(args.only or [])
    selected = [b for b in BIOMES if not only or b["folder"] in only]
    if only and not selected:
        raise SystemExit(f"No biome folders matched --only {sorted(only)}")

    for biome in selected:
        folder = CLIENT / "assets" / biome["folder"]
        write_surface_material(
            folder / "mat_floor.tres",
            0,
            biome["floor"],
            biome["floor_shadow"],
            biome["accent"],
            force=args.force,
            dry_run=args.dry_run,
        )
        write_surface_material(
            folder / "mat_wall.tres",
            1,
            biome["wall"],
            biome["wall_shadow"],
            biome["accent"],
            force=args.force,
            dry_run=args.dry_run,
        )
        write_surface_material(
            folder / "mat_accent.tres",
            ACCENT_SURFACE_KIND,
            biome["accent"],
            biome["wall_shadow"],
            ACCENT_HIGHLIGHTS.get(biome["folder"], biome["accent"]),
            force=args.force,
            dry_run=args.dry_run,
        )
        if not args.dry_run:
            print(f"Wrote pixel-diorama materials for {biome['folder']}")


if __name__ == "__main__":
    main()
