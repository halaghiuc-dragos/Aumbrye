extends Node

var _failures := 0


func _ready() -> void:
	var arena_scene := load("res://scenes/combat/combat_arena.tscn") as PackedScene
	var arena := arena_scene.instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().process_frame
	var player := arena.get_node("Player") as CharacterBody3D
	var dummy := arena.get_node("TrainingDummies/TrainingGruntA") as Node3D
	var practice_hurtbox := player.get_node("Hurtbox") as Hurtbox
	var description := arena.get_node("PracticeObjectives/Panel/Content/Description") as Label
	_check(description != null, "arena builds the player-facing practice panel")
	arena.call("_start_practice", "parry")
	_check(practice_hurtbox.practice_invulnerable, "practice suppresses incoming damage")
	var blocked := practice_hurtbox.receive_hit(DamageInfo.create(20.0, 10.0, dummy))
	_check(blocked.outgoing == 0.0 and blocked.poise_outgoing == 0.0, "practice protection covers health and poise")
	arena.call("_on_practice_parry", dummy)
	_check(description.text == tr("PRACTICE_PARRY_DONE"), "successful parry advances the exercise")
	var parry_listener_count := guard_listener_count(player)
	arena.call("_retry_practice")
	_check(practice_hurtbox.practice_invulnerable, "retry restarts the selected exercise safely")
	_check(guard_listener_count(player) == parry_listener_count, "retry does not duplicate parry listeners")
	var guard := player.get_node("Guard") as Guard
	arena.call("_start_practice", "dodge")
	_check(not guard.parry_success.is_connected(Callable(arena, "_on_practice_parry")), "switching exercises removes stale listeners")
	arena.call("_on_training_attack_resolved", DamageResolution.new())
	_check(description.text != tr("PRACTICE_DODGE_DONE"), "a non-dodge result does not complete dodge practice")
	var dodged := DamageResolution.new()
	dodged.dodged = true
	arena.call("_on_training_attack_resolved", dodged)
	_check(description.text == tr("PRACTICE_DODGE_DONE"), "an actually avoided strike completes dodge practice")
	arena.call("_retry_practice")
	_check(dummy.attack_telegraph_started.get_connections().size() == 1, "retry does not duplicate telegraph listeners")
	arena.call("_start_practice", "poise_break")
	var dummy_poise := dummy.get_node("Poise") as Poise
	dummy_poise.take_poise_damage(dummy_poise.max_poise)
	_check(description.text == tr("PRACTICE_POISE_BREAK_DONE"), "dummy poise-break signal completes its exercise")
	arena.call("_start_practice", "recovery")
	var stamina := player.get_node("Stamina") as Stamina
	stamina.restore(Stamina.EXHAUSTION_RECOVERY)
	_check(description.text == tr("PRACTICE_RECOVERY_DONE"), "stamina recovery signal completes its exercise")
	arena.call("_start_practice", "guard_break")
	guard.is_guard_active = true
	var unblockable := DamageInfo.create(20.0, 10.0, dummy)
	unblockable.attack_class = "unblockable"
	guard.modify_incoming_hit(unblockable)
	_check(description.text == tr("PRACTICE_GUARD_BREAK_DONE"), "real unblockable guard-break event completes its exercise")
	_check(practice_hurtbox.practice_invulnerable, "guard-break exercise remains protected")
	practice_hurtbox.practice_invulnerable = false
	practice_hurtbox.team = "player"
	print("PRACTICE OBJECTIVES RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func guard_listener_count(player: CharacterBody3D) -> int:
	var guard := player.get_node("Guard") as Guard
	return guard.parry_success.get_connections().size()
