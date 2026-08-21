"""Character archetype part dimensions and joint layout (voxel integers)."""

from __future__ import annotations

from dataclasses import dataclass

from palette import PALETTES, RGB


@dataclass(frozen=True)
class PartSpec:
    name: str
    size: tuple[int, int, int]
    joint: tuple[int, int, int] = (0, 0, 0)
    parent: str = "Root"
    mount: str = ""
    mesh_offset: tuple[int, int, int] = (0, 0, 0)
    accent_band: bool = False
    skip_manifest: bool = False


@dataclass(frozen=True)
class ExtraSpec:
    name: str
    size: tuple[int, int, int]
    offset: tuple[int, int, int]
    parent: str
    accent: bool = True


@dataclass(frozen=True)
class ArchetypeSpec:
    id: str
    profile: str
    theme_index: int
    parts: tuple[PartSpec, ...]
    extras: tuple[ExtraSpec, ...] = ()
    animation_library: str = ""


def _biped_parts(
    leg: tuple[int, int, int],
    torso: tuple[int, int, int],
    head: tuple[int, int, int],
    arm: tuple[int, int, int],
    hip_x: int,
    shoulder_x: int,
    shoulder_y: int,
    head_accent: bool = False,
) -> tuple[PartSpec, ...]:
    ly = leg[1]
    ty = torso[1]
    arm_len = arm[1]
    return (
        PartSpec("LegL", leg, (-hip_x, ly, 0)),
        PartSpec("LegR", leg, (hip_x, ly, 0)),
        PartSpec("Torso", torso, (0, ly, 0), accent_band=head_accent),
        # Two voxels below the top of the torso, not level with it: the torso notches its top
        # layer for a neck, and a head sitting exactly on the joint leaves that notch empty and the
        # neck reading as a separate column between two blocks. Done with the joint rather than a
        # `meshOffset` because hair and the Visor / Hood extras all hang off the Head *pivot* — a
        # mesh-only offset slides the skull out from under everything attached to it.
        PartSpec("Head", head, (0, ty - 2, 0), parent="Torso", accent_band=head_accent),
        PartSpec(
            "ArmL",
            arm,
            (-shoulder_x, shoulder_y, 0),
            parent="Torso",
            mount="ShieldMount",
            mesh_offset=(0, -arm_len, 0),
        ),
        PartSpec(
            "ArmR",
            arm,
            (shoulder_x, shoulder_y, 0),
            parent="Torso",
            mount="WeaponMount",
            mesh_offset=(0, -arm_len, 0),
        ),
    )


def _quadruped_parts(theme_index: int) -> tuple[PartSpec, ...]:
    return (
        PartSpec("Torso", (11, 9, 20), (0, 8, 0)),
        PartSpec("Head", (8, 7, 9), (0, 5, 9), parent="Torso", accent_band=True),
        PartSpec("Tail", (3, 3, 8), (0, 6, -10), parent="Torso"),
        PartSpec("LegL", (3, 8, 3), (-4, 8, 7)),
        PartSpec("LegR", (3, 8, 3), (4, 8, 7)),
        PartSpec("LegBL", (3, 8, 3), (-4, 8, -7)),
        PartSpec("LegBR", (3, 8, 3), (4, 8, -7)),
    )


BIOME_THEME_INDEX = {
    "castle": 0,
    "crystal": 1,
    "swamp": 2,
    "frost": 3,
    "cathedral": 4,
    "vault": 5,
    "prism": 6,
    "mire": 7,
    "hollow": 8,
    "umbral": 9,
}

PROFILE_ANIM_LIBRARY = {
    "player": "res://assets/animations/diorama/player_locomotion.res",
    "melee": "res://assets/animations/diorama/melee_locomotion.res",
    "ranged": "res://assets/animations/diorama/ranged_locomotion.res",
    "shield": "res://assets/animations/diorama/shield_locomotion.res",
    "brute": "res://assets/animations/diorama/brute_locomotion.res",
    "dummy": "res://assets/animations/diorama/melee_locomotion.res",
    "hound": "res://assets/animations/diorama/hound_locomotion.res",
}


def _player_height_scale(height_key: str) -> tuple[int, int]:
    if height_key == "compact":
        return (-1, -1)
    if height_key == "tall":
        return (1, 2)
    return (0, 0)


def _player_bulk_scale(bulk_key: str) -> tuple[int, int]:
    if bulk_key == "lean":
        return (-1, -1)
    if bulk_key == "heavy":
        return (1, 1)
    return (0, 0)


