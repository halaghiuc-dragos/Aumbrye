extends Node

## Profiles the configured maximum non-boss waves presentation workload in the real arena scene.
## Run on a display for renderer timings; headless remains useful for script/object-count costs.

const WAVES_SCENE := preload("res://scenes/dungeon/waves_run.tscn")
const WavesRunScript := preload("res://scripts/dungeon/waves_run.gd")
const PROFILE_WAVE := 45
const SAMPLE_FRAMES := 300
const SETTLE_FRAMES := 180
const WavesTorchlightScript := preload("res://scripts/dungeon/waves_torchlight.gd")

var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var waves := WAVES_SCENE.instantiate() as Node3D
	get_tree().root.add_child(waves)
	get_tree().current_scene = waves
	var fuel_objective := waves.get_node_or_null("WavesFuelObjective") as Node3D
	_check(fuel_objective != null, "arena creates a visible recovery waystone")
	if fuel_objective:
		waves.call("_set_fuel_objective_for_wave", PROFILE_WAVE)
		_check(fuel_objective.visible, "waystone is active during a combat wave")
		var hud := waves.get("_hud") as Node
		var minimap := hud.get("_minimap") as Node if hud else null
		_check(
			minimap != null and minimap.get("_radar_objective_marker") == fuel_objective,
			"offscreen arena radar tracks the active recovery objective"
		)
		_check(
			fuel_objective.get_node_or_null("RecoveryRing") is MeshInstance3D
			and fuel_objective.get_node_or_null("Beacon") is MeshInstance3D
			and fuel_objective.get_node_or_null("RecoveryLight") is OmniLight3D,
			"waystone has a recognizable emissive marker and light"
		)
		_check(
			fuel_objective.position.is_equal_approx(WavesRunScript.fuel_objective_position_for_wave(PROFILE_WAVE)),
			"runtime waystone location follows the deterministic wave schedule"
		)
	for _frame in SETTLE_FRAMES:
		await get_tree().process_frame
	var torchlight := waves.get_node_or_null("WavesTorchlight")
	_check(torchlight != null, "WavesTorchlight is present in the arena")
	if torchlight:
		torchlight.call("set_lit", true, true)
		var lights := torchlight.find_children("*", "OmniLight3D", true, false)
		var flames: Array = torchlight.get("_pyre_flames")
		var geometry := torchlight.get_node_or_null("PyreGeometry")
		var batches: Array = geometry.find_children("*", "MultiMeshInstance3D", true, false) if geometry else []
		var batch_instances := 0
		for batch_node in batches:
			var batch := batch_node as MultiMeshInstance3D
			if batch.multimesh:
				batch_instances += batch.multimesh.instance_count
		_check(lights.size() == 10, "only near pyres allocate dynamic OmniLights")
		_check(flames.size() == 18, "all near and far pyre flames remain present")
		var visible_flames := 0
		for flame in flames:
			if (flame as Node3D).visible:
				visible_flames += 1
		_check(visible_flames == 18, "far emissive pyre silhouettes remain lit without dynamic lights")
		_check(
			batches.size() == 2 and batch_instances == 54,
			"static pyre geometry is batched into two materials"
		)

	# Isolate this deterministic fixture from any locally restored wave/save state.
	waves.call("_clear_enemies")
	waves.call("_clear_spawn_markers")
	waves.set("_wave_completion_committed", true)
	var enemy_ids := WavesRunService.get_enemies_for_wave(PROFILE_WAVE)
	var bird_count := get_tree().get_nodes_in_group("waves_bird").size()
	_check(enemy_ids.size() == 16, "wave 45 exercises the configured maximum 16-enemy intermission");
	_check(bird_count > 0, "outdoor bird presentation was attached before sampling")
	WavesRunService.current_wave = PROFILE_WAVE
	waves.set("_lobby_active", false)
	waves.set("_spawn_generation", 1)
	waves.set("_pending_spawns", enemy_ids.size())
	var plan_publications_before := int(waves.get("_radar_marker_plan_publish_count"))
	for index in enemy_ids.size():
		waves.call("_spawn_enemy_telegraphed", enemy_ids[index], index, enemy_ids.size(), 1)
	var peak_markers := (waves.get("_spawn_markers") as Array).size()
	_check(peak_markers == enemy_ids.size(), "maximum-wave telegraphs are all created in the synchronous spawn batch")
	var shared_mesh: Mesh = null
	for marker in waves.get("_spawn_markers") as Array:
		var ring := (marker as Node3D).get_node("Ring") as MeshInstance3D
		if shared_mesh == null:
			shared_mesh = ring.mesh
		else:
			_check(ring.mesh == shared_mesh, "spawn markers share one immutable ring mesh")
		var marker_index := (waves.get("_spawn_markers") as Array).find(marker)
		var expected_role := str(waves.call("_spawn_marker_role", enemy_ids[marker_index]))
		_check(str((marker as Node3D).get("_role_icon_key")) == expected_role, "spawn marker encodes the incoming enemy role")
		_check((marker as Node3D).get_node_or_null("RoleIcon") is MeshInstance3D, "spawn marker exposes a readable role silhouette")
		_check((marker as Node3D).get_node_or_null("Countdown") is Label3D, "spawn marker retains the arrival countdown")
	await get_tree().process_frame
	_check(
		int(waves.get("_radar_marker_plan_publish_count")) - plan_publications_before == 1,
		"same-frame telegraph additions publish one radar spawn plan"
	)

	# The last authored stagger is 1.8 seconds after the base 1.1-second tell. Allow relocation
	# retries as well, then verify the live wave reaches its expected occupancy before sampling.
	for _frame in 900:
		await get_tree().process_frame
		if int(waves.get("_pending_spawns")) == 0:
			break
	var active := (waves.get("_active_enemies") as Array).size()
	print(
		"WAVES PRESENTATION SPAWN wave=%d pending=%d active=%d generation=%d lobby=%s"
		% [
			WavesRunService.current_wave,
			int(waves.get("_pending_spawns")),
			active,
			int(waves.get("_spawn_generation")),
			str(waves.get("_lobby_active")),
		]
	)
	_check(int(waves.get("_pending_spawns")) == 0, "all configured maximum-wave spawn timers completed")
	_check(active == enemy_ids.size(), "all maximum-wave enemies spawned after readable telegraphs")
	_check(
		int(waves.get("_radar_marker_incremental_remove_count")) == enemy_ids.size(),
		"telegraph activation removes each radar marker incrementally"
	)

	# Compare equal numbers of actual bird transform updates while all 28 birds and 16 enemies are
	# resident. The first loop reproduces the former group/metadata/node-lookup route; the second
	# invokes the cached runtime records. This is script CPU only, separate from frame-level metrics.
	waves.set_process(false)
	var old_route_usec := _benchmark_old_bird_route(waves, 600)
	var cached_route_usec := _benchmark_cached_bird_route(waves, 600)
	waves.set_process(true)

	var peak_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var peak_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var viewport := get_viewport()
	var viewport_rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	for _frame in 3:
		await get_tree().process_frame
	get_tree().paused = true
	var optimized_metrics := await _sample_render_metrics(viewport_rid)
	var legacy_fixture := _enable_legacy_pyre_fixture(waves)
	for _frame in 3:
		await get_tree().process_frame
	var legacy_metrics := await _sample_render_metrics(viewport_rid)
	get_tree().paused = false
	_restore_optimized_pyre_fixture(waves, legacy_fixture)
	var is_headless := DisplayServer.get_name() == "headless"
	peak_objects = maxi(peak_objects, int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	print(
		"WAVES PRESENTATION OPTIMIZED render_capture=%s frames=%d avg_frame_ms=%.3f p95_frame_ms=%.3f max_frame_ms=%.3f avg_script_ms=%.3f avg_render_cpu_ms=%.3f p95_render_cpu_ms=%.3f avg_render_gpu_ms=%.3f p95_render_gpu_ms=%.3f avg_draw_calls=%.1f avg_primitives=%.0f peak_objects=%d peak_nodes=%d"
		% [
			"unavailable_headless" if is_headless else "display",
			SAMPLE_FRAMES,
			_mean(optimized_metrics.frame), _percentile(optimized_metrics.frame, 0.95), _max(optimized_metrics.frame),
			_mean(optimized_metrics.script), _mean(optimized_metrics.render_cpu), _percentile(optimized_metrics.render_cpu, 0.95),
			_mean(optimized_metrics.render_gpu), _percentile(optimized_metrics.render_gpu, 0.95),
			_mean(optimized_metrics.draw_calls), _mean(optimized_metrics.primitives), peak_objects, peak_nodes,
		]
	)
	print(
		"WAVES PRESENTATION LEGACY_PYRE_MODEL render_capture=%s avg_frame_ms=%.3f p95_frame_ms=%.3f avg_render_cpu_ms=%.3f p95_render_cpu_ms=%.3f avg_render_gpu_ms=%.3f p95_render_gpu_ms=%.3f avg_draw_calls=%.1f avg_primitives=%.0f legacy_pyre_meshes=54 legacy_lights=18"
		% [
			"unavailable_headless" if is_headless else "display",
			_mean(legacy_metrics.frame), _percentile(legacy_metrics.frame, 0.95),
			_mean(legacy_metrics.render_cpu), _percentile(legacy_metrics.render_cpu, 0.95),
			_mean(legacy_metrics.render_gpu), _percentile(legacy_metrics.render_gpu, 0.95),
			_mean(legacy_metrics.draw_calls), _mean(legacy_metrics.primitives),
		]
	)
	if not is_headless:
		_check(
			_mean(optimized_metrics.draw_calls) <= _mean(legacy_metrics.draw_calls),
			"batched pyre geometry does not exceed the reconstructed legacy pyre draw-call count"
		)
		_check(_mean(legacy_metrics.render_gpu) > 0.0, "GPU render timing is available for the graphical comparison")
	else:
		print("WAVES PRESENTATION GPU/CPU render time and draw calls unavailable in headless mode")
	print(
		"WAVES PRESENTATION PERF wave=%d enemies=%d birds=%d telegraphs=%d old_bird_route_usec=%d cached_bird_route_usec=%d old_group_queries=600 cached_group_queries=0 old_group_result_arrays=600 cached_per_tick_arrays=0 cached_records=%d"
		% [PROFILE_WAVE, active, bird_count, peak_markers, old_route_usec, cached_route_usec, (waves.get("_bird_records") as Array).size()]
	)
	var first_marker_ids: Dictionary = {}
	for marker in waves.get("_spawn_marker_pool") as Array:
		first_marker_ids[(marker as Node3D).get_instance_id()] = true
	_check(first_marker_ids.size() == enemy_ids.size(), "completed spawn markers enter the bounded reuse pool")
	waves.set("_spawn_generation", 2)
	waves.set("_pending_spawns", enemy_ids.size())
	for index in enemy_ids.size():
		waves.call("_spawn_enemy_telegraphed", enemy_ids[index], index, enemy_ids.size(), 2)
	var reused_markers := 0
	for marker in waves.get("_spawn_markers") as Array:
		if first_marker_ids.has((marker as Node3D).get_instance_id()):
			reused_markers += 1
	_check(reused_markers == enemy_ids.size(), "a second maximum spawn batch reuses every prior marker node")
	_check(int(waves.get("_spawn_marker_create_count")) == enemy_ids.size(), "marker node allocation stops at one maximum batch")
	waves.call("_clear_spawn_markers")
	var pooled_marker := (waves.get("_spawn_marker_pool") as Array)[0] as Node3D
	pooled_marker.call("setup", Color.WHITE, 1.0, "ranged")
	var ranged_icon := (pooled_marker.get_node("RoleIcon") as MeshInstance3D).mesh
	pooled_marker.call("setup", Color.WHITE, 1.0, "control")
	var control_icon := (pooled_marker.get_node("RoleIcon") as MeshInstance3D).mesh
	_check(ranged_icon != control_icon, "pooled marker switches to the new role silhouette on reuse")
	pooled_marker.call("deactivate")
	print(
		"WAVES MARKER POOL created=%d reused=%d retained=%d"
		% [
			int(waves.get("_spawn_marker_create_count")),
			int(waves.get("_spawn_marker_reuse_count")),
			(waves.get("_spawn_marker_pool") as Array).size(),
		]
	)
	print("WAVES PRESENTATION PERF RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _percentile(values: PackedFloat32Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(float(sorted.size()) * fraction), 0, sorted.size() - 1)]


func _max(values: PackedFloat32Array) -> float:
	var maximum := 0.0
	for value in values:
		maximum = maxf(maximum, value)
	return maximum


func _sample_render_metrics(viewport_rid: RID) -> Dictionary:
	var samples := {
		"frame": PackedFloat32Array(),
		"script": PackedFloat32Array(),
		"render_cpu": PackedFloat32Array(),
		"render_gpu": PackedFloat32Array(),
		"draw_calls": PackedFloat32Array(),
		"primitives": PackedFloat32Array(),
	}
	var previous := Time.get_ticks_usec()
	for _frame in SAMPLE_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		(samples.frame as PackedFloat32Array).append(float(now - previous) / 1000.0)
		previous = now
		(samples.script as PackedFloat32Array).append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		(samples.render_cpu as PackedFloat32Array).append(
			RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
		)
		(samples.render_gpu as PackedFloat32Array).append(
			RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		)
		(samples.draw_calls as PackedFloat32Array).append(
			float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		)
		(samples.primitives as PackedFloat32Array).append(
			float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		)
	return samples


func _enable_legacy_pyre_fixture(waves: Node3D) -> Dictionary:
	var geometry := waves.get_node("WavesTorchlight/PyreGeometry") as Node3D
	var legacy_geometry := Node3D.new()
	legacy_geometry.name = "LegacyPyreMeshes"
	geometry.add_child(legacy_geometry)
	var sources: Array[MultiMeshInstance3D] = []
	var mesh_count := 0
	for child in geometry.get_children():
		var batch := child as MultiMeshInstance3D
		if batch == null or batch.multimesh == null:
			continue
		sources.append(batch)
		batch.visible = false
		for instance_index in batch.multimesh.instance_count:
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.mesh = batch.multimesh.mesh
			mesh_instance.material_override = batch.material_override
			mesh_instance.transform = batch.multimesh.get_instance_transform(instance_index)
			legacy_geometry.add_child(mesh_instance)
			mesh_count += 1
	var torchlight := waves.get_node("WavesTorchlight") as Node3D
	var flames: Array = torchlight.get("_pyre_flames")
	var legacy_lights: Array[OmniLight3D] = []
	for index in range(10, flames.size()):
		var flame := flames[index] as Node3D
		if flame == null:
			continue
		var light := OmniLight3D.new()
		light.name = "LegacyFarPyreLight"
		light.light_color = Color(1.0, 0.62, 0.28)
		light.light_energy = 2.1
		light.omni_range = 54.4
		light.shadow_enabled = false
		light.position = Vector3(0.0, 0.6, 0.0)
		flame.add_child(light)
		legacy_lights.append(light)
	_check(mesh_count == 54, "legacy renderer fixture reconstructs all 54 individual pyre meshes")
	_check(legacy_lights.size() == 8, "legacy renderer fixture restores eight far pyre lights")
	return {"root": legacy_geometry, "sources": sources, "lights": legacy_lights}


func _restore_optimized_pyre_fixture(_waves: Node3D, fixture: Dictionary) -> void:
	for source in fixture.get("sources", []) as Array:
		if is_instance_valid(source):
			(source as MultiMeshInstance3D).visible = true
	var legacy_root := fixture.get("root") as Node3D
	if legacy_root and is_instance_valid(legacy_root):
		legacy_root.queue_free()
	for light in fixture.get("lights", []) as Array:
		if is_instance_valid(light):
			(light as OmniLight3D).queue_free()


func _benchmark_old_bird_route(waves: Node, iterations: int) -> int:
	var elapsed := 0
	var bird_time := float(waves.get("_bird_time"))
	for _iteration in iterations:
		var started := Time.get_ticks_usec()
		for candidate in get_tree().get_nodes_in_group("waves_bird"):
			if not candidate is Node3D:
				continue
			var bird := candidate as Node3D
			var radius := float(bird.get_meta("orbit_radius", 6.0))
			var speed := float(bird.get_meta("orbit_speed", 0.5))
			var phase := float(bird.get_meta("orbit_phase", 0.0))
			var wing_phase := float(bird.get_meta("wing_phase", 0.0))
			var home_x := float(bird.get_meta("home_x", 0.0))
			var home_y := float(bird.get_meta("home_y", 10.0))
			var home_z := float(bird.get_meta("home_z", 0.0))
			var angle := bird_time * speed + phase
			bird.position = Vector3(
				home_x + cos(angle) * radius,
				home_y + sin(bird_time * 1.6 + phase) * 0.35,
				home_z + sin(angle) * radius
			)
			bird.rotation.y = angle + PI * 0.5
			var wing_l := bird.get_node_or_null("WingL") as Node3D
			var wing_r := bird.get_node_or_null("WingR") as Node3D
			var flap := sin(bird_time * 8.0 + wing_phase) * 0.35
			if wing_l:
				wing_l.rotation.z = flap
			if wing_r:
				wing_r.rotation.z = -flap
		elapsed += Time.get_ticks_usec() - started
	return elapsed


func _benchmark_cached_bird_route(waves: Node, iterations: int) -> int:
	var elapsed := 0
	for _iteration in iterations:
		var started := Time.get_ticks_usec()
		waves.call("_animate_birds")
		elapsed += Time.get_ticks_usec() - started
	return elapsed
