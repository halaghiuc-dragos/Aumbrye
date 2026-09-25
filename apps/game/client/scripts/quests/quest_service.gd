extends Node


signal quest_updated(quest_id: String, state: String)
## SY-02: fired on every progress tick, not just on completion -- `quest_updated` only fires from
## `complete_quest()`, so a kill/fetch quest going from 1/3 to 2/3 previously produced no signal at
## all for anything to show a toast off of.
signal quest_progress_advanced(quest_id: String, count: int, required: int)
signal quest_progress_changed(
	quest_id: String, objective_id: String, old_count: int, new_count: int, required: int
)

const STATE_INACTIVE := "inactive"
const STATE_ACTIVE := "active"
const STATE_COMPLETED := "completed"
const STATE_SETTLING := "settling"

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
const REWARD_RECEIPTS_FLAG := "quest_reward_receipts"

var _active_by_type: Dictionary = {}
var _index_built := false
var _fetch_reconcile_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RunFlow.run_started.connect(_on_run_started)
	RunFlow.run_ended.connect(_on_run_ended)
	if CharacterService and not CharacterService.quests_changed.is_connected(_rebuild_active_index):
		CharacterService.quests_changed.connect(_rebuild_active_index)
	if InventoryService and not InventoryService.inventory_changed.is_connected(_on_inventory_changed):
		InventoryService.inventory_changed.connect(_on_inventory_changed)
	call_deferred("_recover_settling_quests")


func _recover_settling_quests() -> void:
	for quest_id in QuestCatalog.get_all_ids():
		if CharacterService.get_quest_state(quest_id) != STATE_SETTLING:
			continue
		var def := QuestCatalog.get_definition(quest_id)
		CharacterService.set_quest_state(
			quest_id, STATE_INACTIVE if bool(def.get("repeatable", false)) else STATE_COMPLETED
		)
		quest_updated.emit(quest_id, CharacterService.get_quest_state(quest_id))
	_rebuild_active_index()


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
	if not is_base_offerable(quest_id):
		return false
	return BountyService.is_offerable(quest_id)


func is_base_offerable(quest_id: String) -> bool:
	var def := QuestCatalog.get_definition(quest_id)
	if def.is_empty():
		return false
	if CharacterService.get_quest_state(quest_id) != STATE_INACTIVE:
		return false
	if not prerequisites_met(quest_id):
		return false
	if not DialogueConditions.evaluate(def.get("availableWhen")):
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
	BountyService.notify_accepted(quest_id)
	_rebuild_active_index()
	quest_updated.emit(quest_id, STATE_ACTIVE)
	if str(QuestCatalog.get_definition(quest_id).get("type", "")) == TYPE_FETCH:
		_reconcile_fetch_quest(quest_id)
	return true


func complete_quest(quest_id: String) -> bool:
	var def := QuestCatalog.get_definition(quest_id)
	if def.is_empty():
		return false
	if CharacterService.get_quest_state(quest_id) != STATE_ACTIVE:
		return false
	var repeatable := bool(def.get("repeatable", false))
	var progress := CharacterService.get_quest_progress(quest_id)
	progress["completions"] = int(progress.get("completions", 0)) + 1
	progress["lastCompletedRun"] = _runs_started()
	progress["count"] = 0
	progress["seen"] = []
	CharacterService.set_quest_state(quest_id, STATE_SETTLING)
	CharacterService.set_quest_progress(quest_id, progress)
	_rebuild_active_index()
	_grant_rewards(quest_id, def)
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
		if CharacterService.get_quest_state(quest_id) == STATE_COMPLETED or get_completions(quest_id) > 0:
			result.append(QuestCatalog.get_definition(quest_id))
	return result


func register_kill(enemy_id: String = "", credit: Dictionary = {}) -> void:
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
		var source := credit.get("source") as Node
		if source == null or not source.is_in_group("player"):
			continue
		var required_weapon := str(defeat_def.get("weaponItemId", ""))
		if required_weapon != "" and str(credit.get("weaponItemId", "")) != required_weapon:
			continue
		_advance_count(quest_id, defeat_def)


func register_fetch(item_id: String) -> void:
	for quest_id in _active_quest_ids(TYPE_FETCH).duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		if str(def.get("targetItemId", "")) != item_id:
			continue
		_reconcile_fetch_quest(quest_id)


func _on_inventory_changed() -> void:
	if _fetch_reconcile_pending:
		return
	_fetch_reconcile_pending = true
	call_deferred("_reconcile_all_fetch_quests")