def _adjust_size(
    size: tuple[int, int, int],
    dx: int,
    dy: int,
    dz: int,
    min_size: int = 3,
) -> tuple[int, int, int]:
    return (
        max(min_size, size[0] + dx),
        max(min_size, size[1] + dy),
        max(min_size, size[2] + dz),
    )


def player_archetype(height_key: str, bulk_key: str) -> ArchetypeSpec:
    hdy, tdy = _player_height_scale(height_key)
    bdx, bdz = _player_bulk_scale(bulk_key)
    leg = _adjust_size((6, 12, 6), 0, hdy, 0)
    torso = _adjust_size((12, 16, 8), bdx, tdy, bdz)
    head = (8, 8, 8)
    arm = _adjust_size((5, 13, 5), bdx - 1, hdy, bdz - 1, 4)
    ty = torso[1]
    shoulder_y = max(1, int(round(ty * 0.88)))
    suffix = ""
    if height_key != "standard":
        suffix += f"_{height_key}"
    if bulk_key != "standard":
        suffix += f"_{bulk_key}"
    archetype_id = f"player_warden{suffix}"
    extras: tuple[ExtraSpec, ...] = (
        ExtraSpec("Visor", (4, 2, 3), (0, 5, 4), "Head"),
        # Size is ignored for the hood — `generate_character_voxels._write_hood` grows it from the
        # head — and the offset drops it so the cowl closes below the jaw. It used to be an
        # 8x4x7 box parked behind the head, which covered neither the crown nor the sides.
        ExtraSpec("Hood", (0, 0, 0), (0, -3, 0), "Head", accent=False),
        ExtraSpec("BeltTrim", (13, 3, 7), (0, 3, 0), "Torso", accent=True),
        # Seated on the shoulder, not hovering above and behind it: at (0, 1, -2) the pauldrons
        # cleared the top of the arm entirely and read as two separate blocks floating beside the
        # neck.
        ExtraSpec("Pauldron", (5, 3, 6), (0, -1, 0), "ArmL", accent=True),
        ExtraSpec("PauldronR", (5, 3, 6), (0, -1, 0), "ArmR", accent=True),
    )
    return ArchetypeSpec(
        id=archetype_id,
        profile="biped",
        theme_index=10,
        # hip_x = 4, not 3. At 3 the two six-voxel legs span -6..0 and 0..6 and meet exactly on
        # the centre line, so the greedy mesher sees one continuous volume and the warden stands
        # on a single slab instead of on two feet. Four leaves a two-voxel gap that survives the
        # downsample to the pixel viewport.
        parts=_biped_parts(leg, torso, head, arm, 4, 8, shoulder_y),
        extras=extras,
        animation_library=PROFILE_ANIM_LIBRARY["player"],
    )


def profile_archetype(
    archetype_id: str,
    profile_key: str,
    leg: tuple[int, int, int],
    torso: tuple[int, int, int],
    head: tuple[int, int, int],
    arm: tuple[int, int, int],
    hip_x: int,
    shoulder_x: int,
    head_accent: bool = False,
    theme_index: int = 0,
    extras: tuple[ExtraSpec, ...] = (),
) -> ArchetypeSpec:
    ty = torso[1]
    shoulder_y = max(1, int(round(ty * 0.88)))
    profile = "hound" if profile_key == "hound" else "biped"
    if profile_key == "hound":
        parts = _quadruped_parts(theme_index)
        profile = "quadruped"
    else:
        parts = _biped_parts(
            leg, torso, head, arm, hip_x, shoulder_x, shoulder_y, head_accent=head_accent
        )
    return ArchetypeSpec(
        id=archetype_id,
        profile=profile,
        theme_index=theme_index,
        parts=parts,
        extras=extras,
        animation_library=PROFILE_ANIM_LIBRARY.get(profile_key, PROFILE_ANIM_LIBRARY["melee"]),
    )


