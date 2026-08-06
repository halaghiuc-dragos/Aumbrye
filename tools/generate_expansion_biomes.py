#!/usr/bin/env python3
"""Generate 5 expansion biomes: rooms, materials, content JSON."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from generated_manifest import prepare_write, record_write

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "apps" / "game" / "client"
CONTENT = ROOT / "content"

BIOMES = [
    {
        "id": "iron_vault",
        "name": "Iron Vault",
        "folder": "vault",
        "prefix": "vault",
        "floor": (0.35, 0.32, 0.30, 1.0),
        "wall": (0.22, 0.20, 0.18, 1.0),
        "accent": (0.55, 0.35, 0.22, 1.0),
        "lighting": {
            "ambient_color": (0.4, 0.35, 0.32),
            "ambient_energy": 0.45,
            "fog_enabled": True,
            "fog_color": (0.12, 0.1, 0.08),
            "fog_density": 0.018,
        },
        "enemy_pool": [
            ("castle_grunt", 3),
            ("castle_archer", 2),
            ("castle_shield", 2),
            ("castle_hound", 2),
        ],
        "boss": "boss_castle_knight",
        "miniboss": "miniboss_castle_captain",
        "trap": "spike_trap",
        "treasure": ("health_potion", 2, "iron_scrap", 3),
        "secret": ("knight_relic", 1, "health_potion", 3),
        "side": ("iron_scrap", 2),
        "armory": ("castle_sword", 1),
    },
    {
        "id": "prism_depths",
        "name": "Prism Depths",
        "folder": "prism",
        "prefix": "prism",
        "floor": (0.55, 0.72, 0.92, 1.0),
        "wall": (0.38, 0.52, 0.78, 1.0),
        "accent": (0.75, 0.85, 1.0, 1.0),
        "lighting": {
            "ambient_color": (0.42, 0.58, 0.82),
            "ambient_energy": 0.58,
            "fog_enabled": True,
            "fog_color": (0.15, 0.25, 0.42),
            "fog_density": 0.022,
        },
        "enemy_pool": [
            ("crystal_slime", 3),
            ("crystal_bat", 2),
            ("crystal_spitter", 2),
            ("crystal_wisp", 2),
        ],
        "boss": "boss_crystal_sovereign",
        "miniboss": "miniboss_crystal_guardian",
        "trap": "spike_trap",
        "treasure": ("health_potion", 2, "crystal_frost_ring", 1),
        "secret": ("crystal_prism_amulet", 1, "health_potion", 3),
        "side": ("crystal_shard_blade", 1),
        "armory": ("crystal_shard_blade", 1),
    },
    {
        "id": "venom_mire",
        "name": "Venom Mire",
        "folder": "mire",
        "prefix": "mire",
        "floor": (0.28, 0.42, 0.22, 1.0),
        "wall": (0.16, 0.32, 0.14, 1.0),
        "accent": (0.45, 0.65, 0.25, 1.0),
        "lighting": {
            "ambient_color": (0.28, 0.42, 0.22),
            "ambient_energy": 0.42,
            "fog_enabled": True,
            "fog_color": (0.08, 0.18, 0.06),
            "fog_density": 0.038,
        },
        "enemy_pool": [
            ("swamp_bogling", 3),
            ("swamp_leech", 2),
            ("swamp_spitter", 2),
            ("swamp_brute", 2),
        ],
        "boss": "boss_swamp_devourer",
        "miniboss": "swamp_hydra",
        "trap": "poison_pool",
        "treasure": ("health_potion", 2, "swamp_mire_charm", 1),
        "secret": ("swamp_toxin_dagger", 1, "health_potion", 3),
        "side": ("swamp_bog_boots", 1),
        "armory": ("swamp_toxin_dagger", 1),
    },
    {
        "id": "glacial_hollow",
        "name": "Glacial Hollow",
        "folder": "hollow",
        "prefix": "hollow",
        "floor": (0.72, 0.8, 0.88, 1.0),
        "wall": (0.58, 0.68, 0.78, 1.0),
        "accent": (0.85, 0.92, 1.0, 1.0),
        "lighting": {
            "ambient_color": (0.58, 0.68, 0.82),
            "ambient_energy": 0.62,
            "fog_enabled": True,
            "fog_color": (0.75, 0.85, 0.95),
            "fog_density": 0.028,
        },
        "enemy_pool": [
            ("frost_raider", 3),
            ("frost_archer", 2),
            ("frost_knight", 2),
            ("frost_hound", 2),
        ],
        "boss": "boss_frost_warlord",
        "miniboss": "miniboss_castle_captain",
        "trap": "frost_trap",
        "treasure": ("health_potion", 2, "frost_ice_ring", 1),
        "secret": ("frost_warlord_blade", 1, "health_potion", 3),
        "side": ("frost_raider_boots", 1),
        "armory": ("frost_glacier_sword", 1),
    },
    {
        "id": "umbral_chapel",
        "name": "Umbral Chapel",
        "folder": "umbral",
        "prefix": "umbral",
        "floor": (0.14, 0.1, 0.2, 1.0),
        "wall": (0.09, 0.07, 0.14, 1.0),
        "accent": (0.35, 0.2, 0.45, 1.0),
        "lighting": {
            "ambient_color": (0.18, 0.12, 0.26),
            "ambient_energy": 0.34,
            "fog_enabled": True,
            "fog_color": (0.06, 0.04, 0.1),
            "fog_density": 0.024,
        },
        "enemy_pool": [
            ("cathedral_acolyte", 3),
            ("cathedral_shade", 2),
            ("cathedral_warden", 2),
            ("castle_hound", 1),
        ],
        "boss": "boss_cathedral_hollow",
        "miniboss": "miniboss_cathedral_bell",
        "trap": "shadow_trap",
        "treasure": ("health_potion", 2, "cathedral_holy_charm", 1),
        "secret": ("cathedral_shadow_dagger", 1, "health_potion", 3),
        "side": ("cathedral_warden_helm", 1),
        "armory": ("cathedral_arcane_staff", 1),
    },
]

ROOM_SPECS = [
    ("entrance", "hub", True, False),
    ("stairs", "combat", False, False),
    ("courtyard", "combat", False, False),
    ("hall", "combat", False, False),
    ("treasure", "treasure", False, False),
    ("secret", "secret", False, False),
    ("arena", "arena", False, False),
    ("boss", "boss", False, True),
    ("puzzle", "puzzle", False, False),
]


def color_str(c) -> str:
    return f"Color({c[0]}, {c[1]}, {c[2]}, {c[3]})"


def write_material(path: Path, color) -> None:
    # Pixel-diorama materials are generated by tools/generate_pixel_diorama_materials.py
    pass


def write_room(
    folder: Path,
    prefix: str,
    asset_folder: str,
    suffix: str,
    room_type: str,
    door_s: bool,
    door_n: bool,
    *,
    force: bool,
    dry_run: bool,
) -> None:
    template_id = f"{prefix}_{suffix}"
    node_name = "".join(p.capitalize() for p in template_id.split("_"))
    tscn = f"""[gd_scene load_steps=6 format=3 uid="uid://{template_id}"]