func _reconcile_all_fetch_quests() -> void:
	_fetch_reconcile_pending = false
	for quest_id in _active_quest_ids(TYPE_FETCH).duplicate():
		_reconcile_fetch_quest(str(quest_id))


func _reconcile_fetch_quest(quest_id: String) -> void:
	if CharacterService.get_quest_state(quest_id) != STATE_ACTIVE:
		return
	var def := QuestCatalog.get_definition(quest_id)
	var item_id := str(def.get("targetItemId", ""))
	var mode := str(def.get("objectiveMode", "possession"))
	if item_id == "" or mode == "collection":
		return
	var held := InventoryService.count_item(item_id) if InventoryService else 0
	var progress := CharacterService.get_quest_progress(quest_id)
	var old_count := int(progress.get("count", 0))
	progress["count"] = held
	CharacterService.set_quest_progress(quest_id, progress)
	_emit_progress_change(quest_id, def, old_count, held)
	if mode == "possession" and held >= int(def.get("requiredCount", 1)):
		complete_quest(quest_id)


func can_hand_in_fetch(quest_id: String) -> bool:
	var def := QuestCatalog.get_definition(quest_id)
	if CharacterService.get_quest_state(quest_id) != STATE_ACTIVE:
		return false
	if str(def.get("type", "")) != TYPE_FETCH or str(def.get("objectiveMode", "")) != "delivery":
		return false
	return InventoryService.count_item(str(def.get("targetItemId", ""))) >= int(def.get("requiredCount", 1))


func hand_in_fetch_quest(quest_id: String) -> bool:
	if not can_hand_in_fetch(quest_id):
		return false
	var def := QuestCatalog.get_definition(quest_id)
	var item_id := str(def.get("targetItemId", ""))
	var required := int(def.get("requiredCount", 1))
	var target := InventoryService.inventory
	var working := GridInventory.new(target.grid_width, target.grid_height)
	working.from_save_dict(target.to_save_dict())
	if working.remove_items_by_id(item_id, required) != required:
		return false
	target.from_save_dict(working.to_save_dict())
	return complete_quest(quest_id)


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
		var old_count := int(progress.get("count", 0))
		var seen: Array = progress.get("seen", [])
		if discovery_id in seen:
			continue
		seen.append(discovery_id)
		progress["seen"] = seen
		progress["count"] = int(progress.get("count", 0)) + 1
		CharacterService.set_quest_progress(quest_id, progress)
		_emit_progress_change(quest_id, def, old_count, int(progress["count"]))
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
		if not _run_context_matches(def):
			continue
		_advance_count(quest_id, def)


const RESCUE_NPCS := {
	"halbrek": "serjeant_halbrek",
	"ivo": "clerk_ivo",
	"nettle": "fenwife_nettle",
	"corrin": "lampwright_corrin",
	"odile": "lector_odile",
	"veil": "widow_of_the_stair",
}


## Rescue dialogue uses an abstract accompany-on-this-run contract, not an implied off-screen
## teleport. A commitment survives room/floor changes, resolves on a successful escape, and is
## lost only if that run ends unsuccessfully. A defer deliberately keeps the NPC available.
func set_rescue_state(npc_id: String, state: String) -> bool:
	if not RESCUE_NPCS.has(npc_id):
		return false
	match state:
		"committed":
			CharacterService.set_flag("rescue_committed_%s" % npc_id, true)
			CharacterService.set_flag("rescue_deferred_%s" % npc_id, false)
			return true
		"deferred":
			CharacterService.set_flag("rescue_deferred_%s" % npc_id, true)
			return true
	return false


func resolve_committed_rescues(outcome: String) -> void:
	var escaped := outcome == RunLifecycleScript.OUTCOME_ESCAPED
	for npc_id in RESCUE_NPCS:
		if not bool(CharacterService.get_flag("rescue_committed_%s" % npc_id, false)):
			continue
		CharacterService.set_flag("rescue_committed_%s" % npc_id, false)
		if escaped:
			CharacterService.set_flag("rescued_%s" % npc_id, true)
			register_rescue(str(RESCUE_NPCS[npc_id]))
		else:
			CharacterService.set_flag("lost_%s" % npc_id, true)


func register_run_outcome(outcome: String, context: Dictionary = {}) -> void:
	var results: Dictionary = {}
	if RunFlow:
		results = RunFlow.last_run_results.duplicate(true)
	var mode := str(context.get("run_mode", results.get("run_mode", "")))
	var summary := _make_run_summary(outcome, results, mode)
	_record_last_run(summary)
	_check_escape_quests(outcome == RunLifecycleScript.OUTCOME_ESCAPED)
	_check_clear_without_quests(outcome, results)
	_check_reach_depth_quests(summary)


