extends RefCounted
class_name Equipment

const ItemQualityScript := preload("res://scripts/items/item_quality.gd")


const SLOT_ORDER: Array[String] = [
	"helmet",
	"chest",
	"gloves",
	"boots",
	"weapon",
	"secondary",
	"ring",
	"amulet",
	"relic",
]

const STAT_KEYS: Array[String] = [
	"maxHealth",
	"healthRegen",
	"evasion",
	"defense",
	"damagePercent",
	"moveSpeedPercent",
	"staminaMax",
	"bonusDamage",
	"critChance",
	"poiseDamage",
	"armor",
	"blockReduction",
	"poise",
	"staminaRegen",
	"staminaCostReduction",
	"damageReduction",
	"moveSpeed",
	"manaMax",
	"manaRegen",
	"resistPhysical",
	"resistFire",
	"resistFrost",
	"resistPoison",
	"resistLightning",
	"resistArcane",
	"lootQuality",
	"xpGain",
	"goldFind",
	"cooldownReduction",
	# Carried on gear since the first loot pass but absent from this list, so slot_stats never
	# summed it and nothing downstream could read it. It scales how fast the player swings.
	"attackSpeed",
]

const FLAT_DAMAGE_STAT_KEYS: Array[String] = [
	"physicalDamage",
	"fireDamage",
	"frostDamage",
	"arcaneDamage",
	"poisonDamage",
]

const UNIT_FLAT := 0
const UNIT_PERCENT := 1
const UNIT_FRACTION := 2

const STAT_DISPLAY: Dictionary = {
	"maxHealth": {"key": "STAT_MAX_HEALTH", "label": "Health", "unit": UNIT_FLAT},
	"healthRegen": {"key": "STAT_HEALTH_REGEN", "label": "Health Regen", "unit": UNIT_FLAT},
	"evasion": {"key": "STAT_EVASION", "label": "Evasion", "unit": UNIT_FLAT},
	"defense": {"key": "STAT_DEFENSE", "label": "Defense", "unit": UNIT_FLAT},
	"damagePercent": {"key": "STAT_DAMAGE_PERCENT", "label": "Damage", "unit": UNIT_PERCENT},
	"moveSpeedPercent": {"key": "STAT_MOVE_SPEED_PCT", "label": "Move Speed", "unit": UNIT_PERCENT},
	"staminaMax": {"key": "STAT_STAMINA_MAX", "label": "Stamina", "unit": UNIT_FLAT},
	"bonusDamage": {"key": "STAT_BONUS_DAMAGE", "label": "Attack Damage", "unit": UNIT_FLAT},
	"critChance": {"key": "STAT_CRIT_CHANCE", "label": "Critical Chance", "unit": UNIT_FRACTION},
	"poiseDamage": {"key": "STAT_POISE_DAMAGE", "label": "Poise Damage", "unit": UNIT_FRACTION},
	"armor": {"key": "STAT_ARMOR", "label": "Armor", "unit": UNIT_FLAT},
	"blockReduction":
	{"key": "STAT_BLOCK_REDUCTION", "label": "Block Reduction", "unit": UNIT_FRACTION},
	"poise": {"key": "STAT_POISE", "label": "Poise", "unit": UNIT_FLAT},
	"staminaRegen": {"key": "STAT_STAMINA_REGEN", "label": "Stamina Regen", "unit": UNIT_FRACTION},
	"staminaCostReduction":
	{"key": "STAT_STAMINA_COST_RED", "label": "Stamina Cost Reduction", "unit": UNIT_FRACTION},
	"damageReduction":
	{"key": "STAT_DAMAGE_REDUCTION", "label": "Damage Reduction", "unit": UNIT_FRACTION},
	"moveSpeed": {"key": "STAT_MOVE_SPEED", "label": "Move Speed", "unit": UNIT_FRACTION},
	"manaMax": {"key": "STAT_MANA_MAX", "label": "Mana", "unit": UNIT_FLAT},
	"manaRegen": {"key": "STAT_MANA_REGEN", "label": "Mana Regen", "unit": UNIT_FRACTION},
	"resistPhysical":
	{"key": "STAT_RESIST_PHYSICAL", "label": "Physical Resistance", "unit": UNIT_FRACTION},
	"resistFire": {"key": "STAT_RESIST_FIRE", "label": "Fire Resistance", "unit": UNIT_FRACTION},
	"resistFrost": {"key": "STAT_RESIST_FROST", "label": "Frost Resistance", "unit": UNIT_FRACTION},
	"resistPoison":
	{"key": "STAT_RESIST_POISON", "label": "Poison Resistance", "unit": UNIT_FRACTION},
	"resistLightning":
	{"key": "STAT_RESIST_LIGHTNING", "label": "Lightning Resistance", "unit": UNIT_FRACTION},
	"resistArcane":
	{"key": "STAT_RESIST_ARCANE", "label": "Arcane Resistance", "unit": UNIT_FRACTION},
	"lootQuality": {"key": "STAT_LOOT_QUALITY", "label": "Loot Quality", "unit": UNIT_FRACTION},
	"xpGain": {"key": "STAT_XP_GAIN", "label": "Experience Gain", "unit": UNIT_FRACTION},
	"goldFind": {"key": "STAT_GOLD_FIND", "label": "Gold Find", "unit": UNIT_FRACTION},
	"cooldownReduction":
	{"key": "STAT_COOLDOWN_RED", "label": "Cooldown Reduction", "unit": UNIT_FRACTION},
	"attackSpeed": {"key": "STAT_ATTACK_SPEED", "label": "Attack Speed", "unit": UNIT_FRACTION},
	"physicalDamage":
	{"key": "STAT_PHYSICAL_DAMAGE", "label": "Physical Damage", "unit": UNIT_FLAT},
	"fireDamage": {"key": "STAT_FIRE_DAMAGE", "label": "Fire Damage", "unit": UNIT_FLAT},
	"frostDamage": {"key": "STAT_FROST_DAMAGE", "label": "Frost Damage", "unit": UNIT_FLAT},
	"arcaneDamage": {"key": "STAT_ARCANE_DAMAGE", "label": "Arcane Damage", "unit": UNIT_FLAT},
	"poisonDamage": {"key": "STAT_POISON_DAMAGE", "label": "Poison Damage", "unit": UNIT_FLAT},
	"lifesteal": {"key": "STAT_LIFESTEAL", "label": "Lifesteal", "unit": UNIT_FRACTION},
}

