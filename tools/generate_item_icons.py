#!/usr/bin/env python3
"""Draw the item icon atlas.

The shipped atlas was corrupt — streaked scanline garbage rather than artwork — so every item
icon in the game rendered as coloured noise: inventory cells, equipment slots, merchant and
blacksmith lists, loot popups, and the starting-weapon icon on the character-creation screen.

Each cell is authored on the 16x16 grid the manifest declares (content/ui/item_icon_atlas.json)
with hard edges and a dark keyline, so icons stay crisp under nearest filtering and stay legible
against the dark panel background.

Every icon is a (shape, palette) pair: the shape says what kind of thing it is at a glance, the
palette says which biome or material it belongs to. Items that share a silhouette are told apart
by colour, which is the same convention the rarity borders already use.

Usage:
    python tools/generate_item_icons.py [--check]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "content" / "ui" / "item_icon_atlas.json"
ATLAS = ROOT / "apps" / "game" / "client" / "assets" / "ui" / "item_icons.png"

CELL = 16

#: base, light, dark, accent
PALETTES: dict[str, tuple] = {
    "iron": ((132, 138, 148), (188, 194, 204), (58, 62, 72), (214, 190, 120)),
    "steel": ((176, 184, 196), (226, 232, 240), (74, 80, 92), (226, 196, 122)),
    "castle": ((150, 156, 170), (212, 218, 230), (60, 60, 74), (226, 188, 96)),
    "gold": ((214, 172, 72), (244, 216, 138), (110, 82, 26), (255, 240, 190)),
    "silver": ((196, 202, 214), (238, 242, 248), (86, 92, 104), (226, 232, 240)),
    "frost": ((120, 178, 214), (196, 232, 248), (36, 74, 106), (232, 250, 255)),
    "crystal": ((122, 206, 210), (196, 244, 246), (32, 92, 100), (240, 255, 255)),
    "flame": ((216, 108, 52), (248, 182, 96), (98, 38, 16), (255, 226, 150)),
    "poison": ((122, 176, 74), (186, 226, 128), (44, 74, 28), (222, 250, 160)),
    "swamp": ((110, 140, 78), (168, 200, 124), (40, 58, 30), (206, 232, 152)),
    "shadow": ((116, 96, 156), (172, 152, 210), (40, 30, 62), (208, 190, 250)),
    "cathedral": ((164, 140, 200), (216, 200, 240), (58, 44, 88), (240, 214, 130)),
    "blood": ((186, 62, 62), (232, 122, 116), (78, 22, 22), (250, 178, 168)),
    "ruby": ((198, 58, 78), (240, 128, 142), (84, 20, 30), (252, 186, 194)),
    "jade": ((84, 172, 122), (152, 222, 178), (28, 72, 50), (198, 246, 216)),
    "sun": ((228, 190, 84), (250, 228, 152), (114, 84, 22), (255, 248, 206)),
    "wind": ((160, 206, 196), (216, 242, 236), (62, 92, 88), (238, 255, 250)),
    "tide": ((84, 148, 178), (150, 208, 230), (28, 62, 82), (206, 240, 252)),
    "void": ((96, 82, 128), (152, 136, 186), (30, 24, 46), (188, 168, 232)),
    "aumbral": ((196, 118, 210), (240, 182, 246), (78, 34, 92), (255, 226, 160)),
    "arcane": ((132, 132, 214), (190, 190, 246), (46, 46, 104), (226, 226, 255)),
    "health": ((202, 66, 78), (240, 130, 132), (82, 24, 30), (250, 190, 190)),
    "mana": ((84, 118, 206), (150, 178, 244), (28, 44, 96), (196, 216, 255)),
    "stamina": ((196, 176, 74), (238, 224, 138), (86, 74, 22), (250, 242, 176)),
    "slot": ((78, 80, 92), (108, 112, 126), (44, 46, 56), (92, 96, 110)),
}

OUTLINE = (18, 16, 24)


def px(d: ImageDraw.ImageDraw, x: int, y: int, colour) -> None:
    d.point((x, y), fill=colour)


def box(d: ImageDraw.ImageDraw, x0: int, y0: int, x1: int, y1: int, colour) -> None:
    d.rectangle([min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)], fill=colour)


# --------------------------------------------------------------------------------------- weapons


def shape_sword(d, p) -> None:
    base, light, dark, accent = p
    box(d, 7, 2, 8, 9, base)
    box(d, 7, 2, 7, 9, light)
    px(d, 8, 2, dark)
    box(d, 4, 10, 11, 10, accent)
    box(d, 7, 11, 8, 13, dark)
    box(d, 6, 14, 9, 14, accent)


def shape_greatsword(d, p) -> None:
    base, light, dark, accent = p
    box(d, 6, 1, 9, 9, base)
    box(d, 6, 1, 7, 9, light)
    box(d, 9, 2, 9, 9, dark)
    box(d, 3, 10, 12, 10, accent)
    box(d, 7, 11, 8, 13, dark)
    box(d, 6, 14, 9, 15, accent)


def shape_dagger(d, p) -> None:
    base, light, dark, accent = p
    box(d, 7, 3, 8, 8, base)
    box(d, 7, 3, 7, 8, light)
    box(d, 5, 9, 10, 9, accent)
    box(d, 7, 10, 8, 12, dark)
    box(d, 6, 13, 9, 13, accent)


def shape_staff(d, p) -> None:
    base, light, dark, accent = p
    box(d, 7, 5, 8, 15, dark)
    box(d, 7, 5, 7, 15, base)
    box(d, 6, 2, 9, 4, accent)
    box(d, 5, 3, 10, 3, accent)
    px(d, 7, 3, light)


def shape_bow(d, p) -> None:
    """Recurve limbs on the left, string taut down the middle, arrow nocked and pointing right."""
    base, light, dark, accent = p
    limb = [(1, 8), (2, 6), (3, 5), (4, 4), (5, 4), (6, 4), (7, 4), (8, 4), (9, 5), (10, 6), (11, 8)]
    for y, x in limb:
        box(d, x, y, x + 1, y, base)
        px(d, x + 1, y, light)
    px(d, 8, 0, base)
    px(d, 8, 15, base)
    for y in range(1, 15):
        px(d, 4 if 3 <= y <= 12 else 6, y, dark)
    box(d, 4, 7, 14, 8, light)
    d.polygon([(12, 5), (15, 7), (15, 8), (12, 10)], fill=accent)
    box(d, 4, 6, 5, 9, dark)


def shape_spear(d, p) -> None:
    base, light, dark, accent = p
    box(d, 7, 6, 8, 15, dark)
    px(d, 7, 6, base)
    box(d, 7, 2, 8, 5, base)
    px(d, 7, 2, light)
    box(d, 6, 4, 9, 4, accent)


def shape_hammer(d, p) -> None:
    base, light, dark, accent = p
    box(d, 3, 3, 12, 7, base)
    box(d, 3, 3, 12, 3, light)
    box(d, 3, 7, 12, 7, dark)
    box(d, 7, 8, 8, 15, dark)
    box(d, 7, 8, 7, 15, accent)


def shape_shield(d, p) -> None:
    base, light, dark, accent = p
    d.polygon([(3, 2), (12, 2), (12, 9), (7, 14), (3, 9)], fill=base)
    d.polygon([(5, 4), (10, 4), (10, 9), (7, 12), (5, 9)], fill=dark)
    box(d, 7, 5, 8, 11, accent)
    box(d, 5, 7, 10, 8, accent)


# --------------------------------------------------------------------------------------- armour


def shape_helm(d, p) -> None:
    base, light, dark, accent = p
    d.polygon([(4, 5), (5, 3), (10, 3), (11, 5), (11, 12), (4, 12)], fill=base)
    box(d, 5, 4, 10, 4, light)
    box(d, 5, 7, 10, 8, dark)
    box(d, 7, 7, 8, 8, accent)


def shape_crown(d, p) -> None:
    base, light, dark, accent = p
    box(d, 3, 9, 12, 12, base)
    box(d, 3, 9, 12, 9, light)
    d.polygon([(3, 9), (4, 4), (6, 9)], fill=base)
    d.polygon([(6, 9), (7, 3), (9, 9)], fill=base)
    d.polygon([(9, 9), (11, 4), (12, 9)], fill=base)
    px(d, 4, 5, accent)
    px(d, 7, 4, accent)
    px(d, 11, 5, accent)
    box(d, 5, 11, 10, 11, dark)


def shape_plate(d, p) -> None:
    base, light, dark, accent = p
    d.polygon([(4, 3), (11, 3), (12, 6), (11, 13), (4, 13), (3, 6)], fill=base)
    box(d, 5, 4, 10, 4, light)
    box(d, 7, 5, 8, 12, dark)
    box(d, 4, 6, 5, 7, accent)
    box(d, 10, 6, 11, 7, accent)


def shape_cloak(d, p) -> None:
    base, light, dark, accent = p
    d.polygon([(5, 2), (10, 2), (13, 13), (2, 13)], fill=base)
    d.polygon([(6, 3), (9, 3), (10, 12), (5, 12)], fill=dark)
    box(d, 5, 2, 10, 2, accent)
    px(d, 7, 4, light)


def shape_gauntlets(d, p) -> None:
    """Mitten silhouette with the finger gaps cut back out.

    Drawing fingers as adjacent bars merged them into one solid dome — the icon read as a bucket.
    Cutting transparent notches out of a filled hand is what makes the separate digits survive at
    16px, and the outline pass then wraps each one.
    """
    base, light, dark, accent = p
    clear = (0, 0, 0, 0)
    box(d, 5, 4, 12, 10, base)
    box(d, 5, 4, 12, 4, light)
    for x in (7, 9, 11):
        box(d, x, 3, x, 6, clear)
    box(d, 6, 3, 6, 3, clear)
    box(d, 8, 3, 8, 3, clear)
    # Thumb, angled off the left side below the fingers.
    box(d, 3, 7, 4, 9, base)
    px(d, 3, 7, light)
    for x in (6, 8, 10):
        px(d, x, 8, dark)
    box(d, 4, 11, 13, 13, accent)
    box(d, 4, 13, 13, 13, dark)


def shape_boots(d, p) -> None:
    base, light, dark, accent = p
    box(d, 3, 3, 6, 10, base)
    box(d, 3, 10, 9, 12, base)
    box(d, 3, 3, 6, 3, light)
    box(d, 3, 12, 9, 13, dark)
    box(d, 3, 8, 6, 9, accent)


# ------------------------------------------------------------------------------------- trinkets


def shape_ring(d, p) -> None:
    base, light, dark, accent = p
    d.ellipse([3, 5, 12, 14], outline=base, width=2)
    d.ellipse([5, 7, 10, 12], outline=dark, width=1)
    d.polygon([(7, 1), (10, 4), (7, 6), (4, 4)], fill=accent)
    px(d, 7, 3, light)


def shape_amulet(d, p) -> None:
    base, light, dark, accent = p
    for x, y in [(4, 2), (5, 3), (6, 4), (9, 4), (10, 3), (11, 2)]:
        px(d, x, y, dark)
    d.polygon([(7, 5), (11, 9), (7, 14), (4, 9)], fill=base)
    d.polygon([(7, 7), (9, 9), (7, 12), (6, 9)], fill=accent)
    px(d, 7, 8, light)


def shape_charm(d, p) -> None:
    base, light, dark, accent = p
    for x in range(5, 11):
        px(d, x, 2, dark)
    box(d, 7, 3, 8, 5, dark)
    d.ellipse([4, 5, 11, 13], fill=base)
    d.ellipse([6, 7, 9, 11], fill=accent)
    px(d, 6, 7, light)


def shape_medallion(d, p) -> None:
    base, light, dark, accent = p
    d.ellipse([3, 3, 12, 12], fill=base)
    d.ellipse([5, 5, 10, 10], fill=accent)
    px(d, 6, 6, light)
    for x, y in [(7, 1), (7, 14), (1, 7), (14, 7), (2, 2), (13, 2), (2, 13), (13, 13)]:
        px(d, x, y, accent)
    d.ellipse([3, 3, 12, 12], outline=dark)


def shape_chalice(d, p) -> None:
    base, light, dark, accent = p
    d.polygon([(4, 3), (11, 3), (9, 9), (6, 9)], fill=base)
    box(d, 4, 3, 11, 4, accent)
    box(d, 7, 9, 8, 12, dark)
    box(d, 4, 12, 11, 13, base)
    px(d, 5, 4, light)


def shape_banner(d, p) -> None:
    base, light, dark, accent = p
    box(d, 3, 1, 4, 15, dark)
    d.polygon([(5, 3), (12, 3), (12, 10), (8, 8), (5, 10)], fill=base)
    box(d, 5, 3, 12, 3, light)
    box(d, 7, 5, 10, 6, accent)


# ----------------------------------------------------------------------------------- consumables


def shape_potion(d, p) -> None:
    base, light, dark, accent = p
    box(d, 6, 2, 9, 4, dark)
    box(d, 6, 1, 9, 1, accent)
    d.polygon([(5, 5), (10, 5), (12, 9), (12, 13), (3, 13), (3, 9)], fill=dark)
    d.polygon([(5, 8), (10, 8), (11, 12), (4, 12)], fill=base)
    px(d, 5, 9, light)


def shape_vial(d, p) -> None:
    base, light, dark, accent = p
    box(d, 6, 2, 9, 3, accent)
    box(d, 6, 4, 9, 5, dark)
    d.polygon([(5, 6), (10, 6), (10, 13), (5, 13)], fill=dark)
    box(d, 6, 9, 9, 12, base)
    px(d, 6, 9, light)


def shape_dust(d, p) -> None:
    base, light, dark, accent = p
    d.polygon([(4, 7), (11, 7), (10, 13), (5, 13)], fill=base)
    box(d, 5, 5, 10, 6, dark)
    for x, y in [(3, 3), (7, 2), (12, 4), (5, 1), (10, 1)]:
        px(d, x, y, accent)
        px(d, x, y + 1, light)


def shape_crystal(d, p) -> None:
    base, light, dark, accent = p
    d.polygon([(7, 1), (11, 6), (9, 14), (5, 14), (3, 6)], fill=base)
    d.polygon([(7, 1), (7, 14), (5, 14), (3, 6)], fill=light)
    d.polygon([(7, 4), (9, 7), (7, 11)], fill=accent)
    d.polygon([(9, 7), (11, 6), (9, 14)], fill=dark)


def shape_orb(d, p) -> None:
    base, light, dark, accent = p
    d.ellipse([3, 3, 12, 12], fill=base)
    d.ellipse([3, 3, 12, 12], outline=dark)
    d.ellipse([5, 5, 8, 8], fill=light)
    d.arc([4, 4, 11, 11], start=40, end=150, fill=accent)


def shape_heart(d, p) -> None:
    base, light, dark, accent = p
    box(d, 4, 4, 6, 5, base)
    box(d, 9, 4, 11, 5, base)
    box(d, 3, 5, 12, 8, base)
    box(d, 4, 9, 11, 10, base)
    box(d, 5, 11, 10, 11, base)
    box(d, 6, 12, 9, 12, base)
    box(d, 7, 13, 8, 13, base)
    box(d, 4, 5, 5, 6, light)
    box(d, 8, 7, 10, 9, dark)
    px(d, 11, 5, accent)


def shape_veil(d, p) -> None:
    base, light, dark, accent = p
    for i, y in enumerate(range(3, 13)):
        offset = (i % 3) - 1
        box(d, 3 + offset, y, 12 + offset, y, base if i % 2 else dark)
    box(d, 3, 3, 12, 3, accent)
    px(d, 5, 6, light)


def shape_key(d, p) -> None:
    base, light, dark, accent = p
    d.ellipse([2, 4, 8, 10], outline=base, width=2)
    d.ellipse([4, 6, 6, 8], fill=dark)
    box(d, 8, 6, 14, 7, base)
    box(d, 8, 6, 14, 6, light)
    box(d, 11, 8, 11, 10, accent)
    box(d, 13, 8, 13, 10, accent)


def shape_scrap(d, p) -> None:
    base, light, dark, accent = p
    d.polygon([(3, 6), (7, 3), (12, 5), (13, 10), (8, 13), (4, 11)], fill=base)
    d.polygon([(5, 7), (7, 5), (10, 6), (10, 9), (7, 11)], fill=dark)
    px(d, 5, 6, light)
    px(d, 11, 6, accent)


def shape_token(d, p) -> None:
    base, light, dark, accent = p
    d.ellipse([2, 2, 13, 13], fill=base)
    d.ellipse([2, 2, 13, 13], outline=dark)
    d.polygon([(7, 4), (10, 7), (5, 7)], fill=accent)
    d.polygon([(7, 8), (10, 11), (5, 11)], fill=accent)
    px(d, 4, 4, light)


SHAPES = {
    "sword": shape_sword,
    "greatsword": shape_greatsword,
    "dagger": shape_dagger,
    "staff": shape_staff,
    "bow": shape_bow,
    "spear": shape_spear,
    "hammer": shape_hammer,
    "shield": shape_shield,
    "helm": shape_helm,
    "crown": shape_crown,
    "plate": shape_plate,
    "cloak": shape_cloak,
    "gauntlets": shape_gauntlets,
    "boots": shape_boots,
    "ring": shape_ring,
    "amulet": shape_amulet,
    "charm": shape_charm,
    "medallion": shape_medallion,
    "chalice": shape_chalice,
    "banner": shape_banner,
    "potion": shape_potion,
    "vial": shape_vial,
    "dust": shape_dust,
    "crystal": shape_crystal,
    "orb": shape_orb,
    "heart": shape_heart,
    "veil": shape_veil,
    "key": shape_key,
    "scrap": shape_scrap,
    "token": shape_token,
}

#: cell key -> (shape, palette)
ICONS: dict[str, tuple[str, str]] = {
    # Castle set
    "castle_amulet": ("amulet", "castle"),
    "castle_banner": ("banner", "castle"),
    "castle_boots": ("boots", "castle"),
    "castle_buckler": ("shield", "castle"),
    "castle_chalice": ("chalice", "gold"),
    "castle_crown": ("crown", "gold"),
    "castle_gauntlets": ("gauntlets", "castle"),
    "castle_helm": ("helm", "castle"),
    "castle_plate": ("plate", "castle"),
    "castle_ring": ("ring", "castle"),
    "castle_sword": ("sword", "castle"),
    # Cathedral set
    "cathedral_arcane_staff": ("staff", "cathedral"),
    "cathedral_gloves": ("gauntlets", "cathedral"),
    "cathedral_holy_charm": ("charm", "sun"),
    "cathedral_pilgrim_boots": ("boots", "cathedral"),
    "cathedral_sanctum_ring": ("ring", "cathedral"),
    "cathedral_shadow_cloak": ("cloak", "shadow"),
    "cathedral_shadow_dagger": ("dagger", "shadow"),
    "cathedral_warden_helm": ("helm", "cathedral"),
    # Crystal set
    "crystal_bow": ("bow", "crystal"),
    "crystal_frost_ring": ("ring", "crystal"),
    "crystal_prism_amulet": ("amulet", "crystal"),
    "crystal_shard_blade": ("sword", "crystal"),
    # Frost set
    "frost_amulet": ("amulet", "frost"),
    "frost_crystal": ("crystal", "frost"),
    "frost_gauntlets": ("gauntlets", "frost"),
    "frost_glacier_sword": ("greatsword", "frost"),
    "frost_ice_ring": ("ring", "frost"),
    "frost_knight_helm": ("helm", "frost"),
    "frost_knight_plate": ("plate", "frost"),
    "frost_raider_boots": ("boots", "frost"),
    "frost_relic_shard": ("crystal", "frost"),
    "frost_warlord_blade": ("greatsword", "frost"),
    # Flame / ember
    "ember_gauntlets": ("gauntlets", "flame"),
    "flame_sword": ("sword", "flame"),
    "flame_relic_core": ("orb", "flame"),
    "relic_flame_core": ("orb", "flame"),
    # Swamp / poison
    "swamp_bog_boots": ("boots", "swamp"),
    "swamp_mire_charm": ("charm", "swamp"),
    "swamp_toxin_dagger": ("dagger", "poison"),
    "venom_dagger": ("dagger", "poison"),
    "poison_relic_vial": ("vial", "poison"),
    "relic_poison_vial": ("vial", "poison"),
    # Iron / steel commons
    "iron_boots": ("boots", "iron"),
    "iron_gauntlets": ("gauntlets", "iron"),
    "iron_helm": ("helm", "iron"),
    "iron_plate": ("plate", "iron"),
    "iron_sword": ("sword", "iron"),
    "iron_scrap": ("scrap", "iron"),
    "steel_boots": ("boots", "steel"),
    "steel_gauntlets": ("gauntlets", "steel"),
    "steel_helm": ("helm", "steel"),
    "steel_plate": ("plate", "steel"),
    "training_greatsword": ("greatsword", "iron"),
    "guard_spear": ("spear", "iron"),
    "war_hammer": ("hammer", "steel"),
    "knight_blade": ("sword", "steel"),
    "knight_relic": ("orb", "steel"),
    "hunter_bow": ("bow", "swamp"),
    "rogue_dagger": ("dagger", "steel"),
    "sage_staff": ("staff", "arcane"),
    "tide_boots": ("boots", "tide"),
    # Jewellery
    "gold_ring": ("ring", "gold"),
    "silver_ring": ("ring", "silver"),
    "jade_amulet": ("amulet", "jade"),
    "ruby_amulet": ("amulet", "ruby"),
    "void_amulet": ("amulet", "void"),
    # Aumbral (top rarity, formerly named "mythic")
    "mythic_aegis": ("shield", "aumbral"),
    "mythic_blade": ("greatsword", "aumbral"),
    "mythic_crown": ("crown", "aumbral"),
    "mythic_ring": ("ring", "aumbral"),
    # Relics
    "relic_bloodstone": ("orb", "blood"),
    "blood_relic_stone": ("orb", "blood"),
    "relic_frost_shard": ("crystal", "frost"),
    "relic_shadow_veil": ("veil", "shadow"),
    "shadow_relic_veil": ("veil", "shadow"),
    "relic_stone_heart": ("heart", "iron"),
    "stone_relic_heart": ("heart", "iron"),
    "relic_sun_medallion": ("medallion", "sun"),
    "sun_relic_medallion": ("medallion", "sun"),
    "relic_wind_charm": ("charm", "wind"),
    "wind_relic_charm": ("charm", "wind"),
    # Charms / buffs
    "bloodlust": ("charm", "blood"),
    "bloodlust_charm": ("charm", "blood"),
    "iron_will": ("charm", "iron"),
    "swift_step": ("charm", "wind"),
    "swift_step_charm": ("charm", "wind"),
    # Consumables and materials
    "health_potion": ("potion", "health"),
    "mana_potion": ("potion", "mana"),
    "stamina_potion": ("potion", "stamina"),
    "elixir_might": ("vial", "flame"),
    "elixir_vigor": ("vial", "jade"),
    "arcane_dust": ("dust", "arcane"),
    "shadow_essence": ("dust", "shadow"),
    "dungeon_key": ("key", "gold"),
    # Endless-mode skip tokens
    "skip_10_floors": ("token", "silver"),
    "skip_50_floors": ("token", "steel"),
    "skip_100_floors": ("token", "gold"),
    "skip_250_floors": ("token", "sun"),
    "skip_500_floors": ("token", "aumbral"),
    # Empty equipment-slot silhouettes
    "slot/helmet": ("helm", "slot"),
    "slot/chest": ("plate", "slot"),
    "slot/gloves": ("gauntlets", "slot"),
    "slot/boots": ("boots", "slot"),
    "slot/weapon": ("sword", "slot"),
    "slot/secondary": ("shield", "slot"),
    "slot/ring": ("ring", "slot"),
    "slot/amulet": ("amulet", "slot"),
    "slot/relic": ("orb", "slot"),
}


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def draw_icon(shape: str, palette: str) -> Image.Image:
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(cell)
    SHAPES[shape](draw, PALETTES[palette])
    return outline(cell)


def outline(cell: Image.Image) -> Image.Image:
    """Dark keyline around the silhouette, so icons hold their shape on any panel colour."""
    pixels = cell.load()
    edges = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    edge_pixels = edges.load()
    for y in range(CELL):
        for x in range(CELL):
            if pixels[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < CELL and 0 <= ny < CELL and pixels[nx, ny][3] != 0:
                    edge_pixels[x, y] = (*OUTLINE, 255)
                    break
    return Image.alpha_composite(edges, cell)


def draw_unknown() -> Image.Image:
    """The manifest's fallback cell. Deliberately unlike any real icon."""
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw = ImageDraw.Draw(cell)
    box(draw, 1, 1, 14, 14, (52, 48, 62))
    draw.rectangle([1, 1, 14, 14], outline=(150, 140, 170))
    for x, y in [(6, 4), (7, 4), (8, 4), (9, 5), (9, 6), (8, 7), (7, 8), (7, 9), (7, 11)]:
        px(draw, x, y, (226, 218, 240))
    return cell