func _make_run_summary(outcome: String, results: Dictionary, mode: String) -> Dictionary:
	var summary := {
		"outcome": outcome,
		"runMode": mode,
		"biome": "",
		"dungeon": "",
		"tier": 0,
		"dungeonDepth": int(results.get("floor_reached", 0)) if mode != RunModeConfig.MODE_WAVES else 0,
		"waveIndex": int(results.get("floor_reached", 0)) if mode == RunModeConfig.MODE_WAVES else 0,
		"boss": bool(results.get("boss_defeated", false)),
		"kills": int(results.get("kills", 0)),
	}
	if RunFlow:
		summary["biome"] = str(RunFlow.current_biome_id)
		summary["dungeon"] = str(RunFlow.current_dungeon_id)
		summary["tier"] = int(RunFlow.current_difficulty_tier)
	return summary


func _record_last_run(summary: Dictionary) -> void:
	if CharacterService == null:
		return
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


func _check_reach_depth_quests(summary: Dictionary) -> void:
	for quest_id in _active_quest_ids(TYPE_REACH_DEPTH).duplicate():
		var def := QuestCatalog.get_definition(quest_id)
		if not _run_context_matches(def, str(summary.get("runMode", ""))):
			continue
		if int(summary.get("dungeonDepth", 0)) < int(def.get("requiredCount", 1)):
			continue
		complete_quest(quest_id)


func _advance_count(quest_id: String, def: Dictionary) -> void:
	var progress := CharacterService.get_quest_progress(quest_id)
	var old_count := int(progress.get("count", 0))
	var count: int = old_count + 1
	progress["count"] = count
	CharacterService.set_quest_progress(quest_id, progress)
	var required := int(def.get("requiredCount", 1))
	_emit_progress_change(quest_id, def, old_count, count)
	if count >= required:
		complete_quest(quest_id)


func _emit_progress_change(
	quest_id: String, def: Dictionary, old_count: int, new_count: int
) -> void:
	if old_count == new_count:
		return
	var required := int(def.get("requiredCount", 1))
	var objective_id := str(def.get("objectiveId", def.get("type", "objective")))
	quest_progress_changed.emit(quest_id, objective_id, old_count, new_count, required)
	if new_count > old_count:
		quest_progress_advanced.emit(quest_id, new_count, required)


func _run_context_matches(def: Dictionary, mode_override: String = "") -> bool:
	if RunFlow == null:
		return true
	var mode := mode_override if mode_override != "" else str(RunFlow.run_mode)
	var allowed_modes: Variant = def.get("allowedModes", [])
	if allowed_modes is Array and not (allowed_modes as Array).is_empty() and mode not in allowed_modes:
		return false
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


func get_claimable_rewards() -> Array:
	var raw: Variant = CharacterService.get_flag(REWARD_RECEIPTS_FLAG, [])
	return (raw as Array).duplicate(true) if raw is Array else []


func claim_reward(receipt_id: String) -> bool:
	var receipts := get_claimable_rewards()
	for index in receipts.size():
		var receipt: Dictionary = receipts[index]
		if str(receipt.get("id", "")) != receipt_id:
			continue
		var item_id := str(receipt.get("itemId", ""))
		var quantity := int(receipt.get("quantity", 1))
		if not InventoryService.add_item(item_id, quantity):
			return false
		receipts.remove_at(index)
		CharacterService.set_flag(REWARD_RECEIPTS_FLAG, receipts)
		LocalSave.request_autosave(LocalSave.SavePriority.IMMEDIATE)
		return true
	return false


func _grant_rewards(quest_id: String, def: Dictionary) -> void:
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
		var receipts := get_claimable_rewards()
		var receipt_id := "%s:%s:%d" % [quest_id, reward_id, get_completions(quest_id) + 1]
		if not receipts.any(func(entry: Variant) -> bool: return entry is Dictionary and str(entry.get("id", "")) == receipt_id):
			receipts.append({"id": receipt_id, "questId": quest_id, "itemId": reward_id, "quantity": reward_qty})
			CharacterService.set_flag(REWARD_RECEIPTS_FLAG, receipts)
	for flag_entry in rewards.get("flags", []):
		if flag_entry is Dictionary:
			CharacterService.set_flag(
				str(flag_entry.get("flag", "")), flag_entry.get("value", true)
			)
	var recipe_id := str(rewards.get("recipeId", ""))
	if recipe_id != "" and LocalSave:
		LocalSave.add_recipe(recipe_id)
