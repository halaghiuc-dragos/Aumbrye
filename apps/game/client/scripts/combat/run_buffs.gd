extends Node

## In-run relics and buffs — cleared on run end (PROG-4.3).

signal buffs_changed

var _active: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_active_buffs() -> Array[Dictionary]:
	return _active.duplicate(true)


func has_relic(relic_id: String) -> bool:
	for entry in _active:
		if entry.get("relicId", "") == relic_id:
			return true
	return false


func add_relic(relic_id: String) -> bool:
	var def := RelicCatalog.get_definition(relic_id)
	if def.is_empty():
		return false
	var max_stacks: int = int(def.get("maxStacks", 1))
	var current_stacks := 0
	for entry in _active:
		if entry.get("relicId", "") == relic_id:
			current_stacks = int(entry.get("stacks", 1))
			break
	if current_stacks >= max_stacks:
		return false
	if current_stacks == 0:
		_active.append({"relicId": relic_id, "stacks": 1})
	else:
		for entry in _active:
			if entry.get("relicId", "") == relic_id:
				entry["stacks"] = current_stacks + 1
				break
	buffs_changed.emit()
	return true


func get_stat_totals() -> Dictionary:
	var totals: Dictionary = {}
	for entry in _active:
		var def: Dictionary = RelicCatalog.get_definition(str(entry.get("relicId", "")))
		var stacks: int = int(entry.get("stacks", 1))
		var stats: Dictionary = def.get("stats", {})
		for stat in stats:
			totals[stat] = totals.get(stat, 0.0) + float(stats[stat]) * stacks
	return totals


func clear_all() -> void:
	if _active.is_empty():
		return
	_active.clear()
	buffs_changed.emit()


func to_save_array() -> Array:
	return _active.duplicate(true)


func from_save_array(data: Variant) -> void:
	_active.clear()
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				_active.append(entry.duplicate())
	buffs_changed.emit()
