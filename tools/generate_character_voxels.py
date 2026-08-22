#!/usr/bin/env python3
"""Generate .voxels.json character assets and rig manifests for the Godot client."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "voxel-import"))
sys.path.insert(0, str(ROOT / "tools"))

from voxel_sculpt import (  # noqa: E402
    MATERIALS,
    sculpt_face,
    sculpt_for_part,
    sculpt_hair,
)
from voxel_sculpt import (  # noqa: E402
    FACE_MASKS,
    GARMENT_PALETTES,
    HAIR_RECIPES,
    HOOD_DROP,
    SKIRT_DROP,
    sculpt_garment,
    sculpt_hood,
)

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

# Tall and compact used to reuse the standard meshes and shift every joint by +/-2 voxels, on the
# reasoning that stature is only a matter of where the parts sit. It is not: the head's joint is
# the top of the torso, so moving the joint without lengthening the torso mesh opened a two-voxel
# gap at the tall warden's neck and sank the compact warden's head two voxels into its chest.
# `player_archetype` returns correct per-frame dimensions and `_biped_parts` derives every joint
# from those sizes, so generating the variants like all the others is both correct and less code.
HEIGHT_VARIANT_MANIFESTS: dict[str, dict] = {}

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
        # `color` stays as the single-colour fallback for any reader that predates materials.
        "color": [round(c, 4) for c in color],
        # Palette *slots*, not RGB: the runtime resolves these per theme, so a warden's steel stays
        # distinct from its plate in all eleven themes. Snapping literal colours cannot promise
        # that — two authored values can land on the same nearest slot and collapse the shading.
        "paletteSlots": list(MATERIALS),
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


#: Hair styles with geometry. `none` has no mesh by definition and `CharacterAppearance` never
#: asks for one. Only `short` and `long` existed before, and both shipped with an empty `cells`
#: array — so four of the seven options a player can pick did nothing at all, and the two that
#: did anything drew a solid slab.
#: Driven off the sculptor's own table, so a style added there is emitted here without a second
#: list to keep in step. The two lists disagreeing is exactly how a style ends up selectable in the
#: creation screen with no mesh behind it.
HAIR_STYLES: tuple[str, ...] = tuple(HAIR_RECIPES)


def _write_hair(out_dir: Path, head_size: tuple[int, int, int]) -> None:
    """Hair volumes, sized to the head so they need no offset at the call site."""
    for style in HAIR_STYLES:
        sculpt = sculpt_hair(style, *head_size)
        cells = sculpt.normalised_cells(shift_y=False)
        if not cells:
            continue
        span = [max(c[i] for c in cells) + 1 for i in range(3)]
        # White, not a palette slot. The runtime multiplies the whole hair mesh by the player's
        # chosen colour, so anything other than white would tint that choice toward a biome slot —
        # which is precisely the behaviour that left every warden with the same dark hair.
        payload = {
            "edge": VOXEL_EDGE,
            "size": span,
            "color": [1.0, 1.0, 1.0],
            "palette": [[1.0, 1.0, 1.0]],
            "cells": cells,
        }
        (out_dir / f"hair_{style}.voxels.json").write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )


#: Literal colours for a face plate, not palette slots. Index 0 is white so that the runtime's
#: per-instance skin tint *becomes* the skin colour; index 1 is near-black so features survive being
#: multiplied by any tone. Loaded with `theme = -1` so nothing snaps them to the biome palette.
FACE_PALETTE = [[1.0, 1.0, 1.0], [0.18, 0.15, 0.16]]


def _write_faces(out_dir: Path) -> None:
    for style in FACE_MASKS:
        sculpt = sculpt_face(style)
        cells = sculpt.normalised_cells()
        if not cells:
            continue
        span = [max(c[i] for c in cells) + 1 for i in range(3)]
        payload = {
            "edge": VOXEL_EDGE,
            "size": span,
            "color": FACE_PALETTE[0],
            "palette": FACE_PALETTE,
            "cells": cells,
        }
        (out_dir / f"face_{style}.voxels.json").write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )


def _write_garments(out_dir: Path, torso_size: tuple[int, int, int]) -> None:
    """Default clothing, one volume per class, with its own literal palette.

    `skirtDrop` travels with the asset so the runtime knows how far below the torso's base the
    volume begins — a robe and a set of faulds hang below the body they belong to, and the alignment
    cannot be recovered from the mesh alone.
    """
    torso_vox = sculpt_for_part("Torso", torso_size)
    for class_id, palette in GARMENT_PALETTES.items():
        sculpt = sculpt_garment(class_id, torso_vox)
        cells = sculpt.normalised_cells(shift_y=False)
        if not cells:
            continue
        span = [max(c[i] for c in cells) + 1 for i in range(3)]
        payload = {
            "edge": VOXEL_EDGE,
            "size": span,
            "color": palette[0],
            "palette": palette,
            "skirtDrop": SKIRT_DROP,
            "cells": cells,
        }
        (out_dir / f"garment_{class_id}.voxels.json").write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )


def _write_hood(out_dir: Path, head_size: tuple[int, int, int], color: tuple[float, float, float]) -> None:
    """A cowl grown from the head, replacing the box the archetype table used to declare.

    Normalised, so the volume starts at y = 0; the manifest gives the Hood extra an offset of
    `-HOOD_DROP` to put its hem below the jaw.
    """
    head_vox = sculpt_for_part("Head", head_size)
    sculpt = sculpt_hood(head_vox, HOOD_DROP)
    cells = sculpt.normalised_cells()
    if not cells:
        return
    span = [max(c[i] for c in cells) + 1 for i in range(3)]
    payload = {
        "edge": VOXEL_EDGE,
        "size": span,
        "color": [round(c, 4) for c in color],
        "paletteSlots": list(MATERIALS),
        "cells": cells,
    }
    (out_dir / "hood.voxels.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )


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
        head = next((p.size for p in spec.parts if p.name == "Head"), None)
        if spec.id == "player_warden":
            # Hair and faces are authored once and shared by every frame — the runtime loads them
            # from `player_warden/` whatever archetype it is building, and scales them to the head
            # it finds.
            if head is not None:
                _write_hair(out_dir, head)
            _write_faces(out_dir)
        # Garments are *not* shared, for the same reason the hood is not. `sculpt_garment` grows the
        # clothing out of the torso volume it is given — every panel, hem, sash and yoke is placed
        # from that torso's own width, depth and height — and the runtime never scaled the result.
        # Authored once from the standard 12-wide torso, the surcoat was too narrow to close around
        # Stout's 14-wide chest and hung off the sides of Slight's 10-wide one. One per frame.
        torso = next((p.size for p in spec.parts if p.name == "Torso"), None)
        if spec.id.startswith("player_warden") and torso is not None:
            _write_garments(out_dir, torso)
        # The hood is *not* shared: it is grown from the head to close under the jaw, so it has to
        # be grown from each stature's own head. Writing it only for the base archetype left the
        # other twenty-four with whatever the ExtraSpec literal produced — a flat 8x4x7 slab parked
        # behind the skull on some, and nothing at all on the ones whose literal was (0, 0, 0).
        # The Hooded option was broken on 24 of 25 statures.
        if spec.id.startswith("player_warden") and head is not None:
            _write_hood(out_dir, head, _part_color(spec, spec.parts[0]))
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
