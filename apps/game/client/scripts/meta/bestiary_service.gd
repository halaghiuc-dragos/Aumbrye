class_name BestiaryService
extends RefCounted


const CATALOG_PATH := "content/bestiary/entries.json"
const KILLS_FLAG := "bestiary_kills"
const OBSERVATIONS_FLAG := "bestiary_observations"
const STUDIED_FLAG := "bestiary_studied_count"
const MASTERED_FLAG := "bestiary_mastered_count"
const COMPLETE_FLAG := "bestiary_complete"

const TIER_UNKNOWN := 0
const TIER_SIGHTED := 1
const TIER_STUDIED := 2
const TIER_MASTERED := 3

const KILLS_FOR_SIGHTED := 1
const KILLS_FOR_STUDIED := 10
const SIGNATURES_FOR_STUDIED := 2
## Mastered means the fight is understood, not ground out: a few kills, a few attacks seen, and
## two of them answered.
const KILLS_FOR_MASTERED := 5
const SIGNATURES_FOR_MASTERED := 3
const COUNTERS_FOR_MASTERED := 2

static var _entries: Dictionary = {}
## Tier per enemy, for the active character. Recomputed for one enemy when it changes.
static var _tiers: Dictionary = {}
static var _tiers_owner := ""
static var _tiers_ready := false
static var _order: Array[String] = []
static var _loaded := false


static func get_entry(enemy_id: String) -> Dictionary:
	_ensure_loaded()
	var entry: Variant = _entries.get(enemy_id, {})
	return entry if entry is Dictionary else {}


static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	return _order.duplicate()


static func entry_count() -> int:
	_ensure_loaded()
	return _order.size()


static func get_kills(enemy_id: String) -> int:
	var record := _kill_record()
	var raw: Variant = record.get(enemy_id, 0)
	if raw is int or raw is float:
		return int(raw)
	return 0


static func _tier_from(kills: int, observation: Dictionary) -> int:
	var seen := bool(observation.get("seen", false))
	var signatures: int = (observation.get("signatures", {}) as Dictionary).size()
	var counters: int = (observation.get("counters", {}) as Dictionary).size()
	if (
		kills >= KILLS_FOR_MASTERED
		and signatures >= SIGNATURES_FOR_MASTERED
		and counters >= COUNTERS_FOR_MASTERED
	):
		return TIER_MASTERED
	if kills >= KILLS_FOR_STUDIED or signatures >= SIGNATURES_FOR_STUDIED:
		return TIER_STUDIED
	if seen or kills >= KILLS_FOR_SIGHTED:
		return TIER_SIGHTED
	return TIER_UNKNOWN


static func _ensure_tiers() -> void:
	var owner_id: String = LocalSave.get_active_character_id() if LocalSave else ""
	if _tiers_ready and owner_id == _tiers_owner:
		return
	_ensure_loaded()
	var kills := _kill_record()
	var observations := _observation_record()
	_tiers.clear()
	for enemy_id in _order:
		_tiers[enemy_id] = _tier_from(
			int(kills.get(enemy_id, 0)), observations.get(enemy_id, {}) as Dictionary
		)
	_tiers_owner = owner_id
	_tiers_ready = true


static func _update_tier(enemy_id: String) -> void:
	_ensure_tiers()
	var observation := _observation_record().get(enemy_id, {}) as Dictionary
	_tiers[enemy_id] = _tier_from(get_kills(enemy_id), observation)


static func get_tier(enemy_id: String) -> int:
	_ensure_tiers()
	return int(_tiers.get(enemy_id, TIER_UNKNOWN))


## Kills still needed for the next tier under the same rule `get_tier` applies.
static func kills_to_next_tier(enemy_id: String) -> int:
	var kills := get_kills(enemy_id)
	match get_tier(enemy_id):
		TIER_UNKNOWN:
			return KILLS_FOR_SIGHTED - kills
		TIER_SIGHTED:
			return KILLS_FOR_STUDIED - kills
		TIER_STUDIED:
			return maxi(0, KILLS_FOR_MASTERED - kills)
	return 0


## What is still missing for mastery, worded the way it is checked: "kill 5, see 3 attacks,
## counter 2".
static func mastery_remaining(enemy_id: String) -> Dictionary:
	var observation := _observation_record().get(enemy_id, {}) as Dictionary
	return {
		"kills": maxi(0, KILLS_FOR_MASTERED - get_kills(enemy_id)),
		"attacks": maxi(0, SIGNATURES_FOR_MASTERED - (observation.get("signatures", {}) as Dictionary).size()),
		"counters": maxi(0, COUNTERS_FOR_MASTERED - (observation.get("counters", {}) as Dictionary).size()),
	}


