extends Node

## Quest progress tracking — optional, never blocks portals (QUEST-4.1).

signal quest_updated(quest_id: String, state: String)

const STATE_INACTIVE := "inactive"
const STATE_ACTIVE := "active"
const STATE_COMPLETED := "completed"

const RunLifecycleScript := preload("res://scripts/app/run_lifecycle.gd")

## Active quest ids indexed by trigger type ("kill", "fetch", "escape"), rebuilt only when
## quest state actually changes (accept/complete/save load) rather than scanned per trigger.
var _active_by_type: Dictionary = {}
var _index_built := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RunFlow.run_started.connect(_on_run_started)
	RunFlow.run_ended.connect(_on_run_ended)
	if CharacterService and not CharacterService.quests_changed.is_connected(_rebuild_active_index):
		CharacterService.quests_changed.connect(_rebuild_active_index)


func _rebuild_active_index() -> void:
	_active_by_type.clear()
	for quest_id in QuestCatalog.get_all_ids():
		if CharacterService.get_quest_state(quest_id) != STATE_ACTIVE:
			continue
		var def := QuestCatalog.get_definition(quest_id)
		var quest_type := str(def.get("type", ""))
		if quest_type == "":
			continue
		if not _active_by_type.has(quest_type):
			_active_by_type[quest_type] = []
		(_active_by_type[quest_type] as Array).append(quest_id)
	_index_built = true


func _active_quest_ids(quest_type: String) -> Array:
	if not _index_built:
		_rebuild_active_index()
	return _active_by_type.get(quest_type, [])


func accept_quest(quest_id: String) -> bool:
	var def := QuestCatalog.get_definition(quest_id)
	if def.is_empty():
		return false
	var current := CharacterService.get_quest_state(quest_id)
	if current == STATE_ACTIVE or current == STATE_COMPLETED:
		return false
	CharacterService.set_quest_state(quest_id, STATE_ACTIVE)
	CharacterService.set_quest_progress(quest_id, {"count": 0})
	_rebuild_active_index()
	quest_updated.emit(quest_id, STATE_ACTIVE)
	return true


func complete_quest(quest_id: String) -> bool:
	var def := QuestCatalog.get_definition(quest_id)
	if def.is_empty():
		return false
	if CharacterService.get_quest_state(quest_id) != STATE_ACTIVE:
		return false
	_grant_rewards(def)
	CharacterService.set_quest_state(quest_id, STATE_COMPLETED)
	_rebuild_active_index()
	quest_updated.emit(quest_id, STATE_COMPLETED)
	if AchievementService:
		AchievementService.notify("quest_completed")
	return true


func get_available_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest_id in QuestCatalog.get_all_ids():
		var def := QuestCatalog.get_definition(quest_id)
		var state := CharacterService.get_quest_state(quest_id)
		if state == STATE_INACTIVE:
			result.append(def)
	return result


func get_active_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest_id in QuestCatalog.get_all_ids():
		if CharacterService.get_quest_state(quest_id) == STATE_ACTIVE:
			result.append(QuestCatalog.get_definition(quest_id))
	return result


func get_completed_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest_id in QuestCatalog.get_all_ids():
		if CharacterService.get_quest_state(quest_id) == STATE_COMPLETED:
			result.append(QuestCatalog.get_definition(quest_id))
	return result


func register_kill(enemy_id: String = "") -> void:
	for quest_id in _active_quest_ids("kill").duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		var target: String = str(def.get("targetId", ""))
		if target != "" and enemy_id != "" and target != enemy_id:
			continue
		var progress := CharacterService.get_quest_progress(quest_id)
		var count: int = int(progress.get("count", 0)) + 1
		progress["count"] = count
		CharacterService.set_quest_progress(quest_id, progress)
		var required: int = int(def.get("requiredCount", 1))
		if count >= required:
			complete_quest(quest_id)


func register_fetch(item_id: String) -> void:
	for quest_id in _active_quest_ids("fetch").duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		if str(def.get("targetItemId", "")) != item_id:
			continue
		complete_quest(quest_id)


func register_run_outcome(outcome: String, _context: Dictionary = {}) -> void:
	_check_escape_quests(outcome == RunLifecycleScript.OUTCOME_ESCAPED)


func _on_run_started() -> void:
	for quest_id in _active_quest_ids("escape"):
		CharacterService.set_quest_progress(quest_id, {"escaped": false})


func _on_run_ended(_results: Dictionary) -> void:
	for quest_id in _active_quest_ids("escape"):
		CharacterService.set_quest_progress(quest_id, {"escaped": false})


func _check_escape_quests(escaped: bool) -> void:
	if not escaped:
		return
	for quest_id in _active_quest_ids("escape").duplicate():
		complete_quest(quest_id)


func _grant_rewards(def: Dictionary) -> void:
	var rewards: Variant = def.get("rewards", {})
	if not rewards is Dictionary:
		return
	if rewards.has("gold"):
		CharacterService.add_gold(int(rewards.get("gold", 0)))
	for item_entry in rewards.get("items", []):
		if item_entry is Dictionary:
			InventoryService.add_item(
				str(item_entry.get("itemId", "")), int(item_entry.get("quantity", 1))
			)