const UPGRADE_STEP := 0.06

const UPGRADE_PATHS: Dictionary = {
	"standard": {"key": "FORGE_PATH_STANDARD", "label": "Standard", "step": 0.06, "perLevel": {}},
	"heavy":
	{
		"key": "FORGE_PATH_HEAVY",
		"label": "Heavy",
		"step": 0.08,
		"perLevel": {"poiseDamage": 0.02, "staminaCostReduction": -0.01},
	},
	"keen":
	{
		"key": "FORGE_PATH_KEEN",
		"label": "Keen",
		"step": 0.04,
		"perLevel": {"critChance": 0.012, "evasion": 1.0},
	},
	"blessed":
	{
		"key": "FORGE_PATH_BLESSED",
		"label": "Blessed",
		"step": 0.05,
		"perLevel": {"maxHealth": 6.0, "healthRegen": 0.4},
	},
}

const INFUSIONS: Dictionary = {
	"fire":
	{
		"key": "FORGE_INFUSION_FIRE",
		"label": "Fire",
		"resist": "resistFire",
		"convert": 0.35,
		"rate": 0.88,
	},
	"frost":
	{
		"key": "FORGE_INFUSION_FROST",
		"label": "Frost",
		"resist": "resistFrost",
		"convert": 0.35,
		"rate": 0.88,
	},
	"poison":
	{
		"key": "FORGE_INFUSION_POISON",
		"label": "Poison",
		"resist": "resistPoison",
		"convert": 0.35,
		"rate": 0.88,
	},
	"arcane":
	{
		"key": "FORGE_INFUSION_ARCANE",
		"label": "Arcane",
		"resist": "resistArcane",
		"convert": 0.3,
		"rate": 0.90,
	},
	"lightning":
	{
		"key": "FORGE_INFUSION_LIGHTNING",
		"label": "Lightning",
		"resist": "resistLightning",
		"convert": 0.3,
		"rate": 0.90,
	},
}

