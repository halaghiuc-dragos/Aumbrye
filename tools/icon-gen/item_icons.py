"""Fills the gaps in the item icon atlas.

177 of 264 authored items had no cell and fell back to the "?" marker, which is most of the loot a
player will ever pick up. Rather than redraw the shipped art, this composes the missing icons from
the same vocabulary it uses: one silhouette per item shape, one colour ramp per material family,
and the ramp chosen from the item's own biome and rarity. A frost longsword and a castle longsword
are then obviously the same weapon in different metal, which is what makes a loot list scannable.

Existing cells are never touched; new icons are appended below the shipped rows. This module now
provides drawing rules to ``atlas_build.py`` only; the atlas builder is the sole publisher.
"""

import sys

from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import shapes  # noqa: E402

CELL = 16
COLUMNS = 16
ATLAS_PATH = "apps/game/client/assets/ui/item_icons.png"
MANIFEST_PATH = "content/ui/item_icon_atlas.json"

# (outline, dark, mid, light, highlight, accent-dark, accent, accent-light)
RAMPS = {
    "castle": (
        (0x1b, 0x1a, 0x22), (0x45, 0x46, 0x52), (0x6f, 0x72, 0x80),
        (0x9c, 0xa1, 0xad), (0xd2, 0xd7, 0xdf), (0x4a, 0x33, 0x18),
        (0x7d, 0x58, 0x28), (0xb8, 0x89, 0x45),
    ),
    "vault": (
        (0x22, 0x18, 0x12), (0x5a, 0x38, 0x1e), (0x8c, 0x5a, 0x2c),
        (0xba, 0x82, 0x44), (0xe6, 0xb6, 0x72), (0x2a, 0x2a, 0x2e),
        (0x51, 0x52, 0x59), (0x86, 0x89, 0x92),
    ),
    "crystal": (
        (0x14, 0x1e, 0x38), (0x27, 0x46, 0x7c), (0x3f, 0x77, 0xba),
        (0x74, 0xb4, 0xe2), (0xc4, 0xe9, 0xff), (0x3a, 0x22, 0x5c),
        (0x63, 0x3f, 0x94), (0x9c, 0x76, 0xcc),
    ),
    "frozen": (
        (0x16, 0x27, 0x33), (0x33, 0x59, 0x6e), (0x5b, 0x8f, 0xa6),
        (0x96, 0xc8, 0xd8), (0xe2, 0xf6, 0xff), (0x2c, 0x3c, 0x5e),
        (0x4e, 0x66, 0x94), (0x86, 0x9d, 0xc6),
    ),
    "swamp": (
        (0x14, 0x21, 0x12), (0x2e, 0x48, 0x1f), (0x4f, 0x74, 0x2f),
        (0x7d, 0xa5, 0x4a), (0xbb, 0xdb, 0x8a), (0x3c, 0x2c, 0x14),
        (0x62, 0x49, 0x22), (0x92, 0x73, 0x3e),
    ),
    "cathedral": (
        (0x1a, 0x13, 0x25), (0x3c, 0x2c, 0x54), (0x60, 0x4a, 0x84),
        (0x91, 0x7d, 0xb6), (0xcd, 0xc0, 0xe6), (0x4d, 0x37, 0x0e),
        (0x86, 0x62, 0x1e), (0xc6, 0x9c, 0x3e),
    ),
    "umbral": (
        (0x12, 0x0f, 0x1c), (0x2b, 0x24, 0x40), (0x48, 0x3e, 0x66),
        (0x71, 0x67, 0x92), (0xa9, 0xa1, 0xc4), (0x38, 0x2a, 0x12),
        (0x63, 0x4c, 0x22), (0x9a, 0x7c, 0x42),
    ),
    "prism": (
        (0x1d, 0x16, 0x30), (0x45, 0x2d, 0x6e), (0x72, 0x4f, 0xa8),
        (0xa6, 0x87, 0xd4), (0xe2, 0xd2, 0xf7), (0x11, 0x44, 0x48),
        (0x1d, 0x77, 0x7c), (0x4b, 0xb2, 0xb6),
    ),
    "mire": (
        (0x1a, 0x22, 0x14), (0x3a, 0x4c, 0x1e), (0x5f, 0x79, 0x2c),
        (0x8f, 0xac, 0x48), (0xc8, 0xdd, 0x88), (0x3a, 0x18, 0x30),
        (0x63, 0x2a, 0x52), (0x96, 0x51, 0x82),
    ),
    "hollow": (
        (0x1a, 0x24, 0x2c), (0x39, 0x50, 0x5e), (0x5f, 0x7f, 0x91),
        (0x93, 0xb5, 0xc4), (0xd8, 0xec, 0xf4), (0x36, 0x30, 0x24),
        (0x5c, 0x53, 0x3c), (0x8d, 0x82, 0x64),
    ),
    # Neutral families for things with no biome of their own.
    "iron": (
        (0x1a, 0x1b, 0x1f), (0x3d, 0x40, 0x47), (0x64, 0x69, 0x72),
        (0x91, 0x97, 0xa1), (0xc6, 0xcc, 0xd4), (0x38, 0x28, 0x16),
        (0x60, 0x46, 0x24), (0x92, 0x6e, 0x3c),
    ),
    "gold": (
        (0x2e, 0x20, 0x08), (0x6f, 0x4e, 0x12), (0xac, 0x7c, 0x1e),
        (0xdc, 0xae, 0x3c), (0xff, 0xe4, 0x94), (0x2a, 0x22, 0x2c),
        (0x4c, 0x40, 0x52), (0x7d, 0x70, 0x86),
    ),
    "elixir": (
        (0x24, 0x12, 0x14), (0x62, 0x1c, 0x24), (0x9d, 0x2e, 0x36),
        (0xcc, 0x55, 0x58), (0xf0, 0x97, 0x92), (0x2c, 0x24, 0x14),
        (0x50, 0x42, 0x22), (0x84, 0x6f, 0x3c),
    ),
}

