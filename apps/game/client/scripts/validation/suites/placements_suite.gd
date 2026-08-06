extends "res://scripts/validation/validation_suite.gd"

const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")
const ProcgenPlacementsScript := preload("res://scripts/dungeon/procgen/procgen_placements.gd")
const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")
const RoomGraphAssignerScript := preload("res://scripts/dungeon/procgen/room_graph_assigner.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")


func get_category() -> String:
	return "placements"


func run() -> void:
	_test_anchors_inside_room()
	_test_loot_from_biome_data()
	_test_loot_scales_with_tier()
	_test_stream_independence()
	_test_placement_determinism()
	_test_trap_ids_resolvable()
	_test_missing_boss_fails()
	_test_threat_budget_respected()
	_test_treasure_main_when_treasure_room()


func _test_anchors_inside_room() -> void:
	var ok := true
	var details := ""
	for kind in RoomTemplateCatalogScript.KIND_SPECS.keys():
		var spec: Dictionary = RoomTemplateCatalogScript.KIND_SPECS[kind]
		var anchors: Dictionary = spec.get("anchors", {})
		for role in ["enemy", "cover", "chest", "trap"]:
			for anchor in anchors.get(role, []):
				if not RoomTemplateCatalogScript.anchor_inside_kind(kind, anchor):
					ok = false
					details = "kind=%s role=%s anchor=%s" % [kind, role, str(anchor)]
					break
	ctx.record(
		"placements.anchors_inside_room",
		get_category(),
		ok,
		"all catalog anchors inside kind bounds" if ok else details,
		"PLC-02"
	)


func _test_loot_from_biome_data() -> void:
	var ok := true
	var details := ""
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var biome := BiomeRegistry.get_biome(biome_id)
		if biome.is_empty():
			ok = false
			details = "failed to load %s" % biome_id
			break
		var tables: Dictionary = biome.get("lootTables", {})
		for role in ["treasure", "secret", "side", "armory"]:
			for entry in tables.get(role, []):
				var item_id := str(entry.get("itemId", ""))
				if not ItemCatalog.has_item(item_id):
					ok = false
					details = "%s missing item %s" % [biome_id, item_id]
					break
	ctx.record(
		"placements.loot_from_biome_data",
		get_category(),
		ok,
		"loot item ids resolve in ItemCatalog" if ok else details,
		"PLC-01"
	)


func _test_loot_scales_with_tier() -> void:
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var values: Array = []
	for tier in range(1, 6):
		var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, tier, 1, 1)
		if not gen.get("ok", false):
			ctx.record(
				"placements.loot_scales_with_tier",
				get_category(),
				false,
				"generation failed at tier %d" % tier,
				"PLC-03"
			)
			return
		values.append(float(gen.get("definition", {}).get("budgets", {}).get("lootValue", 0.0)))
	var monotonic := true
	for i in range(1, values.size()):
		if values[i] < values[i - 1]:
			monotonic = false
			break
	var budgets: Dictionary = biome.get("budgets", {})
	var expected_delta := float(budgets.get("lootPerTier", 14)) * 4.0
	var actual_delta: float = values[4] - values[0]
	var within := absf(actual_delta - expected_delta) <= expected_delta * 0.2 + 1.0
	ctx.record(
		"placements.loot_scales_with_tier",
		get_category(),
		monotonic and within,
		"tier loot values %s delta=%.1f expected~%.1f" % [str(values), actual_delta, expected_delta],
		"PLC-03"
	)


func _test_stream_independence() -> void:
	var base := _placements_for_seed(TC.SEED_A, 1)
	var burned := _placements_for_seed_with_assign_burn(TC.SEED_A, 1, 7)
	var enemies_match := JSON.stringify(base.get("enemies", [])) == JSON.stringify(
		burned.get("enemies", [])
	)
	var loot_match := JSON.stringify(base.get("loot", [])) == JSON.stringify(burned.get("loot", []))
	ctx.record(
		"placements.stream_independence",
		get_category(),
		enemies_match and loot_match,
		"extra assign draws do not change enemies/loot",
		"PLC-05"
	)


func _test_placement_determinism() -> void:
	ProcgenRng.clear_cache()
	var a := _placements_for_seed(TC.SEED_B, 3)
	ProcgenRng.clear_cache()
	var b := _placements_for_seed(TC.SEED_B, 3)
	var match := JSON.stringify(a) == JSON.stringify(b)
	ctx.record(
		"placements.determinism",
		get_category(),
		match,
		"same seed yields identical placements JSON",
		"PLC-05"
	)