const BlacksmithServiceScript := preload("res://scripts/hub/blacksmith_service.gd")


static func empty_equipped() -> Dictionary:
	var eq: Dictionary = {}
	for slot in SLOT_ORDER:
		eq[slot] = {}
	return eq


static func slot_for_item_def(def: Dictionary) -> String:
	var explicit: String = def.get("equipmentSlot", "")
	if explicit != "":
		return explicit
	match def.get("itemType", ""):
		"weapon":
			return "weapon"
		"material":
			if def.get("runRelicId", "") != "":
				return "relic"
	return ""


static func can_equip_in_slot(def: Dictionary, slot: String) -> bool:
	if def.is_empty() or slot == "":
		return false
	return slot_for_item_def(def) == slot


static func aggregate_stats(
	equipped: Dictionary, affix_resolver: Callable = Callable()
) -> Dictionary:
	var totals: Dictionary = {}
	for stat in STAT_KEYS:
		totals[stat] = 0.0
	for slot in SLOT_ORDER:
		var instance: Dictionary = equipped.get(slot, {})
		if instance.is_empty():
			continue
		_add_instance_stats(totals, instance, affix_resolver)
	return totals


static func stats_for_instance(
	instance: Dictionary, affix_resolver: Callable = Callable()
) -> Dictionary:
	var fake := empty_equipped()
	var def := ItemCatalog.get_definition(instance.get("itemId", ""))
	var slot := slot_for_item_def(def)
	if slot != "":
		fake[slot] = instance
	return aggregate_stats(fake, affix_resolver)

static func stat_display_name(stat: String) -> String:
	var entry: Dictionary = STAT_DISPLAY.get(stat, {})
	var fallback: String = str(entry.get("label", stat.capitalize()))
	var key: String = str(entry.get("key", ""))
	if key == "":
		return fallback
	var translated := String(TranslationServer.translate(key))
	return fallback if translated == key else translated


static func stat_unit(stat: String) -> int:
	var entry: Dictionary = STAT_DISPLAY.get(stat, {})
	return int(entry.get("unit", UNIT_FLAT))


static func format_stat_value(stat: String, value: float, always_sign: bool = true) -> String:
	var prefix := "+" if (always_sign and value > 0.0) else ""
	match stat_unit(stat):
		UNIT_FRACTION:
			return "%s%.1f%%" % [prefix, value * 100.0]
		UNIT_PERCENT:
			return "%s%.0f%%" % [prefix, value]
		_:
			return "%s%.0f" % [prefix, value]


static func format_stat_line(stat: String, value: float) -> String:
	if is_zero_approx(value):
		return ""
	return "%s %s" % [format_stat_value(stat, value), stat_display_name(stat)]

static func upgrade_path_label(path: String) -> String:
	var entry: Dictionary = UPGRADE_PATHS.get(normalize_upgrade_path(path), {})
	var fallback: String = str(entry.get("label", "Standard"))
	var key: String = str(entry.get("key", ""))
	if key == "":
		return fallback
	var translated := String(TranslationServer.translate(key))
	return fallback if translated == key else translated


static func infusion_label(infusion: String) -> String:
	var entry: Dictionary = INFUSIONS.get(infusion, {})
	if entry.is_empty():
		return ""
	var fallback: String = str(entry.get("label", infusion.capitalize()))
	var key: String = str(entry.get("key", ""))
	var translated := String(TranslationServer.translate(key))
	return fallback if translated == key else translated


static func normalize_upgrade_path(path: String) -> String:
	var key := path.to_lower().strip_edges()
	return key if UPGRADE_PATHS.has(key) else "standard"


static func upgrade_multiplier(upgrade_level: int, path: String = "standard") -> float:
	var entry: Dictionary = UPGRADE_PATHS.get(normalize_upgrade_path(path), {})
	var step := float(entry.get("step", UPGRADE_STEP))
	return 1.0 + step * float(maxi(0, upgrade_level))


