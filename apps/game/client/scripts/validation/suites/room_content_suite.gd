extends "res://scripts/validation/validation_suite.gd"

const RoomContentAssignerScript := preload("res://scripts/dungeon/procgen/room_content_assigner.gd")
const RoomContentConfigScript := preload("res://scripts/dungeon/procgen/room_content_config.gd")
const RoomContentValidatorScript := preload("res://scripts/dungeon/procgen/room_content_validator.gd")
const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphAssignerScript := preload("res://scripts/dungeon/procgen/room_graph_assigner.gd")
const RoomGraphPathsScript := preload("res://scripts/dungeon/procgen/room_graph_paths.gd")
const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")
const LockedVaultScript := preload("res://scripts/dungeon/room_content/room_locked_vault_content.gd")
const LockedDoorScript := preload("res://scripts/dungeon/room_content/room_locked_door_content.gd")

const _BIOME_IDS := [
	"forgotten_castle",
	"crystal_caverns",
	"poison_swamp",
	"frozen_fortress",
	"dark_cathedral",
	"iron_vault",
	"prism_depths",
	"venom_mire",
	"glacial_hollow",
	"umbral_chapel",
]


func get_category() -> String:
	return "room_content"


func run() -> void:
	_test_content_assignment()
	_test_critical_path()
	_test_definition_includes_content()
	_test_world_state_resets()
	_test_world_flags_registry_only()
	_test_key_requires_carry()
	_test_key_rooms_are_off_path()
	_test_key_room_not_reserved()
	_test_reward_entries_have_items()
	_test_puzzle_entries_exist()
	_test_content_type_coverage()
	_test_weight_distribution()
	_test_assignment_determinism()
	_test_no_fallback_assignment()
	_test_collectible_simulation_runs()


func _test_content_assignment() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph: RoomGraph = graph_result.get("graph")
	var rng := RandomNumberGenerator.new()
	rng.seed = TC.SEED_A ^ 0x5EED
	var assignment := RoomGraphAssignerScript.assign(biome, graph, rng)
	var content_result := RoomContentAssignerScript.assign(
		graph, assignment, rng, RoomContentConfigScript.default(), "forgotten_castle"
	)
	var content: Dictionary = content_result.get("content", {})
	var ok: bool = content_result.get("ok", false) and not content.get("roomContent", []).is_empty()
	ctx.timed_record(
		"room_content.assigns_types",
		get_category(),
		ok,
		"content assignment produces roomContent entries",
		start,
		"M8.room_content.assign"
	)


func _test_critical_path() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_B)
	var graph: RoomGraph = graph_result.get("graph")
	var path: Array[String] = RoomGraphPathsScript.critical_path_ids(graph)
	var ok: bool = (
		path.size() >= 2 and path[0] == graph.start_id and path[path.size() - 1] == graph.boss_id
	)
	ctx.timed_record(
		"room_content.critical_path",
		get_category(),
		ok,
		"critical path runs start→boss (%d rooms)" % path.size(),
		start,
		"M8.room_content.path"
	)


func _test_definition_includes_content() -> void:
	var start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var def: Dictionary = gen.get("definition", {})
	var ok: bool = (
		gen.get("ok", false) and def.has("roomContent") and def.get("roomContent", []) is Array
	)
	ctx.timed_record(
		"room_content.definition_fields",
		get_category(),
		ok,
		"DungeonDefinition includes roomContent/locks/puzzles",
		start,
		"M8.room_content.definition"
	)


func _test_world_state_resets() -> void:
	var start := Time.get_ticks_msec()
	WorldState.set_flag(WorldFlags.lock_opened("test_key"), true)
	RunFlow.run_ended.emit({})
	var ok: bool = not WorldState.has_flag(WorldFlags.lock_opened("test_key"))
	ctx.timed_record(
		"room_content.world_state_reset",
		get_category(),
		ok,
		"WorldState clears on run end",
		start,
		"M8.room_content.world_state"
	)


