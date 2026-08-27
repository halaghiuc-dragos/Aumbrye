extends Node


signal quest_updated(quest_id: String, state: String)

const STATE_INACTIVE := "inactive"
const STATE_ACTIVE := "active"
const STATE_COMPLETED := "completed"

const TYPE_KILL := "kill"
const TYPE_FETCH := "fetch"
const TYPE_ESCAPE := "escape"
const TYPE_CLEAR_WITHOUT := "clear_without"
const TYPE_REACH_DEPTH := "reach_depth"
const TYPE_DISCOVER := "discover"
const TYPE_ESCORT := "escort"
const TYPE_DEFEAT_WITH := "defeat_with"

const QUEST_TYPES: Array[String] = [
	TYPE_KILL,
	TYPE_FETCH,
	TYPE_ESCAPE,
	TYPE_CLEAR_WITHOUT,
	TYPE_REACH_DEPTH,
	TYPE_DISCOVER,
	TYPE_ESCORT,
	TYPE_DEFEAT_WITH,
]

const RunLifecycleScript := preload("res://scripts/app/run_lifecycle.gd")

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
		if quest_type not in QUEST_TYPES:
			push_error("QuestService: quest '%s' has unknown type '%s'" % [quest_id, quest_type])
			assert(false, "QuestService: quest '%s' has unknown type '%s'" % [quest_id, quest_type])
			continue
		if not _active_by_type.has(quest_type):
			_active_by_type[quest_type] = []
		(_active_by_type[quest_type] as Array).append(quest_id)
	_index_built = true


func _active_quest_ids(quest_type: String) -> Array:
	if not _index_built:
		_rebuild_active_index()
	return _active_by_type.get(quest_type, [])


func get_completions(quest_id: String) -> int:
	return int(CharacterService.get_quest_progress(quest_id).get("completions", 0))


func prerequisites_met(quest_id: String) -> bool:
	var def := QuestCatalog.get_definition(quest_id)
	for prerequisite in def.get("prerequisites", []):
		var required_id := str(prerequisite)
		if required_id == "":
			continue
		if (
			CharacterService.get_quest_state(required_id) != STATE_COMPLETED
			and get_completions(required_id) <= 0
		):
			return false
	return true


func is_offerable(quest_id: String) -> bool:
	var def := QuestCatalog.get_definition(quest_id)
	if def.is_empty():
		return false
	if CharacterService.get_quest_state(quest_id) != STATE_INACTIVE:
		return false
	if not prerequisites_met(quest_id):
		return false
	if not DialogueConditions.evaluate(def.get("availableWhen")):
		return false
	if not BountyService.is_offerable(quest_id):
		return false
	var completions := get_completions(quest_id)
	if completions > 0 and not bool(def.get("repeatable", false)):
		return false
	var max_completions := int(def.get("maxCompletions", 0))
	if max_completions > 0 and completions >= max_completions:
		return false
	var cooldown_runs := int(def.get("cooldownRuns", 0))
	if cooldown_runs > 0 and completions > 0:
		var progress := CharacterService.get_quest_progress(quest_id)
		var last_run := int(progress.get("lastCompletedRun", 0))
		if _runs_started() < last_run + cooldown_runs:
			return false
	return true


func accept_quest(quest_id: String) -> bool:
	if not is_offerable(quest_id):
		return false
	var progress := CharacterService.get_quest_progress(quest_id)
	progress["count"] = 0
	progress["seen"] = []
	CharacterService.set_quest_state(quest_id, STATE_ACTIVE)
	CharacterService.set_quest_progress(quest_id, progress)
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
	var repeatable := bool(def.get("repeatable", false))
	var progress := CharacterService.get_quest_progress(quest_id)
	progress["completions"] = int(progress.get("completions", 0)) + 1
	progress["lastCompletedRun"] = _runs_started()
	progress["count"] = 0
	progress["seen"] = []
	var next_state := STATE_INACTIVE if repeatable else STATE_COMPLETED
	CharacterService.set_quest_state(quest_id, next_state)
	CharacterService.set_quest_progress(quest_id, progress)
	_rebuild_active_index()
	BountyService.notify_completed(quest_id)
	quest_updated.emit(quest_id, next_state)
	if AchievementService:
		AchievementService.notify("quest_completed")
	return true