static func slot_stats(slot: Dictionary, affix_resolver: Callable = Callable()) -> Dictionary:
	var item_id: String = slot.get("itemId", "")
	if item_id == "":
		return {}
	if BlacksmithServiceScript.get_slot_durability(slot) <= 0:
		var empty: Dictionary = {}
		for stat in STAT_KEYS:
			empty[stat] = 0.0
		return empty
	var def := ItemCatalog.get_definition(item_id)
	var upgrade_level := int(slot.get("upgradeLevel", 0))
	var upgrade_path := normalize_upgrade_path(str(slot.get("upgradePath", "standard")))
	var base_stats: Dictionary = def.get("stats", {})
	var recipe_bonus := RecipeCatalog.upgrade_stat_bonus(item_id, upgrade_level)
	var use_recipe_bonus := not recipe_bonus.is_empty()
	var mult := upgrade_multiplier(upgrade_level, upgrade_path)
	# Condition scales the item's own numbers, so it multiplies with the upgrade level rather than
	# adding beside it: upgrading a chipped sword makes a better chipped sword, and never turns it
	# into a masterforged one. Affixes are added afterwards and are deliberately untouched -- they
	# are enchantments on the item, not part of its make.
	mult *= ItemQualityScript.stat_multiplier(str(slot.get("quality", "")))
	var totals: Dictionary = {}
	for stat in STAT_KEYS:
		var base_val := float(base_stats.get(stat, 0.0))
		if use_recipe_bonus:
			totals[stat] = base_val + float(recipe_bonus.get(stat, 0.0))
		else:
			totals[stat] = base_val * mult
	for flat_stat in FLAT_DAMAGE_STAT_KEYS:
		var base_val := float(base_stats.get(flat_stat, 0.0))
		if use_recipe_bonus:
			totals["bonusDamage"] = totals.get("bonusDamage", 0.0) + base_val + float(
				recipe_bonus.get(flat_stat, 0.0)
			)
		else:
			totals["bonusDamage"] = totals.get("bonusDamage", 0.0) + base_val * mult
	for affix in slot.get("affixes", []):
		if not affix is Dictionary:
			continue
		var affix_id: String = affix.get("affixId", "")
		var value: float = float(affix.get("value", 0.0))
		if affix_resolver.is_valid():
			var stat_name: String = affix_resolver.call(affix_id)
			if stat_name != "":
				if stat_name in FLAT_DAMAGE_STAT_KEYS:
					totals["bonusDamage"] = totals.get("bonusDamage", 0.0) + value
				elif stat_name in STAT_KEYS:
					totals[stat_name] = totals.get(stat_name, 0.0) + value
	_apply_upgrade_path_riders(totals, upgrade_path, upgrade_level)
	_apply_infusion(totals, str(slot.get("infusion", "")))
	return totals


static func _apply_upgrade_path_riders(
	totals: Dictionary, path: String, upgrade_level: int
) -> void:
	if upgrade_level <= 0:
		return
	var entry: Dictionary = UPGRADE_PATHS.get(path, {})
	var per_level: Dictionary = entry.get("perLevel", {})
	for stat in per_level:
		if stat in STAT_KEYS:
			totals[stat] = totals.get(stat, 0.0) + float(per_level[stat]) * float(upgrade_level)


static func _apply_infusion(totals: Dictionary, infusion: String) -> void:
	var entry: Dictionary = INFUSIONS.get(infusion, {})
	if entry.is_empty():
		return
	var convert_fraction := float(entry.get("convert", 0.0))
	var rate := float(entry.get("rate", 1.0))
	var damage := float(totals.get("bonusDamage", 0.0))
	if damage > 0.0:
		totals["bonusDamage"] = damage * (1.0 - convert_fraction) + damage * convert_fraction * rate
	var resist_stat := str(entry.get("resist", ""))
	if resist_stat in STAT_KEYS:
		totals[resist_stat] = totals.get(resist_stat, 0.0) + convert_fraction * 0.25


static func _add_instance_stats(
	totals: Dictionary, instance: Dictionary, affix_resolver: Callable
) -> void:
	var instance_stats := slot_stats(instance, affix_resolver)
	for stat in STAT_KEYS:
		totals[stat] = totals.get(stat, 0.0) + float(instance_stats.get(stat, 0.0))
