extends Node

## Autoload — hub ↔ dungeon ↔ results flow (FLOW-2.1 / FLOW-4.1).

signal run_started
signal run_ended(results: Dictionary)
signal returned_to_hub(message: String)
signal run_warning(message: String)

const RUN_META_KEYS: Array[String] = [
	"dungeon_definition",
	"run_seed",
	"tier_generation_seed",
	"run_id",
	"run_snapshot",
	"floor_transition",
	"run_results",
]

const HUB_SCENE := RunSceneRouter.HUB_SCENE
const TOWER_DISPLAY_NAME := "Aumbrye Tower"
const CASTLE_RUN_SCENE := RunSceneRouter.CASTLE_RUN_SCENE
const WAVES_RUN_SCENE := RunSceneRouter.WAVES_RUN_SCENE
const ARENA_SCENE := RunSceneRouter.ARENA_SCENE
const RESULTS_SCENE := RunSceneRouter.RESULTS_SCENE
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const DEFAULT_BIOME := "forgotten_castle"
## Intentionally off pending server-authoritative runs; net_suite covers the stub path.
const USE_ONLINE_PROCgen := false

## Achievement / progression tuning
const SPEED_CLEAR_MAX_SECONDS := 900.0
const WAVES_COMPLETION_XP := 500
## BUG-30: endless runs can reach hundreds of floors; these bound the run-history arrays so
## RAM and save size stop growing linearly with floor count in the one mode meant to be played
## forever. Gating logic only ever queries near current_floor, so keeping the highest-numbered
## entries (rather than an arbitrary window) never drops something a live check still needs.
const MAX_CLEARED_FLOORS_TRACKED := 50
const MAX_LOOT_HISTORY_TRACKED := 500

const RM := preload("res://scripts/app/run_mode_config.gd")
const SkipFloorSvc := preload("res://scripts/dungeon/skip_floor_service.gd")
const XP_SHARD_FLAG := "recoverable_xp_shard"
const DEATH_GOLD_STAKE_RATIO := 0.4

## Preloaded rather than referenced by class_name: RunFlow is an autoload, so it is compiled before
## the project-wide global-class table is fully built and a bare `CloudOutbox` fails to resolve.
const CloudOutboxScript := preload("res://scripts/net/cloud_outbox.gd")

var _pending_endless_seed := 0
var _pending_descent_pact := ""
## Floor-skip item reserved for the run being started, spent only once a floor generates.
var _pending_skip_item := ""
## Progress counters as they stood when the current floor began, so restarting a floor can undo
## that attempt instead of banking its kills and loot claims.
var _floor_entry_marker := {}
var _pending_region_card := false
var _active_descent_pact := ""
var _base_run_modifiers: Array[String] = []
var _pending_alternate_mode := ""
var _pending_challenge: Dictionary = {}
var _pending_mode_floors := 0
var _active_alternate_mode := ""
var _active_challenge: Dictionary = {}
var _run_highlights: Dictionary = {}

var run_mode: String = "castle"

var current_biome_id: String = DEFAULT_BIOME
var current_dungeon_id: String = DungeonCatalog.DEFAULT_DUNGEON_ID
var current_dungeon_tier: int = 1
var current_difficulty_tier: int = 1
var current_floor: int = 1
var max_floors: int = RunFloorConfig.MAX_FLOORS

var last_hub_message := ""
var last_run_results: Dictionary = {}
var current_run_id: String = ""
var current_dungeon_definition: Dictionary = {}
var current_seed: int = 0
var current_generator: String = ""
var current_tier_seed: int = 0
var current_generation_seed: int = 0
var current_generation_warnings: Array = []
var _run_active := false
var _run_start_time := 0.0
var _kill_count := 0
var _boss_defeated := false
var _boss_fight_active := false
var _boss_fight_damage_taken := false
var _loot_collected: Array[String] = []
var _loot_claimed_instance_ids: Array[String] = []
## BUG-14: monotonic per-run counter mixed into every loot roll seed so two drops of the same
## item in one run cannot roll identical affixes. Persisted with the run so it stays unique
## across save/load and deterministic for a given seed (never rolled back on death, so ordinals
## are never reused even after a checkpoint strips collected loot).
var _loot_drop_ordinal := 0
var _pending_snapshot: Dictionary = {}
var _is_continue := false
var _cleared_floors: Array[int] = []
## Validation-only: when set, the next `_resolve_floor_definition` call returns this value ([] = empty).
var _test_resolve_floor_override: Variant = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	PixelDioramaBootstrap.prime()


## C-84: the single owner of the replay pump. `RunReplay.pump()` already early-returns when neither
## recording nor playing, so this costs nothing outside a replay, and the input accessors no longer
## each carry a call they only needed one of per frame.
func _physics_process(_delta: float) -> void:
	PlayerInput.pump_frame()


func start_new_castle_run() -> void:
	start_new_run(DungeonCatalog.DEFAULT_DUNGEON_ID)


## Reserves the seed the next endless run will use so the portal can preview the exact biome and
## difficulty a skip lands on, rather than a different roll.
func next_endless_preview_seed() -> int:
	_pending_endless_seed = randi_range(1, 2_147_483_646)
	return _pending_endless_seed


func start_endless_run(start_floor: int = 1, skip_item_id: String = "") -> void:
	if skip_item_id != "":
		# Read the destination floor without spending the item yet. Skips are rare milestone
		# rewards; consuming one up front meant a failed floor generation destroyed it for nothing.
		if not SkipFloorSvc.has_skip(InventoryService.inventory, skip_item_id):
			last_hub_message = "You do not have that skip item."
			return
		start_floor = SkipFloorSvc.start_floor_for_item(skip_item_id)
		_pending_skip_item = skip_item_id
	var endless_seed := _pending_endless_seed
	if endless_seed <= 0:
		endless_seed = randi_range(1, 2_147_483_646)
	_pending_endless_seed = 0
	_pending_descent_pact = ""
	RunModifierService.apply_endless_floor_modifiers(start_floor, endless_seed)
	_base_run_modifiers = RunModifierService.active_modifiers()
	_active_descent_pact = ""
	var starting_biome := BiomeRegistry.biome_for_floor(endless_seed, start_floor)
	_pending_region_card = true
	await _start_mode_run(RM.MODE_ENDLESS, starting_biome, endless_seed, start_floor)


## The week's challenge: one seed, one rule set, the same run for everyone who plays it.
func start_challenge_run() -> void:
	var challenge := ChallengeService.get_active_challenge()
	if challenge.is_empty():
		_emit_run_warning("No challenge is posted this week.")
		return
	var dungeon_id := str(challenge.get("dungeonId", DungeonCatalog.DEFAULT_DUNGEON_ID))
	if not DungeonTierService.is_dungeon_unlocked(dungeon_id):
		_emit_run_warning("This week's hall is not open to you yet.")
		return
	var requested_tier := int(challenge.get("difficultyTier", 1))
	var tier := requested_tier
	if not DungeonTierService.is_difficulty_tier_unlocked(dungeon_id, tier):
		tier = maxi(1, DungeonTierService.get_unlocked_difficulty_cap(dungeon_id))
	challenge["difficultyTier"] = tier
	challenge["standard"] = tier == requested_tier
	_pending_challenge = challenge
	_pending_alternate_mode = ""
	_pending_mode_floors = 0
	await start_new_run(dungeon_id, int(challenge.get("seed", 1)), tier)


func start_alternate_mode_run(mode_id: String) -> void:
	if not RunModeCatalog.has_mode(mode_id):
		_emit_run_warning("That mode does not exist.")
		return
	if not RunModeCatalog.is_unlocked(mode_id):
		_emit_run_warning("That mode is not unlocked yet.")
		return
	_pending_alternate_mode = mode_id
	_pending_challenge = {}
	_pending_mode_floors = RunModeCatalog.floors_of(mode_id)
	if RunModeCatalog.base_mode_of(mode_id) == RM.MODE_ENDLESS:
		await start_endless_run(1)
	else:
		await start_new_run(RunModeCatalog.dungeon_of(mode_id))


func get_active_alternate_mode() -> String:
	return _active_alternate_mode


func get_active_challenge() -> Dictionary:
	return _active_challenge


func start_waves_run() -> void:
	_pending_alternate_mode = ""
	_pending_challenge = {}
	_pending_mode_floors = 0
	_start_waves_run(false)


func continue_waves_run() -> void:
	_start_waves_run(true)


