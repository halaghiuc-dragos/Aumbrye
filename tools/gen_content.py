import json
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CONTENT = os.path.join(ROOT, "content")
ITEMS = os.path.join(CONTENT, "items")
EQUIP_DIR = os.path.join(ITEMS, "equipment")
CONS_DIR = os.path.join(ITEMS, "consumables")
MAT_DIR = os.path.join(ITEMS, "materials")
QUEST_DIR = os.path.join(ITEMS, "quest")
AFFIX_DIR = os.path.join(CONTENT, "affixes")
RECIPE_DIR = os.path.join(CONTENT, "recipes")

FRACTION_STATS = {
    "critChance",
    "poiseDamage",
    "blockReduction",
    "damageReduction",
    "staminaRegen",
    "staminaCostReduction",
    "moveSpeed",
    "manaRegen",
    "lootQuality",
    "xpGain",
    "goldFind",
    "cooldownReduction",
    "resistPhysical",
    "resistFire",
    "resistFrost",
    "resistPoison",
    "resistLightning",
    "resistArcane",
}

TIER_ORDER = ["common", "magic", "rare", "epic", "legendary", "aumbral"]
TIER_SCALE = [1.0, 2.0, 3.4, 5.0, 7.0, 9.5]


def write_json(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def read_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def quantise(stat, value):
    if stat in FRACTION_STATS:
        return round(value, 3)
    return int(round(value))


def scale_stats(stats, multiplier):
    out = {}
    for stat, value in stats.items():
        scaled = quantise(stat, value * multiplier)
        if scaled:
            out[stat] = scaled
    return out


def scaling_line(scaling):
    if not scaling:
        return ""
    parts = ["%s %s" % (key.capitalize(), grade) for key, grade in scaling.items()]
    return "Scaling: " + ", ".join(parts) + "."


def generate_equipment(bases):
    archetypes = {entry["id"]: entry for entry in bases["archetypes"]}
    written = []
    for tier in bases["materialTiers"]:
        for arch_id in tier["archetypes"]:
            arch = archetypes[arch_id]
            item_id = "%s_%s" % (tier["id"], arch_id)
            stats = scale_stats(arch["implicit"], tier["statMultiplier"])
            for stat, value in tier.get("resist", {}).items():
                stats[stat] = quantise(stat, value)
            description = " ".join(
                part for part in [arch["line"], tier["line"], scaling_line(arch.get("scaling"))] if part
            )
            item = {
                "id": item_id,
                "name": "%s %s" % (tier["name"], arch["noun"]),
                "itemType": arch["itemType"],
                "equipmentSlot": arch["equipmentSlot"],
                "gridWidth": arch["gridWidth"],
                "gridHeight": arch["gridHeight"],
                "stackSize": 1,
                "rarity": tier["rarity"],
                "description": description,
                "value": int(round(arch["baseValue"] * tier["valueMultiplier"])),
                "lootValue": int(round(arch["baseValue"] * tier["valueMultiplier"] * 0.5)),
                "maxDurability": arch["maxDurability"],
                "baseId": arch_id,
                "materialTier": tier["id"],
                "biome": tier["biome"],
                "scaling": arch.get("scaling", {}),
                "stats": stats,
            }
            if arch.get("weaponId"):
                item["weaponId"] = arch["weaponId"]
            if arch.get("block"):
                item["block"] = dict(arch["block"])
            write_json(os.path.join(EQUIP_DIR, item_id + ".json"), item)
            written.append(item_id)
    return written


def generate_uniques(bases, uniques):
    archetypes = {entry["id"]: entry for entry in bases["archetypes"]}
    written = []
    for entry in uniques["uniques"]:
        arch = archetypes[entry["archetype"]]
        item = {
            "id": entry["id"],
            "name": entry["name"],
            "itemType": arch["itemType"],
            "equipmentSlot": arch["equipmentSlot"],
            "gridWidth": arch["gridWidth"],
            "gridHeight": arch["gridHeight"],
            "stackSize": 1,
            "rarity": entry["rarity"],
            "description": entry["description"],
            "value": entry["value"],
            "lootValue": int(round(entry["value"] * 0.5)),
            "maxDurability": arch["maxDurability"],
            "unique": True,
            "baseId": entry["archetype"],
            "biome": entry["biome"],
            "scaling": arch.get("scaling", {}),
            "ruleText": entry["ruleText"],
            "rules": entry["rules"],
            "stats": entry["stats"],
        }
        if arch.get("weaponId"):
            item["weaponId"] = arch["weaponId"]
        if arch.get("block"):
            item["block"] = dict(arch["block"])
        write_json(os.path.join(EQUIP_DIR, entry["id"] + ".json"), item)
        written.append(entry["id"])
    return written


FOOTPRINTS = [
    (r"greatsword|warlord_blade|glacier_sword", (2, 4)),
    (r"hammer|maul", (2, 4)),
    (r"banner", (1, 4)),
    (r"spear|halberd|pike", (1, 4)),
    (r"staff|rod", (1, 4)),
    (r"bow", (2, 3)),
    (r"dagger|knife|shiv", (1, 2)),
    (r"sword|blade|sabre|rapier", (2, 3)),
    (r"buckler", (2, 2)),
    (r"aegis|shield", (2, 3)),
    (r"ring", (1, 1)),
    (r"amulet|charm|pendant|talisman|chalice", (1, 2)),
    (r"helm|crown|hood|mask", (2, 2)),
    (r"gauntlet|glove", (2, 2)),
    (r"boots|greaves|sabaton", (2, 2)),
    (r"plate|cloak|cuirass|mail|robe|vest", (2, 3)),
]


def normalise_footprints():
    changed = []
    for name in sorted(os.listdir(EQUIP_DIR)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(EQUIP_DIR, name)
        item = read_json(path)
        if item.get("baseId") or item.get("unique"):
            continue
        key = (item.get("id", "") + " " + item.get("name", "")).lower()
        for pattern, (width, height) in FOOTPRINTS:
            if re.search(pattern, key):
                if item.get("gridWidth") != width or item.get("gridHeight") != height:
                    item["gridWidth"] = width
                    item["gridHeight"] = height
                    write_json(path, item)
                    changed.append(item["id"])
                break
    return changed


AFFIXES = [
    ("sharp", "Sharp", "prefix", "physicalDamage", ["weapon"], 100, (2, 4)),
    ("vicious", "Vicious", "prefix", "physicalDamage", ["weapon"], 90, (3, 5)),
    ("keen", "Keen", "prefix", "critChance", ["weapon"], 80, (0.01, 0.02)),
    ("executioners", "Executioner's", "prefix", "critChance", ["weapon"], 40, (0.015, 0.025)),
    ("arcane", "Arcane", "prefix", "arcaneDamage", ["weapon"], 70, (2, 4)),
    ("blazing", "Blazing", "prefix", "fireDamage", ["weapon"], 70, (2, 4)),
    ("rimed", "Rimed", "prefix", "frostDamage", ["weapon"], 70, (2, 4)),
    ("septic", "Septic", "prefix", "poisonDamage", ["weapon"], 70, (2, 4)),
    ("heavy", "Heavy", "prefix", "poiseDamage", ["weapon"], 60, (0.02, 0.04)),
    ("brutal", "Brutal", "prefix", "damagePercent", ["weapon"], 50, (2, 3)),
    ("swift", "Swift", "prefix", "cooldownReduction", ["weapon", "accessory"], 45, (0.01, 0.02)),
    ("hungry", "Hungry", "prefix", "bonusDamage", ["weapon"], 55, (2, 3)),
    ("sturdy", "Sturdy", "prefix", "armor", ["weapon", "armor"], 90, (1, 3)),
    ("fortified", "Fortified", "prefix", "defense", ["armor"], 85, (2, 4)),
    ("nimble", "Nimble", "prefix", "staminaRegen", ["weapon", "armor"], 80, (0.01, 0.02)),
    ("bulwark", "Bulwark", "prefix", "blockReduction", ["armor"], 40, (0.01, 0.02)),
    ("stalwart", "Stalwart", "prefix", "poise", ["armor"], 70, (1, 3)),
    ("warded", "Warded", "prefix", "damageReduction", ["armor"], 35, (0.01, 0.015)),
    ("padded", "Padded", "prefix", "maxHealth", ["armor"], 85, (6, 12)),
    ("lightfoot", "Lightfoot", "prefix", "evasion", ["armor"], 70, (1, 3)),
    ("gilded", "Gilded", "prefix", "goldFind", ["armor", "accessory"], 45, (0.02, 0.04)),
    ("scholars", "Scholar's", "prefix", "xpGain", ["armor", "accessory"], 40, (0.02, 0.03)),
    ("fortunate", "Fortunate", "prefix", "lootQuality", ["accessory"], 30, (0.01, 0.02)),
    ("vital", "Vital", "prefix", "healthRegen", ["armor", "accessory"], 60, (1, 2)),
    ("attuned", "Attuned", "prefix", "manaMax", ["armor", "accessory"], 65, (5, 10)),
    ("tireless", "Tireless", "prefix", "staminaMax", ["armor", "accessory"], 70, (3, 6)),
    ("of_the_bear", "of the Bear", "suffix", "maxHealth", ["armor", "weapon"], 90, (5, 10)),
    ("of_flames", "of Flames", "suffix", "fireDamage", ["weapon"], 75, (2, 4)),
    ("of_frost", "of Frost", "suffix", "frostDamage", ["weapon"], 75, (2, 4)),
    ("of_poison", "of Poison", "suffix", "poisonDamage", ["weapon"], 75, (2, 4)),
    ("of_haste", "of Haste", "suffix", "moveSpeed", ["armor", "weapon"], 70, (0.01, 0.02)),
    ("of_vigor", "of Vigor", "suffix", "staminaRegen", ["armor", "weapon"], 80, (0.01, 0.02)),
    ("of_the_eagle", "of the Eagle", "suffix", "critChance", ["weapon"], 60, (0.01, 0.02)),
    ("of_the_storm", "of the Storm", "suffix", "bonusDamage", ["weapon"], 55, (2, 4)),
    ("of_ruin", "of Ruin", "suffix", "damagePercent", ["weapon"], 45, (2, 3)),
    ("of_the_wolf", "of the Wolf", "suffix", "moveSpeedPercent", ["armor"], 50, (2, 3)),
    ("of_the_ox", "of the Ox", "suffix", "staminaMax", ["armor", "weapon"], 70, (3, 6)),
    ("of_the_deep", "of the Deep", "suffix", "manaMax", ["armor", "accessory"], 65, (5, 10)),
    ("of_the_spring", "of the Spring", "suffix", "manaRegen", ["accessory", "armor"], 50, (0.01, 0.02)),
    ("of_endurance", "of Endurance", "suffix", "staminaCostReduction", ["armor"], 45, (0.01, 0.02)),
    ("of_the_mountain", "of the Mountain", "suffix", "poise", ["armor"], 65, (1, 3)),
    ("of_the_tower", "of the Tower", "suffix", "defense", ["armor"], 80, (2, 4)),
    ("of_warding", "of Warding", "suffix", "resistArcane", ["armor", "accessory"], 55, (0.02, 0.03)),
    ("of_embers", "of Embers", "suffix", "resistFire", ["armor", "accessory"], 55, (0.02, 0.03)),
    ("of_the_thaw", "of the Thaw", "suffix", "resistFrost", ["armor", "accessory"], 55, (0.02, 0.03)),
    ("of_the_fen", "of the Fen", "suffix", "resistPoison", ["armor", "accessory"], 55, (0.02, 0.03)),
    ("of_the_stormwall", "of the Stormwall", "suffix", "resistLightning", ["armor", "accessory"], 55, (0.02, 0.03)),
    ("of_stone", "of Stone", "suffix", "resistPhysical", ["armor"], 50, (0.02, 0.03)),
    ("of_avarice", "of Avarice", "suffix", "goldFind", ["accessory", "armor"], 40, (0.02, 0.04)),
    ("of_seeking", "of Seeking", "suffix", "lootQuality", ["accessory"], 30, (0.01, 0.02)),
    ("of_the_scholar", "of the Scholar", "suffix", "xpGain", ["accessory", "armor"], 35, (0.02, 0.03)),
    ("of_recovery", "of Recovery", "suffix", "healthRegen", ["armor", "accessory"], 55, (1, 2)),
]


def build_tiers(stat, base):
    low, high = base
    tiers = {}
    for index, name in enumerate(TIER_ORDER):
        factor = TIER_SCALE[index]
        min_v = quantise(stat, low * factor)
        max_v = quantise(stat, high * factor)
        if max_v <= min_v:
            max_v = min_v + (0.005 if stat in FRACTION_STATS else 1)
            max_v = quantise(stat, max_v)
        tiers[name] = {"min": min_v, "max": max_v}
    return tiers


def generate_affixes():
    packs = {"prefix": [], "suffix": []}
    for affix_id, display, kind, stat, item_types, weight, base in AFFIXES:
        packs[kind].append(
            {
                "id": affix_id,
                "displayName": display,
                "kind": kind,
                "stat": stat,
                "itemTypes": item_types,
                "weight": weight,
                "template": "+{value} {stat}",
                "tiers": build_tiers(stat, base),
            }
        )
    write_json(
        os.path.join(AFFIX_DIR, "prefixes.json"),
        {"schemaVersion": 1, "affixes": packs["prefix"]},
    )
    write_json(
        os.path.join(AFFIX_DIR, "suffixes.json"),
        {"schemaVersion": 1, "affixes": packs["suffix"]},
    )
    return len(packs["prefix"]), len(packs["suffix"])


CONSUMABLES = [
    {
        "id": "flask_dregs",
        "name": "Flask Dregs",
        "grid": (1, 1),
        "stack": 5,
        "rarity": "common",
        "value": 60,
        "description": "What settles at the bottom of somebody else's flask. It still counts.",
        "effect": {"kind": "refillFlask", "amount": 1, "usableInHub": False},
    },
    {
        "id": "flask_deep_draught",
        "name": "Deep Draught",
        "grid": (1, 2),
        "stack": 3,
        "rarity": "rare",
        "value": 180,
        "description": "Drawn from the well beneath the chapel, where the rope runs out before the water does.",
        "effect": {"kind": "refillFlask", "amount": 2, "usableInHub": False},
    },
    {
        "id": "flask_ashen_measure",
        "name": "Ashen Measure",
        "grid": (1, 1),
        "stack": 5,
        "rarity": "magic",
        "value": 110,
        "description": "Measured out by the spoonful, by someone who expected to need it later.",
        "effect": {"kind": "refillFlask", "amount": 1, "usableInHub": False},
    },
    {
        "id": "firebomb",
        "name": "Firebomb",
        "grid": (1, 1),
        "stack": 8,
        "rarity": "common",
        "value": 45,
        "description": "Pitch in a clay shell. Thrown underarm, and thrown early.",
        "effect": {
            "kind": "throw",
            "statusId": "burn",
            "duration": 10,
            "radius": 4.5,
            "usableInHub": False,
        },
    },
    {
        "id": "frost_flask",
        "name": "Frost Flask",
        "grid": (1, 1),
        "stack": 8,
        "rarity": "magic",
        "value": 70,
        "description": "Cold enough that the glass is the part you have to be careful with.",
        "effect": {
            "kind": "throw",
            "statusId": "freeze",
            "duration": 4,
            "radius": 4.0,
            "usableInHub": False,
        },
    },
    {
        "id": "venom_pot",
        "name": "Venom Pot",
        "grid": (1, 1),
        "stack": 8,
        "rarity": "common",
        "value": 50,
        "description": "Fen-brewed. The seal is wax and the wax is not reliable.",
        "effect": {
            "kind": "throw",
            "statusId": "poison",
            "duration": 12,
            "radius": 4.5,
            "usableInHub": False,
        },
    },
    {
        "id": "caltrops",
        "name": "Caltrops",
        "grid": (1, 1),
        "stack": 8,
        "rarity": "common",
        "value": 40,
        "description": "Scattered behind you, and remembered too late by whoever follows.",
        "effect": {
            "kind": "throw",
            "statusId": "bleed",
            "duration": 8,
            "radius": 3.5,
            "usableInHub": False,
        },
    },
    {
        "id": "thunder_stone",
        "name": "Thunder Stone",
        "grid": (1, 1),
        "stack": 6,
        "rarity": "rare",
        "value": 120,
        "description": "Struck against the floor. The noise arrives before the decision to use it does.",
        "effect": {
            "kind": "throw",
            "statusId": "stun",
            "duration": 3,
            "radius": 5.0,
            "usableInHub": False,
        },
    },
    {
        "id": "alchemists_fire",
        "name": "Alchemist's Fire",
        "grid": (1, 2),
        "stack": 4,
        "rarity": "epic",
        "value": 260,
        "description": "The recipe was kept in one head and that head is not available for questions.",
        "effect": {
            "kind": "throw",
            "statusId": "burn",
            "duration": 20,
            "radius": 6.0,
            "usableInHub": False,
        },
    },
    {
        "id": "elixir_iron_skin",
        "name": "Elixir of Iron Skin",
        "grid": (1, 2),
        "stack": 5,
        "rarity": "magic",
        "value": 90,
        "description": "Thick and grey and difficult to swallow, which is said to be the point.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_iron_skin",
            "duration": 90,
            "stat": "armor",
            "amount": 20,
        },
    },
    {
        "id": "elixir_swiftness",
        "name": "Elixir of Swiftness",
        "grid": (1, 2),
        "stack": 5,
        "rarity": "magic",
        "value": 95,
        "description": "The taste does not last. Neither does the effect. Both are remembered fondly.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_swiftness",
            "duration": 60,
            "stat": "moveSpeed",
            "amount": 0.15,
        },
    },
    {
        "id": "elixir_clarity",
        "name": "Elixir of Clarity",
        "grid": (1, 2),
        "stack": 5,
        "rarity": "rare",
        "value": 140,
        "description": "Distilled in the cathedral cellars, for readers who worked past the last candle.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_clarity",
            "duration": 90,
            "stat": "manaMax",
            "amount": 40,
        },
    },
    {
        "id": "elixir_focus",
        "name": "Elixir of Focus",
        "grid": (1, 2),
        "stack": 5,
        "rarity": "rare",
        "value": 150,
        "description": "Narrows the world to the width of an arm's reach. Everything outside that stops mattering.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_focus",
            "duration": 60,
            "stat": "critChance",
            "amount": 0.1,
        },
    },
    {
        "id": "elixir_warding",
        "name": "Elixir of Warding",
        "grid": (1, 2),
        "stack": 5,
        "rarity": "epic",
        "value": 220,
        "description": "Poured over the tongue rather than drunk. The distinction was insisted upon.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_warding",
            "duration": 90,
            "stat": "damageReduction",
            "amount": 0.12,
        },
    },
    {
        "id": "whetstone_ember",
        "name": "Ember Whetstone",
        "grid": (1, 1),
        "stack": 5,
        "rarity": "magic",
        "value": 100,
        "description": "Draw it once along the edge. The heat stays in the steel longer than in the stone.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_ember_edge",
            "duration": 120,
            "stat": "fireDamage",
            "amount": 12,
            "usableInHub": False,
        },
    },
    {
        "id": "whetstone_rime",
        "name": "Rime Whetstone",
        "grid": (1, 1),
        "stack": 5,
        "rarity": "magic",
        "value": 100,
        "description": "Cold to hold. The edge frosts over between strokes.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_rime_edge",
            "duration": 120,
            "stat": "frostDamage",
            "amount": 12,
            "usableInHub": False,
        },
    },
    {
        "id": "whetstone_venom",
        "name": "Venom Whetstone",
        "grid": (1, 1),
        "stack": 5,
        "rarity": "magic",
        "value": 100,
        "description": "Handled with a rag. The rag is thrown away afterward.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_venom_edge",
            "duration": 120,
            "stat": "poisonDamage",
            "amount": 12,
            "usableInHub": False,
        },
    },
    {
        "id": "whetstone_arcane",
        "name": "Arcane Whetstone",
        "grid": (1, 1),
        "stack": 5,
        "rarity": "rare",
        "value": 170,
        "description": "It sharpens nothing. The blade cuts better regardless, which nobody has explained.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_arcane_edge",
            "duration": 120,
            "stat": "arcaneDamage",
            "amount": 14,
            "usableInHub": False,
        },
    },
    {
        "id": "homeward_bone",
        "name": "Homeward Bone",
        "grid": (1, 1),
        "stack": 3,
        "rarity": "rare",
        "value": 200,
        "description": "A finger bone, filed smooth by the thumb of whoever carried it last.",
        "effect": {"kind": "escape", "usableInHub": False},
    },
    {
        "id": "escape_stone",
        "name": "Escape Stone",
        "grid": (1, 2),
        "stack": 2,
        "rarity": "epic",
        "value": 380,
        "description": "Ends the descent on your terms. Whatever you are carrying comes back with you.",
        "effect": {"kind": "escape", "usableInHub": False},
    },
    {
        "id": "everburning_torch",
        "name": "Everburning Torch",
        "grid": (1, 2),
        "stack": 1,
        "rarity": "rare",
        "value": 240,
        "description": "It has never gone out. That is the whole of what is known about it.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_torchlight",
            "duration": 180,
            "stat": "lootQuality",
            "amount": 0.2,
            "usableInHub": False,
        },
    },
    {
        "id": "seekers_lantern",
        "name": "Seeker's Lantern",
        "grid": (1, 2),
        "stack": 1,
        "rarity": "epic",
        "value": 360,
        "description": "The flame leans toward whatever is hidden, and away from whoever is holding it.",
        "effect": {
            "kind": "applyStatus",
            "statusId": "elixir_seeking",
            "duration": 240,
            "stat": "lootQuality",
            "amount": 0.35,
            "usableInHub": False,
        },
    },
    {
        "id": "antidote",
        "name": "Antidote",
        "grid": (1, 1),
        "stack": 8,
        "rarity": "common",
        "value": 35,
        "description": "Bitter, and worth it. Clears whatever is currently working on you.",
        "effect": {"kind": "cure"},
    },
    {
        "id": "bloodstaunch",
        "name": "Bloodstaunch",
        "grid": (1, 1),
        "stack": 8,
        "rarity": "common",
        "value": 45,
        "description": "Moss packed in a twist of linen. Field medicine, from a field that lost.",
        "effect": {"kind": "heal", "amount": 65},
    },
    {
        "id": "greater_health_potion",
        "name": "Greater Health Potion",
        "grid": (1, 1),
        "stack": 5,
        "rarity": "magic",
        "value": 60,
        "description": "Twice the measure, at rather more than twice the price.",
        "effect": {"kind": "heal", "amount": 110},
    },
    {
        "id": "greater_stamina_potion",
        "name": "Greater Stamina Potion",
        "grid": (1, 1),
        "stack": 5,
        "rarity": "magic",
        "value": 55,
        "description": "Drunk between rooms, by people who have learned to count doors.",
        "effect": {"kind": "restoreStamina", "amount": 90},
    },
    {
        "id": "greater_mana_potion",
        "name": "Greater Mana Potion",
        "grid": (1, 1),
        "stack": 5,
        "rarity": "magic",
        "value": 65,
        "description": "Kept in a leaded bottle, because the ordinary kind does not hold it.",
        "effect": {"kind": "restoreMana", "amount": 90},
    },
]


