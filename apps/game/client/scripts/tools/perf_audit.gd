extends Node

## Measures what each playable scene actually costs, so optimisation work starts from numbers
## rather than from guesses about what is probably slow.
##
## Reports the frame time the player would feel (average and worst-in-twenty, which is what reads
## as a stutter), what the renderer is being asked to draw, and how much of the frame the scripts
## are taking as opposed to the GPU. A scene that draws little but processes a lot needs a
## different fix from one that draws a lot, and averaging them together hides both.
##
## Run with a display -- headless reports a GPU cost of nothing:
##   godot --path apps/game/client res://scenes/debug/perf_audit.tscn

const SETTLE_FRAMES := 240
const SAMPLE_FRAMES := 300

const TARGETS: Array[Dictionary] = [
	{"id": "hub", "path": "res://scenes/hub/hub.tscn"},
	{"id": "combat_arena", "path": "res://scenes/combat/combat_arena.tscn"},
	{"id": "castle_slice", "path": "res://scenes/dungeon/forgotten_castle_slice.tscn"},
	{"id": "castle_run", "path": "res://scenes/dungeon/castle_run.tscn"},
]

## Frame budgets. 16.7ms is 60fps; a scene over that is dropping frames on this machine, and this
## machine is not the slowest one anyone will play on.
const BUDGET_MS := 16.7


func _ready() -> void:
	get_tree().current_scene = null
	if CharacterService != null and CharacterService.get_class_id() == "":
		CharacterService.set_class_id("knight")
	if LocalSave != null:
		LocalSave.set_character_profile("Perf Warden", CharacterService.get_class_id())
	# castle_run will not build a floor without a dungeon definition. Without this it loads, errors,
	# and reports the cost of an empty room -- which is how it first came out looking cheap.
	if RunFlow == null or RunFlow.current_dungeon_definition.is_empty():
		var fixture := ContentLoader.load_json(
			"content/fixtures/dungeon_definition_v2_gdscript.json"
		)
		if not fixture.is_empty():
			get_tree().root.set_meta("dungeon_definition", fixture)

	# The tree root is still finishing its own setup on the frame this node's `_ready()` runs in --
	# `add_child` on it from here fails with "Parent node is busy setting up children". Every target
	# after the first was safe by accident, landing after the previous one's settle/sample frames
	# had already let a frame pass; only the first `_measure` call raced the root and silently
	# measured an empty scene (0 draws, 0 objects) while still printing a frame time.
	await get_tree().process_frame

	print("PERF %-14s %8s %8s %7s %9s %8s %9s %8s" % [
		"scene", "avg_ms", "p95_ms", "fps", "draws", "prims_k", "objects", "nodes"])
	var over_budget: Array[String] = []
	for target in TARGETS:
		var row := await _measure(str(target["id"]), str(target["path"]))
		if row.is_empty():
			continue
		if float(row["avg_ms"]) > BUDGET_MS:
			over_budget.append("%s at %.1fms" % [row["id"], row["avg_ms"]])
	print("")
	if over_budget.is_empty():
		print("PERF all scenes inside the %.1fms budget" % BUDGET_MS)
	else:
		print("PERF over budget: %s" % ", ".join(over_budget))
	get_tree().quit(0)


func _measure(id: String, path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		print("PERF %-14s missing" % id)
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		print("PERF %-14s could not load" % id)
		return {}
	var instance := packed.instantiate()
	get_tree().root.add_child(instance)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	# Wall-clock frame time, which is what the player feels. TIME_PROCESS is script time only and
	# would report a scene as fast while the GPU was missing every frame.
	var samples: PackedFloat32Array = []
	var last := Time.get_ticks_usec()
	for _i in SAMPLE_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - last) / 1000.0)
		last = now
	var frame_ms := _mean(samples)
	var p95 := _percentile(samples, 0.95)

	var row := {
		"id": id,
		"avg_ms": frame_ms,
		"p95_ms": p95,
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	}
	print("PERF %-14s %8.2f %8.2f %7.0f %9.0f %8.1f %9.0f %8.0f" % [
		id, frame_ms, p95, 1000.0 / maxf(frame_ms, 0.001),
		row["draws"], float(row["prims"]) / 1000.0, row["objects"], row["nodes"]])

	instance.queue_free()
	for _i in 20:
		await get_tree().process_frame
	return row


func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


func _percentile(values: PackedFloat32Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(float(sorted.size()) * fraction), 0, sorted.size() - 1)]