func start_new_run(dungeon_id: String, run_seed: Variant = null, difficulty_tier: int = 1) -> void:
	var resolved_id := _resolve_dungeon_id(dungeon_id)
	if not DungeonTierService.is_dungeon_unlocked(resolved_id):
		_emit_run_warning("That dungeon is not unlocked yet.")
		return
	if not DungeonTierService.is_difficulty_tier_unlocked(resolved_id, difficulty_tier):
		_emit_run_warning("That difficulty is not unlocked yet.")
		return
	var order := DungeonCatalog.get_order_for_dungeon(resolved_id)
	if not DungeonSeedService.can_access_tier(order):
		_emit_run_warning("Tier %d is locked — you cannot use a seed for that tier yet." % order)
		return
	current_dungeon_id = resolved_id
	current_biome_id = DungeonCatalog.get_biome_id(resolved_id)
	current_dungeon_tier = order
	current_difficulty_tier = difficulty_tier
	RunModifierService.set_modifiers(
		DungeonCatalog.get_modifiers_for_difficulty(resolved_id, difficulty_tier)
	)
	_base_run_modifiers = RunModifierService.active_modifiers()
	_pending_descent_pact = ""
	_active_descent_pact = ""
	await _start_mode_run(RM.MODE_CASTLE, current_biome_id, run_seed, 1)


func start_castle_run_with_seed(run_seed_value: int) -> void:
	start_run_with_seed(DungeonCatalog.DEFAULT_DUNGEON_ID, run_seed_value)


func start_run_with_seed(dungeon_id: String, run_seed_value: int) -> void:
	await start_new_run(dungeon_id, run_seed_value)


func continue_castle_run() -> void:
	var saved := LocalSave.get_active_run()
	if not LocalSave.has_continuable_run():
		last_hub_message = "No saved castle run to continue."
		return
	var mode := str(saved.get("runMode", RM.MODE_CASTLE))
	if mode != RM.MODE_CASTLE and mode != "":
		last_hub_message = "Saved run is not a castle run — use the correct portal."
		return
	_is_continue = true
	_pending_snapshot = saved.get("snapshot", {}) if saved.get("snapshot", {}) is Dictionary else {}
	_restore_castle_run(saved)


func continue_endless_run() -> void:
	var saved := LocalSave.get_active_run()
	if not LocalSave.has_continuable_run():
		last_hub_message = "No saved endless run to continue."
		return
	if str(saved.get("runMode", "")) != RM.MODE_ENDLESS:
		last_hub_message = "Saved run is not an endless run."
		return
	_is_continue = true
	_pending_snapshot = saved.get("snapshot", {}) if saved.get("snapshot", {}) is Dictionary else {}
	_restore_castle_run(saved)


func start_castle_run() -> void:
	start_new_castle_run()


func _start_mode_run(mode: String, biome_id: String, run_seed: Variant, start_floor: int) -> void:
	run_mode = mode
	_is_continue = false
	_pending_snapshot.clear()
	var preserved_tier := current_dungeon_tier
	var preserved_difficulty := current_difficulty_tier
	var preserved_dungeon_id := current_dungeon_id
	_reset_run_stats()
	current_dungeon_tier = preserved_tier
	current_difficulty_tier = preserved_difficulty
	current_dungeon_id = preserved_dungeon_id
	max_floors = RunFloorConfig.max_floors_for_mode(run_mode)
	_promote_pending_rule_set(start_floor)
	current_dungeon_definition = {}
	current_run_id = ""
	current_seed = 0
	current_generator = ""
	current_tier_seed = 0
	current_generation_seed = 0
	current_generation_warnings.clear()
	current_biome_id = biome_id
	current_floor = maxi(1, start_floor)
	_clear_floor_cache()
	# PERF-03: overlap the first floor's room-template loads with dungeon generation below.
	BiomeRegistry.prewarm_room_scenes(biome_id)
	# …and parse the biome's enemy/trap/loot JSON now rather than at each node's _ready.
	BiomeRegistry.prewarm_content(biome_id)

	var gen := await _generate_dungeon(biome_id, run_seed, current_floor)
	if not gen.get("ok", false):
		var reason := str(gen.get("reason", gen.get("error", "unknown")))
		var fail_seed := maxi(1, int(gen.get("input_seed", _resolved_run_seed(run_seed))))
		var fail_msg := "Floor generation failed — seed %d, reason %s" % [fail_seed, reason]
		if CrashLogger:
			CrashLogger.log_error("run_flow.procgen_failed", {"message": fail_msg})
		else:
			push_error("RunFlow: %s" % fail_msg)
		# No floor was reached, so the skip item is not spent.
		_pending_skip_item = ""
		return_to_hub(fail_msg)
		return

	current_dungeon_definition = gen.get("definition", {})
	current_run_id = str(gen.get("run_id", ""))
	current_generator = str(gen.get("generator", "gdscript"))
	current_tier_seed = int(gen.get("tier_seed", 0))
	current_generation_seed = int(gen.get("generation_seed", 0))
	current_generation_warnings = gen.get("warnings", [])
	if run_seed != null:
		current_seed = maxi(1, int(run_seed))
	else:
		current_seed = maxi(1, int(gen.get("input_seed", gen.get("generation_seed", 0))))
	_set_current_floor_cache(current_dungeon_definition)

	if current_dungeon_definition.is_empty():
		last_hub_message = "Failed to load dungeon definition."
		_pending_skip_item = ""
		return_to_hub(last_hub_message)
		return

	_consume_pending_skip()
	_enter_run()


## Spends a reserved floor-skip item now that a floor has actually been generated.
func _consume_pending_skip() -> void:
	if _pending_skip_item == "":
		return
	var item_id := _pending_skip_item
	_pending_skip_item = ""
	if not SkipFloorSvc.consume_skip(InventoryService.inventory, item_id):
		push_warning("RunFlow: reserved skip item '%s' vanished before it could be spent." % item_id)


func _resolved_run_seed(run_seed: Variant) -> int:
	if run_seed != null:
		return maxi(1, int(run_seed))
	return 0


## C-110: the layout comes from the C# generator when the server is reachable and from the GDScript
## generator when it is not, and the two are **not** verified to agree — `cross_stack_parity_suite`
## asserted seed mixing, room-kit specs and the biome catalog, never a generated layout, and
## ADR-0002 lists "diff the canonical JSON across a seed matrix" as still-open work. `SeededRandom.cs`
## is SplitMix64 with a frozen contract; the GDScript side uses Godot's built-in RNG seeded through
## a SplitMix64 *mixer*, which is not the same thing as the same stream.
##
## The consequence is that seeded reproducibility was connectivity-dependent: two players entering
## the same seed got different dungeons if one of them was offline. Where reproducibility is the
## whole point of the run — an explicitly entered seed, or the weekly challenge that is meant to be
## "the same run for everyone who plays it" — the local generator is now used unconditionally, so
## every participant walks the same floor regardless of connectivity. Ordinary runs still prefer the
## server. Fix (3), full generator parity, remains ADR-0002's.
func _generate_dungeon(biome_id: String, run_seed: Variant, floor_index: int = 1) -> Dictionary:
	var reproducibility_required := run_seed != null or not _active_challenge.is_empty()
	if not reproducibility_required and USE_ONLINE_PROCgen and ApiConfig.cloud_calls_enabled():
		var online := await _try_online_generate(biome_id, run_seed, floor_index)
		if online.get("ok", false):
			return online
	return LocalProcgen.generate(
		biome_id,
		run_seed,
		floor_index,
		run_mode,
		current_dungeon_tier,
		ProgressionService.level if ProgressionService else 1
	)


func _try_online_generate(biome_id: String, run_seed: Variant, floor_index: int = 1) -> Dictionary:
	var created := await ApiClient.create_run(biome_id, run_seed, current_dungeon_tier)
	if not created.get("ok", false):
		return {"ok": false, "error": str(created.get("error", "create_run failed"))}
	var run_id := str(created.get("body", {}).get("runId", ""))
	if run_id == "":
		return {"ok": false, "error": "missing run id"}
	var dungeon := await ApiClient.get_dungeon(run_id)
	if not dungeon.get("ok", false):
		return {"ok": false, "error": str(dungeon.get("error", "get_dungeon failed"))}
	var definition: Dictionary = dungeon.get("body", {})
	return {
		"ok": true,
		"definition": definition,
		"run_id": run_id,
		"input_seed": run_seed,
		"generation_seed": definition.get("seed", run_seed),
		"floor_index": floor_index,
	}


