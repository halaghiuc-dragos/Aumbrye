extends Node

## Exercises actual roster actors in the arena scene and measures live telegraph, attack, recovery,
## and no-telegraph windows. This supplements the deterministic roster quota audit with behavior.

const WAVES_SCENE := preload("res://scenes/dungeon/waves_run.tscn")
const EnemyState := preload("res://scripts/enemies/castle_enemy_base.gd").State
const SCENARIOS := [15, 45, 50]
const SAMPLE_PHYSICS_FRAMES := 900
const SCENARIO_SEEDS := 4
const MIN_ACTIONABLE_GAP_SECONDS := 0.2

var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var waves := WAVES_SCENE.instantiate() as Node3D
	get_tree().root.add_child(waves)
	get_tree().current_scene = waves
	for _frame in 120:
		await get_tree().physics_frame
	var player := waves.get_node_or_null("Player") as Node3D
	_check(player != null, "arena test harness contains the production player")
	if player == null:
		get_tree().quit(1)
		return
	var player_health := player.get_node_or_null("Health") as Health
	if player_health:
		player_health.max_health = 1000000.0
		player_health.current = player_health.max_health
	var original_wave := WavesRunService.current_wave
	var original_seed := int(WavesRunService.get("_run_seed"))
	for wave in SCENARIOS:
		var worst_gap := SAMPLE_PHYSICS_FRAMES
		var worst_punish := SAMPLE_PHYSICS_FRAMES
		for seed_index in SCENARIO_SEEDS:
			var metrics := await _run_scenario(waves, player, int(wave), 74000 + int(wave) * 97 + seed_index * 7919)
			worst_gap = mini(worst_gap, int(metrics.get("longest_clear_window", 0)))
			worst_punish = mini(worst_punish, int(metrics.get("longest_punish_window", 0)))
		_check(worst_gap >= ceili(MIN_ACTIONABLE_GAP_SECONDS * Engine.physics_ticks_per_second), "wave %d retains >= %.2fs actionable no-telegraph gap in all %d seeds (worst %.2fs)" % [int(wave), MIN_ACTIONABLE_GAP_SECONDS, SCENARIO_SEEDS, float(worst_gap) / Engine.physics_ticks_per_second])
		_check(worst_punish >= ceili(MIN_ACTIONABLE_GAP_SECONDS * Engine.physics_ticks_per_second), "wave %d retains >= %.2fs recovery-only punish window in all %d seeds (worst %.2fs)" % [int(wave), MIN_ACTIONABLE_GAP_SECONDS, SCENARIO_SEEDS, float(worst_punish) / Engine.physics_ticks_per_second])
	WavesRunService.current_wave = original_wave
	WavesRunService.set("_run_seed", original_seed)
	waves.queue_free()
	print("WAVES RUNTIME PRESSURE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _run_scenario(waves: Node3D, player: Node3D, wave: int, run_seed: int) -> Dictionary:
	waves.call("_clear_enemies")
	for _frame in 2:
		await get_tree().physics_frame
	EnemyBlackboard._rooms.clear()
	AttackTokenService.reset_all()
	WavesRunService.current_wave = wave
	WavesRunService.set("_run_seed", run_seed)
	waves.set("_lobby_active", false)
	waves.set("_wave_completion_committed", true)
	waves.set("_pending_spawns", 0)
	waves.call("_set_fuel_objective_for_wave", wave)
	var roster: Array[String] = WavesRunService.get_enemies_for_wave(wave)
	_check(not roster.is_empty(), "wave %d resolves its production roster" % wave)
	var telemetry := {"telegraphs": 0, "attacks": 0}
	for index in roster.size():
		var angle := TAU * float(index) / float(maxi(1, roster.size()))
		var radius := 10.0 + float(index % 3) * 0.5
		var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		waves.call("_spawn_enemy", roster[index], point)
	var enemies: Array = waves.get("_active_enemies")
	var encounter_key := int(player.get_instance_id())
	for enemy_value in enemies:
		if not is_instance_valid(enemy_value):
			continue
		var enemy := enemy_value as Node
		if enemy == null or not enemy.is_inside_tree():
			continue
		if enemy.has_method("set_player"):
			enemy.call("set_player", player)
		enemy.set_meta("encounter_key", encounter_key)
		if enemy.has_signal("attack_telegraph_started"):
			enemy.attack_telegraph_started.connect(
				func(_attack_class: String) -> void:
					telemetry["telegraphs"] = int(telemetry["telegraphs"]) + 1
			)
		if enemy.has_signal("attack_active"):
			enemy.attack_active.connect(
				func() -> void:
					telemetry["attacks"] = int(telemetry["attacks"]) + 1
			)
	for enemy_value in enemies:
		if not is_instance_valid(enemy_value):
			continue
		var enemy := enemy_value as Node
		if enemy == null or not enemy.is_inside_tree():
			continue
		if enemy.has_method("_join_room_board"):
			enemy.call("_join_room_board")
			if enemy.has_method("_latch_aggro"):
				enemy.call("_latch_aggro")

	var active_enemy_count := enemies.size()
	var boss_count := 0
	for enemy_id in roster:
		if str(EnemyCatalog.get_definition(enemy_id).get("enemy_type", "")) == "boss":
			boss_count += 1
	_check(boss_count == (1 if WavesRunService.is_boss_wave(wave) else 0), "wave %d keeps its boss separate from ordinary pressure" % wave)

	var active_actor_frames := 0
	var recovery_actor_frames := 0
	var recovery_token_violations := 0
	var punish_window_frames := 0
	var pressure_frames := 0
	var max_windups := 0
	var max_active := 0
	var longest_clear_window := 0
	var current_clear_window := 0
	var longest_punish_window := 0
	var current_punish_window := 0
	for _frame in SAMPLE_PHYSICS_FRAMES:
		await get_tree().physics_frame
		var engaged := 0
		var windups := 0
		var active := 0
		var recoveries := 0
		for enemy_value in enemies:
			if not is_instance_valid(enemy_value):
				continue
			var enemy := enemy_value as Node
			if enemy == null or not enemy.is_inside_tree() or bool(enemy.call("is_dead")):
				continue
			var state := int(enemy.get("_state"))
			if not bool(enemy.get("_aggro_locked")):
				continue
			engaged += 1
			if state == EnemyState.WINDUP:
				windups += 1
			elif state == EnemyState.ATTACK:
				active += 1
			elif state == EnemyState.RECOVERY:
				recoveries += 1
				var enemy_data: Dictionary = enemy.get("_data") as Dictionary
				if str(enemy_data.get("enemy_type", "")) != "swarm" and not bool(enemy.get("_attack_token_held")):
					recovery_token_violations += 1
		active_actor_frames += active
		recovery_actor_frames += recoveries
		if engaged > 0:
			pressure_frames += 1
			if windups + active > 0:
				current_clear_window = 0
				current_punish_window = 0
			else:
				current_clear_window += 1
				longest_clear_window = maxi(longest_clear_window, current_clear_window)
			if recoveries > 0 and windups + active == 0:
				punish_window_frames += 1
				current_punish_window += 1
				longest_punish_window = maxi(longest_punish_window, current_punish_window)
			else:
				current_punish_window = 0
		max_windups = maxi(max_windups, windups)
		max_active = maxi(max_active, active)
	var measured_seconds := float(SAMPLE_PHYSICS_FRAMES) / Engine.physics_ticks_per_second
	var clear_window_seconds := float(longest_clear_window) / Engine.physics_ticks_per_second
	var punish_seconds := float(punish_window_frames) / Engine.physics_ticks_per_second
	print(
		"WAVES RUNTIME PRESSURE wave=%d seed=%d enemies=%d bosses=%d telegraphs=%d attacks=%d sample_s=%.1f engaged_actor_frames=%d active_actor_frames=%d recovery_actor_frames=%d recovery_token_violations=%d punish_window_s=%.2f no_telegraph_window_s=%.2f max_concurrent_windups=%d max_concurrent_active=%d"
		% [wave, run_seed, active_enemy_count, boss_count, telemetry.telegraphs, telemetry.attacks, measured_seconds, pressure_frames, active_actor_frames, recovery_actor_frames, recovery_token_violations, punish_seconds, clear_window_seconds, max_windups, max_active]
	)
	_check(telemetry.telegraphs > 0 and telemetry.attacks > 0, "wave %d produces live enemy telegraph and attack events" % wave)
	_check(pressure_frames > 0, "wave %d contains engaged runtime actors" % wave)
	_check(recovery_actor_frames > 0 and punish_window_frames > 0, "wave %d presents actual recovery/punish windows" % wave)
	_check(recovery_token_violations == 0, "wave %d retains each ordinary attack permit through recovery" % wave)
	return {"longest_clear_window": longest_clear_window, "longest_punish_window": longest_punish_window}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