static func get_revealed(enemy_id: String) -> Dictionary:
	var entry := get_entry(enemy_id)
	if entry.is_empty():
		return {}
	var tier := get_tier(enemy_id)
	var revealed := {
		"enemyId": enemy_id,
		"tier": tier,
		"kills": get_kills(enemy_id),
	}
	if tier >= TIER_SIGHTED:
		revealed["name"] = str(entry.get("name", enemy_id))
		revealed["biomeId"] = str(entry.get("biomeId", ""))
		revealed["sighted"] = str(entry.get("sighted", ""))
	if tier >= TIER_STUDIED:
		revealed["studied"] = str(entry.get("studied", ""))
	if tier >= TIER_MASTERED:
		revealed["mastered"] = str(entry.get("mastered", ""))
	return revealed


static func studied_count() -> int:
	var total := 0
	for enemy_id in get_all_ids():
		if get_tier(enemy_id) >= TIER_STUDIED:
			total += 1
	return total


static func mastered_count() -> int:
	var total := 0
	for enemy_id in get_all_ids():
		if get_tier(enemy_id) >= TIER_MASTERED:
			total += 1
	return total


static func is_complete() -> bool:
	var total := entry_count()
	return total > 0 and mastered_count() >= total


static func record_kill(enemy_id: String) -> void:
	if enemy_id == "":
		return
	_ensure_loaded()
	if not _entries.has(enemy_id):
		return
	if CharacterService == null:
		return
	var record := _kill_record()
	record[enemy_id] = get_kills(enemy_id) + 1
	CharacterService.set_flag(KILLS_FLAG, record)
	_update_tier(enemy_id)
	_refresh_progress()


static func record_sighting(enemy_id: String) -> void:
	if enemy_id == "" or CharacterService == null:
		return
	_ensure_loaded()
	if not _entries.has(enemy_id):
		return
	var observations := _observation_record()
	var observation: Dictionary = observations.get(enemy_id, {}) as Dictionary
	if bool(observation.get("seen", false)):
		return
	observation["seen"] = true
	observations[enemy_id] = observation
	CharacterService.set_flag(OBSERVATIONS_FLAG, observations)
	_update_tier(enemy_id)
	_refresh_progress()


static func record_signature(enemy_id: String, signature_id: String) -> void:
	if enemy_id == "" or signature_id == "" or CharacterService == null:
		return
	_ensure_loaded()
	if not _entries.has(enemy_id):
		return
	var observations := _observation_record()
	var observation: Dictionary = observations.get(enemy_id, {}) as Dictionary
	observation["seen"] = true
	var signatures: Dictionary = observation.get("signatures", {}) as Dictionary
	if signatures.has(signature_id):
		return
	signatures[signature_id] = true
	observation["signatures"] = signatures
	observations[enemy_id] = observation
	CharacterService.set_flag(OBSERVATIONS_FLAG, observations)
	_update_tier(enemy_id)
	_refresh_progress()


static func record_counter(enemy_id: String, counter_id: String) -> void:
	if enemy_id == "" or counter_id == "" or CharacterService == null:
		return
	_ensure_loaded()
	if not _entries.has(enemy_id):
		return
	var observations := _observation_record()
	var observation: Dictionary = observations.get(enemy_id, {}) as Dictionary
	observation["seen"] = true
	var counters: Dictionary = observation.get("counters", {}) as Dictionary
	if counters.has(counter_id):
		return
	counters[counter_id] = true
	observation["counters"] = counters
	observations[enemy_id] = observation
	CharacterService.set_flag(OBSERVATIONS_FLAG, observations)
	_update_tier(enemy_id)
	_refresh_progress()


static func _refresh_progress() -> void:
	var studied := studied_count()
	var mastered := mastered_count()
	CharacterService.set_flag(STUDIED_FLAG, studied)
	CharacterService.set_flag(MASTERED_FLAG, mastered)
	if is_complete() and not CharacterService.is_flag_truthy(COMPLETE_FLAG):
		CharacterService.set_flag(COMPLETE_FLAG, true)
		if AchievementService:
			AchievementService.notify("bestiary_completed")


static func clear_cache() -> void:
	_tiers.clear()
	_tiers_ready = false
	_entries.clear()
	_order.clear()
	_loaded = false


static func _kill_record() -> Dictionary:
	if CharacterService == null:
		return {}
	var raw: Variant = CharacterService.get_flag(KILLS_FLAG, {})
	return raw.duplicate() if raw is Dictionary else {}


static func _observation_record() -> Dictionary:
	if CharacterService == null:
		return {}
	var raw: Variant = CharacterService.get_flag(OBSERVATIONS_FLAG, {})
	return raw.duplicate(true) if raw is Dictionary else {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Variant = ContentLoader.load_json(CATALOG_PATH)
	if not data is Dictionary:
		push_warning("BestiaryService: missing %s" % CATALOG_PATH)
		return
	for entry in (data as Dictionary).get("entries", []):
		if not entry is Dictionary:
			continue
		var enemy_id := str((entry as Dictionary).get("enemyId", ""))
		if enemy_id == "":
			continue
		_entries[enemy_id] = entry
		_order.append(enemy_id)