func get_bounty_tokens() -> int:
	return BountyService.get_tokens()


func get_available_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest_id in QuestCatalog.get_all_ids():
		if is_offerable(quest_id):
			result.append(QuestCatalog.get_definition(quest_id))
	return result


func _runs_started() -> int:
	return int(CharacterService.get_flag("runs_started", 0))


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
	BestiaryService.record_kill(enemy_id)
	for quest_id in _active_quest_ids(TYPE_KILL).duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		var target: String = str(def.get("targetId", ""))
		if target != "" and enemy_id != "" and target != enemy_id:
			continue
		if not _run_context_matches(def):
			continue
		_advance_count(quest_id, def)
	for quest_id in _active_quest_ids(TYPE_DEFEAT_WITH).duplicate():
		var defeat_def := QuestCatalog.get_definition(quest_id)
		if enemy_id == "" or str(defeat_def.get("targetId", "")) != enemy_id:
			continue
		if not _run_context_matches(defeat_def):
			continue
		var required_weapon := str(defeat_def.get("weaponItemId", ""))
		if required_weapon != "" and _equipped_weapon_id() != required_weapon:
			continue
		_advance_count(quest_id, defeat_def)


func register_fetch(item_id: String) -> void:
	for quest_id in _active_quest_ids(TYPE_FETCH).duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		if str(def.get("targetItemId", "")) != item_id:
			continue
		var held := 0
		if InventoryService:
			held = InventoryService.count_item(item_id)
		var progress := CharacterService.get_quest_progress(quest_id)
		progress["count"] = held
		CharacterService.set_quest_progress(quest_id, progress)
		if held >= int(def.get("requiredCount", 1)):
			complete_quest(quest_id)


func register_discovery(discovery_id: String) -> void:
	if discovery_id == "":
		return
	for quest_id in _active_quest_ids(TYPE_DISCOVER).duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		var target := str(def.get("targetDiscoveryId", ""))
		if target != "" and target != discovery_id:
			continue
		if not _run_context_matches(def):
			continue
		var progress := CharacterService.get_quest_progress(quest_id)
		var seen: Array = progress.get("seen", [])
		if discovery_id in seen:
			continue
		seen.append(discovery_id)
		progress["seen"] = seen
		progress["count"] = int(progress.get("count", 0)) + 1
		CharacterService.set_quest_progress(quest_id, progress)
		if int(progress["count"]) >= int(def.get("requiredCount", 1)):
			complete_quest(quest_id)


func register_rescue(npc_id: String) -> void:
	if npc_id == "":
		return
	for quest_id in _active_quest_ids(TYPE_ESCORT).duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		var target := str(def.get("targetNpcId", ""))
		if target != "" and target != npc_id:
			continue
		_advance_count(quest_id, def)


func register_run_outcome(outcome: String, _context: Dictionary = {}) -> void:
	var results: Dictionary = {}
	if RunFlow:
		results = RunFlow.last_run_results
	_record_last_run(outcome, results)
	_check_escape_quests(outcome == RunLifecycleScript.OUTCOME_ESCAPED)
	_check_clear_without_quests(outcome, results)
	_check_reach_depth_quests(results)


func _record_last_run(outcome: String, results: Dictionary) -> void:
	if CharacterService == null:
		return
	var summary := {
		"outcome": outcome,
		"biome": "",
		"dungeon": "",
		"tier": 0,
		"floor": int(results.get("floor_reached", 0)),
		"boss": bool(results.get("boss_defeated", false)),
		"kills": int(results.get("kills", 0)),
	}
	if RunFlow:
		summary["biome"] = str(RunFlow.current_biome_id)
		summary["dungeon"] = str(RunFlow.current_dungeon_id)
		summary["tier"] = int(RunFlow.current_difficulty_tier)
	CharacterService.set_flag("last_run", summary)