SHAPES = {
    "flask": shapes.FLASK, "ingot_bar": shapes.INGOT_BAR, "bow_recurve": shapes.BOW_RECURVE,
    "torch": shapes.TORCH, "runestone": shapes.RUNESTONE, "pouch": shapes.POUCH,
    "whetstone": shapes.WHETSTONE,
    "sword": shapes.SWORD, "greatsword": shapes.GREATSWORD, "dagger": shapes.DAGGER,
    "axe": shapes.AXE, "spear": shapes.SPEAR, "staff": shapes.STAFF,
    "helm": shapes.HELM, "cuirass": shapes.CUIRASS, "glove": shapes.GLOVE,
    "boot": shapes.BOOT, "shield": shapes.SHIELD, "amulet": shapes.AMULET,
    "ring": shapes.RING, "scroll": shapes.SCROLL,
    "gem": shapes.GEM, "shard": shapes.SHARD,
    # Carried over from the first atlas and redrawn to the outlined rules; reached through
    # curated.CURATED rather than through the name heuristics.
    "crown": shapes.CROWN, "chalice": shapes.CHALICE, "banner": shapes.BANNER,
    "cloak": shapes.CLOAK, "charm": shapes.CHARM, "medallion": shapes.MEDALLION,
    "orb": shapes.ORB, "heart": shapes.HEART, "veil": shapes.VEIL, "key": shapes.KEY,
    "hammer": shapes.HAMMER, "token": shapes.TOKEN, "scrap": shapes.SCRAP,
    # Sub-types, so a family is not one silhouette repeated in six colours.
    "rapier": shapes.RAPIER, "shortsword": shapes.SHORTSWORD, "buckler": shapes.BUCKLER,
    "towershield": shapes.TOWERSHIELD, "halberd": shapes.HALBERD, "bomb": shapes.BOMB,
    "caltrops": shapes.CALTROPS, "oil": shapes.OIL,
}

BIOME_RAMP = {
    "forgotten_castle": "castle", "iron_vault": "vault", "crystal_caverns": "crystal",
    "frozen_fortress": "frozen", "poison_swamp": "swamp", "dark_cathedral": "cathedral",
    "umbral_chapel": "umbral", "prism_depths": "prism", "venom_mire": "mire",
    "glacial_hollow": "hollow",
}

BASE_SHAPE = {
    "longsword": "sword", "sword": "sword", "scimitar": "sword",
    "rapier": "rapier", "shortsword": "shortsword",
    "greatsword": "greatsword", "claymore": "greatsword",
    "warhammer": "hammer", "maul": "hammer",
    "dagger": "dagger", "knife": "dagger", "axe": "axe", "waraxe": "axe",
    "spear": "spear", "pike": "spear", "halberd": "halberd",
    "bow": "bow_recurve", "longbow": "bow_recurve", "shortbow": "bow_recurve",
    "staff": "staff", "rod": "staff",
    "helm": "helm", "cuirass": "cuirass", "gauntlets": "glove", "greaves": "boot",
    "kiteshield": "shield", "towershield": "towershield", "buckler": "buckler",
    "pendant": "amulet", "band": "ring",
}

