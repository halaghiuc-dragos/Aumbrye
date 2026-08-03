extends RefCounted
class_name AffixRoller

## Local affix roller stub when backend LOOT-4.1 is unavailable.

const PREFIXES_PATH := "content/affixes/prefixes.json"
const SUFFIXES_PATH := "content/affixes/suffixes.json"
const RARITY_PATH := "content/affixes/rarity_rules.json"
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")

static var _prefixes: Array = []
static var _suffixes: Array = []
static var _rarity_rules: Dictionary = {}
static var _loaded := false


static func roll_instance(item_id: String, roll_seed: int = -1, forced_rarity: String = "", run_mode: String = "") -> Dictionary:
	_ensure_loaded()
	var def := ItemCatalog.get_definition(item_id)
	if def.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	if roll_seed >= 0:
		rng.seed = roll_seed
	else:
		rng.randomize()
	var rarity: String = RarityRegistryScript.normalize(forced_rarity) if forced_rarity != "" else _pick_rarity(rng, run_mode)
	var affix_count := _roll_affix_count(rarity, rng)
	var affixes: Array = []
	var pool: Array = _prefixes.duplicate()
	pool.append_array(_suffixes)
	_shuffle_with_rng(pool, rng)
	for i in mini(affix_count, pool.size()):
		var affix_def: Dictionary = pool[i]
		var value := rng.randi_range(int(affix_def.get("min", 1)), int(affix_def.get("max", 3)))
		affixes.append({
			"affixId": affix_def.get("id", ""),
			"value": value,
		})
	return {
		"instanceId": _make_instance_id(item_id, roll_seed if roll_seed >= 0 else rng.randi()),
		"itemId": item_id,
		"quantity": 1,
		"rarity": rarity,
		"affixes": affixes,
		"rollSeed": roll_seed if roll_seed >= 0 else rng.seed,
	}


static func get_affix_stat(affix_id: String) -> String:
	_ensure_loaded()
	for affix in _prefixes:
		if affix.get("id", "") == affix_id:
			return str(affix.get("stat", ""))
	for affix in _suffixes:
		if affix.get("id", "") == affix_id:
			return str(affix.get("stat", ""))
	return ""


static func roll_identical(item_id: String, roll_seed: int) -> Dictionary:
	return roll_instance(item_id, roll_seed)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var prefixes := ContentLoader.load_json(PREFIXES_PATH)
	var suffixes := ContentLoader.load_json(SUFFIXES_PATH)
	var rules := ContentLoader.load_json(RARITY_PATH)
	_prefixes = prefixes.get("affixes", [])
	_suffixes = suffixes.get("affixes", [])
	_rarity_rules = _parse_rarity_rules(rules)
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


static func _pick_rarity(rng: RandomNumberGenerator, run_mode: String = "") -> String:
	var bonus: float = RarityRegistryScript.mode_drop_bonus(run_mode)
	var weights: Dictionary = {}
	var total_weight := 0
	for rarity in _rarity_rules:
		var norm: String = RarityRegistryScript.normalize(rarity)
		if int(_rarity_rules[rarity].get("weight", 0)) <= 0:
			continue
		var weight := int(_rarity_rules[rarity].get("weight", 0))
		if bonus > 0.0 and RarityRegistryScript.tier_index(norm) >= RarityRegistryScript.tier_index("rare"):
			weight = int(round(float(weight) * (1.0 + bonus)))
		weights[norm] = int(weights.get(norm, 0)) + weight
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


static func _make_instance_id(item_id: String, instance_seed: int) -> String:
	return "%s_%d" % [item_id, instance_seed]


static func _shuffle_with_rng(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