def generate_consumables():
    written = []
    for entry in CONSUMABLES:
        effect = dict(entry["effect"])
        item = {
            "id": entry["id"],
            "name": entry["name"],
            "itemType": "consumable",
            "gridWidth": entry["grid"][0],
            "gridHeight": entry["grid"][1],
            "stackSize": entry["stack"],
            "rarity": entry["rarity"],
            "description": entry["description"],
            "consumableEffect": effect,
            "value": entry["value"],
            "lootValue": int(round(entry["value"] * 0.5)),
        }
        write_json(os.path.join(CONS_DIR, entry["id"] + ".json"), item)
        written.append(entry["id"])
    return written


MATERIAL_TIER_IDS = {
    1: "pitiron",
    2: "graysteel",
    3: "mirebrass",
    4: "hoarfrost",
    5: "reliquary",
    6: "spellglass",
}

MATERIALS = [
    ("pitiron_slag", "Pit-Iron Slag", 1, 6, "Skimmed off the top and never thrown away."),
    ("graysteel_ingot", "Graysteel Ingot", 2, 14, "Stamped with a vault mark and a number nobody kept the ledger for."),
    ("mirebrass_dross", "Mirebrass Dross", 3, 24, "Green residue, scraped from the crucible with a flat blade."),
    ("hoarfrost_shard", "Hoarfrost Shard", 4, 40, "It does not melt in the hand. It does not warm, either."),
    ("reliquary_gilt", "Reliquary Gilt", 5, 62, "Gold leaf lifted from a case that held something else."),
    ("spellglass_sliver", "Spellglass Sliver", 6, 90, "Sharp on every plane. There is no safe way to hold it."),
    ("cinder_dust", "Cinder Dust", 1, 4, "What a common thing becomes when the forge takes it back."),
    ("glimmer_ash", "Glimmer Ash", 2, 12, "It catches light that is not in the room."),
    ("sable_grain", "Sable Grain", 3, 28, "Coarse and black, and heavier than it looks by a noticeable margin."),
    ("storm_salt", "Storm Salt", 4, 55, "Gathered where lightning met stone. It hums against the jar."),
    ("aumbral_tear", "Aumbral Tear", 5, 120, "It does not evaporate and it does not freeze. It waits."),
    ("ember_catalyst", "Ember Catalyst", 3, 45, "Fire that has been persuaded to stay in one place."),
    ("rime_catalyst", "Rime Catalyst", 3, 45, "Cold that has been persuaded of the same thing."),
    ("venom_catalyst", "Venom Catalyst", 3, 45, "Sealed twice, because once was found to be optimistic."),
    ("arcane_catalyst", "Arcane Catalyst", 4, 70, "The jar is unmarked. The contents object to being described."),
    ("storm_catalyst", "Storm Catalyst", 4, 70, "It stands the hair up on the arm holding it."),
    (
        "reforging_stone",
        "Reforging Stone",
        4,
        85,
        "Worn concave by use. Every stroke takes something out and puts nothing back.",
    ),
    ("transmutation_seal", "Transmutation Seal", 5, 160, "Pressed into wax, once, by a hand that then broke the die."),
    ("binding_thread", "Binding Thread", 5, 140, "Spun from something that was already spun once."),
    ("whetting_oil", "Whetting Oil", 2, 18, "Pressed from swamp seed. It keeps rust off and keeps nothing else."),
    (
        "hardening_quench",
        "Hardening Quench",
        3,
        34,
        "Water from under the fortress. It has been cold for a very long time.",
    ),
    ("bog_resin", "Bog Resin", 2, 16, "Amber-dark and slow. Something small is suspended in the middle of it."),
    ("chapel_wax", "Chapel Wax", 3, 30, "Poured off the candle stubs at the end of a service that ran late."),
    (
        "vault_sealing_wax",
        "Vault Sealing Wax",
        2,
        20,
        "Red, brittle, and stamped with an office that no longer exists.",
    ),
    ("cracked_lodestone", "Cracked Lodestone", 4, 66, "It still points. It points at the floor."),
]


