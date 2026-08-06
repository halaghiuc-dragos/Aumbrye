extends "res://scripts/validation/validation_suite.gd"

const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")
const VfxServiceScript := preload("res://scripts/art/vfx/vfx_service.gd")

const BUDGET_DUNGEON_BUILD_MS := 1500
const BUDGET_PROCGEN_MS := 250
const BUDGET_SAVE_WRITE_MS := 50
const BUDGET_CONTENT_LOAD_MS := 750
const BUDGET_NODE_COUNT := 8000
const BUDGET_STATIC_MEMORY_BYTES := 512 * 1024 * 1024


func get_category() -> String:
	return "performance"


func run() -> void:
	await _test_vfx_burst_pool()
	_test_frame_budget()
	_test_dungeon_build_ms()
	_test_procgen_generate_ms()
	_test_save_write_ms()
	_test_content_load_ms()
	_test_node_count_after_build()
	_test_static_memory_after_build()


func _test_vfx_burst_pool() -> void:
	var start := Time.get_ticks_msec()
	var service := VfxServiceScript.new()
	ctx.owner.add_child(service)
	await ctx.owner.get_tree().process_frame
	var peak := 0
	for _i in 200:
		service.play("hit_spark", Vector3.ZERO, Vector3.UP)
		peak = maxi(peak, service.get_burst_pool_size())
	var reused := false
	for _i in 50:
		var before := service.get_burst_pool_size()
		service.play("hit_spark", Vector3.ZERO, Vector3.UP)
		reused = service.get_burst_pool_size() <= before + 1
		if reused:
			break
	service.queue_free()
	ctx.timed_record(
		"perf.vfx_burst_pool",
		get_category(),
		peak <= VfxServiceScript.BURST_POOL_MAX and reused,
		"VfxService pools bursts and reuses instances (peak=%d)" % peak,
		start,
		"VFX-13"
	)


func _test_frame_budget() -> void:
	var baseline_path := "user://perf_baseline.json"
	if not FileAccess.file_exists(baseline_path):
		skip(
			"perf.frame_budget",
			"user://perf_baseline.json absent; record baseline in-editor first",
			"VFX-13"
		)
		return
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string(baseline_path)
	var data: Variant = JSON.parse_string(text)
	var p95 := 0.0
	if data is Dictionary:
		p95 = float(data.get("p95_frame_ms", data.get("frame_time_p95_ms", 0.0)))
	var ok := p95 > 0.0 and p95 <= 16.67
	ctx.timed_record(
		"perf.frame_budget",
		get_category(),
		ok,
		"p95 frame time %.2f ms (budget 16.67)" % p95,
		start,
		"VFX-13"
	)


func _test_dungeon_build_ms() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var elapsed := 0
	if gen.get("ok", false):
		var build_start := Time.get_ticks_msec()
		var root := Node3D.new()
		ctx.owner.add_child(root)
		var player: CharacterBody3D = (
			load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
		)
		root.add_child(player)
		var builder := DungeonBuilder.new()
		root.add_child(builder)
		builder.build_from_definition(root, player, gen.get("definition", {}))
		elapsed = Time.get_ticks_msec() - build_start
		root.queue_free()
	ctx.timed_record(
		"perf.dungeon_build_ms",
		get_category(),
		elapsed > 0 and elapsed < BUDGET_DUNGEON_BUILD_MS,
		"dungeon build %d ms (budget %d)" % [elapsed, BUDGET_DUNGEON_BUILD_MS],
		start,
		"VSU-05"
	)


func _test_procgen_generate_ms() -> void:
	var start := Time.get_ticks_msec()
	var gen_start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var elapsed := Time.get_ticks_msec() - gen_start
	ctx.timed_record(
		"perf.procgen_generate_ms",
		get_category(),
		gen.get("ok", false) and elapsed < BUDGET_PROCGEN_MS,
		"procgen generate %d ms (budget %d)" % [elapsed, BUDGET_PROCGEN_MS],
		start,
		"VSU-05"
	)


func _test_save_write_ms() -> void:
	var backup: Dictionary = ctx.backup_save_file()
	var start := Time.get_ticks_msec()
	LocalSave.delete_save()
	InventoryService.inventory = GridInventory.new()
	LocalSave.autosave()
	var elapsed := Time.get_ticks_msec() - start
	ctx.restore_save_file(backup)
	ctx.timed_record(
		"perf.save_write_ms",
		get_category(),
		elapsed < BUDGET_SAVE_WRITE_MS,
		"save write %d ms (budget %d)" % [elapsed, BUDGET_SAVE_WRITE_MS],
		start,
		"VSU-05"
	)


func _test_content_load_ms() -> void:
	var start := Time.get_ticks_msec()
	var load_start := Time.get_ticks_msec()
	ContentLoader.load_json("content/items/catalog.json")
	var elapsed := Time.get_ticks_msec() - load_start
	ctx.timed_record(
		"perf.content_load_ms",
		get_category(),
		elapsed < BUDGET_CONTENT_LOAD_MS,
		"content load %d ms (budget %d)" % [elapsed, BUDGET_CONTENT_LOAD_MS],
		start,
		"VSU-05"
	)


func _test_node_count_after_build() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var count := 0
	if gen.get("ok", false):
		var root := Node3D.new()
		ctx.owner.add_child(root)
		var player: CharacterBody3D = (
			load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
		)
		root.add_child(player)
		var builder := DungeonBuilder.new()
		root.add_child(builder)
		builder.build_from_definition(root, player, gen.get("definition", {}))
		count = _count_nodes(root)
		root.queue_free()
	ctx.timed_record(
		"perf.node_count_after_build",
		get_category(),
		count > 0 and count < BUDGET_NODE_COUNT,
		"built dungeon node count %d (budget %d)" % [count, BUDGET_NODE_COUNT],
		start,
		"VSU-05"
	)


func _test_static_memory_after_build() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	if gen.get("ok", false):
		var root := Node3D.new()
		ctx.owner.add_child(root)
		var player: CharacterBody3D = (
			load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
		)
		root.add_child(player)
		var builder := DungeonBuilder.new()
		root.add_child(builder)
		builder.build_from_definition(root, player, gen.get("definition", {}))
		root.queue_free()
	var static_mem := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	ctx.timed_record(
		"perf.static_memory_after_build",
		get_category(),
		static_mem < BUDGET_STATIC_MEMORY_BYTES,
		"static memory %d bytes (budget %d)" % [static_mem, BUDGET_STATIC_MEMORY_BYTES],
		start,
		"VSU-05"
	)


static func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count