func _restore_castle_run(saved: Dictionary) -> void:
	current_run_id = str(saved.get("runId", ""))
	current_biome_id = str(saved.get("biomeId", DEFAULT_BIOME))
	current_seed = int(saved.get("seed", 0))
	run_mode = str(saved.get("runMode", RM.MODE_CASTLE))
	current_floor = int(saved.get("currentFloor", 1))
	max_floors = int(saved.get("maxFloors", RunFloorConfig.max_floors_for_mode(run_mode)))
	current_dungeon_tier = int(
		saved.get("dungeonTier", DungeonCatalog.get_order_for_dungeon(current_dungeon_id))
	)
	current_difficulty_tier = int(saved.get("difficultyTier", 1))
	RunModifierService.set_modifiers(
		DungeonCatalog.get_modifiers_for_difficulty(current_dungeon_id, current_difficulty_tier)
	)
	if run_mode == RM.MODE_ENDLESS:
		RunModifierService.apply_endless_floor_modifiers(current_floor, current_seed)
	_base_run_modifiers = RunModifierService.active_modifiers()
	_pending_descent_pact = ""
	_active_descent_pact = ""
	current_dungeon_id = str(saved.get("dungeonId", DungeonCatalog.DEFAULT_DUNGEON_ID))
	if not DungeonCatalog.is_valid(current_dungeon_id):
		if DungeonCatalog.is_valid(current_biome_id):
			current_dungeon_id = current_biome_id
		else:
			current_dungeon_id = DungeonCatalog.DEFAULT_DUNGEON_ID
	current_biome_id = DungeonCatalog.get_biome_id(current_dungeon_id)
	_clear_floor_cache()
	# PERF-03: overlap the resumed floor's room-template loads with any regeneration below.
	BiomeRegistry.prewarm_room_scenes(current_biome_id)
	BiomeRegistry.prewarm_content(current_biome_id)
	var def: Variant = saved.get("dungeonDefinition", {})
	current_dungeon_definition = def if def is Dictionary else {}
	if current_dungeon_definition.is_empty():
		var regen := await _generate_dungeon(current_biome_id, current_seed, current_floor)
		if regen.get("ok", false):
			current_dungeon_definition = regen.get("definition", {})
	if not current_dungeon_definition.is_empty():
		_set_current_floor_cache(current_dungeon_definition)

	if current_dungeon_definition.is_empty():
		_is_continue = false
		_pending_snapshot.clear()
		LocalSave.clear_active_run()
		last_hub_message = "Saved run data was invalid."
		return_to_hub(last_hub_message)
		return

	_cleared_floors.clear()
	for floor_num in _pending_snapshot.get("clearedFloors", saved.get("clearedFloors", [])):
		var floor_index := int(floor_num)
		if floor_index > 0 and not _cleared_floors.has(floor_index):
			_cleared_floors.append(floor_index)
	_trim_cleared_floors()
	var saved_tier := int(saved.get("dungeonTier", 1))
	if saved_tier > DungeonTierService.get_max_unlocked_tier():
		_is_continue = false
		_pending_snapshot.clear()
		LocalSave.clear_active_run()
		last_hub_message = "That dungeon tier is locked — continue from the hub portal."
		return_to_hub(last_hub_message)
		return
	if not DungeonTierService.is_dungeon_unlocked(current_dungeon_id):
		_is_continue = false
		_pending_snapshot.clear()
		LocalSave.clear_active_run()
		last_hub_message = "That dungeon is not unlocked yet."
		return_to_hub(last_hub_message)
		return
	var max_cleared := _max_cleared_floor()
	if current_floor > max_cleared + 1:
		current_floor = maxi(1, max_cleared + 1)
		last_hub_message = (
			"Saved floor was ahead of progression — restored to floor %d." % current_floor
		)
	_kill_count = int(_pending_snapshot.get("killCount", 0))
	_boss_defeated = bool(_pending_snapshot.get("bossDefeated", false))
	if _boss_defeated and not _cleared_floors.has(current_floor):
		_boss_defeated = false
	_loot_collected.clear()
	_loot_claimed_instance_ids.clear()
	for item in _pending_snapshot.get("lootCollected", []):
		_loot_collected.append(str(item))
	for inst_id in _pending_snapshot.get("lootClaimedInstanceIds", []):
		_loot_claimed_instance_ids.append(str(inst_id))
	_trim_loot_history()
	_loot_drop_ordinal = int(
		_pending_snapshot.get("lootDropOrdinal", saved.get("lootDropOrdinal", 0))
	)

	_enter_run()


## Snapshots per-floor progress so restart_current_floor can roll a failed attempt back.
func _mark_floor_entry() -> void:
	_floor_entry_marker = {
		"floor": current_floor,
		"kills": _kill_count,
		"loot": _loot_collected.size(),
		"claims": _loot_claimed_instance_ids.size(),
	}


func _enter_run() -> void:
	_mark_floor_entry()
	var root := get_tree().root
	var definition_copy := current_dungeon_definition.duplicate(true)
	root.set_meta("dungeon_definition", definition_copy)
	root.set_meta("run_seed", current_seed)
	root.set_meta(
		"tier_generation_seed",
		(
			current_generation_seed
			if current_generation_seed > 0
			else (DungeonSeedService.generation_seed(
				current_seed, current_dungeon_tier, current_floor
			))
		)
	)
	root.set_meta("run_id", current_run_id)
	if _is_continue and not _pending_snapshot.is_empty():
		root.set_meta("run_snapshot", _pending_snapshot.duplicate(true))
	elif root.has_meta("run_snapshot"):
		root.remove_meta("run_snapshot")

	var active_run := {
		"schemaVersion": SaveMigrator.CURRENT_VERSION,
		"runMode": run_mode,
		"runId": current_run_id,
		"seed": current_seed,
		"biomeId": current_biome_id,
		"dungeonId": current_dungeon_id,
		"dungeonTier": current_dungeon_tier,
		"difficultyTier": current_difficulty_tier,
		"currentFloor": current_floor,
		"maxFloors": max_floors,
		"dungeonDefinition": definition_copy,
		"clearedFloors": _cleared_floors.duplicate(),
		"generator": current_generator,
		"input_seed": current_seed,
		"tier_seed": current_tier_seed,
		"generation_seed": current_generation_seed,
		"generationWarnings": current_generation_warnings.duplicate(),
	}
	if _is_continue and not _pending_snapshot.is_empty():
		active_run["snapshot"] = _pending_snapshot.duplicate(true)
	LocalSave.set_active_run(active_run)

	_run_active = true
	_run_start_time = Time.get_ticks_msec() / 1000.0
	_register_run_started()
	_goto_scene(CASTLE_RUN_SCENE)
	run_started.emit()
	if CombatEvents:
		CombatEvents.dispatch(CombatEvents.ON_RUN_START, {})


func go_to_arena() -> void:
	_goto_scene(ARENA_SCENE)


func return_to_hub(message: String = "") -> void:
	if run_mode == RM.MODE_WAVES and _run_active:
		LocalSave.clear_waves_active_run()
		WavesRunService.begin_new_run()
	_run_active = false
	last_hub_message = message
	_clear_run_meta()
	LocalSave.autosave_checkpoint()
	_goto_scene(HUB_SCENE)
	returned_to_hub.emit(message)


## Leaves the floor keeping everything collected, at the cost of the run's XP and the run itself.
##
## C-230: the "escape" consumable (escape_stone / homeward_bone) used to call the generic
## `return_to_hub()`, which destroys nothing, grants nothing and — critically — never calls
## `clear_active_run()`. Loot was banked for free and the same run could then be resumed from the
## portal, turning every descent into a zero-risk extraction trip. This is the deliberate version:
## the haul is kept, the floor's XP is forfeited into a recoverable shard, and the run ends.
func escape_with_loot() -> bool:
	if not _run_active:
		return false
	var player := get_tree().get_first_node_in_group("player")
	var elapsed := 0.0
	if _run_start_time > 0.0:
		elapsed = (Time.get_ticks_msec() / 1000.0) - _run_start_time
	var full_xp := ProgressionService.calculate_run_xp(_kill_count, _boss_defeated, false)
	if player is Node3D and full_xp > 0:
		store_recoverable_xp_shard(
			(player as Node3D).global_position, current_floor, current_dungeon_id, full_xp, 0
		)
	_run_highlights = RunBuffs.get_run_highlights()
	RunBuffs.clear_all()
	_register_endless_depth_reached()
	last_run_results = (
		RunLifecycle
		. build_results(
			RunLifecycle.OUTCOME_RETREATED,
			elapsed,
			_kill_count,
			_loot_collected,
			{"gained": 0, "levels_gained": 0},
			full_xp,
			_escape_rules_summary(),
			{
				"run_mode": run_mode,
				"floor_reached": current_floor,
				"boss_defeated": _boss_defeated,
				"loot_kept": true,
				"loot_lost": [],
				"xp_deferred": full_xp,
			}
		)
	)
	var run_id := current_run_id
	var loot_instance_ids := _loot_claimed_instance_ids.duplicate()
	LocalSave.clear_active_run()
	LocalSave.autosave_checkpoint()
	QuestService.register_run_outcome(RunLifecycle.OUTCOME_RETREATED, {"run_mode": run_mode})
	MerchantService.restock_all()
	_decorate_run_results()
	run_ended.emit(last_run_results)
	_cloud_finalize_run(run_id, "retreated", elapsed, _boss_defeated, loot_instance_ids)
	get_tree().root.set_meta("run_results", last_run_results)
	_run_active = false
	_clear_in_run_meta()
	_goto_scene(RESULTS_SCENE)
	return true


