class_name RunModeCatalog
extends RefCounted


const CATALOG_PATH := "content/modes/catalog.json"

static var _modes: Dictionary = {}
static var _order: Array[String] = []
static var _loaded := false


static func clear_cache() -> void:
	_modes.clear()
	_order.clear()
	_loaded = false


static func get_all() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for mode_id in _order:
		out.append(_modes[mode_id])
	return out


static func get_mode(mode_id: String) -> Dictionary:
	_ensure_loaded()
	var mode: Variant = _modes.get(mode_id, {})
	return mode if mode is Dictionary else {}


static func has_mode(mode_id: String) -> bool:
	_ensure_loaded()
	return _modes.has(mode_id)


static func base_mode_of(mode_id: String) -> String:
	return str(get_mode(mode_id).get("baseMode", RunModeConfig.MODE_CASTLE))


static func dungeon_of(mode_id: String) -> String:
	var dungeon_id := str(get_mode(mode_id).get("dungeonId", ""))
	return dungeon_id if dungeon_id != "" else DungeonCatalog.DEFAULT_DUNGEON_ID


static func floors_of(mode_id: String) -> int:
	return int(get_mode(mode_id).get("floors", 0))


static func is_permadeath(mode_id: String) -> bool:
	return bool(get_mode(mode_id).get("permadeath", false))


static func scoring_of(mode_id: String) -> String:
	return str(get_mode(mode_id).get("scoring", "depth"))


static func base_modifiers(mode_id: String) -> Array[String]:
	return _string_array(get_mode(mode_id).get("modifiers", []))


static func modifiers_for_floor(mode_id: String, floor_index: int) -> Array[String]:
	var active := base_modifiers(mode_id)
	var steps: Variant = get_mode(mode_id).get("escalation", [])
	if steps is Array:
		for step in steps as Array:
			if not step is Dictionary:
				continue
			if floor_index < int((step as Dictionary).get("fromFloor", 1)):
				continue
			for modifier_id in _string_array((step as Dictionary).get("modifiers", [])):
				if modifier_id not in active:
					active.append(modifier_id)
	return active


static func unlock_condition(mode_id: String) -> Dictionary:
	var condition: Variant = get_mode(mode_id).get("unlock", {})
	return condition if condition is Dictionary else {}


static func is_unlocked(mode_id: String, counters: Dictionary = {}) -> bool:
	return ProgressCounters.meets(unlock_condition(mode_id), counters)


static func unlock_hint(mode_id: String, counters: Dictionary = {}) -> String:
	var missing := ProgressCounters.shortfall(unlock_condition(mode_id), counters)
	if missing.is_empty():
		return ""
	return (
		"Locked — %d %s (you have %d)"
		% [
			int(missing.get("need", 0)),
			ProgressCounters.describe(str(missing.get("key", ""))),
			int(missing.get("have", 0)),
		]
	)


static func describe_rules(mode_id: String) -> String:
	var lines: Array[String] = []
	var floors := floors_of(mode_id)
	if floors > 0:
		lines.append("%d floors." % floors)
	if is_permadeath(mode_id):
		lines.append("No bonfire return — where you fall, the run ends.")
	match scoring_of(mode_id):
		"time":
			lines.append("Scored by how fast you finish.")
		"kills":
			lines.append("Scored by how much you kill.")
		_:
			lines.append("Scored by how deep you get.")
	var modifiers := base_modifiers(mode_id)
	if not modifiers.is_empty():
		lines.append(RunModifierService.describe_all(modifiers))
	var steps: Variant = get_mode(mode_id).get("escalation", [])
	if steps is Array and not (steps as Array).is_empty():
		lines.append("The rules harden as you descend.")
	return "\n".join(lines)


static func _string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if not raw is Array:
		return out
	for entry in raw as Array:
		var value := str(entry)
		if value != "" and value not in out:
			out.append(value)
	return out


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Variant = ContentLoader.load_json(CATALOG_PATH)
	if not data is Dictionary:
		push_warning("RunModeCatalog: missing %s" % CATALOG_PATH)
		return
	for entry in (data as Dictionary).get("modes", []):
		if not entry is Dictionary:
			continue
		var mode_id := str((entry as Dictionary).get("id", ""))
		if mode_id == "":
			continue
		_modes[mode_id] = entry
		_order.append(mode_id)