func _on_run_started() -> void:
	_reset_escape_progress()


func _on_run_ended(_results: Dictionary) -> void:
	_reset_escape_progress()


func _reset_escape_progress() -> void:
	for quest_id in _active_quest_ids(TYPE_ESCAPE):
		var progress := CharacterService.get_quest_progress(quest_id)
		progress["escaped"] = false
		CharacterService.set_quest_progress(quest_id, progress)


func _check_escape_quests(escaped: bool) -> void:
	if not escaped:
		return
	for quest_id in _active_quest_ids(TYPE_ESCAPE).duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		if not _run_context_matches(def):
			continue
		complete_quest(quest_id)


func _check_clear_without_quests(outcome: String, results: Dictionary) -> void:
	if outcome != RunLifecycleScript.OUTCOME_ESCAPED:
		return
	for quest_id in _active_quest_ids(TYPE_CLEAR_WITHOUT).duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		if not _run_context_matches(def):
			continue
		var max_seconds := float(def.get("maxSeconds", 0.0))
		if max_seconds > 0.0 and float(results.get("time_seconds", 0.0)) > max_seconds:
			continue
		var max_kills := int(def.get("maxKills", -1))
		if max_kills >= 0 and int(results.get("kills", 0)) > max_kills:
			continue
		if bool(def.get("requiresBoss", false)) and not bool(results.get("boss_defeated", false)):
			continue
		complete_quest(quest_id)


func _check_reach_depth_quests(results: Dictionary) -> void:
	for quest_id in _active_quest_ids(TYPE_REACH_DEPTH).duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		if not _run_context_matches(def):
			continue
		if int(results.get("floor_reached", 0)) < int(def.get("requiredCount", 1)):
			continue
		complete_quest(quest_id)


func _advance_count(quest_id: String, def: Dictionary) -> void:
	var progress := CharacterService.get_quest_progress(quest_id)
	var count: int = int(progress.get("count", 0)) + 1
	progress["count"] = count
	CharacterService.set_quest_progress(quest_id, progress)
	if count >= int(def.get("requiredCount", 1)):
		complete_quest(quest_id)


func _run_context_matches(def: Dictionary) -> bool:
	if RunFlow == null:
		return true
	var dungeon_id := str(def.get("dungeonId", ""))
	if dungeon_id != "" and str(RunFlow.current_dungeon_id) != dungeon_id:
		return false
	var biome_id := str(def.get("biomeId", ""))
	if biome_id != "" and str(RunFlow.current_biome_id) != biome_id:
		return false
	var min_tier := int(def.get("minDifficultyTier", 0))
	if min_tier > 0 and int(RunFlow.current_difficulty_tier) < min_tier:
		return false
	return true


func _equipped_weapon_id() -> String:
	if InventoryService == null:
		return ""
	return str(InventoryService.inventory.get_equipped_weapon_id())


func _grant_rewards(def: Dictionary) -> void:
	var rewards: Variant = def.get("rewards", {})
	if not rewards is Dictionary:
		return
	if rewards.has("gold"):
		CharacterService.add_gold(int(rewards.get("gold", 0)))
	for item_entry in rewards.get("items", []):
		if not item_entry is Dictionary:
			continue
		var reward_id := str(item_entry.get("itemId", ""))
		if reward_id == "":
			continue
		var reward_qty := maxi(1, int(item_entry.get("quantity", 1)))
		for _i in reward_qty:
			if not InventoryService.add_item(reward_id, 1):
				InventoryService.notify_reward_lost(reward_id)
				break
	for flag_entry in rewards.get("flags", []):
		if flag_entry is Dictionary:
			CharacterService.set_flag(
				str(flag_entry.get("flag", "")), flag_entry.get("value", true)
			)
	var recipe_id := str(rewards.get("recipeId", ""))
	if recipe_id != "" and LocalSave:
		LocalSave.add_recipe(recipe_id)