WEAPON_SHAPE = {
    "sword_basic": "sword", "castle_sword": "sword", "greatsword": "greatsword",
    "dagger": "dagger", "axe": "axe", "spear": "spear", "bow": "bow_recurve", "staff": "staff",
}

SLOT_SHAPE = {
    "weapon": "sword", "helmet": "helm", "chest": "cuirass", "gloves": "glove",
    "boots": "boot", "secondary": "shield", "amulet": "amulet", "ring": "ring",
}


# Consumables and materials are the two biggest groups and the ones with the least structured data
# behind them -- no baseId, no slot, often no biome -- so they are read off the authored name. This
# is what stops twenty-seven consumables all rendering as the same red disc.
NAME_SHAPE = [
    (("whetstone", "honing"), "whetstone"),
    (("torch", "lantern", "candle"), "torch"),
    (("stone", "bone", "lodestone", "sigil", "seal", "tear"), "runestone"),
    (("dust", "ash", "grain", "salt", "gilt", "wax", "thread", "resin"), "pouch"),
    (("ingot", "slag", "dross", "steel", "brass", "iron"), "ingot_bar"),
    (("shard", "sliver", "fragment", "splinter"), "shard"),
    (("catalyst", "glass", "gem", "crystal", "core", "heart", "eye"), "gem"),
    (("caltrop",), "caltrops"),
    (("bomb", "alchemist", "firebomb"), "bomb"),
    (("oil", "quench", "grease"), "oil"),
    (("fire", "flask", "pot", "draught", "potion", "elixir"), "flask"),
]

NAME_RAMP = [
    (("health", "bloodstaunch", "blood"), "elixir"),
    (("mana", "clarity", "arcane", "spell", "focus"), "cathedral"),
    (("stamina", "swift", "venom", "antidote", "bog", "mire"), "swamp"),
    (("frost", "rime", "hoarfrost", "ice"), "frozen"),
    (("ember", "fire", "cinder", "burn", "flame", "pitch"), "vault"),
    (("storm", "thunder", "glimmer", "spellglass"), "crystal"),
    (("aumbral", "sable", "chapel", "reliquary"), "umbral"),
    (("gilt", "seal", "sigil", "warding", "iron skin"), "gold"),
]


def _match(name: str, table):
    lowered = name.lower()
    for words, value in table:
        if any(word in lowered for word in words):
            return value
    return None


def shape_for(item: dict) -> str:
    base = str(item.get("baseId", ""))
    if base in BASE_SHAPE:
        return BASE_SHAPE[base]
    weapon = str(item.get("weaponId", ""))
    if weapon in WEAPON_SHAPE:
        return WEAPON_SHAPE[weapon]
    slot = str(item.get("equipmentSlot", ""))
    if slot in SLOT_SHAPE:
        return SLOT_SHAPE[slot]
    item_type = str(item.get("itemType", ""))
    name = str(item.get("name", ""))
    if item_type in ("consumable", "material"):
        if "scroll" in name.lower() or "tome" in name.lower() or "map" in name.lower():
            return "scroll"
        matched = _match(name, NAME_SHAPE)
        if matched:
            return matched
        return "flask" if item_type == "consumable" else "ingot_bar"
    return "gem"


def ramp_for(item: dict) -> str:
    biome = str(item.get("biome") or item.get("theme") or "")
    if biome in BIOME_RAMP:
        return BIOME_RAMP[biome]
    matched = _match(str(item.get("name", "")), NAME_RAMP)
    if matched:
        return matched
    item_type = str(item.get("itemType", ""))
    if item_type == "consumable":
        return "elixir"
    rarity = str(item.get("rarity", "common"))
    if rarity in ("legendary", "aumbral"):
        return "gold"
    return "iron"


def draw(px, rows, ramp, col, row) -> None:
    lut = {
        "o": ramp[0], "d": ramp[1], "m": ramp[2], "l": ramp[3], "h": ramp[4],
        "a": ramp[5], "b": ramp[6], "c": ramp[7],
    }
    for y, line in enumerate(rows):
        for x, ch in enumerate(line):
            if ch == ".":
                continue
            r, g, b = lut[ch]
            px[col * CELL + x, row * CELL + y] = (r, g, b, 255)


def main() -> None:
    raise SystemExit(
        "Direct publication is retired; use tools/icon-gen/atlas_build.py "
        "(--dry-run/--force supported) to publish the complete owned atlas set."
    )


if __name__ == "__main__":
    raise SystemExit(
        "Direct publication is retired; use tools/icon-gen/atlas_build.py "
        "(--dry-run/--force supported) to publish the complete owned atlas set."
    )