def generate_materials():
    written = []
    for material_id, name, tier, value, description in MATERIALS:
        item = {
            "id": material_id,
            "name": name,
            "itemType": "material",
            "gridWidth": 1,
            "gridHeight": 1,
            "stackSize": 20,
            "description": description,
            "value": value,
            "lootValue": max(1, int(round(value * 0.6))),
            "materialTier": MATERIAL_TIER_IDS[tier],
        }
        write_json(os.path.join(MAT_DIR, material_id + ".json"), item)
        written.append(material_id)
    return written


RECIPES = [
    {
        "id": "forge_salvage",
        "type": "salvage",
        "itemId": "any",
        "goldCost": 0,
    },
    {
        "id": "forge_reroll_affix",
        "type": "reroll",
        "itemId": "any",
        "goldCost": 300,
        "materials": [
            {"itemId": "reforging_stone", "quantity": 1},
            {"itemId": "sable_grain", "quantity": 4},
        ],
    },
    {
        "id": "forge_transmute_rarity",
        "type": "transmute",
        "itemId": "any",
        "goldCost": 900,
        "materials": [
            {"itemId": "transmutation_seal", "quantity": 1},
            {"itemId": "storm_salt", "quantity": 6},
        ],
    },
    {
        "id": "forge_transfer_rule",
        "type": "transfer",
        "itemId": "any",
        "goldCost": 2400,
        "materials": [
            {"itemId": "binding_thread", "quantity": 2},
            {"itemId": "aumbral_tear", "quantity": 3},
        ],
    },
    {
        "id": "forge_infuse_fire",
        "type": "infuse",
        "itemId": "any",
        "goldCost": 400,
        "materials": [
            {"itemId": "ember_catalyst", "quantity": 2},
            {"itemId": "whetting_oil", "quantity": 3},
        ],
    },
    {
        "id": "forge_infuse_frost",
        "type": "infuse",
        "itemId": "any",
        "goldCost": 400,
        "materials": [
            {"itemId": "rime_catalyst", "quantity": 2},
            {"itemId": "hardening_quench", "quantity": 3},
        ],
    },
    {
        "id": "forge_infuse_poison",
        "type": "infuse",
        "itemId": "any",
        "goldCost": 400,
        "materials": [
            {"itemId": "venom_catalyst", "quantity": 2},
            {"itemId": "bog_resin", "quantity": 3},
        ],
    },
    {
        "id": "forge_infuse_arcane",
        "type": "infuse",
        "itemId": "any",
        "goldCost": 650,
        "materials": [
            {"itemId": "arcane_catalyst", "quantity": 2},
            {"itemId": "chapel_wax", "quantity": 3},
        ],
    },
    {
        "id": "forge_infuse_lightning",
        "type": "infuse",
        "itemId": "any",
        "goldCost": 650,
        "materials": [
            {"itemId": "storm_catalyst", "quantity": 2},
            {"itemId": "cracked_lodestone", "quantity": 2},
        ],
    },
    {
        "id": "forge_convert_cinder_to_glimmer",
        "type": "convert",
        "itemId": "glimmer_ash",
        "goldCost": 60,
        "materials": [{"itemId": "cinder_dust", "quantity": 5}],
    },
    {
        "id": "forge_convert_glimmer_to_sable",
        "type": "convert",
        "itemId": "sable_grain",
        "goldCost": 140,
        "materials": [{"itemId": "glimmer_ash", "quantity": 5}],
    },
    {
        "id": "forge_convert_sable_to_storm",
        "type": "convert",
        "itemId": "storm_salt",
        "goldCost": 320,
        "materials": [{"itemId": "sable_grain", "quantity": 5}],
    },
    {
        "id": "forge_convert_storm_to_tear",
        "type": "convert",
        "itemId": "aumbral_tear",
        "goldCost": 700,
        "materials": [{"itemId": "storm_salt", "quantity": 5}],
    },
]