[ext_resource type="Script" path="res://scripts/dungeon/castle/castle_room_scene.gd" id="1_room"]
[ext_resource type="Script" path="res://scripts/dungeon/castle/castle_blockout.gd" id="2_blockout"]
[ext_resource type="Script" path="res://scripts/dungeon/doorway_socket.gd" id="3_socket"]
[ext_resource type="Material" path="res://assets/{asset_folder}/mat_floor.tres" id="4_floor"]
[ext_resource type="Material" path="res://assets/{asset_folder}/mat_wall.tres" id="5_wall"]

[node name="{node_name}" type="Node3D"]
script = ExtResource("1_room")
template_id = "{template_id}"
room_type = "{room_type}"

[node name="CastleBlockout" type="Node3D" parent="."]
script = ExtResource("2_blockout")
room_width = 16.0
room_depth = 12.0
door_south = {"true" if door_s else "false"}
door_north = {"true" if door_n else "false"}
floor_material = ExtResource("4_floor")
wall_material = ExtResource("5_wall")

[node name="DoorwaySockets" type="Node3D" parent="."]

[node name="Socket_S" type="Marker3D" parent="DoorwaySockets"]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 6.0)
script = ExtResource("3_socket")
direction = 2

[node name="Socket_N" type="Marker3D" parent="DoorwaySockets"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -6.0)
script = ExtResource("3_socket")
direction = 0

