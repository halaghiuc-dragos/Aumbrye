class_name HubGrowthService
extends RefCounted


const CATALOG_PATH := "content/ui/hub_growth.json"
const FLAG_SEEN := "hub_growth_seen"
const FLAG_PENDING := "hub_growth_pending"

static var _entries: Array[Dictionary] = []
static var _loaded := false


static func clear_cache() -> void:
	_entries.clear()
	_loaded = false


static func get_all() -> Array[Dictionary]:
	_ensure_loaded()
	return _entries.duplicate()


static func get_entry(entry_id: String) -> Dictionary:
	_ensure_loaded()
	for entry in _entries:
		if str(entry.get("id", "")) == entry_id:
			return entry
	return {}


static func get_unlocked_ids() -> Array[String]:
	var counters := ProgressCounters.snapshot()
	var out: Array[String] = []
	for entry in get_all():
		var condition: Variant = entry.get("condition", {})
		if not condition is Dictionary:
			continue
		if ProgressCounters.meets(condition as Dictionary, counters):
			out.append(str(entry.get("id", "")))
	return out


static func is_unlocked(entry_id: String, counters: Dictionary = {}) -> bool:
	var entry := get_entry(entry_id)
	if entry.is_empty():
		return false
	var condition: Variant = entry.get("condition", {})
	if not condition is Dictionary:
		return false
	return ProgressCounters.meets(condition as Dictionary, counters)


static func get_standing() -> Array[Dictionary]:
	var counters := ProgressCounters.snapshot()
	var rows: Array[Dictionary] = []
	for entry in get_all():
		var condition: Variant = entry.get("condition", {})
		var condition_dict: Dictionary = condition if condition is Dictionary else {}
		var unlocked := ProgressCounters.meets(condition_dict, counters)
		var row := {
			"id": str(entry.get("id", "")),
			"name": str(entry.get("name", "")),
			"anchor": str(entry.get("anchor", "")),
			"prop": str(entry.get("prop", "")),
			"description": str(entry.get("description", "")),
			"unlocked": unlocked,
			"requirement": "",
		}
		if not unlocked:
			var missing := ProgressCounters.shortfall(condition_dict, counters)
			if not missing.is_empty():
				row["requirement"] = (
					"%d %s — you have %d"
					% [
						int(missing.get("need", 0)),
						ProgressCounters.describe(str(missing.get("key", ""))),
						int(missing.get("have", 0)),
					]
				)
		rows.append(row)
	return rows


static func unlocked_count() -> int:
	return get_unlocked_ids().size()


static func total_count() -> int:
	return get_all().size()


## `SY-03`: mirrors `VaultService.evaluate()`/`consume_announcements()` exactly -- cheap and
## idempotent, safe to call any time progress may have moved (a run's end, hub boot). Newly-unlocked
## entries queue for `consume_announcements()`, which the hub drains on its own boot pass to give
## the player one line naming what just changed, the same beat `_spawn_growth_props()` in
## `hub_diorama.gd` builds into the plaza.
static func evaluate() -> Array[Dictionary]:
	var seen := _seen_record()
	var pending := _pending_record()
	var opened: Array[Dictionary] = []
	var dirty := false
	for entry_id in get_unlocked_ids():
		if bool(seen.get(entry_id, false)):
			continue
		seen[entry_id] = true
		pending[entry_id] = true
		dirty = true
		opened.append(get_entry(entry_id).duplicate(true))
	if dirty:
		CharacterService.set_flag(FLAG_SEEN, seen)
		CharacterService.set_flag(FLAG_PENDING, pending)
	return opened


## Drains the queue of unlocks the player has not been shown yet.
static func consume_announcements() -> Array[Dictionary]:
	var pending := _pending_record()
	if pending.is_empty():
		return []
	var out: Array[Dictionary] = []
	for entry_id in pending.keys():
		var entry := get_entry(str(entry_id))
		if not entry.is_empty():
			out.append(entry.duplicate(true))
	CharacterService.set_flag(FLAG_PENDING, {})
	return out


static func _seen_record() -> Dictionary:
	var stored: Variant = CharacterService.get_flag(FLAG_SEEN, {})
	return (stored as Dictionary).duplicate() if stored is Dictionary else {}


static func _pending_record() -> Dictionary:
	var stored: Variant = CharacterService.get_flag(FLAG_PENDING, {})
	return (stored as Dictionary).duplicate() if stored is Dictionary else {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Variant = ContentLoader.load_json(CATALOG_PATH)
	if not data is Dictionary:
		push_warning("HubGrowthService: missing %s" % CATALOG_PATH)
		return
	for entry in (data as Dictionary).get("entries", []):
		if entry is Dictionary:
			_entries.append(entry)
