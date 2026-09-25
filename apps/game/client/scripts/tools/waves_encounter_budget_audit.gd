extends Node

const SEEDS := 64

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Waves encounter budget audit: %s" % message)


func _role(enemy_id: String) -> String:
	var definition := EnemyCatalog.get_definition(enemy_id)
	var kind := str(definition.get("enemy_type", "melee"))
	if kind == "ranged":
		return "ranged"
	if kind == "shield":
		return "control"
	return "melee"


func _long_reach(enemy: Dictionary) -> bool:
	var reach := maxf(float(enemy.get("attack_range", 0.0)), float(enemy.get("preferred_range", 0.0)))
	for attack in enemy.get("attacks", []):
		if attack is Dictionary:
			reach = maxf(reach, float(attack.get("max_range", 0.0)))
	return reach >= 8.0


func _ready() -> void:
	var service := WavesRunService
	service._ensure_definition()
	var original_seed := int(service.get("_run_seed"))
	var definition: Dictionary = service.get("_definition")
	var budget: Dictionary = definition.get("encounter_budget", {})
	var checked := 0
	for seed_index in SEEDS:
		service.set("_run_seed", seed_index + 1)
		for wave in 50:
			var enemies: Array[String] = service.get_enemies_for_wave(wave + 1)
			var has_boss_wave := service.is_boss_wave(wave + 1)
			var ordinary_count := enemies.size() - (1 if has_boss_wave else 0)
			_check(
				enemies.size() == service._enemy_count_for_wave(wave + 1) + (1 if has_boss_wave else 0),
				"seed %d wave %d preserves the authored spawn count" % [seed_index + 1, wave + 1]
			)
			var role_counts := {"melee": 0, "ranged": 0, "control": 0}
			var fast_count := 0
			var long_reach_count := 0
			var threat_total := 0.0
			var bosses := 0
			for index in enemies.size():
				var enemy_id := enemies[index]
				var enemy := EnemyCatalog.get_definition(enemy_id)
				_check(not enemy.is_empty(), "seed %d wave %d emits known enemy %s" % [seed_index + 1, wave + 1, enemy_id])
				if str(enemy.get("enemy_type", "")) == "boss":
					bosses += 1
					_check(index == enemies.size() - 1, "boss escort is a separate final entry")
					continue
				var role := _role(enemy_id)
				role_counts[role] = int(role_counts[role]) + 1
				if float(enemy.get("move_speed", 0.0)) >= 5.0:
					fast_count += 1
				if _long_reach(enemy):
					long_reach_count += 1
				threat_total += float(enemy.get("threat_cost", 0.0))
			_check(bosses == (1 if has_boss_wave else 0), "boss waves append exactly one eligible warden")
			_check(role_counts.melee >= int(budget.get("min_melee_count", 1)), "seed %d wave %d retains melee pressure (roles=%s enemies=%s)" % [seed_index + 1, wave + 1, role_counts, enemies])
			_check(role_counts.ranged <= ceili(float(budget.get("max_ranged_ratio", 0.35)) * ordinary_count), "seed %d wave %d respects ranged concurrency" % [seed_index + 1, wave + 1])
			_check(role_counts.control <= ceili(float(budget.get("max_control_ratio", 0.25)) * ordinary_count), "seed %d wave %d respects control concurrency" % [seed_index + 1, wave + 1])
			_check(fast_count <= ceili(float(budget.get("max_fast_ratio", 0.35)) * ordinary_count), "seed %d wave %d respects fast-attacker concurrency" % [seed_index + 1, wave + 1])
			_check(long_reach_count <= ceili(float(budget.get("max_long_reach_ratio", 0.35)) * ordinary_count), "seed %d wave %d respects long-reach concurrency" % [seed_index + 1, wave + 1])
			_check(threat_total <= float(budget.get("max_average_threat_cost", 35.0)) * ordinary_count, "seed %d wave %d respects encounter threat budget (total=%.1f limit=%.1f enemies=%s)" % [seed_index + 1, wave + 1, threat_total, float(budget.get("max_average_threat_cost", 35.0)) * ordinary_count, enemies])
			var intros := service._newly_unlocked_enemy_ids(wave + 1, service._ordinary_enemy_candidates(service._roster_for_wave(wave + 1)))
			for intro_id in intros:
				_check(intro_id in enemies, "seed %d wave %d introduces newly unlocked %s" % [seed_index + 1, wave + 1, intro_id])
			checked += 1
	service.set("_run_seed", original_seed)
	print("WAVES ENCOUNTER BUDGET RESULT %d failures across %d seed/wave combinations" % [_failures, checked])
	get_tree().quit(0 if _failures == 0 else 1)
