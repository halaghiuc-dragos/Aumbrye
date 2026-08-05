extends Node

## Autoload — gold, level, flags, quest progress (M4 character state).

signal gold_changed(amount: int)
signal coins_changed(amount: int)
signal level_changed(level: int)
signal flags_changed
signal quests_changed

const DEFAULT_GOLD := 100
const DEFAULT_LEVEL := 1

var gold: int = DEFAULT_GOLD
var coins: int = DEFAULT_GOLD
var class_id: String = ""
var appearance_theme: int = 0
var flags: Dictionary = {}
var quests: Dictionary = {}


var level: int:
	get:
		return get_level()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ProgressionService:
		ProgressionService.progression_changed.connect(_on_progression_changed)


func get_level() -> int:
	if ProgressionService:
		return ProgressionService.level
	return DEFAULT_LEVEL


func _on_progression_changed() -> void:
	level_changed.emit(get_level())


func get_flag(flag_id: String, default_value: Variant = false) -> Variant:
	return flags.get(flag_id, default_value)


func set_flag(flag_id: String, value: Variant = true) -> void:
	flags[flag_id] = value
	flags_changed.emit()
	LocalSave.autosave()


func has_flag(flag_id: String) -> bool:
	return bool(flags.get(flag_id, false))


func get_coins() -> int:
	return coins


func add_coins(amount: int) -> void:
	add_gold(amount)


func spend_coins(amount: int) -> bool:
	return spend_gold(amount)


func can_afford_coins(amount: int) -> bool:
	return can_afford(amount)


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	coins = gold
	gold_changed.emit(gold)
	coins_changed.emit(coins)
	LocalSave.autosave()


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	coins = gold
	gold_changed.emit(gold)
	coins_changed.emit(coins)
	LocalSave.autosave()
	return true


func can_afford(amount: int) -> bool:
	return gold >= amount


func set_level(_new_level: int) -> void:
	# Level is owned by ProgressionService; kept for legacy callers.
	level_changed.emit(get_level())


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


func get_class_id() -> String:
	return class_id


func set_class_id(new_class_id: String) -> void:
	class_id = new_class_id
	LocalSave.autosave()


func to_save_dict() -> Dictionary:
	return {
		"gold": gold,
		"coins": coins,
		"classId": class_id,
		"appearanceTheme": appearance_theme,
		"flags": flags.duplicate(),
		"quests": quests.duplicate(),
	}


func from_save_dict(data: Dictionary) -> void:
	gold = int(data.get("coins", data.get("gold", DEFAULT_GOLD)))
	coins = gold
	class_id = str(data.get("classId", ""))
	appearance_theme = int(data.get("appearanceTheme", 0))
	flags = {}
	var saved_flags: Variant = data.get("flags", {})
	if saved_flags is Dictionary:
		flags = saved_flags.duplicate()
	quests = {}
	var saved_quests: Variant = data.get("quests", {})
	if saved_quests is Dictionary:
		quests = saved_quests.duplicate()
	gold_changed.emit(gold)
	coins_changed.emit(coins)
	level_changed.emit(get_level())


func reset_to_defaults() -> void:
	gold = DEFAULT_GOLD
	coins = DEFAULT_GOLD
	class_id = ""
	appearance_theme = 0
	flags.clear()
	quests.clear()
	gold_changed.emit(gold)
	coins_changed.emit(coins)
	level_changed.emit(get_level())
