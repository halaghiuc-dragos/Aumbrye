"""Build every character part as a .glb with Blender.

    Blender/blender -b -P tools/blender/build_characters.py -- [--only player_warden]

Part dimensions and joints come from `archetypes.py`; manifests in content/characters are rewritten
to point at the generated .glb files.
"""

from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import bl_lib  # noqa: E402
import appearance  # noqa: E402
import characters  # noqa: E402
from archetypes import ARCHETYPES  # noqa: E402

ASSETS = os.path.join(ROOT, "apps", "game", "client", "assets", "characters")
MANIFESTS = os.path.join(ROOT, "content", "characters")
RES = "res://assets/characters"


def _only():
    if "--only" in sys.argv:
        return sys.argv[sys.argv.index("--only") + 1]
    return ""


def build_part(spec, part):
    name = part.name
    if spec.profile == "quadruped":
        if name == "Torso":
            return characters.quadruped_torso(part.size)
        if name == "Head":
            return characters.hound_head(part.size)
        if name == "Tail":
            return characters.hound_tail(part.size)
        return characters.hound_leg(part.size)
    if name == "Torso":
        return characters.quadruped_torso(part.size) if spec.profile == "quadruped" else characters.torso(
            part.size, "player" if spec.id.startswith("player") else "enemy", part.accent_band
        )
    if name == "Head":
        return characters.head(part.size, "player" if spec.id.startswith("player") else "enemy", part.accent_band)
    if name in ("ArmL", "ArmR"):
        return characters.arm(part.size)
    if name in ("LegL", "LegR", "LegBL", "LegBR"):
        return characters.leg(part.size)
    return None


def build_extra(spec, extra, head_size):
    if extra.name == "Visor":
        return characters.visor(extra.size)
    if extra.name == "Hood":
        return characters.hood(head_size)
    if extra.name == "BeltTrim":
        return characters.belttrim(extra.size)
    if extra.name == "Bow":
        return characters.bow(extra.size)
    if extra.name == "Shield":
        return characters.shield(extra.size)
    if extra.name == "TargetStripe":
        return characters.target_stripe(extra.size)
    if extra.name in ("Pauldron", "PauldronR"):
        return characters.pauldron(extra.size)
    return None


def main():
    only = _only()
    for spec in ARCHETYPES:
        if only and spec.id != only:
            continue
        out_dir = os.path.join(ASSETS, spec.id)
        head_size = next((p.size for p in spec.parts if p.name == "Head"), (8, 8, 8))
        for part in spec.parts:
            bl_lib.reset_scene()
            model = build_part(spec, part)
            if model is None:
                continue
            obj = model.finish()
            bl_lib.export_glb(obj, os.path.join(out_dir, f"{part.name.lower()}.glb"))
        for extra in spec.extras:
            bl_lib.reset_scene()
            model = build_extra(spec, extra, head_size)
            if model is None:
                continue
            obj = model.finish()
            bl_lib.export_glb(obj, os.path.join(out_dir, f"{extra.name.lower()}.glb"))
        if spec.id.startswith("player_warden"):
            torso_size = next(p.size for p in spec.parts if p.name == "Torso")
            for class_id in appearance.GARMENT_PALETTES:
                bl_lib.reset_scene()
                bl_lib.export_glb(
                    appearance.garment(class_id, torso_size).finish(),
                    os.path.join(out_dir, f"garment_{class_id}.glb"),
                )
        if spec.id == "player_warden":
            for style in appearance.HAIR_RECIPES:
                bl_lib.reset_scene()
                bl_lib.export_glb(
                    appearance.hair(style, head_size).finish(), os.path.join(out_dir, f"hair_{style}.glb")
                )
            for style in appearance.FACE_MASKS:
                bl_lib.reset_scene()
                bl_lib.export_glb(appearance.face(style).finish(), os.path.join(out_dir, f"face_{style}.glb"))
        print("built", spec.id)


if __name__ == "__main__":
    main()
