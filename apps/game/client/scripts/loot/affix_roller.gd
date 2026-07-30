extends RefCounted
class_name AffixRoller

## Local affix roller stub when backend LOOT-4.1 is unavailable.

const PREFIXES_PATH := "content/affixes/prefixes.json"
const SUFFIXES_PATH := "content/affixes/suffixes.json"
const RARITY_PATH := "content/affixes/rarity_rules.json"

static var _prefixes: Array = []
static var _suffixes: Array = []
static var _rarity_rules: Dictionary = {}
static var _loaded := false


static func roll_instance(item_id: String, roll_seed: int = -1) -> Dictionary:
	_ensure_loaded()
	var def := ItemCatalog.get_definition(item_id)
	if def.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	if roll_seed >= 0:
		rng.seed = roll_seed
	else:
		rng.randomize()
	var rarity := _pick_rarity(rng)
	var affix_count: int = int(_rarity_rules.get(rarity, {}).get("affixCount", 0))
	var affixes: Array = []
	var pool: Array = _prefixes.duplicate()
	pool.append_array(_suffixes)
	pool.shuffle()
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
	_rarity_rules = rules.get("rarities", {})
	_loaded = true


static func _pick_rarity(rng: RandomNumberGenerator) -> String:
	var total_weight := 0
	for rarity in _rarity_rules:
		total_weight += int(_rarity_rules[rarity].get("weight", 0))
	if total_weight <= 0:
		return "common"
	var roll := rng.randi_range(1, total_weight)
	var cumulative := 0
	for rarity in _rarity_rules:
		cumulative += int(_rarity_rules[rarity].get("weight", 0))
		if roll <= cumulative:
			return rarity
	return "common"


static func _make_instance_id(item_id: String, seed: int) -> String:
	return "%s_%d" % [item_id, seed]