def generate_recipes():
    written = []
    for recipe in RECIPES:
        write_json(os.path.join(RECIPE_DIR, recipe["id"] + ".json"), recipe)
        written.append(recipe["id"])
    return written


def rebuild_catalog():
    def ids_in(directory):
        found = []
        for name in sorted(os.listdir(directory)):
            if not name.endswith(".json"):
                continue
            found.append(read_json(os.path.join(directory, name))["id"])
        return found

    equipment = ids_in(EQUIP_DIR)
    consumables = ids_in(CONS_DIR)
    materials = ids_in(MAT_DIR) + ids_in(QUEST_DIR)
    catalog = {
        "schemaVersion": 1,
        "equipment": sorted(equipment),
        "consumables": sorted(consumables),
        "materials": sorted(materials),
    }
    write_json(os.path.join(ITEMS, "catalog.json"), catalog)
    return catalog


def main():
    bases = read_json(os.path.join(ROOT, "tools", "item_bases.json"))
    uniques = read_json(os.path.join(ROOT, "tools", "uniques.json"))
    generated = generate_equipment(bases)
    authored = generate_uniques(bases, uniques)
    reshaped = normalise_footprints()
    prefix_count, suffix_count = generate_affixes()
    consumables = generate_consumables()
    materials = generate_materials()
    recipes = generate_recipes()
    catalog = rebuild_catalog()
    print("generated equipment: %d" % len(generated))
    print("uniques: %d" % len(authored))
    print("footprints reshaped: %d" % len(reshaped))
    print("affixes: %d prefixes, %d suffixes" % (prefix_count, suffix_count))
    print("new consumables: %d" % len(consumables))
    print("new materials: %d" % len(materials))
    print("new recipes: %d" % len(recipes))
    print(
        "catalog: %d equipment, %d consumables, %d materials"
        % (
            len(catalog["equipment"]),
            len(catalog["consumables"]),
            len(catalog["materials"]),
        )
    )


if __name__ == "__main__":
    main()