func abandon_active_run() -> void:
	if not _run_active:
		return_to_hub("Returned to Aumbrye Tower.")
		return
	var full_xp := ProgressionService.calculate_run_xp(_kill_count, _boss_defeated, false)
	var abandon_xp := ProgressionService.apply_abandon_xp_fraction(full_xp)
	if abandon_xp > 0:
		ProgressionService.grant_xp(abandon_xp, "abandon")
	InventoryService.remove_run_loot(_loot_collected)
	RunBuffs.clear_all()
	_register_endless_depth_reached()
	LocalSave.clear_active_run()
	_run_active = false
	return_to_hub("Run abandoned. Loot from this run was lost.")


func complete_run_via_portal() -> void:
	if not _run_active:
		return
	if run_mode == RM.MODE_ENDLESS:
		push_warning("RunFlow: endless runs have no exit portal")
		return
	if not can_escape_run():
		push_warning("RunFlow: escape blocked — defeat the boss on the final floor first")
		return
	if current_floor < max_floors:
		push_warning("RunFlow: escape blocked until final floor is cleared")
		return
	_run_active = false
	var elapsed := (Time.get_ticks_msec() / 1000.0) - _run_start_time
	var full_xp := ProgressionService.calculate_run_xp(_kill_count, _boss_defeated, true)
	var xp_result := ProgressionService.grant_xp(full_xp, "escape")
	_run_highlights = RunBuffs.get_run_highlights()
	RunBuffs.clear_all()
	last_run_results = (
		RunLifecycle
		. build_results(
			RunLifecycle.OUTCOME_ESCAPED,
			elapsed,
			_kill_count,
			_loot_collected,
			xp_result,
			full_xp,
			_escape_rules_summary(),
			{
				"run_mode": run_mode,
				"floor_reached": current_floor,
				"boss_defeated": _boss_defeated,
				"loot_kept": true,
				"run_relics_lost": false,
				"loot_lost": [],
			}
		)
	)
	var run_id := current_run_id
	var loot_instance_ids := _loot_claimed_instance_ids.duplicate()
	var boss := _boss_defeated
	var cleared_dungeon := current_dungeon_id
	LocalSave.clear_active_run()
	LocalSave.autosave_checkpoint()
	QuestService.register_run_outcome(RunLifecycle.OUTCOME_ESCAPED, {"run_mode": run_mode})
	MerchantService.restock_all()
	_decorate_run_results()
	run_ended.emit(last_run_results)
	_cloud_finalize_run(run_id, "escaped", elapsed, boss, loot_instance_ids)
	_clear_in_run_meta()
	_handle_escape_meta(elapsed, boss)
	# Published after _clear_in_run_meta, which wipes the other in-run meta keys. It currently
	# skips "run_results" specifically, but writing afterwards keeps this correct without relying
	# on that exemption. There used to be a duplicate write before the clear as well.
	get_tree().root.set_meta("run_results", last_run_results)
	if run_mode == RM.MODE_CASTLE:
		_mark_dungeon_cleared(cleared_dungeon)
		DungeonTierService.record_clear_result(
			cleared_dungeon, current_difficulty_tier, elapsed
		)
		DungeonTierService.on_dungeon_cleared(cleared_dungeon, current_difficulty_tier)
	_goto_scene(RESULTS_SCENE)


func on_player_died() -> void:
	if get_tree().get_first_node_in_group("training_arena"):
		return
	var active := LocalSave.get_active_run()
	var checkpoint: Variant = active.get("lastCheckpoint", {})
	if checkpoint is Dictionary and not checkpoint.is_empty() and not _is_permadeath_run():
		_bonfire_death_respawn(checkpoint)
		return
	var elapsed := 0.0
	if _run_start_time > 0.0:
		elapsed = (Time.get_ticks_msec() / 1000.0) - _run_start_time
	var full_xp := ProgressionService.calculate_run_xp(_kill_count, _boss_defeated, false)
	var death_xp := ProgressionService.apply_death_xp_fraction(full_xp)
	var xp_result := ProgressionService.grant_xp(death_xp, "death")
	var xp_deferred := full_xp - death_xp
	var failure_point := _record_failure_point()
	var gold_staked := _take_death_gold_stake()
	_store_recoverable_xp_shard_from_active_run(xp_deferred, gold_staked)
	var depth_result := _register_endless_depth_reached()
	var loot_lost := _loot_collected.duplicate()
	InventoryService.remove_run_loot(_loot_collected)
	InventoryService.apply_death_durability_loss(BlacksmithService.DEATH_DURABILITY_LOSS)
	var had_relics := _had_run_relics()
	RunBuffs.clear_all()
	CharacterService.set_flag("deaths", int(CharacterService.get_flag("deaths", 0)) + 1)
	last_run_results = (
		RunLifecycle
		. build_results(
			RunLifecycle.OUTCOME_DIED,
			elapsed,
			_kill_count,
			[],
			xp_result,
			full_xp,
			_death_rules_summary(),
			{
				"run_mode": run_mode,
				"floor_reached": current_floor,
				"boss_defeated": _boss_defeated,
				"loot_kept": false,
				"run_relics_lost": had_relics,
				"loot_lost": loot_lost,
				"xp_deferred": xp_deferred,
				"gold_staked": gold_staked,
				"endless_best_floor": int(depth_result.get("newBest", 0)),
				"endless_previous_best": int(depth_result.get("previousBest", 0)),
				"descent_tokens_awarded": int(depth_result.get("tokens", 0)),
				"failure_point": failure_point,
				"assists_active": AccessibilitySettings.assists_active(),
			}
		)
	)
	var run_id := current_run_id
	var loot_instance_ids := _loot_claimed_instance_ids.duplicate()
	var boss := _boss_defeated
	LocalSave.clear_active_run()
	LocalSave.autosave_checkpoint()
	QuestService.register_run_outcome(RunLifecycle.OUTCOME_DIED, {"run_mode": run_mode})
	MerchantService.restock_all()
	_decorate_run_results()
	run_ended.emit(last_run_results)
	_cloud_finalize_run(run_id, "died", elapsed, boss, loot_instance_ids)
	get_tree().root.set_meta("run_results", last_run_results)
	_run_active = false
	_clear_in_run_meta()
	_goto_scene(RESULTS_SCENE)


func register_kill(enemy_id: String = "") -> void:
	_kill_count += 1
	QuestService.register_kill(enemy_id)
	if AchievementService:
		AchievementService.notify("enemy_killed")


func begin_boss_fight() -> void:
	_boss_fight_active = true
	_boss_fight_damage_taken = false


func register_player_boss_damage() -> void:
	if _boss_fight_active:
		_boss_fight_damage_taken = true


func register_boss_defeated() -> void:
	_boss_defeated = true
	_register_cleared_floor(current_floor)
	if AchievementService:
		if _boss_fight_active and not _boss_fight_damage_taken:
			AchievementService.notify("boss_defeated_no_damage")
	_boss_fight_active = false
	if run_mode == RM.MODE_CASTLE:
		_mark_dungeon_cleared(current_dungeon_id)


func rest_at_bonfire(player: Node = null) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var starved := RunModifierService.has_modifier(RunModifierService.MODIFIER_STARVED_HEARTH)
	var health := player.get_node_or_null("Health") as Health
	if health:
		if starved:
			health.heal(health.max_health * 0.5)
		else:
			health.reset_health()
	var stamina := player.get_node_or_null("Stamina") as Stamina
	if stamina:
		stamina.reset_stamina()
	var heal := player.get_node_or_null("PlayerHeal")
	if heal and heal.has_method("refill_charges") and not starved:
		heal.call("refill_charges")
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.has_method("respawn_at_rest"):
			enemy.call("respawn_at_rest")
	var castle := get_tree().get_first_node_in_group("castle_run")
	if castle and castle.has_method("persist_bonfire_checkpoint"):
		castle.call("persist_bonfire_checkpoint")


func get_current_floor() -> int:
	return current_floor


func get_max_floors() -> int:
	return max_floors


func is_final_floor() -> bool:
	if run_mode == RM.MODE_ENDLESS:
		return false
	var last_floor := mini(max_floors, RunFloorConfig.MAX_FLOORS)
	return RunFloorConfig.clamp_floor(current_floor, run_mode) >= last_floor


func can_escape_run() -> bool:
	if run_mode == RM.MODE_ENDLESS:
		return false
	return _boss_defeated and is_final_floor()


func can_retreat_to_hub() -> bool:
	if not _run_active or not _boss_defeated:
		return false
	return run_mode == RM.MODE_ENDLESS or run_mode == RM.MODE_CASTLE


func retreat_to_hub() -> void:
	if not can_retreat_to_hub():
		return
	var castle := get_tree().get_first_node_in_group("castle_run")
	if castle and castle.has_method("_persist_snapshot"):
		castle.call("_persist_snapshot")
	var active := LocalSave.get_active_run()
	if not active.is_empty():
		active["currentFloor"] = current_floor
		active["dungeonTier"] = current_dungeon_tier
		active["difficultyTier"] = current_difficulty_tier
		active["dungeonId"] = current_dungeon_id
		active["dungeonDefinition"] = current_dungeon_definition.duplicate(true)
		LocalSave.set_active_run(active)
	_register_endless_depth_reached()
	_run_active = false
	last_hub_message = "Retreated to %s. Continue from the portal." % TOWER_DISPLAY_NAME
	_clear_in_run_meta()
	LocalSave.autosave_checkpoint()
	_goto_scene(HUB_SCENE)
	returned_to_hub.emit(last_hub_message)


