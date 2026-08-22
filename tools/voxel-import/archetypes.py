"""Character archetype part dimensions and joint layout (voxel integers)."""

from __future__ import annotations

import math

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
    head_seat: int = 2,
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
        PartSpec("Head", head, (0, ty - head_seat, 0), parent="Torso", accent_band=head_accent),
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


#: Arm length as a fraction of total height, from the same standard figure (13 of 36).
ARM_RATIO = 13.0 / 36.0

#: One axis, five bodies.
#:
#: Stature and build were two independent five-step sliders, which is twenty-five rigs to build and
#: animate for a choice the player experiences as "what shape is my warden". Worse, twenty-one of
#: the twenty-five were interpolations nobody would pick deliberately. Five named frames cover the
#: four corners of that grid plus the middle, and every one of them is a silhouette you can tell
#: from the other four across a room.
#:
#: `total` is body height in voxels; `torso_w` is chest width.
PLAYER_FRAMES: dict[str, dict] = {
    "slight":   {"total": 30, "torso_w": 10},
    "lean":     {"total": 39, "torso_w": 10},
    "standard": {"total": 36, "torso_w": 12},
    "stout":    {"total": 31, "torso_w": 14},
    "towering": {"total": 42, "torso_w": 14},
}

#: leg : head, as fractions of total height; the torso takes the remainder.
#:
#: Was 3:4:2 of nine — legs 33% of height and torso 44%. That is a toddler's proportion, and it is
#: what "the proportions are completely broken" was pointing at: every frame came out short-legged
#: and long-bodied, most visibly on the small ones. A stylised adult figure sits nearer 40% legs and
#: 39% torso, which is what these are.
LEG_RATIO = 0.40
HEAD_RATIO = 0.21


def player_archetype(frame_key: str) -> ArchetypeSpec:
    frame = PLAYER_FRAMES.get(frame_key, PLAYER_FRAMES["standard"])
    total = int(frame["total"])
    torso_w = int(frame["torso_w"])

    leg_h = int(round(total * LEG_RATIO))
    # Floored at eight. Seven leaves no chin: the face plate is placed two voxels above the head's
    # base and sized off the head, and on a seven-voxel skull the plate reaches the collar, so the
    # jaw is gone and the head reads as sunk into the chest. Slight and Stout were the two frames
    # that rounded down to seven, and they are exactly the two that looked wrong.
    #
    # The cost is honest: a floor means the short frames carry a proportionally larger head — 27%
    # of height on Slight against 21% on Towering. That is the stylised convention rather than an
    # accident, but it is a real departure from "one figure, resized", and `frame_audit` checks it
    # as a band now instead of as a constant.
    head_side = max(8, int(round(total * HEAD_RATIO)))
    torso_h = total - leg_h - head_side

    # Hips must not be wider than the chest: outer edge inside the torso's, gap on the centre line.
    leg_w = max(4, torso_w // 2 - 1)
    leg = (leg_w, leg_h, leg_w)
    torso = (torso_w, torso_h, max(6, torso_w * 2 // 3))
    # Cubic, and driven by the frame's height. Total height is leg + torso + head, so this is the
    # only thing that may set it.
    head = (head_side, head_side, head_side)
    # Wide enough to survive the one-voxel inset below and still read. At two voxels the arm
    # protruded a single voxel past a narrow torso and, being shallower than the torso in z, was
    # hidden behind its own body — which is why hands went missing on the narrow frames.
    arm_w = max(3, int(round(torso_w * 0.34)))
    arm = (arm_w, int(round(total * ARM_RATIO)), arm_w)
    ty = torso[1]
    # Two layers of torso above the shoulder joint, always. A bare fraction of the torso height
    # rounds differently on each frame — 0.88 landed on 91% of the torso for Slight and 92% for
    # Stout against 86-88% for the rest — and those are exactly the two frames whose pauldrons rose
    # past the collar and closed over the head. The clamp is what holds; the fraction only decides
    # where the shoulder sits on the frames tall enough for it to matter.
    shoulder_y = max(1, min(ty - 2, int(round(ty * 0.86))))
    # Pulled in one voxel from flush: at exactly flush the arm and torso abut with zero overlap and
    # the contour pass draws a hard line down the seam, so the arms read as slabs bolted on. One
    # voxel of interpenetration removes it and still leaves `arm_w - 1` voxels visible.
    # Exactly one voxel of overlap, expressed as one. `round(tw/2 + aw/2) - 1` *looked* like one
    # voxel and was not: on an odd sum it rounds to even, and the narrow frames ended up with the
    # arm protruding 1.5 voxels past a torso that is deeper than the arm — so from the front the
    # body hid it and the warden appeared to have no hands.
    shoulder_x = math.ceil(torso_w / 2) + math.ceil(arm_w / 2) - 1

    archetype_id = "player_warden" if frame_key == "standard" else f"player_warden_{frame_key}"

    # Every measurement here is a fraction of the part it sits on, never a literal: literals tuned
    # against the standard figure are what left the visor proud of a small skull and the belt
    # setting the silhouette's width for every build.
    visor = (max(2, head_side // 2), max(1, head_side // 4), max(2, head_side * 3 // 8))
    visor_offset = (0, head_side - 3, head_side // 2)
    hood_offset = (0, -max(1, head_side * 3 // 8), 0)
    belt = (torso[0] + 1, 3, max(3, torso[2] - 1))
    pauldron = (arm[0] + 1, 3, arm[2] + 2)

    extras: tuple[ExtraSpec, ...] = (
        ExtraSpec("Visor", visor, visor_offset, "Head"),
        # Size is ignored for the hood — `generate_character_voxels._write_hood` grows it from the
        # head — and the offset drops it so the cowl closes below the jaw.
        ExtraSpec("Hood", (0, 0, 0), hood_offset, "Head", accent=False),
        ExtraSpec("BeltTrim", belt, (0, 3, 0), "Torso", accent=True),
        ExtraSpec("Pauldron", pauldron, (0, -1, 0), "ArmL", accent=True),
        ExtraSpec("PauldronR", pauldron, (0, -1, 0), "ArmR", accent=True),
    )
    return ArchetypeSpec(
        id=archetype_id,
        profile="biped",
        parts=_biped_parts(
            leg,
            torso,
            head,
            arm,
            # Half a leg plus one, so the two legs leave a gap on the centre line instead of
            # meeting there with two coincident faces.
            leg_w // 2 + 1,
            shoulder_x,
            shoulder_y,
            # One layer, matching the collar notch the torso cuts in its top layer exactly. At two
            # the head sank a layer *past* the notch into solid chest, and since the head is
            # narrower than the torso on every frame the shoulders closed over it — worst on the
            # frames where a two-voxel bite is the largest share of the skull (Slight and Stout).
            head_seat=1,
        ),
        theme_index=10,
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
    for frame_key in PLAYER_FRAMES:
        specs.append(player_archetype(frame_key))

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
