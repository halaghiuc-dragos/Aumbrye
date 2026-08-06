"""Tests for voxel import pipeline."""

from __future__ import annotations

import tempfile
from pathlib import Path

from archetypes import ARCHETYPE_BY_ID, PART_FILE_NAMES, _palette_colours
from convert import generate_sources
from mesh_builder import mesh_model, validate_mesh_on_grid
from palette import flatten_palette, snap_colour
from vox_io import build_box_model, read_vox, write_vox


def test_palette_snap_accepts_theme_colours() -> None:
    for colour in flatten_palette():
        assert snap_colour(colour) == colour


def test_box_mesh_on_grid() -> None:
    model = build_box_model((4, 6, 4), (0.22, 0.20, 0.28))
    mesh = mesh_model(model)
    validate_mesh_on_grid(mesh)
    assert mesh.triangle_count() <= 400


def test_vox_roundtrip() -> None:
    model = build_box_model((3, 5, 3), (0.35, 0.32, 0.38), (0.55, 0.42, 0.28))
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "part.vox"
        write_vox(path, model)
        loaded = read_vox(path)
        assert len(loaded.voxels) == len(model.voxels)


def test_archetype_sources_convert() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        art = root / "art-source" / "characters"
        art.mkdir(parents=True)
        spec = ARCHETYPE_BY_ID["player_warden"]
        body, accent = _palette_colours(spec.theme_index)
        out = art / spec.id
        out.mkdir(parents=True, exist_ok=True)
        for part in spec.parts:
            if part.size == (0, 0, 0):
                continue
            model = build_box_model(part.size, body, accent if part.accent_band else None)
            write_vox(out / f"{PART_FILE_NAMES[part.name]}.vox", model)
        model = read_vox(out / "torso.vox")
        mesh = mesh_model(model)
        payload = {
            "vertices": [list(v) for v in mesh.vertices],
            "normals": [list(n) for n in mesh.normals],
            "colors": [list(c) for c in mesh.colors],
            "indices": mesh.indices,
        }
        assert len(payload["vertices"]) > 0
        assert len(payload["indices"]) % 3 == 0


def test_generate_sources_writes_vox() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        import convert as convert_mod

        convert_mod.ART_SOURCE = root / "art-source" / "characters"
        convert_mod.MESH_JSON_DIR = root / "mesh-json"
        convert_mod.CONTENT_DIR = root / "content"
        generate_sources(force=True)
        spec = ARCHETYPE_BY_ID["enemy_biome_castle"]
        torso = convert_mod.ART_SOURCE / spec.id / "torso.vox"
        assert torso.exists()