func get_dungeon_tier() -> int:
	return current_dungeon_tier


func get_difficulty_tier() -> int:
	return current_difficulty_tier


func get_dungeon_id() -> String:
	return current_dungeon_id


func get_run_mode() -> String:
	return run_mode


func ascend_floor() -> void:
	if not _run_active or not _boss_defeated:
		return
	if not _cleared_floors.has(current_floor):
		return
	if run_mode == RM.MODE_CASTLE and current_floor >= max_floors:
		return
	_stash_current_floor_in_cache()
	current_floor += 1
	_boss_defeated = _cleared_floors.has(current_floor)
	await _transition_floor(true)


func descend_floor() -> void:
	if not _run_active or current_floor <= 1:
		return
	if run_mode == RM.MODE_ENDLESS:
		return
	_stash_current_floor_in_cache()
	current_floor -= 1
	_boss_defeated = _cleared_floors.has(current_floor)
	await _transition_floor(false)


func _transition_floor(ascending: bool) -> void:
	var previous_definition := current_dungeon_definition.duplicate(true)
	var attempted_floor := current_floor
	if run_mode == RM.MODE_ENDLESS:
		var next_biome := BiomeRegistry.biome_for_floor(current_seed, current_floor)
		if next_biome != current_biome_id:
			_pending_region_card = true
		current_biome_id = next_biome
	# PERF-03: kick off background loads for the next floor's room templates as early as possible
	# in the transition so their disk cost overlaps with dungeon generation and the scene swap,
	# instead of landing entirely inside DungeonBuilder's (now chunked) build call.
	BiomeRegistry.prewarm_room_scenes(current_biome_id)
	BiomeRegistry.prewarm_content(current_biome_id)
	if _active_alternate_mode != "":
		RunModifierService.set_modifiers(
			RunModeCatalog.modifiers_for_floor(_active_alternate_mode, current_floor)
		)
		_base_run_modifiers = RunModifierService.active_modifiers()
	elif run_mode == RM.MODE_ENDLESS:
		RunModifierService.apply_endless_floor_modifiers(current_floor, current_seed)
		_base_run_modifiers = RunModifierService.active_modifiers()
	_apply_pending_descent_pact()
	var definition := await _resolve_floor_definition(current_floor)
	if definition.is_empty():
		if ascending:
			current_floor -= 1
		else:
			current_floor += 1
		current_dungeon_definition = previous_definition
		_restore_floor_modifiers()
		_emit_run_warning(
			(
				"Could not generate floor %d — you are still on floor %d."
				% [attempted_floor, current_floor]
			)
		)
		return
	current_dungeon_definition = definition
	_set_current_floor_cache(current_dungeon_definition)
	_mark_floor_entry()

	var root := get_tree().root
	root.set_meta("dungeon_definition", current_dungeon_definition.duplicate(true))
	(
		root
		. set_meta(
			"floor_transition",
			{
				"ascending": ascending,
				"floor": current_floor,
			}
		)
	)
	root.set_meta("run_snapshot", _build_floor_transition_snapshot(ascending))
	_persist_active_run()
	LocalSave.autosave_checkpoint()
	_goto_scene(CASTLE_RUN_SCENE)


## Everything the results screen needs that is not part of the outcome itself: the seed to share,
## the relics that carried the run, and the comparison against every run before it.
func _decorate_run_results() -> void:
	if _run_highlights.is_empty():
		_run_highlights = RunBuffs.get_run_highlights()
	if RunReplay.is_recording():
		RunReplay.stop_recording()
		RunReplay.save_to_meta()
	last_run_results["replay_available"] = RunReplay.entry_count() > 0
	last_run_results["seed"] = current_seed
	last_run_results["dungeon_id"] = current_dungeon_id
	last_run_results["dungeon_name"] = DungeonCatalog.get_display_name(current_dungeon_id)
	last_run_results["difficulty_tier"] = current_difficulty_tier
	last_run_results["highlights"] = _run_highlights
	last_run_results["alternate_mode"] = _active_alternate_mode
	last_run_results["challenge_id"] = str(_active_challenge.get("id", ""))
	if _active_alternate_mode != "":
		last_run_results["mode_name"] = str(
			RunModeCatalog.get_mode(_active_alternate_mode).get("name", "")
		)
	if not _active_challenge.is_empty():
		last_run_results["challenge_name"] = str(_active_challenge.get("name", ""))
		last_run_results["challenge"] = ChallengeService.record_result(
			_active_challenge, last_run_results
		)
	RunHistoryService.record(last_run_results)
	last_run_results["history"] = RunHistoryService.summarize(last_run_results)
	_run_highlights = {}
	_active_alternate_mode = ""
	_active_challenge = {}


func set_pending_descent_pact(pact_id: String) -> void:
	_pending_descent_pact = pact_id


func get_active_descent_pact() -> String:
	return _active_descent_pact


func consume_pending_region_card() -> bool:
	if not _pending_region_card:
		return false
	_pending_region_card = false
	return true


func _apply_pending_descent_pact() -> void:
	_active_descent_pact = _pending_descent_pact
	_pending_descent_pact = ""
	if _active_descent_pact == "":
		_restore_floor_modifiers()
		return
	RunModifierService.set_modifiers(
		DescentPactService.apply(_active_descent_pact, _base_run_modifiers)
	)


## Alternate rule sets and the weekly challenge own the modifier list for the whole run, so they
## are applied after the dungeon's own difficulty modifiers rather than merged with them.
func _promote_pending_rule_set(start_floor: int) -> void:
	_active_alternate_mode = _pending_alternate_mode
	_active_challenge = _pending_challenge
	_pending_alternate_mode = ""
	_pending_challenge = {}
	if _pending_mode_floors > 0:
		max_floors = mini(_pending_mode_floors, max_floors)
	_pending_mode_floors = 0
	_run_highlights = {}
	if _active_alternate_mode != "":
		RunModifierService.set_modifiers(
			RunModeCatalog.modifiers_for_floor(_active_alternate_mode, start_floor)
		)
		_base_run_modifiers = RunModifierService.active_modifiers()
	elif not _active_challenge.is_empty():
		var raw_modifiers: Variant = _active_challenge.get("modifiers", [])
		var modifiers: Array = raw_modifiers if raw_modifiers is Array else []
		RunModifierService.set_modifiers(modifiers)
		_base_run_modifiers = RunModifierService.active_modifiers()


func _is_permadeath_run() -> bool:
	return _active_alternate_mode != "" and RunModeCatalog.is_permadeath(_active_alternate_mode)


func _restore_floor_modifiers() -> void:
	RunModifierService.set_modifiers(_base_run_modifiers)


func _resolve_floor_definition(floor_index: int) -> Dictionary:
	if _test_resolve_floor_override != null:
		var override: Variant = _test_resolve_floor_override
		_test_resolve_floor_override = null
		if override is Dictionary:
			return override
		return {}
	var cached := _get_cached_floor_definition(floor_index)
	if not cached.is_empty():
		return cached
	var gen := await _generate_dungeon(current_biome_id, current_seed, floor_index)
	if gen.get("ok", false):
		return gen.get("definition", {})
	return {}


func _build_floor_transition_snapshot(ascending: bool) -> Dictionary:
	return {
		"floorTransition": true,
		"ascending": ascending,
		"currentFloor": current_floor,
		"bossDefeated": _boss_defeated,
		"clearedFloors": _cleared_floors.duplicate(),
		"killCount": _kill_count,
		"lootCollected": _loot_collected.duplicate(),
		"lootClaimedInstanceIds": _loot_claimed_instance_ids.duplicate(),
		"lootDropOrdinal": _loot_drop_ordinal,
	}


func _persist_active_run() -> void:
	var active := LocalSave.get_active_run()
	if active.is_empty():
		active = {
			"schemaVersion": SaveMigrator.CURRENT_VERSION,
			"runMode": run_mode,
			"runId": current_run_id,
			"seed": current_seed,
			"biomeId": current_biome_id,
		}
	active["runMode"] = run_mode
	active["currentFloor"] = current_floor
	active["dungeonTier"] = current_dungeon_tier
	active["difficultyTier"] = current_difficulty_tier
	active["dungeonId"] = current_dungeon_id
	active["maxFloors"] = max_floors
	active["dungeonDefinition"] = current_dungeon_definition.duplicate(true)
	active["clearedFloors"] = _cleared_floors.duplicate()
	active["generator"] = current_generator
	active["input_seed"] = current_seed
	active["tier_seed"] = current_tier_seed
	active["generation_seed"] = current_generation_seed
	active["generationWarnings"] = current_generation_warnings.duplicate()
	active["lootDropOrdinal"] = _loot_drop_ordinal
	LocalSave.set_active_run(active, false)


