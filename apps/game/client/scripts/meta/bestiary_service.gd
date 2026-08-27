class_name BestiaryService
extends RefCounted


const CATALOG_PATH := "content/bestiary/entries.json"
const KILLS_FLAG := "bestiary_kills"
const STUDIED_FLAG := "bestiary_studied_count"
const MASTERED_FLAG := "bestiary_mastered_count"
const COMPLETE_FLAG := "bestiary_complete"

const TIER_UNKNOWN := 0
const TIER_SIGHTED := 1
const TIER_STUDIED := 2
const TIER_MASTERED := 3

const KILLS_FOR_SIGHTED := 1
const KILLS_FOR_STUDIED := 10
const KILLS_FOR_MASTERED := 25

static var _entries: Dictionary = {}
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


static func get_tier(enemy_id: String) -> int:
	var kills := get_kills(enemy_id)
	if kills >= KILLS_FOR_MASTERED:
		return TIER_MASTERED
	if kills >= KILLS_FOR_STUDIED:
		return TIER_STUDIED
	if kills >= KILLS_FOR_SIGHTED:
		return TIER_SIGHTED
	return TIER_UNKNOWN


static func kills_to_next_tier(enemy_id: String) -> int:
	var kills := get_kills(enemy_id)
	if kills < KILLS_FOR_SIGHTED:
		return KILLS_FOR_SIGHTED - kills
	if kills < KILLS_FOR_STUDIED:
		return KILLS_FOR_STUDIED - kills
	if kills < KILLS_FOR_MASTERED:
		return KILLS_FOR_MASTERED - kills
	return 0


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
	var studied := studied_count()
	var mastered := mastered_count()
	CharacterService.set_flag(STUDIED_FLAG, studied)
	CharacterService.set_flag(MASTERED_FLAG, mastered)
	if is_complete() and not CharacterService.is_flag_truthy(COMPLETE_FLAG):
		CharacterService.set_flag(COMPLETE_FLAG, true)
		if AchievementService:
			AchievementService.notify("bestiary_completed")


static func clear_cache() -> void:
	_entries.clear()
	_order.clear()
	_loaded = false


static func _kill_record() -> Dictionary:
	if CharacterService == null:
		return {}
	var raw: Variant = CharacterService.get_flag(KILLS_FLAG, {})
	return raw.duplicate() if raw is Dictionary else {}


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
