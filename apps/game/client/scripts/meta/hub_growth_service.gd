class_name HubGrowthService
extends RefCounted

## Which hub dressing the player has earned, derived from progress that already persists.

const CATALOG_PATH := "content/ui/hub_growth.json"

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


## Ids of every dressing piece the hub should be showing right now.
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


## Dressing ids grouped by the hub anchor they belong to, for a diorama to spawn against.
static func get_unlocked_by_anchor() -> Dictionary:
	var counters := ProgressCounters.snapshot()
	var grouped := {}
	for entry in get_all():
		var condition: Variant = entry.get("condition", {})
		if not condition is Dictionary:
			continue
		if not ProgressCounters.meets(condition as Dictionary, counters):
			continue
		var anchor := str(entry.get("anchor", ""))
		if anchor == "":
			continue
		if not grouped.has(anchor):
			grouped[anchor] = []
		(grouped[anchor] as Array).append(str(entry.get("id", "")))
	return grouped


## Every dressing piece with its state and, when still shut, what is missing.
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