func _clear_floor_cache() -> void:
	DungeonBuilder.clear_floor_cache()


## Identity of the run the floor cache currently belongs to.
##
## The cache is static and survives a crash-abandoned run, so entries must be scoped to the run
## that produced them — otherwise two runs sharing floor indices (seeded and weekly-challenge runs
## especially) read each other's floors.
func _run_cache_key() -> String:
	return "%s:%d:%s" % [run_mode, current_seed, current_run_id]


## Binds the shared floor cache to this run, wiping anything left from a different one. Called
## before every store so the binding cannot drift out of date.
func _bind_run_cache() -> void:
	DungeonBuilder.begin_run_cache(_run_cache_key())
	DungeonBuilder.set_reference_floor(current_floor)


func _stash_current_floor_in_cache() -> void:
	if current_dungeon_definition.is_empty():
		return
	_bind_run_cache()
	DungeonBuilder.store_floor_cache(current_floor, current_dungeon_definition)


func _get_cached_floor_definition(floor_index: int) -> Dictionary:
	return DungeonBuilder.get_floor_cache(floor_index)


func _set_current_floor_cache(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	_bind_run_cache()
	DungeonBuilder.store_floor_cache(current_floor, definition)


func register_loot(item_id: String, instance_id: String = "") -> void:
	if item_id not in _loot_collected:
		_loot_collected.append(item_id)
	if instance_id != "" and instance_id not in _loot_claimed_instance_ids:
		_loot_claimed_instance_ids.append(instance_id)
	_trim_loot_history()


func get_loot_claimed_instance_ids() -> Array[String]:
	return _loot_claimed_instance_ids.duplicate()


## BUG-14: call once per rolled-loot unit; mix the result into the roll seed so identical items
## dropped in the same run do not roll identical affixes.
func next_loot_drop_ordinal() -> int:
	_loot_drop_ordinal += 1
	return _loot_drop_ordinal


func get_kill_count() -> int:
	return _kill_count


func get_loot_collected() -> Array[String]:
	return _loot_collected.duplicate()


func get_run_elapsed_seconds() -> float:
	if _run_start_time <= 0.0:
		return 0.0
	return maxf(0.0, (Time.get_ticks_msec() / 1000.0) - _run_start_time)


func get_run_mode_label() -> String:
	if not _run_active:
		return "hub"
	match run_mode:
		RM.MODE_CASTLE:
			return "castle"
		RM.MODE_WAVES:
			return "waves"
		RM.MODE_ENDLESS:
			return "endless"
		_:
			return run_mode


## Interpolates a translated string only when its placeholders survived translation.
##
## A locale whose entry drops or malforms "%d" would otherwise raise at the `%` operator, crashing
## the pause menu for that language only — a failure English-only testing never sees.
func _tr_fmt(key: String, args: Array) -> String:
	var text := tr(key)
	if not text.contains("%"):
		return text
	if text.count("%s") + text.count("%d") != args.size():
		push_warning("RunFlow: translation '%s' has mismatched placeholders for %d args." % [key, args.size()])
		return text
	return text % args


func get_current_objective() -> String:
	if not _run_active:
		return tr("PAUSE_OBJECTIVE_HUB")
	match run_mode:
		RM.MODE_WAVES:
			return _tr_fmt("PAUSE_OBJECTIVE_WAVES", [WavesRunService.current_wave])
		RM.MODE_CASTLE, RM.MODE_ENDLESS:
			if _boss_defeated and _cleared_floors.has(current_floor):
				return tr("PAUSE_OBJECTIVE_STAIRS")
			if _boss_fight_active or not _boss_defeated:
				return tr("PAUSE_OBJECTIVE_BOSS")
			return tr("PAUSE_OBJECTIVE_EXPLORE")
		_:
			return tr("PAUSE_OBJECTIVE_EXPLORE")


func get_abandon_stakes() -> Dictionary:
	var item_count := _loot_collected.size()
	var gold := 0
	for item_id in _loot_collected:
		gold += ItemCatalog.get_loot_value(str(item_id))
	return {"items": item_count, "gold": gold, "floor": current_floor}


func can_restart_current_floor() -> bool:
	return _run_active and run_mode == RM.MODE_CASTLE and not _cleared_floors.has(current_floor)


## Undoes the progress banked during a failed attempt at the current floor.
##
## Without this, restarting repeatedly farmed kill-count XP and kept loot ids claimed against chest
## instances the regenerated floor no longer contains — which then surfaced as duplicate-claim
## rejections or phantom loot at completion.
func _rollback_to_floor_entry() -> void:
	if _floor_entry_marker.is_empty():
		return
	if int(_floor_entry_marker.get("floor", -1)) != current_floor:
		return

	_kill_count = mini(_kill_count, int(_floor_entry_marker.get("kills", _kill_count)))

	# History is trimmed from the front at a cap, so the recorded sizes are upper bounds rather
	# than exact indices — clamp instead of trusting them outright.
	var loot_keep := mini(_loot_collected.size(), int(_floor_entry_marker.get("loot", 0)))
	var dropped_items := _loot_collected.slice(loot_keep)
	_loot_collected = _loot_collected.slice(0, loot_keep)

	var claims_keep := mini(
		_loot_claimed_instance_ids.size(), int(_floor_entry_marker.get("claims", 0))
	)
	_loot_claimed_instance_ids = _loot_claimed_instance_ids.slice(0, claims_keep)

	# Keep the bag in step with the rolled-back ledger.
	if InventoryService and InventoryService.inventory:
		for item_id in dropped_items:
			InventoryService.inventory.remove_items_by_id(str(item_id), 1)


func restart_current_floor() -> void:
	if not can_restart_current_floor():
		return
	_boss_defeated = false
	_boss_fight_active = false
	_boss_fight_damage_taken = false
	DungeonBuilder.erase_floor_cache(current_floor)
	var definition := await _resolve_floor_definition(current_floor)
	if definition.is_empty():
		_emit_run_warning("Could not restart floor %d." % current_floor)
		return
	current_dungeon_definition = definition
	_set_current_floor_cache(definition)
	_rollback_to_floor_entry()
	var root := get_tree().root
	root.set_meta("dungeon_definition", definition.duplicate(true))
	root.set_meta("run_snapshot", {"restartFloor": true, "currentFloor": current_floor})
	_persist_active_run()
	MenuStack.force_unpause()
	_goto_scene(CASTLE_RUN_SCENE)


func is_run_active() -> bool:
	return _run_active


func is_continue_restore() -> bool:
	return _is_continue


func clear_continue_restore() -> void:
	_is_continue = false
	_pending_snapshot.clear()


func _resolve_dungeon_id(dungeon_id: String) -> String:
	if DungeonCatalog.is_valid(dungeon_id):
		return dungeon_id
	for entry in DungeonCatalog.ENTRIES:
		if str(entry.get("biomeId", "")) == dungeon_id:
			return str(entry.get("id", ""))
	return DungeonCatalog.DEFAULT_DUNGEON_ID


func return_to_main_menu() -> void:
	_flush_active_run_snapshot()
	_run_active = false
	MenuStack.force_unpause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDirector.stop_all(0.35)
	AudioDirector.play_menu_music()
	_goto_scene(MAIN_MENU_SCENE)


func _flush_active_run_snapshot() -> void:
	if not _run_active:
		return
	var castle := get_tree().get_first_node_in_group("castle_run")
	if castle and castle.has_method("_persist_snapshot"):
		castle.call("_persist_snapshot")
	var waves := get_tree().get_first_node_in_group("waves_run")
	if waves and waves.has_method("_persist_waves_save"):
		waves.call("_persist_waves_save")
	LocalSave.autosave()


func _max_cleared_floor() -> int:
	var max_floor := 0
	for floor_index in _cleared_floors:
		max_floor = maxi(max_floor, floor_index)
	return max_floor


func _register_cleared_floor(floor_index: int) -> void:
	if _cleared_floors.has(floor_index):
		return
	_cleared_floors.append(floor_index)
	_trim_cleared_floors()


func _trim_cleared_floors() -> void:
	if _cleared_floors.size() <= MAX_CLEARED_FLOORS_TRACKED:
		return
	_cleared_floors.sort()
	while _cleared_floors.size() > MAX_CLEARED_FLOORS_TRACKED:
		_cleared_floors.pop_front()


func _trim_loot_history() -> void:
	while _loot_collected.size() > MAX_LOOT_HISTORY_TRACKED:
		_loot_collected.pop_front()
	while _loot_claimed_instance_ids.size() > MAX_LOOT_HISTORY_TRACKED:
		_loot_claimed_instance_ids.pop_front()


func _reset_run_stats() -> void:
	_kill_count = 0
	_boss_defeated = false
	_boss_fight_active = false
	_boss_fight_damage_taken = false
	_cleared_floors.clear()
	_loot_collected.clear()
	_loot_claimed_instance_ids.clear()
	_loot_drop_ordinal = 0
	current_floor = 1
	_clear_floor_cache()


func _cloud_finalize_run(
	run_id: String, outcome: String, elapsed: float, boss_defeated: bool, loot_instance_ids: Array
) -> void:
	# Queue before firing. This stays fire-and-forget so the results screen never waits on the
	# network, but the outbox guarantees eventual delivery even if the player quits right here or
	# the request never lands.
	var finished_floor := current_floor
	CloudOutboxScript.enqueue(
		run_id, outcome, elapsed, boss_defeated, loot_instance_ids, finished_floor, _kill_count
	)
	LocalSave.autosave()
	_cloud_finalize_run_async(
		run_id, outcome, elapsed, boss_defeated, loot_instance_ids, finished_floor, _kill_count
	)


func _cloud_finalize_run_async(
	run_id: String,
	outcome: String,
	elapsed: float,
	boss_defeated: bool,
	loot_instance_ids: Array,
	finished_floor: int,
	kills: int
) -> void:
	if not ApiConfig.cloud_calls_enabled():
		return
	if run_id != "":
		var result := await ApiClient.complete_run(
			run_id, outcome, elapsed, boss_defeated, loot_instance_ids, finished_floor, kills
		)
		if result.get("ok", false):
			CloudOutboxScript.resolve(run_id)
		else:
			if CrashLogger:
				CrashLogger.log_warning(
					"run_flow.complete_run", {"error": str(result.get("error", "unknown"))}
				)
			else:
				push_warning(
					"RunFlow: complete_run failed — %s" % str(result.get("error", "unknown"))
				)
	var push := await LocalSave.push_to_cloud()
	if not push.get("ok", false) and not push.get("conflict", false):
		if CrashLogger:
			CrashLogger.log_warning(
				"run_flow.cloud_push", {"error": str(push.get("error", "unknown"))}
			)
		else:
			push_warning("RunFlow: cloud push failed — %s" % str(push.get("error", "unknown")))


func _handle_escape_meta(elapsed: float, boss_defeated: bool) -> void:
	if not boss_defeated:
		return
	if AchievementService:
		AchievementService.unlock("boss_slayer")
		AchievementService.unlock_for_biome_clear(current_biome_id)
		if max_floors >= RunFloorConfig.MAX_FLOORS and current_floor >= max_floors:
			AchievementService.unlock("ten_floor_clear")
		if elapsed < SPEED_CLEAR_MAX_SECONDS:
			AchievementService.unlock("speed_clear")
	LeaderboardSettings.load_from_save()
	if LeaderboardSettings.opt_in:
		_submit_leaderboard_async(current_biome_id, current_dungeon_tier, elapsed)


func _submit_leaderboard_async(biome_id: String, tier: int, elapsed: float) -> void:
	var lb := await ApiClient.submit_leaderboard(current_run_id, true)
	last_run_results["leaderboard_submit_attempted"] = true
	last_run_results["leaderboard_submit_ok"] = lb.get("ok", false)
	if not lb.get("ok", false):
		last_run_results["leaderboard_submit_error"] = str(lb.get("error", "unknown"))
	# Only credit the achievement for a submission the server actually accepted — an offline
	# player or a failed POST used to unlock it just for trying.
	var submitted: bool = lb.get("ok", false) and lb.get("body", {}).get("submitted", false)
	last_run_results["leaderboard_submitted"] = submitted
	if AchievementService and submitted:
		AchievementService.unlock("leaderboard_submit")


func _mark_dungeon_cleared(dungeon_id: String) -> void:
	var flag_id := DungeonCatalog.get_clear_flag(dungeon_id)
	if flag_id != "":
		CharacterService.set_flag(flag_id, true)


func _escape_rules_summary() -> String:
	return (
		"Escaped alive: kept all loot and full XP. "
		+ "The tower releases you — your echo returns to Aumbrye Tower with proof of the oath."
	)


func _death_rules_summary() -> String:
	return (
		"The tower pulls you back: 50% XP saved, the rest lingers as a recoverable echo at your death spot, "
		+ "together with a share of your coin. Die again before you reach it and it is gone. "
		+ "Run loot and relics are lost. Your echo wakes in Aumbrye Tower — the ascent begins again."
	)


func _respawn_rules_summary() -> String:
	return (
		"Bonfire respawn: 50% XP saved, the rest lingers as a recoverable echo at your death spot. "
		+ "Loot gained since the last bonfire was stripped."
	)


## C-132: room content needs to tell the player why a door refused them.
func emit_run_warning(message: String) -> void:
	_emit_run_warning(message)


func _emit_run_warning(message: String) -> void:
	last_hub_message = message
	run_warning.emit(message)


func _had_run_relics() -> bool:
	return not RunBuffs.get_active_buffs().is_empty()


func store_recoverable_xp_shard(
	world_pos: Vector3, floor_index: int, dungeon_id: String, xp_amount: int, gold_amount: int = 0
) -> void:
	if xp_amount <= 0 and gold_amount <= 0:
		return
	(
		CharacterService
		. set_flag(
			XP_SHARD_FLAG,
			{
				"x": world_pos.x,
				"y": world_pos.y,
				"z": world_pos.z,
				"floor": floor_index,
				"dungeonId": dungeon_id,
				"xp": xp_amount,
				"gold": gold_amount,
			}
		)
	)


## The stake: a share of the character's coin is left where they fell. Storing a new echo
## overwrites the old one, so a second death before recovery loses the first for good.
func _take_death_gold_stake() -> int:
	var held := CharacterService.gold
	if held <= 0:
		return 0
	var staked := int(floor(float(held) * DEATH_GOLD_STAKE_RATIO))
	if staked <= 0:
		return 0
	if not CharacterService.spend_gold(staked):
		return 0
	return staked


## Where the run actually ended, aggregated locally so tiers can be tuned without a backend.
func _record_failure_point() -> Dictionary:
	var enemy_id := _nearest_enemy_catalog_id()
	var region := BiomeRegistry.get_display_name(current_biome_id)
	if region == "":
		region = current_biome_id
	var label := "%s, floor %d" % [region, current_floor]
	if enemy_id != "":
		label = "%s — %s" % [label, enemy_id]
	var entry := {
		"runMode": run_mode,
		"dungeonId": current_dungeon_id,
		"biomeId": current_biome_id,
		"floor": current_floor,
		"difficultyTier": current_difficulty_tier,
		"enemyId": enemy_id,
		"bossFight": _boss_fight_active,
		"assists": AccessibilitySettings.assists_active(),
		"label": label,
	}
	ProgressionService.record_failure_point(entry)
	return entry


func _nearest_enemy_catalog_id() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		return ""
	var origin: Vector3 = (player as Node3D).global_position
	var best := ""
	var best_distance := INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not (enemy is Node3D) or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and bool(enemy.call("is_dead")):
			continue
		var distance: float = origin.distance_squared_to((enemy as Node3D).global_position)
		if distance >= best_distance:
			continue
		best_distance = distance
		best = str(enemy.get_meta("catalog_id", ""))
	return best


func _register_endless_depth_reached() -> Dictionary:
	if run_mode != RM.MODE_ENDLESS:
		return {}
	var result := ProgressionService.register_endless_depth(current_floor)
	for milestone in result.get("milestones", []):
		if not milestone is Dictionary:
			continue
		var reward: Dictionary = (milestone as Dictionary).get("reward", {})
		var skip_item := str(reward.get("skipItemId", ""))
		var quantity := maxi(0, int(reward.get("skipQuantity", 0)))
		if skip_item == "" or quantity <= 0:
			continue
		if not ItemCatalog.has_item(skip_item):
			continue
		for _i in quantity:
			InventoryService.add_loot(skip_item)
	return result


func get_recoverable_xp_shard() -> Dictionary:
	var shard: Variant = CharacterService.get_flag(XP_SHARD_FLAG, {})
	return shard if shard is Dictionary and not shard.is_empty() else {}


func clear_recoverable_xp_shard() -> void:
	if get_recoverable_xp_shard().is_empty():
		return
	CharacterService.set_flag(XP_SHARD_FLAG, {})


func _bonfire_death_respawn(checkpoint: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var death_pos: Vector3 = Vector3.ZERO
	if player is Node3D:
		death_pos = (player as Node3D).global_position
	var elapsed := 0.0
	if _run_start_time > 0.0:
		elapsed = (Time.get_ticks_msec() / 1000.0) - _run_start_time
	var full_xp := ProgressionService.calculate_run_xp(_kill_count, _boss_defeated, false)
	var death_xp := ProgressionService.apply_death_xp_fraction(full_xp)
	var xp_result := ProgressionService.grant_xp(death_xp, "death")
	var xp_deferred := full_xp - death_xp
	var gold_staked := _take_death_gold_stake()
	store_recoverable_xp_shard(
		death_pos, current_floor, current_dungeon_id, xp_deferred, gold_staked
	)
	var loot_lost := _strip_loot_since_checkpoint(checkpoint)
	var had_relics := _had_run_relics()
	_run_highlights = RunBuffs.get_run_highlights()
	RunBuffs.clear_all()
	CharacterService.set_flag("deaths", int(CharacterService.get_flag("deaths", 0)) + 1)
	_kill_count = int(checkpoint.get("killCount", 0))
	_boss_defeated = bool(checkpoint.get("bossDefeated", false))
	_loot_collected.clear()
	_loot_claimed_instance_ids.clear()
	for item in checkpoint.get("lootCollected", []):
		_loot_collected.append(str(item))
	for inst_id in checkpoint.get("lootClaimedInstanceIds", []):
		_loot_claimed_instance_ids.append(str(inst_id))
	_trim_loot_history()
	WorldState.restore_flags(checkpoint.get("worldFlags", {}))
	var respawn_results := (
		RunLifecycle
		. build_results(
			RunLifecycle.OUTCOME_RESPAWNED,
			elapsed,
			_kill_count,
			_loot_collected,
			xp_result,
			full_xp,
			_respawn_rules_summary(),
			{
				"run_mode": run_mode,
				"floor_reached": current_floor,
				"boss_defeated": _boss_defeated,
				"loot_kept": loot_lost.is_empty(),
				"run_relics_lost": had_relics,
				"loot_lost": loot_lost,
				"xp_deferred": xp_deferred,
				"gold_staked": gold_staked,
			}
		)
	)
	var active := LocalSave.get_active_run()
	active["snapshot"] = checkpoint.duplicate(true)
	active.erase("playerDead")
	LocalSave.set_active_run(active)
	LocalSave.autosave_checkpoint()
	_is_continue = true
	_pending_snapshot = checkpoint.duplicate(true)
	get_tree().root.set_meta("run_snapshot", checkpoint.duplicate(true))
	get_tree().root.set_meta("run_respawn_results", respawn_results)
	_goto_scene(CASTLE_RUN_SCENE)


func _strip_loot_since_checkpoint(checkpoint: Dictionary) -> Array[String]:
	var kept: Array[String] = []
	for item in checkpoint.get("lootCollected", []):
		kept.append(str(item))
	var to_remove: Array[String] = []
	for item_id in _loot_collected:
		if item_id not in kept:
			to_remove.append(item_id)
	if not to_remove.is_empty():
		InventoryService.remove_run_loot(to_remove)
	_loot_collected = kept.duplicate()
	return to_remove


func _store_recoverable_xp_shard_from_active_run(xp_amount: int, gold_amount: int = 0) -> void:
	if xp_amount <= 0 and gold_amount <= 0:
		return
	var active := LocalSave.get_active_run()
	var snapshot: Variant = active.get("snapshot", {})
	if not snapshot is Dictionary:
		return
	var player: Variant = snapshot.get("player", {})
	if not player is Dictionary or player.is_empty():
		return
	store_recoverable_xp_shard(
		Vector3(
			float(player.get("x", 0.0)), float(player.get("y", 0.0)), float(player.get("z", 0.0))
		),
		current_floor,
		current_dungeon_id,
		xp_amount,
		gold_amount
	)


## Replays the stored input stream against the seed it was captured on. Recording is
## suppressed for the duration so a playback cannot overwrite its own source.
func start_replay_run() -> bool:
	var replay := RunReplay.load_from_meta()
	if replay.is_empty():
		return false
	var replay_seed := RunReplay.replay_seed(replay)
	if replay_seed <= 0:
		return false
	if not RunReplay.start_playback(replay):
		return false
	start_castle_run_with_seed(replay_seed)
	return true


func stop_replay_run() -> void:
	RunReplay.stop_playback()


func _register_run_started() -> void:
	CharacterService.set_flag("runs_started", int(CharacterService.get_flag("runs_started", 0)) + 1)
	if RunReplay.is_playing():
		RunReplay.rebase_playback()
	else:
		RunReplay.start_recording(current_seed, current_floor)


func _clear_in_run_meta() -> void:
	var root := get_tree().root
	for key in RUN_META_KEYS:
		if key == "run_results":
			continue
		if root.has_meta(key):
			root.remove_meta(key)


func _clear_run_meta() -> void:
	var root := get_tree().root
	for key in RUN_META_KEYS:
		if root.has_meta(key):
			root.remove_meta(key)
	if root.has_meta("run_respawn_results"):
		root.remove_meta("run_respawn_results")


func _goto_scene(path: String) -> void:
	RunSceneRouter.goto_scene(get_tree(), path)


func _start_waves_run(is_continue: bool) -> void:
	run_mode = RM.MODE_WAVES
	_is_continue = is_continue
	_run_active = true
	_run_start_time = Time.get_ticks_msec() / 1000.0
	if is_continue:
		var saved := LocalSave.get_waves_active_run()
		_pending_snapshot = (
			saved.get("snapshot", {}) if saved.get("snapshot", {}) is Dictionary else {}
		)
		WavesRunService.restore_from_save(saved)
	else:
		_pending_snapshot.clear()
		WavesRunService.begin_new_run(randi_range(1, 2_147_483_646))
	var root := get_tree().root
	if _is_continue and not _pending_snapshot.is_empty():
		root.set_meta("run_snapshot", _pending_snapshot.duplicate(true))
	elif root.has_meta("run_snapshot"):
		root.remove_meta("run_snapshot")
	_goto_scene(WAVES_RUN_SCENE)
	_register_run_started()
	run_started.emit()
	if CombatEvents:
		CombatEvents.dispatch(CombatEvents.ON_RUN_START, {})


func quit_waves_run() -> void:
	if run_mode != RM.MODE_WAVES:
		return
	var wave := WavesRunService.current_wave
	var keep_fraction := WavesRunService.get_early_exit_keep_fraction()
	var kept_items: Array[String] = []
	if keep_fraction > 0.0:
		kept_items = WavesRunService.transfer_early_exit_items(keep_fraction)
	LocalSave.clear_waves_active_run()
	WavesRunService.begin_new_run()
	_run_active = false
	if keep_fraction > 0.0 and not kept_items.is_empty():
		last_hub_message = (
			"Left waves at wave %d — kept %d item(s) (%d%% milestone transfer)."
			% [wave, kept_items.size(), int(round(keep_fraction * 100.0))]
		)
	else:
		last_hub_message = "Left waves early — loadout was not kept."
	_clear_in_run_meta()
	return_to_hub(last_hub_message)


func complete_waves_run(rewards: Array[String]) -> void:
	_run_active = false
	var elapsed := (Time.get_ticks_msec() / 1000.0) - _run_start_time
	for item_id in rewards:
		InventoryService.add_item(item_id, 1)
	var xp_result := ProgressionService.grant_xp(WAVES_COMPLETION_XP, "waves")
	last_run_results = (
		RunLifecycle
		. build_results(
			RunLifecycle.OUTCOME_WAVES_COMPLETE,
			elapsed,
			WavesRunService.get_kill_count(),
			rewards,
			xp_result,
			WAVES_COMPLETION_XP,
			"Waves cleared: kept up to 3 chosen items.",
			{
				"run_mode": RM.MODE_WAVES,
				"floor_reached": 0,
				"boss_defeated": false,
				"loot_kept": true,
				"run_relics_lost": false,
				"loot_lost": [],
			}
		)
	)
	LocalSave.clear_waves_active_run()
	LocalSave.autosave_checkpoint()
	QuestService.register_run_outcome(RunLifecycle.OUTCOME_WAVES_COMPLETE, {"run_mode": run_mode})
	MerchantService.restock_all()
	_decorate_run_results()
	run_ended.emit(last_run_results)
	get_tree().root.set_meta("run_results", last_run_results)
	_clear_in_run_meta()
	_goto_scene(RESULTS_SCENE)


func on_waves_failed() -> void:
	var elapsed := 0.0
	if _run_start_time > 0.0:
		elapsed = (Time.get_ticks_msec() / 1000.0) - _run_start_time
	var had_relics := _had_run_relics()
	last_run_results = (
		RunLifecycle
		. build_results(
			RunLifecycle.OUTCOME_WAVES_FAILED,
			elapsed,
			WavesRunService.get_kill_count(),
			[],
			{"gained": 0, "levels_gained": 0},
			0,
			"Waves failed: no items transferred to main inventory.",
			{
				"run_mode": RM.MODE_WAVES,
				"floor_reached": 0,
				"boss_defeated": false,
				"loot_kept": false,
				"run_relics_lost": had_relics,
				"loot_lost": [],
			}
		)
	)
	LocalSave.clear_waves_active_run()
	LocalSave.autosave_checkpoint()
	QuestService.register_run_outcome(RunLifecycle.OUTCOME_WAVES_FAILED, {"run_mode": run_mode})
	MerchantService.restock_all()
	_decorate_run_results()
	run_ended.emit(last_run_results)
	get_tree().root.set_meta("run_results", last_run_results)
	_run_active = false
	_clear_in_run_meta()
	_goto_scene(RESULTS_SCENE)
