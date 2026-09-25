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


static func offers_for_descent(run_seed: int, target_floor: int, base_modifiers: Array = []) -> Array[Dictionary]:
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
		var resolution := resolve(str((pact as Dictionary).get("id", "")), base_modifiers)
		# A pact that cannot change the target floor is not an offer; its flavor can remain authored,
		# but presenting it as a meaningful tradeoff would be misleading.
		if bool(resolution.get("valid", false)):
			var offered := (pact as Dictionary).duplicate(true)
			offered["resolution"] = resolution
			pool.append(offered)
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
	var gain := ContentText.field(pact, "gain")
	var cost := ContentText.field(pact, "cost")
	if gain == "" and cost == "":
		return ContentText.description(pact)
	return "%s / %s" % [gain, cost]


static func apply(pact_id: String, base_modifiers: Array) -> Array[String]:
	return resolve(pact_id, base_modifiers).get("after", []) as Array[String]


## The resolved delta is the pact contract used by both the commit path and the UI. Pact-added
## modifiers intentionally replace conflicting base modifiers; otherwise `no_rest` could fail to
## replace `starved_hearth` simply because base normalization happened first.
static func resolve(pact_id: String, base_modifiers: Array) -> Dictionary:
	var pact := get_pact(pact_id)
	var before: Array[String] = []
	for entry in base_modifiers:
		var id := str(entry)
		if id != "" and id not in before:
			before.append(id)
	before = RunModifierService.normalize_compatible(before)
	var resolved := before.duplicate()
	if pact.is_empty():
		return {"valid": false, "reason": "unknown_pact", "before": before, "after": before}
	for entry in pact.get("removeModifiers", []):
		resolved.erase(str(entry))
	for entry in pact.get("modifiers", []):
		var id := str(entry)
		if id == "":
			continue
		for excluded in RunModifierService.MODIFIER_EXCLUSIONS.get(id, []):
			resolved.erase(str(excluded))
		if id not in resolved and RunModifierService.is_compatible(id, resolved):
			resolved.append(id)
	var after := RunModifierService.normalize_compatible(resolved)
	var added: Array[String] = []
	var removed: Array[String] = []
	for id in after:
		if id not in before:
			added.append(id)
	for id in before:
		if id not in after:
			removed.append(id)
	var rewards: Array[String] = []
	for id in added:
		if id in [RunModifierService.MODIFIER_RICH_VEINS, RunModifierService.MODIFIER_BOSS_HOARD]:
			rewards.append(id)
	return {
		"valid": not added.is_empty() or not removed.is_empty(),
		"before": before,
		"after": after,
		"added": added,
		"removed": removed,
		"rewards": rewards,
	}


static func describe_resolution(resolution: Dictionary) -> String:
	var lines: Array[String] = []
	for id in resolution.get("added", []):
		lines.append(TranslationServer.translate("PACT_DELTA_ADDED").format({"modifier": RunModifierService.describe(str(id))}))
	for id in resolution.get("removed", []):
		lines.append(TranslationServer.translate("PACT_DELTA_REMOVED").format({"modifier": RunModifierService.describe(str(id))}))
	var rewards: Variant = resolution.get("rewards", [])
	if rewards is Array and not (rewards as Array).is_empty():
		lines.append(TranslationServer.translate("PACT_FLOOR_REWARD").format({"rewards": ", ".join((rewards as Array).map(func(id: String) -> String: return RunModifierService.describe(id)))}))
	return "\n".join(lines)


static func _load() -> Dictionary:
	if _data.is_empty():
		var loaded := ContentLoader.load_json(PACTS_PATH)
		if loaded is Dictionary:
			_data = loaded
	return _data
