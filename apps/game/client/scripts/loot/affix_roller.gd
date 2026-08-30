extends RefCounted
class_name AffixRoller


const PREFIXES_PATH := "content/affixes/prefixes.json"
const SUFFIXES_PATH := "content/affixes/suffixes.json"
const RARITY_PATH := "content/affixes/rarity_rules.json"
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const ItemQualityScript := preload("res://scripts/items/item_quality.gd")
const ContentSchemaValidatorScript := preload("res://scripts/app/content_schema_validator.gd")

static var _prefixes: Array = []
static var _suffixes: Array = []
static var _rarity_rules: Dictionary = {}
## Kept beside the per-rarity rules rather than inside them: _parse_rarity_rules reshapes that file
## into a map keyed by rarity, so anything not per-rarity is dropped on the way through.
static var _affix_group_limits: Dictionary = {}
static var _loaded := false
static var _affix_index: Dictionary = {}


static func roll_instance(
	item_id: String, roll_seed: int = -1, forced_rarity: String = "", run_mode: String = ""
) -> Dictionary:
	_ensure_loaded()
	var def := ItemCatalog.get_definition(item_id)
	if def.is_empty():
		return {}
	var effective_seed := roll_seed if roll_seed >= 0 else (randi() & 0x7fffffff)
	var rng := RandomNumberGenerator.new()
	rng.seed = effective_seed
	var loot_quality: float = 0.0
	if ProgressionService:
		loot_quality = float(ProgressionService.get_talent_stat_totals().get("lootQuality", 0.0))
	var rarity: String = (
		RarityRegistryScript.normalize(forced_rarity)
		if forced_rarity != ""
		else _pick_rarity(rng, run_mode, loot_quality)
	)
	var affix_count := _roll_affix_count(rarity, rng)
	var item_type: String = str(def.get("itemType", ""))
	var pool: Array = _build_affix_pool(item_type, rarity)
	var affixes: Array = _pick_weighted_affixes(pool, affix_count, rarity, rng)
	var instance := {
		"instanceId": GridInventory.mint_instance_id(item_id),
		"itemId": item_id,
		"quantity": 1,
		"rarity": rarity,
		"affixes": affixes,
		"rollSeed": effective_seed,
	}
	# Condition is rolled from the same rng as the affixes, after them, so an existing seed keeps
	# producing the affixes it always did and only gains a quality on top.
	var quality := ItemQualityScript.roll(item_type, rarity, rng)
	if quality != "":
		instance["quality"] = quality
	if OS.is_debug_build():
		ContentSchemaValidatorScript.validate_roll_instance(instance, item_id)
	return instance


## Affix lookup is on the hot path: `Equipment.slot_stats` resolves the stat for every affix on
## every equipped piece, and that runs on each inventory change, each stat refresh, each buff tick
## and each equipment reapply. Scanning both 34-entry arrays per affix turned a per-frame-ish
## operation into a few hundred string comparisons, so the packs are indexed once on load.
static func get_affix_stat(affix_id: String) -> String:
	_ensure_loaded()
	var def: Variant = _affix_index.get(affix_id, null)
	return str((def as Dictionary).get("stat", "")) if def is Dictionary else ""


static func roll_identical(item_id: String, roll_seed: int) -> Dictionary:
	return roll_instance(item_id, roll_seed)


static func get_affix_def(affix_id: String) -> Dictionary:
	_ensure_loaded()
	var def: Variant = _affix_index.get(affix_id, null)
	return def if def is Dictionary else {}


static func format_affix_line(affix: Dictionary) -> String:
	var affix_id := str(affix.get("affixId", ""))
	if affix_id == "":
		return ""
	var def := get_affix_def(affix_id)
	var value := float(affix.get("value", 0.0))
	if def.is_empty():
		return "%s %s" % [affix_id, str(value)]
	if is_behavioural(def):
		return "%s — %s" % [str(def.get("displayName", affix_id)), str(def.get("ruleText", ""))]
	var stat := str(def.get("stat", ""))
	var template := str(def.get("template", "+{value} {stat}"))
	var body := template.replace("{value}", Equipment.format_stat_value(stat, value, false)).replace(
		"{stat}", Equipment.stat_display_name(stat)
	)
	return "%s — %s" % [str(def.get("displayName", affix_id)), body]


