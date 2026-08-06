extends Node

## Autoload — gold, level, flags, quest progress (M4 character state).

signal gold_changed(amount: int)
signal coins_changed(amount: int)
signal level_changed(level: int)
signal flags_changed
signal quests_changed
signal appearance_changed(profile: Dictionary)

const DEFAULT_GOLD := 100
const DEFAULT_LEVEL := 1

const VALID_QUEST_STATES: Array[String] = [
	"inactive",
	"active",
	"completed",
	"turned_in",
]

var gold: int = DEFAULT_GOLD
var class_id: String = ""
var appearance_theme: int = 0
var appearance_profile: Dictionary = CharacterAppearance.default_profile()
var flags: Dictionary = {}
var quest_states: Dictionary = {}
var quest_progress: Dictionary = {}

var _unregistered_flag_ids: Dictionary = {}

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


func get_flag(flag_id: String, default_value: Variant = null) -> Variant:
	if flags.has(flag_id):
		return flags[flag_id]
	if default_value != null:
		return default_value
	return CharacterFlags.default_for(flag_id)


func set_flag(flag_id: String, value: Variant = true) -> void:
	if not CharacterFlags.is_registered(flag_id):
		_unregistered_flag_ids[flag_id] = true
	var coerced: Variant = CharacterFlags.coerce(flag_id, value)
	if coerced == null and not CharacterFlags.is_registered(flag_id):
		return
	flags[flag_id] = coerced
	flags_changed.emit()
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)


func has_flag(flag_id: String) -> bool:
	return is_flag_truthy(flag_id)


func is_flag_truthy(flag_id: String) -> bool:
	return CharacterFlags.is_truthy(flag_id, get_flag(flag_id))


func unregistered_flag_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for flag_id in _unregistered_flag_ids:
		ids.append(flag_id)
	return ids


func get_coins() -> int:
	return gold


func add_coins(amount: int, apply_bonus: bool = true) -> void:
	add_gold(amount, apply_bonus)


func spend_coins(amount: int) -> bool:
	return spend_gold(amount)


func can_afford_coins(amount: int) -> bool:
	return can_afford(amount)


## BUG-42: apply_bonus must be false for every refund/credit path (a failed purchase, a failed
## unlock, a save restore) — goldFind is meant to reward *earning* gold, not crediting it back.
## Applying it to refunds turned "fail a purchase with a full bag" into a repeatable money
## printer, since the refund itself compounded the same bonus that made the bag fill up.
func add_gold(amount: int, apply_bonus: bool = true) -> void:
	if amount <= 0:
		return
	var adjusted := amount
	if apply_bonus:
		var bonus: float = 0.0
		if ProgressionService:
			bonus = float(ProgressionService.get_talent_stat_totals().get("goldFind", 0.0))
		adjusted = int(round(float(amount) * (1.0 + bonus)))
	if adjusted <= 0:
		return
	gold += adjusted
	gold_changed.emit(gold)
	coins_changed.emit(gold)
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	coins_changed.emit(gold)
	LocalSave.request_autosave(LocalSave.SavePriority.IMMEDIATE)
	return true


func can_afford(amount: int) -> bool:
	return gold >= amount


func get_quest_state(quest_id: String) -> String:
	return str(quest_states.get(quest_id, "inactive"))


func set_quest_state(quest_id: String, state: String) -> void:
	if state not in VALID_QUEST_STATES:
		push_warning(
			"CharacterService: rejected unknown quest state '%s' for '%s'" % [state, quest_id]
		)
		return
	quest_states[quest_id] = state
	quests_changed.emit()
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)


func get_quest_progress(quest_id: String) -> Dictionary:
	var entry: Variant = quest_progress.get(quest_id, {})
	return entry.duplicate(true) if entry is Dictionary else {}


func set_quest_progress(quest_id: String, progress: Dictionary) -> void:
	quest_progress[quest_id] = progress.duplicate(true)
	quests_changed.emit()
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)


func active_quest_ids() -> Array[String]:
	var ids: Array[String] = []
	for quest_id in quest_states:
		if str(quest_states[quest_id]) == "active":
			ids.append(str(quest_id))
	return ids


func clear_quest(quest_id: String) -> void:
	quest_states.erase(quest_id)
	quest_progress.erase(quest_id)
	quests_changed.emit()
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)


func get_class_id() -> String:
	return class_id


func set_class_id(new_class_id: String) -> void:
	class_id = new_class_id
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)


func to_save_dict() -> Dictionary:
	return {
		"gold": gold,
		"classId": class_id,
		"appearanceTheme": appearance_theme,
		"appearance": appearance_profile.duplicate(true),
		"flags": flags.duplicate(true),
		"quests":
		{
			"states": quest_states.duplicate(true),
			"progress": quest_progress.duplicate(true),
		},
	}


func from_save_dict(data: Dictionary) -> void:
	var saved_gold := int(data.get("gold", DEFAULT_GOLD))
	var saved_coins: Variant = data.get("coins", saved_gold)
	gold = maxi(saved_gold, int(saved_coins))
	class_id = str(data.get("classId", ""))
	appearance_theme = int(data.get("appearanceTheme", 0))
	appearance_profile = CharacterAppearance.sanitize(
		data.get("appearance", {"theme": appearance_theme})
	)
	appearance_theme = int(appearance_profile.get("theme", appearance_theme))
	_unregistered_flag_ids.clear()
	flags = CharacterFlags.coerce_all(data.get("flags", {}))
	_load_quests_from_save(data.get("quests", {}))
	gold_changed.emit(gold)
	coins_changed.emit(gold)
	level_changed.emit(get_level())
	flags_changed.emit()
	quests_changed.emit()


func reset_to_defaults() -> void:
	gold = DEFAULT_GOLD
	class_id = ""
	appearance_theme = 0
	appearance_profile = CharacterAppearance.default_profile()
	flags.clear()
	quest_states.clear()
	quest_progress.clear()
	_unregistered_flag_ids.clear()
	gold_changed.emit(gold)
	coins_changed.emit(gold)
	level_changed.emit(get_level())
	flags_changed.emit()
	quests_changed.emit()


func _load_quests_from_save(saved: Variant) -> void:
	quest_states.clear()
	quest_progress.clear()
	if not saved is Dictionary:
		push_warning("CharacterService: quests payload is %s, expected Dictionary" % typeof(saved))
		return
	var quests: Dictionary = saved
	if quests.has("states") or quests.has("progress"):
		var states: Variant = quests.get("states", {})
		if states is Dictionary:
			for quest_id in states:
				quest_states[str(quest_id)] = str(states[quest_id])
		var progress: Variant = quests.get("progress", {})
		if progress is Dictionary:
			for quest_id in progress:
				var entry: Variant = progress[quest_id]
				if entry is Dictionary:
					quest_progress[str(quest_id)] = entry.duplicate(true)
		return
	for key in quests:
		var quest_key := str(key)
		var value: Variant = quests[key]
		if quest_key.ends_with("_progress"):
			var owner_id := quest_key.substr(0, quest_key.length() - 9)
			if value is Dictionary:
				quest_progress[owner_id] = value.duplicate(true)
		else:
			quest_states[quest_key] = str(value)
