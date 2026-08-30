extends RefCounted
class_name DescentPactService


const PACTS_PATH := "content/progression/descent_pacts.json"
const FloorSeedMixScript := preload("res://scripts/dungeon/floor_seed_mix.gd")
const PACT_OPTION_PREFIX := "pact:"

static var _data: Dictionary = {}


static func reload() -> void:
	_data.clear()


static func all_pacts() -> Array:
	var data := _load()
	var pacts: Variant = data.get("pacts", [])
	return pacts if pacts is Array else []


static func get_pact(pact_id: String) -> Dictionary:
	for pact in all_pacts():
		if pact is Dictionary and str((pact as Dictionary).get("id", "")) == pact_id:
			return pact
	return {}


static func offers_for_descent(run_seed: int, target_floor: int) -> Array[Dictionary]:
	var pacts := all_pacts()
	var offers: Array[Dictionary] = []
	if pacts.is_empty():
		return offers
	var pool: Array = []
	for pact in pacts:
		if not pact is Dictionary:
			continue
		if VaultService and not VaultService.is_pact_available(str((pact as Dictionary).get("id", ""))):
			continue
		pool.append(pact)
	if pool.is_empty():
		return offers
	var count := mini(int(_load().get("offerCount", 2)), pool.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMixScript.mix(maxi(1, run_seed), maxi(1, target_floor) * 977 + 41)
	for _i in count:
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		var pact: Variant = pool[idx]
		pool.remove_at(idx)
		if pact is Dictionary:
			offers.append(pact)
	return offers


static func option_id_for_pact(pact_id: String) -> String:
	return PACT_OPTION_PREFIX + pact_id


static func pact_id_from_option(option_id: String) -> String:
	if not option_id.begins_with(PACT_OPTION_PREFIX):
		return ""
	return option_id.substr(PACT_OPTION_PREFIX.length())


static func describe(pact: Dictionary) -> String:
	var gain := str(pact.get("gain", ""))
	var cost := str(pact.get("cost", ""))
	if gain == "" and cost == "":
		return str(pact.get("description", ""))
	return "%s / %s" % [gain, cost]


static func apply(pact_id: String, base_modifiers: Array) -> Array[String]:
	var pact := get_pact(pact_id)
	var resolved: Array[String] = []
	for entry in base_modifiers:
		var id := str(entry)
		if id != "" and id not in resolved:
			resolved.append(id)
	if pact.is_empty():
		return resolved
	for entry in pact.get("removeModifiers", []):
		resolved.erase(str(entry))
	for entry in pact.get("modifiers", []):
		var id := str(entry)
		if id != "" and id not in resolved:
			resolved.append(id)
	return resolved


static func _load() -> Dictionary:
	if _data.is_empty():
		var loaded := ContentLoader.load_json(PACTS_PATH)
		if loaded is Dictionary:
			_data = loaded
	return _data