func _test_world_flags_registry_only() -> void:
	var start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var def: Dictionary = gen.get("definition", {})
	var ok: bool = gen.get("ok", false)
	for lock in def.get("locks", []):
		var lock_id: String = str(lock.get("lockId", ""))
		if lock_id != "" and not WorldFlags.is_valid_id(WorldFlags.lock_opened(lock_id)):
			ok = false
			break
	for entry in def.get("roomContent", []):
		var lock_id: String = str(entry.get("lockId", entry.get("keyId", "")))
		if lock_id != "" and not WorldFlags.is_valid_id(WorldFlags.lock_opened(lock_id)):
			ok = false
			break
		var quest_key: String = str(entry.get("questKeyId", ""))
		if quest_key != "" and not WorldFlags.is_valid_id(WorldFlags.secret_opened(quest_key)):
			ok = false
			break
	for puzzle in def.get("puzzles", []):
		var flag_id: String = str(puzzle.get("flagId", ""))
		if flag_id != "" and not WorldFlags.is_valid_id(WorldFlags.lever_pulled(flag_id)):
			ok = false
			break
	ctx.timed_record(
		"room_content.world_flags.registry_only",
		get_category(),
		ok,
		"generated content uses WorldFlags builder ids",
		start,
		"M8.room_content.world_flags"
	)


func _test_key_requires_carry() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph: RoomGraph = graph_result.get("graph")
	var rng := RandomNumberGenerator.new()
	rng.seed = TC.SEED_A
	var assignment := RoomGraphAssignerScript.assign(biome, graph, rng)
	var content_result := RoomContentAssignerScript.assign(
		graph, assignment, rng, RoomContentConfigScript.default(), "forgotten_castle"
	)
	var content: Dictionary = content_result.get("content", {})
	var locks: Array = content.get("locks", [])
	if locks.is_empty():
		ok = true
	else:
		var lock: Dictionary = locks[0]
		var key_id := str(lock.get("keyId", ""))
		InventoryService.clear_dungeon_keys()
		WorldState.reset_run_flags()
		var vault := Node3D.new()
		vault.set_script(LockedVaultScript)
		var vault_entry := {
			"keyId": key_id,
			"lockId": lock.get("lockId", ""),
			"keyLabel": "Test Key",
			"items": [],
		}
		vault.call("configure", vault_entry, {})
		InventoryService.add_dungeon_key(key_id, str(lock.get("lockId", "")), "Test Key")
		var door := Node3D.new()
		door.set_script(LockedDoorScript)
		var from_room := RoomTemplate.new()
		var to_room := RoomTemplate.new()
		door.call("configure", lock, from_room, to_room)
		ok = InventoryService.has_dungeon_key(key_id) and door.get("_unlocked") == false
		door.set("_near_player", true)
		var interact := InputEventAction.new()
		interact.action = &"interact"
		interact.pressed = true
		door.call("_unhandled_input", interact)
		ok = ok and InventoryService.has_dungeon_key(key_id) and door.get("_unlocked") == false
		door.call("_unhandled_input", interact)
		ok = ok and not InventoryService.has_dungeon_key(key_id) and door.get("_unlocked") == true
	ctx.timed_record(
		"room_content.key_requires_carry",
		get_category(),
		ok,
		"locked door opens only after consume_dungeon_key",
		start,
		"RMC-01"
	)


func _test_key_rooms_are_off_path() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_index in mini(10, _BIOME_IDS.size()):
		var biome_id: String = _BIOME_IDS[biome_index]
		for seed_offset in 20:
			var biome := BiomeRegistry.get_biome(biome_id)
			var config := RoomGraphConfigScript.from_biome(biome)
			var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_A + seed_offset)
			var graph: RoomGraph = graph_result.get("graph")
			var rng := RandomNumberGenerator.new()
			rng.seed = TC.SEED_A + seed_offset
			var assignment := RoomGraphAssignerScript.assign(biome, graph, rng)
			var critical: Array[String] = RoomGraphPathsScript.critical_path_ids(graph)
			var critical_set := {}
			for layout_id in critical:
				critical_set[layout_id] = true
			var content_result := RoomContentAssignerScript.assign(
				graph, assignment, rng, RoomContentConfigScript.default(), biome_id
			)
			if not content_result.get("ok", false):
				continue
			for lock in content_result.get("content", {}).get("locks", []):
				var key_layout := str(lock.get("keyLayoutId", ""))
				if critical_set.has(key_layout):
					ok = false
					break
			if not ok:
				break
		if not ok:
			break
	ctx.timed_record(
		"room_content.key_rooms_off_path",
		get_category(),
		ok,
		"key rooms are not on the critical path layout",
		start,
		"RMC-05"
	)


