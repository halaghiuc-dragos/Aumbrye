extends RefCounted
class_name RarityRegistry

## Global rarity tiers, display names, upgrade caps, and mode drop bonuses.

const TIER_ORDER: Array[String] = [
	"common", "magic", "rare", "epic", "legendary", "aumbral",
]

const LEGACY_ALIASES: Dictionary = {
	"mythic": "aumbral",
	"umbral": "aumbral",
}

const DISPLAY_NAMES: Dictionary = {
	"common": "Common",
	"magic": "Magic",
	"rare": "Rare",
	"epic": "Epic",
	"legendary": "Legendary",
	"aumbral": "Aumbral",
}

const FILTER_RARITIES: Array[String] = [
	"all", "common", "magic", "rare", "epic", "legendary", "aumbral",
]

const MODE_RARE_BONUS: Dictionary = {
	"endless": 0.08,
	"waves": 0.06,
}

const DISPLAY_COLORS: Dictionary = {
	"common": Color(0.62, 0.62, 0.62),
	"magic": Color(0.35, 0.45, 1.0),
	"rare": Color(1.0, 0.95, 0.35),
	"epic": Color(0.72, 0.38, 1.0),
	"legendary": Color(1.0, 0.55, 0.15),
	"aumbral": Color(0.25, 0.88, 0.92),
}


static func normalize(rarity: String) -> String:
	var key := rarity.to_lower().strip_edges()
	if LEGACY_ALIASES.has(key):
		return str(LEGACY_ALIASES[key])
	return key if key in TIER_ORDER else "common"


static func display_name(rarity: String) -> String:
	var norm := normalize(rarity)
	return str(DISPLAY_NAMES.get(norm, norm.capitalize()))


static func tier_index(rarity: String) -> int:
	var norm := normalize(rarity)
	return TIER_ORDER.find(norm)


static func max_upgrade_level(rarity: String) -> int:
	return 10 if normalize(rarity) == "aumbral" else 5


static func mode_drop_bonus(run_mode: String) -> float:
	return float(MODE_RARE_BONUS.get(run_mode, 0.0))


static func is_aumbral(rarity: String) -> bool:
	return normalize(rarity) == "aumbral"


static func display_color(rarity: String) -> Color:
	var norm := normalize(rarity)
	return DISPLAY_COLORS.get(norm, DISPLAY_COLORS["common"]) as Color


static func slot_background_color(rarity: String) -> Color:
	return display_color(rarity).darkened(0.72)