func _test_trap_ids_resolvable() -> void:
	var ok := true
	var missing := ""
	for biome_id in BiomeRegistry.ALL_BIOMES:
		for seed in [TC.SEED_A, TC.SEED_B]:
			var gen := DungeonProcgenScript.generate(biome_id, seed, 2, 1, 1)
			if not gen.get("ok", false):
				continue
			for trap in gen.get("definition", {}).get("placements", {}).get("traps", []):
				var trap_id := str(trap.get("trapId", ""))
				var path := TrapCatalog.get_scene_path(trap_id)
				if path.is_empty() or not ResourceLoader.exists(path):
					ok = false
					missing = trap_id
					break
	ctx.record(
		"placements.trap_ids_resolvable",
		get_category(),
		ok,
		"all trap ids resolve to scenes" if ok else "missing trap %s" % missing,
		"PLC-06"
	)


func _test_missing_boss_fails() -> void:
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	if not graph_result.get("ok", false):
		ctx.record(
			"placements.missing_boss_fails",
			get_category(),
			false,
			"graph generation failed",
			"PLC-09"
		)
		return
	var graph: RoomGraph = graph_result.get("graph")
	var assignment := RoomGraphAssignerScript.assign(
		biome, graph, ProcgenRng.stream(TC.SEED_A, "assign")
	)
	for room in assignment.get("rooms", []):
		if room.get("type", "") == "boss":
			room["type"] = "combat"
	var result := ProcgenPlacementsScript.place(
		biome, assignment, TC.SEED_A, 1, 1, 1, graph
	)
	ctx.record(
		"placements.missing_boss_fails",
		get_category(),
		not result.get("ok", true),
		"place() returns error without boss room",
		"PLC-09"
	)


func _test_threat_budget_respected() -> void:
	var ok := true
	for _i in 20:
		var gen := DungeonProcgenScript.generate("forgotten_castle", randi(), 3, 5, 1)
		if not gen.get("ok", false):
			continue
		var biome := BiomeRegistry.get_biome("forgotten_castle")
		var budgets: Dictionary = biome.get("budgets", {})
		var cap := (
			float(budgets.get("baseEnemyThreat", 200))
			+ float(budgets.get("threatPerTier", 35)) * 2.0
			+ 5.0 * 5.0
		)
		var used := float(gen.get("definition", {}).get("budgets", {}).get("enemyThreat", 0.0))
		if used > cap + 0.01:
			ok = false
			break
	ctx.record(
		"placements.threat_budget_respected",
		get_category(),
		ok,
		"enemy threat stays within tier budget",
		"PLC-08"
	)


func _test_treasure_main_when_treasure_room() -> void:
	var ok := true
	for _i in 30:
		var gen := DungeonProcgenScript.generate("forgotten_castle", randi(), 2, 1, 1)
		if not gen.get("ok", false):
			continue
		var rooms: Array = gen.get("definition", {}).get("rooms", [])
		var has_treasure := false
		for room in rooms:
			if room.get("type", "") == "treasure":
				has_treasure = true
				break
		if not has_treasure:
			continue
		var loot: Array = gen.get("definition", {}).get("placements", {}).get("loot", [])
		var found := false
		for chest in loot:
			if str(chest.get("chestId", "")) == "treasure_main":
				found = true
				break
		if not found:
			ok = false
			break
	ctx.record(
		"placements.treasure_main",
		get_category(),
		ok,
		"treasure rooms get treasure_main chest",
		"PLC-04"
	)


func _placements_for_seed(seed: int, tier: int) -> Dictionary:
	var gen := DungeonProcgenScript.generate("forgotten_castle", seed, tier, 1, 1)
	return gen.get("definition", {}).get("placements", {})


func _placements_for_seed_with_assign_burn(seed: int, tier: int, burn_count: int) -> Dictionary:
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(
		config, ProcgenRng.stream(seed, "graph").seed
	)
	if not graph_result.get("ok", false):
		return {}
	var graph: RoomGraph = graph_result.get("graph")
	var assign_rng := ProcgenRng.stream(seed, "assign")
	for _i in burn_count:
		assign_rng.randf()
	var assignment := RoomGraphAssignerScript.assign(biome, graph, assign_rng)
	return ProcgenPlacementsScript.place(biome, assignment, seed, tier, 1, 1, graph)
