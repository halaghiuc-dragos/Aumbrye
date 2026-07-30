extends Node

## Autoload — gold, level, flags, quest progress (M4 character state).

signal gold_changed(amount: int)
signal level_changed(level: int)
signal flags_changed
signal quests_changed

const DEFAULT_GOLD := 100
const DEFAULT_LEVEL := 1

var gold: int = DEFAULT_GOLD
var level: int = DEFAULT_LEVEL
var flags: Dictionary = {}
var quests: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_flag(flag_id: String, default_value: Variant = false) -> Variant:
	return flags.get(flag_id, default_value)


func set_flag(flag_id: String, value: Variant = true) -> void:
	flags[flag_id] = value
	flags_changed.emit()
	LocalSave.autosave()


func has_flag(flag_id: String) -> bool:
	return bool(flags.get(flag_id, false))


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)
	LocalSave.autosave()


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	LocalSave.autosave()
	return true


func can_afford(amount: int) -> bool:
	return gold >= amount


func set_level(new_level: int) -> void:
	level = maxi(1, new_level)
	level_changed.emit(level)
	LocalSave.autosave()


func get_quest_state(quest_id: String) -> String:
	return str(quests.get(quest_id, "inactive"))


func set_quest_state(quest_id: String, state: String) -> void:
	quests[quest_id] = state
	quests_changed.emit()
	LocalSave.autosave()


func get_quest_progress(quest_id: String) -> Dictionary:
	var entry: Variant = quests.get(quest_id + "_progress", {})
	return entry if entry is Dictionary else {}


func set_quest_progress(quest_id: String, progress: Dictionary) -> void:
	quests[quest_id + "_progress"] = progress.duplicate()
	quests_changed.emit()
	LocalSave.autosave()


func to_save_dict() -> Dictionary:
	return {
		"gold": gold,
		"level": level,
		"flags": flags.duplicate(),
		"quests": quests.duplicate(),
	}


func from_save_dict(data: Dictionary) -> void:
	gold = int(data.get("gold", DEFAULT_GOLD))
	level = int(data.get("level", DEFAULT_LEVEL))
	flags = {}
	var saved_flags: Variant = data.get("flags", {})
	if saved_flags is Dictionary:
		flags = saved_flags.duplicate()
	quests = {}
	var saved_quests: Variant = data.get("quests", {})
	if saved_quests is Dictionary:
		quests = saved_quests.duplicate()
	gold_changed.emit(gold)
	level_changed.emit(level)


func reset_to_defaults() -> void:
	gold = DEFAULT_GOLD
	level = DEFAULT_LEVEL
	flags.clear()
	quests.clear()
	gold_changed.emit(gold)
	level_changed.emit(level)