[node name="SpawnPoints" type="Node3D" parent="."]

[node name="PlayerSpawn" type="Marker3D" parent="SpawnPoints"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -3)

[node name="RunEntrance" type="Marker3D" parent="SpawnPoints"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -4)
"""
    path = folder / f"{template_id}.tscn"
    if not prepare_write(path, tscn, force=force, dry_run=dry_run):
        return
    folder.mkdir(parents=True, exist_ok=True)
    path.write_text(tscn, encoding="utf-8")
    record_write(path, tscn)


def write_biome_json(biome: dict, *, force: bool, dry_run: bool) -> None:
    templates = [f"{biome['prefix']}_{s[0]}" for s in ROOM_SPECS]
    enemy_pool = [{"enemyId": eid, "weight": w} for eid, w in biome["enemy_pool"]]
    enemy_pool.append({"enemyId": biome["miniboss"], "weight": 1})
    data = {
        "id": biome["id"],
        "name": biome["name"],
        "roomCount": {"min": 6, "max": 10},
        "gridStep": 14,
        "roomTemplateIds": templates,
        "enemyPool": enemy_pool,
        "bossPool": [{"enemyId": biome["boss"]}],
        "budgets": {
            "baseEnemyThreat": 100,
            "baseLootValue": 60,
            "threatPerTier": 20,
            "lootPerTier": 10,
        },
        "requiresSecret": True,
    }
    path = CONTENT / "biomes" / f"{biome['id']}.json"
    text = json.dumps(data, indent=2) + "\n"
    if not prepare_write(path, text, force=force, dry_run=dry_run):
        return
    path.write_text(text, encoding="utf-8")
    record_write(path, text)


def write_audio_profile(biome: dict, *, force: bool, dry_run: bool) -> None:
    data = {
        "id": biome["id"],
        "biomeId": biome["id"],
        "ambienceFreq": 95,
        "exploreFreq": 100,
        "combatFreq": 120,
        "bossFreq": 180,
        "ambiencePath": "res://assets/audio/castle/ambience_loop.wav",
        "bossPath": "res://assets/audio/castle/boss_theme.wav",
        "crossfadeSeconds": 0.8,
    }
    path = CONTENT / "audio_profiles" / f"{biome['id']}.json"
    text = json.dumps(data, indent=2) + "\n"
    if not prepare_write(path, text, force=force, dry_run=dry_run):
        return
    path.write_text(text, encoding="utf-8")
    record_write(path, text)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Print files that would be written")
    parser.add_argument("--force", action="store_true", help="Overwrite manually edited generated files")
    parser.add_argument(
        "--only",
        action="append",
        dest="only",
        metavar="biomeId",
        help="Limit to biome id (repeatable)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    only = set(args.only or [])
    selected = [b for b in BIOMES if not only or b["id"] in only]
    if only and not selected:
        raise SystemExit(f"No biomes matched --only {sorted(only)}")

    for biome in selected:
        room_dir = CLIENT / "scenes" / "rooms" / biome["folder"]
        for suffix, room_type, door_s, door_n in ROOM_SPECS:
            write_room(
                room_dir,
                biome["prefix"],
                biome["folder"],
                suffix,
                room_type,
                door_s,
                door_n,
                force=args.force,
                dry_run=args.dry_run,
            )
        write_biome_json(biome, force=args.force, dry_run=args.dry_run)
        write_audio_profile(biome, force=args.force, dry_run=args.dry_run)
        if not args.dry_run:
            print(f"Generated {biome['id']}")

    materials_script = ROOT / "tools" / "generate_pixel_diorama_materials.py"
    mat_args = [sys.executable, str(materials_script)]
    if args.dry_run:
        mat_args.append("--dry-run")
    if args.force:
        mat_args.append("--force")
    for folder in {b["folder"] for b in selected}:
        mat_args.extend(["--only", folder])
    subprocess.run(mat_args, check=True)


if __name__ == "__main__":
    main()