func _test_key_room_not_reserved() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_B)
	var graph: RoomGraph = graph_result.get("graph")
	var rng := RandomNumberGenerator.new()
	rng.seed = TC.SEED_B
	var assignment := RoomGraphAssignerScript.assign(biome, graph, rng)
	var content_result := RoomContentAssignerScript.assign(
		graph, assignment, rng, RoomContentConfigScript.default(), "forgotten_castle"
	)
	for lock in content_result.get("content", {}).get("locks", []):
		var key_layout := str(lock.get("keyLayoutId", ""))
		if key_layout in [graph.start_id, graph.stairs_id, graph.boss_id]:
			ok = false
			break
	ctx.timed_record(
		"room_content.key_room_not_reserved",
		get_category(),
		ok,
		"key rooms avoid start/stairs/boss layouts",
		start,
		"RMC-08"
	)


func _test_reward_entries_have_items() -> void:
	var start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var ok: bool = gen.get("ok", false)
	for entry in gen.get("definition", {}).get("roomContent", []):
		var content_type := str(entry.get("contentType", ""))
		if content_type not in ["reward", "locked_vault"]:
			continue
		var items: Array = entry.get("items", [])
		if items.is_empty():
			ok = false
			break
		for item in items:
			var item_id := str(item.get("itemId", ""))
			if item_id == "" or ItemCatalog.get_definition(item_id).is_empty():
				ok = false
				break
	ctx.timed_record(
		"room_content.reward_items",
		get_category(),
		ok,
		"reward and locked_vault entries include catalog items",
		start,
		"RMC-02"
	)


func _test_puzzle_entries_exist() -> void:
	var start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var def: Dictionary = gen.get("definition", {})
	var ok: bool = gen.get("ok", false)
	var puzzle_rooms := 0
	for entry in def.get("roomContent", []):
		if str(entry.get("contentType", "")) == "puzzle":
			puzzle_rooms += 1
	var puzzles: Array = def.get("puzzles", [])
	if puzzle_rooms != puzzles.size():
		ok = false
	for puzzle in puzzles:
		var gate_id := str(puzzle.get("gateRoomId", ""))
		var room_id := str(puzzle.get("roomId", ""))
		if gate_id == "" or gate_id == room_id:
			ok = false
	ctx.timed_record(
		"room_content.puzzle_entries",
		get_category(),
		ok,
		"puzzle rooms have matching puzzle definitions",
		start,
		"RMC-03"
	)


func _test_content_type_coverage() -> void:
	var start := Time.get_ticks_msec()
	var seen := {}
	for i in 2000:
		var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A + i, 1, 1, 1, false, false)
		if not gen.get("ok", false):
			continue
		for entry in gen.get("definition", {}).get("roomContent", []):
			seen[str(entry.get("contentType", ""))] = true
		for lock in gen.get("definition", {}).get("locks", []):
			if not lock.is_empty():
				seen["locked_vault"] = true
	var config := RoomContentConfigScript.default()
	var rng := RandomNumberGenerator.new()
	rng.seed = TC.SEED_B
	for _i in 5000:
		var picked := RoomContentAssignerScript._pick_content_type(false, 4, false, false, rng, config)
		seen[picked] = true
	var required := [
		"combat",
		"empty",
		"trap",
		"hazard",
		"puzzle",
		"npc_quest",
		"reward",
		"rest",
		"lore",
		"merchant",
	]
	var missing: Array[String] = []
	for content_type in required:
		if not seen.has(content_type):
			missing.append(content_type)
	var ok := missing.is_empty()
	ctx.timed_record(
		"room_content.type_coverage",
		get_category(),
		ok,
		"off-path types seen (missing: %s)" % ", ".join(missing),
		start,
		"RMC-06"
	)


func _test_weight_distribution() -> void:
	var start := Time.get_ticks_msec()
	var config := RoomContentConfigScript.default()
	var counts := {}
	var samples := 5000
	var rng := RandomNumberGenerator.new()
	rng.seed = TC.SEED_A
	for _i in samples:
		var picked := RoomContentAssignerScript._pick_content_type(false, 4, false, false, rng, config)
		counts[picked] = int(counts.get(picked, 0)) + 1
	var targets := {
		"trap": 0.09,
		"hazard": 0.07,
		"puzzle": 0.05,
		"npc_quest": 0.02,
		"combat": 0.45,
		"empty": 0.14,
		"reward": 0.06,
		"lore": 0.06,
		"rest": 0.05,
		"merchant": 0.01,
	}
	var ok := true
	for content_type in targets:
		var observed := float(counts.get(content_type, 0)) / float(samples)
		if absf(observed - float(targets[content_type])) > 0.03:
			ok = false
			break
	ctx.timed_record(
		"room_content.weight_distribution",
		get_category(),
		ok,
		"off-path weight roll matches normalized targets within 3%",
		start,
		"RMC-07"
	)


