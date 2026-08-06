extends RefCounted
class_name Equipment

## Equipment slot helpers and stat aggregation (LOOT-4.2).

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
]

const FLAT_DAMAGE_STAT_KEYS: Array[String] = [
	"physicalDamage",
	"fireDamage",
	"frostDamage",
	"arcaneDamage",
	"poisonDamage",
]

const UPGRADE_STEP := 0.06
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


static func compare_stats(
	current: Dictionary, candidate: Dictionary, affix_resolver: Callable = Callable()
) -> Dictionary:
	var base := aggregate_stats(current, affix_resolver)
	var slot := slot_for_item_def(ItemCatalog.get_definition(candidate.get("itemId", "")))
	var modified := current.duplicate(true)
	if slot != "":
		modified[slot] = candidate
	var with_item := aggregate_stats(modified, affix_resolver)
	var delta: Dictionary = {}
	for stat in STAT_KEYS:
		delta[stat] = with_item.get(stat, 0.0) - base.get(stat, 0.0)
	return delta


static func format_stat_line(stat: String, value: float) -> String:
	if is_zero_approx(value):
		return ""
	match stat:
		"maxHealth":
			return "+%.0f HP" % value
		"defense":
			return "+%.0f DEF" % value
		"damagePercent":
			return "+%.0f%% DMG" % value
		"moveSpeedPercent":
			return "+%.0f%% SPD" % value
		"staminaMax":
			return "+%.0f STA" % value
		"bonusDamage":
			return "+%.0f DMG" % value
		"physicalDamage", "critChance", "poiseDamage", "blockReduction", "damageReduction":
			return "+%.0f%% %s" % [value * 100.0, stat]
		"staminaRegen", "staminaCostReduction", "moveSpeed", "lootQuality", "xpGain", "goldFind", "cooldownReduction":
			return "+%.0f%% %s" % [value * 100.0, stat]
		_:
			return "+%.0f %s" % [value, stat]


static func format_delta_line(stat: String, delta: float) -> String:
	if is_zero_approx(delta):
		return ""
	var delta_sign := "+" if delta > 0.0 else ""
	match stat:
		"maxHealth":
			return "%s%.0f HP" % [delta_sign, delta]
		"defense":
			return "%s%.0f DEF" % [delta_sign, delta]
		"damagePercent":
			return "%s%.0f%% DMG" % [delta_sign, delta]
		"moveSpeedPercent":
			return "%s%.0f%% SPD" % [delta_sign, delta]
		"staminaMax":
			return "%s%.0f STA" % [delta_sign, delta]
		"bonusDamage":
			return "%s%.0f DMG" % [delta_sign, delta]
		"physicalDamage", "critChance", "poiseDamage", "blockReduction", "damageReduction":
			return "%s%.0f%% %s" % [delta_sign, delta * 100.0, stat]
		"staminaRegen", "staminaCostReduction", "moveSpeed", "lootQuality", "xpGain", "goldFind", "cooldownReduction":
			return "%s%.0f%% %s" % [delta_sign, delta * 100.0, stat]
		_:
			return "%s%.0f %s" % [delta_sign, delta, stat]


static func upgrade_multiplier(upgrade_level: int) -> float:
	return 1.0 + UPGRADE_STEP * float(maxi(0, upgrade_level))


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
	var base_stats: Dictionary = def.get("stats", {})
	var recipe_bonus := RecipeCatalog.upgrade_stat_bonus(item_id, upgrade_level)
	var use_recipe_bonus := not recipe_bonus.is_empty()
	var mult := upgrade_multiplier(upgrade_level)
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
	return totals


static func _add_instance_stats(
	totals: Dictionary, instance: Dictionary, affix_resolver: Callable
) -> void:
	var instance_stats := slot_stats(instance, affix_resolver)
	for stat in STAT_KEYS:
		totals[stat] = totals.get(stat, 0.0) + float(instance_stats.get(stat, 0.0))