def build(manifest: dict) -> tuple[Image.Image, list[str]]:
    columns = int(manifest["columns"])
    rows = int(manifest["rows"])
    atlas = Image.new("RGBA", (columns * CELL, rows * CELL), (0, 0, 0, 0))
    missing: list[str] = []
    for key, pos in manifest["cells"].items():
        if key == "unknown":
            icon = draw_unknown()
        elif key in ICONS:
            shape, palette = ICONS[key]
            icon = draw_icon(shape, palette)
        else:
            missing.append(key)
            continue
        atlas.paste(icon, (int(pos["col"]) * CELL, int(pos["row"]) * CELL))
    fallback = manifest.get("unknown")
    if fallback:
        atlas.paste(draw_unknown(), (int(fallback["col"]) * CELL, int(fallback["row"]) * CELL))
    return atlas, missing


def check(manifest: dict) -> int:
    if not ATLAS.exists():
        print("MISSING %s" % ATLAS)
        return 1
    current = Image.open(ATLAS).convert("RGBA")
    problems: list[str] = []
    for key in manifest["cells"]:
        if key != "unknown" and key not in ICONS:
            problems.append("%s: no shape mapping" % key)
    for key, pos in manifest["cells"].items():
        left, top = int(pos["col"]) * CELL, int(pos["row"]) * CELL
        crop = current.crop((left, top, left + CELL, top + CELL))
        opaque = sum(1 for pixel in crop.getdata() if pixel[3] > 0)
        if opaque < CELL:
            problems.append("%s: cell is empty or near-empty (%d opaque px)" % (key, opaque))
    if problems:
        for problem in problems:
            print("FAIL %s" % problem)
        return 1
    print("OK %s: %d cells drawn" % (ATLAS.name, len(manifest["cells"])))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify every manifest cell is drawn")
    args = parser.parse_args()
    manifest = load_manifest()
    if args.check:
        return check(manifest)
    atlas, missing = build(manifest)
    if missing:
        for key in missing:
            print("WARN no shape mapping for %s" % key)
    ATLAS.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(ATLAS, optimize=True)
    print("Wrote %s (%d cells)" % (ATLAS.relative_to(ROOT), len(manifest["cells"]) - len(missing)))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