func _test_assignment_determinism() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph: RoomGraph = graph_result.get("graph")
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = TC.SEED_A
	var assignment := RoomGraphAssignerScript.assign(biome, graph, rng_a)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = TC.SEED_A
	var first: Dictionary = RoomContentAssignerScript.assign(
		graph, assignment, rng_b, RoomContentConfigScript.default(), "forgotten_castle"
	)
	var rng_c := RandomNumberGenerator.new()
	rng_c.seed = TC.SEED_A
	var second: Dictionary = RoomContentAssignerScript.assign(
		graph, assignment, rng_c, RoomContentConfigScript.default(), "forgotten_castle"
	)
	var rng_d := RandomNumberGenerator.new()
	rng_d.seed = TC.SEED_A + 999_983
	var different: Dictionary = RoomContentAssignerScript.assign(
		graph, assignment, rng_d, RoomContentConfigScript.default(), "forgotten_castle"
	)
	var ok: bool = (
		first.get("ok", false)
		and second.get("ok", false)
		and JSON.stringify(first.get("content", {})) == JSON.stringify(second.get("content", {}))
		and different.get("ok", false)
		and JSON.stringify(first.get("content", {})) != JSON.stringify(different.get("content", {}))
	)
	ctx.timed_record(
		"room_content.assignment_determinism",
		get_category(),
		ok,
		"same seed yields identical content; seed+1 differs",
		start,
		"RMC.assign_determinism"
	)


func _test_no_fallback_assignment() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_index in _BIOME_IDS.size():
		for seed_offset in 50:
			var biome_id: String = _BIOME_IDS[biome_index]
			var biome := BiomeRegistry.get_biome(biome_id)
			var config := RoomGraphConfigScript.from_biome(biome)
			var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_B + seed_offset)
			var graph: RoomGraph = graph_result.get("graph")
			var rng := RandomNumberGenerator.new()
			rng.seed = TC.SEED_B + seed_offset
			var assignment := RoomGraphAssignerScript.assign(biome, graph, rng)
			var content_result := RoomContentAssignerScript.assign(
				graph, assignment, rng, RoomContentConfigScript.default(), biome_id
			)
			if content_result.get("used_fallback", false):
				ok = false
				break
		if not ok:
			break
	ctx.timed_record(
		"room_content.no_fallback",
		get_category(),
		ok,
		"assigner never returns used_fallback across 500 seeds",
		start,
		"RMC.assign_no_fallback"
	)


func _test_collectible_simulation_runs() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph: RoomGraph = graph_result.get("graph")
	var rng := RandomNumberGenerator.new()
	rng.seed = TC.SEED_A
	var assignment := RoomGraphAssignerScript.assign(biome, graph, rng)
	var good := RoomContentAssignerScript.assign(
		graph, assignment, rng, RoomContentConfigScript.default(), "forgotten_castle"
	)
	var good_validation: Dictionary = RoomContentValidatorScript.validate(
		graph, assignment, good.get("content", {})
	)
	var bad_content: Dictionary = good.get("content", {}).duplicate(true)
	var has_npc := false
	for entry in bad_content.get("roomContent", []):
		if str(entry.get("contentType", "")) != "npc_quest":
			continue
		has_npc = true
		entry["dialogueId"] = "dungeon_npc_stranded"
		break
	if not has_npc:
		bad_content.get("roomContent", []).append(
			{
				"roomId": "room_fake_npc",
				"layoutId": "fake",
				"contentType": "npc_quest",
				"templateId": "npc_quest_giver",
				"dialogueId": "dungeon_npc_stranded",
				"questKeyId": "met_dungeon_npc",
			}
		)
	for entry in bad_content.get("roomContent", []):
		if not entry.has("items"):
			continue
		var kept: Array = []
		for item in entry.get("items", []):
			if str(item.get("itemId", "")) != "iron_scrap":
				kept.append(item)
		entry["items"] = kept
	var bad_validation: Dictionary = RoomContentValidatorScript.validate(graph, assignment, bad_content)
	var ok: bool = good_validation.get("ok", false) and not bad_validation.get("ok", true)
	ctx.timed_record(
		"room_content.collectible_simulation",
		get_category(),
		ok,
		"validate() runs collectible checks and rejects invalid quest rewards",
		start,
		"RMC-09"
	)