static func reroll_affixes(existing: Array, rarity: String, roll_seed: int) -> Array:
	_ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = roll_seed if roll_seed >= 0 else 0
	var rerolled: Array = []
	for entry in existing:
		if not entry is Dictionary:
			continue
		var affix_id := str((entry as Dictionary).get("affixId", ""))
		var def := get_affix_def(affix_id)
		if def.is_empty():
			rerolled.append((entry as Dictionary).duplicate(true))
			continue
		rerolled.append({"affixId": affix_id, "value": _roll_tier_value(def, rarity, rng)})
	return rerolled


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var prefixes := ContentLoader.load_json(PREFIXES_PATH)
	var suffixes := ContentLoader.load_json(SUFFIXES_PATH)
	var rules := ContentLoader.load_json(RARITY_PATH)
	_prefixes = prefixes.get("affixes", [])
	_suffixes = suffixes.get("affixes", [])
	_rarity_rules = _parse_rarity_rules(rules)
	_affix_group_limits = rules.get("affixGroupLimits", {})
	_affix_index.clear()
	for pack in [_prefixes, _suffixes]:
		for affix in pack:
			if affix is Dictionary:
				_affix_index[str((affix as Dictionary).get("id", ""))] = affix
	_loaded = true


static func _parse_rarity_rules(rules: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var weights: Dictionary = rules.get("rarityWeights", rules.get("rarities", {}))
	var counts: Dictionary = rules.get("affixCounts", {})
	for rarity in weights:
		var entry: Dictionary = {}
		if weights[rarity] is Dictionary:
			entry = weights[rarity].duplicate()
		else:
			entry["weight"] = int(weights[rarity])
		var norm: String = RarityRegistryScript.normalize(rarity)
		if counts.has(rarity):
			var count_range: Dictionary = counts[rarity]
			entry["min"] = int(count_range.get("min", 0))
			entry["max"] = int(count_range.get("max", entry.get("min", 0)))
		elif counts.has(norm):
			var count_range: Dictionary = counts[norm]
			entry["min"] = int(count_range.get("min", 0))
			entry["max"] = int(count_range.get("max", entry.get("min", 0)))
		out[norm] = entry
	return out


static func _roll_affix_count(rarity: String, rng: RandomNumberGenerator) -> int:
	var rule: Dictionary = _rarity_rules.get(rarity, {})
	var min_c: int = int(rule.get("min", rule.get("affixCount", 0)))
	var max_c: int = int(rule.get("max", min_c))
	if max_c <= min_c:
		return min_c
	return rng.randi_range(min_c, max_c)


static func rarity_weights(run_mode: String = "", loot_quality_bonus: float = 0.0) -> Dictionary:
	_ensure_loaded()
	var bonus: float = RarityRegistryScript.mode_drop_bonus(run_mode) + loot_quality_bonus
	var weights: Dictionary = {}
	for rarity in _rarity_rules:
		var norm: String = RarityRegistryScript.normalize(rarity)
		if int(_rarity_rules[rarity].get("weight", 0)) <= 0:
			continue
		var weight := int(_rarity_rules[rarity].get("weight", 0))
		if (
			bonus > 0.0
			and RarityRegistryScript.tier_index(norm) >= RarityRegistryScript.tier_index("rare")
		):
			weight = int(round(float(weight) * (1.0 + bonus)))
		weights[norm] = int(weights.get(norm, 0)) + weight
	return weights


static func _pick_rarity(
	rng: RandomNumberGenerator, run_mode: String = "", loot_quality_bonus: float = 0.0
) -> String:
	var weights: Dictionary = rarity_weights(run_mode, loot_quality_bonus)
	var total_weight := 0
	for rarity in weights:
		total_weight += int(weights[rarity])
	if total_weight <= 0:
		return "common"
	var roll := rng.randi_range(1, total_weight)
	var cumulative := 0
	for rarity in RarityRegistryScript.TIER_ORDER:
		if not weights.has(rarity):
			continue
		cumulative += int(weights[rarity])
		if roll <= cumulative:
			return rarity
	return "common"


static func _build_affix_pool(item_type: String, rarity: String = "") -> Array:
	var pool: Array = []
	for affix in _prefixes:
		if _affix_applies_to_item(affix, item_type) and _affix_allows_rarity(affix, rarity):
			pool.append(affix)
	for affix in _suffixes:
		if _affix_applies_to_item(affix, item_type) and _affix_allows_rarity(affix, rarity):
			pool.append(affix)
	return pool


## Behavioural affixes declare a `minRarity` so they cannot land on a common or a magic. Finding
## one should read as an event, and the flat stat rolls are what make that contrast work.
static func _affix_allows_rarity(affix_def: Dictionary, rarity: String) -> bool:
	var minimum := str(affix_def.get("minRarity", ""))
	if minimum == "" or rarity == "":
		return true
	var order: Array = RarityRegistryScript.TIER_ORDER
	var need := order.find(RarityRegistryScript.normalize(minimum))
	var have := order.find(RarityRegistryScript.normalize(rarity))
	if need < 0 or have < 0:
		return true
	return have >= need


## True when the affix carries CombatEvents rules rather than a stat line.
static func is_behavioural(affix_def: Dictionary) -> bool:
	var rules: Variant = affix_def.get("rules", [])
	return rules is Array and not (rules as Array).is_empty()


## The rules an equipped instance's affixes contribute, keyed for CombatEvents registration.
static func rules_for_instance(instance: Dictionary) -> Array:
	var out: Array = []
	for entry in instance.get("affixes", []):
		if not entry is Dictionary:
			continue
		var def := get_affix_def(str((entry as Dictionary).get("affixId", "")))
		if is_behavioural(def):
			out.append_array((def.get("rules", []) as Array).duplicate(true))
	return out


static func _affix_applies_to_item(affix_def: Dictionary, item_type: String) -> bool:
	var types: Variant = affix_def.get("itemTypes", [])
	if not types is Array or (types as Array).is_empty():
		return true
	return item_type in types


## Which family an affix belongs to, for the stacking limits.
##
## Five different flat-damage prefixes are five different affixes on five different stats, so
## nothing in the roller stopped a weapon taking all of them at once -- and the result added more
## damage than the weapon itself carried, on every hit, at every attack speed. Grouping them means
## a weapon can still roll elemental damage, just not five kinds of it.
static func _affix_group(affix_def: Dictionary) -> String:
	var stat := str(affix_def.get("stat", ""))
	if stat in Equipment.FLAT_DAMAGE_STAT_KEYS:
		return "flatDamage"
	if stat.begins_with("resist"):
		return "resist"
	return stat


static func _pick_weighted_affixes(
	pool: Array, count: int, rarity: String, rng: RandomNumberGenerator
) -> Array:
	var result: Array = []
	if count <= 0 or pool.is_empty():
		return result
	var group_limits: Dictionary = _affix_group_limits
	var group_taken: Dictionary = {}
	var candidates: Array = pool.duplicate()
	while result.size() < count and not candidates.is_empty():
		var total_weight := 0
		for affix_def in candidates:
			total_weight += maxi(1, int(affix_def.get("weight", 1)))
		var roll := rng.randi_range(1, total_weight)
		var cumulative := 0
		var picked_index := -1
		for i in candidates.size():
			var affix_def: Dictionary = candidates[i]
			cumulative += maxi(1, int(affix_def.get("weight", 1)))
			if roll <= cumulative:
				picked_index = i
				break
		if picked_index < 0:
			break
		var chosen: Dictionary = candidates[picked_index]
		candidates.remove_at(picked_index)
		var group := _affix_group(chosen)
		if group_limits.has(group):
			var taken := int(group_taken.get(group, 0))
			if taken >= int(group_limits[group]):
				# The family is full. Drop every remaining affix from it so the loop does not
				# spin re-picking members it is only going to reject.
				var kept: Array = []
				for candidate in candidates:
					if _affix_group(candidate) != group:
						kept.append(candidate)
				candidates = kept
				continue
			group_taken[group] = taken + 1
		var value := _roll_tier_value(chosen, rarity, rng)
		(
			result
			. append(
				{
					"affixId": chosen.get("id", ""),
					"value": value,
				}
			)
		)
	return result


static func _roll_tier_value(
	affix_def: Dictionary, rarity: String, rng: RandomNumberGenerator
) -> float:
	if is_behavioural(affix_def):
		return 0.0
	var tiers: Variant = affix_def.get("tiers", {})
	if not tiers is Dictionary:
		return float(rng.randi_range(1, 3))
	var norm := RarityRegistryScript.normalize(rarity)
	var tier: Variant = (tiers as Dictionary).get(norm)
	if tier == null:
		tier = (tiers as Dictionary).get("aumbral")
	if tier == null:
		tier = (tiers as Dictionary).get("mythic")
	if tier == null:
		tier = (tiers as Dictionary).get("legendary")
	if not tier is Dictionary:
		return float(rng.randi_range(1, 3))
	var min_v: float = float(tier.get("min", 1))
	var max_v: float = float(tier.get("max", min_v))
	if max_v <= min_v:
		return min_v
	if min_v == floor(min_v) and max_v == floor(max_v):
		return float(rng.randi_range(int(min_v), int(max_v)))
	return min_v + rng.randf() * (max_v - min_v)