def all_archetypes() -> list[ArchetypeSpec]:
    specs: list[ArchetypeSpec] = []
    for height in ("compact", "standard", "tall"):
        for bulk in ("lean", "standard", "heavy"):
            specs.append(player_archetype(height, bulk))

    specs.append(
        profile_archetype(
            "enemy_melee",
            "melee",
            (6, 12, 7),
            (14, 16, 10),
            (9, 9, 9),
            (6, 14, 6),
            4,
            8,
            head_accent=True,
        )
    )
    specs.append(
        profile_archetype(
            "enemy_ranged",
            "ranged",
            (5, 11, 6),
            (11, 14, 8),
            (7, 7, 7),
            (4, 13, 4),
            3,
            6,
            extras=(ExtraSpec("Bow", (2, 16, 2), (0, 0, 2), "WeaponMount"),),
        )
    )
    specs.append(
        profile_archetype(
            "enemy_shield",
            "shield",
            (6, 12, 8),
            (16, 17, 11),
            (9, 9, 9),
            (6, 13, 6),
            4,
            9,
            extras=(ExtraSpec("Shield", (3, 15, 12), (-2, 3, 2), "ShieldMount"),),
        )
    )
    specs.append(
        profile_archetype(
            "enemy_brute",
            "brute",
            (7, 13, 8),
            (20, 21, 13),
            (11, 11, 11),
            (8, 17, 8),
            5,
            12,
            head_accent=True,
        )
    )
    specs.append(
        profile_archetype(
            "enemy_dummy",
            "dummy",
            (6, 12, 8),
            (14, 17, 10),
            (10, 10, 10),
            (6, 14, 6),
            4,
            8,
            extras=(
                ExtraSpec("TargetStripe", (18, 3, 3), (0, 9, 5), "Torso", accent=True),
            ),
        )
    )
    specs.append(
        profile_archetype("enemy_hound", "hound", (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0), 0, 0)
    )

    for biome, theme_index in BIOME_THEME_INDEX.items():
        specs.append(
            profile_archetype(
                f"enemy_biome_{biome}",
                "melee",
                (6, 12, 7),
                (13, 16, 9),
                (9, 9, 9),
                (6, 14, 6),
                4,
                8,
                head_accent=biome in ("crystal", "umbral"),
                theme_index=theme_index,
            )
        )

    return specs


def equipment_archetypes() -> list[ArchetypeSpec]:
    return [
        ArchetypeSpec(
            id="equipment_castle_helm",
            profile="biped",
            theme_index=0,
            parts=(PartSpec("Head", (10, 10, 10), accent_band=True),),
        ),
        ArchetypeSpec(
            id="equipment_iron_helm",
            profile="biped",
            theme_index=0,
            parts=(PartSpec("Head", (9, 9, 9), accent_band=True),),
        ),
        ArchetypeSpec(
            id="equipment_castle_plate",
            profile="biped",
            theme_index=0,
            parts=(PartSpec("Torso", (15, 17, 10), accent_band=True),),
        ),
    ]


def theme_colours(theme_index: int) -> tuple[RGB, RGB]:
    row = PALETTES[theme_index % len(PALETTES)]
    body = row[2]
    accent = row[4]
    return body, accent


def _palette_colours(theme_index: int) -> tuple[RGB, RGB]:
    return theme_colours(theme_index)


# C-37: these values used to be underscored (`ArmL` -> `arm_l`) while `cli.py` derived file names
# with a bare `part_name.lower()` (`ArmL` -> `arml`) and never consulted this map. The two
# spellings coexisted in `art-source/characters/`: 98 pairs across the 26 archetypes, every pair
# byte-identical, 37% of the voxel source tree. The generated client assets use the `cli.py`
# spelling, so the underscored half was the dead half — and an artist who opened `arm_l.vox`,
# edited it and re-ran the importer saw no change in game and no error.
#
# Standardised on the spelling the shipped assets already use, so nothing has to be regenerated.
# The map is kept because `PART_NODE_NAMES` is derived from its key set, and because a single
# place to look up a part's file name is what was missing.
PART_FILE_NAMES: dict[str, str] = {
    "LegL": "legl",
    "LegR": "legr",
    "LegBL": "legbl",
    "LegBR": "legbr",
    "Torso": "torso",
    "Head": "head",
    "ArmL": "arml",
    "ArmR": "armr",
    "Tail": "tail",
}

PART_NODE_NAMES: dict[str, str] = {name: name for name in PART_FILE_NAMES}

ARCHETYPES: list[ArchetypeSpec] = all_archetypes()
ARCHETYPE_BY_ID: dict[str, ArchetypeSpec] = {spec.id: spec for spec in ARCHETYPES}

EQUIPMENT_VISUALS: dict[str, dict] = {
    "castle_helm": {"theme": 0, "size": (10, 10, 10)},
    "iron_helm": {"theme": 0, "size": (9, 9, 9)},
    "castle_plate": {"theme": 0, "size": (15, 17, 10)},
}
