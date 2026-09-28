extends "res://scripts/bosses/arena_boss.gd"


## The knight's central rule is not extra damage: his largest commitments expose the cracked
## guard-side seam during recovery. Players create a punish by respecting spacing, then taking the
## short opening instead of treating every phase as the same generic bruiser.
const COMMITTED_STANCE_WINDOWS := {
	"cleave": 0.72,
	"sig_two_stage_overhead": 0.95,
	"sig_two_stage_overhead_b": 0.8,
	"charge": 0.72,
	"triple_three": 0.88,
}
const STANCE_VULNERABILITY := {
	"region": "broken_guard",
	"regionDamageMult": 2.0,
	"bodyDamageMult": 0.5,
	"radius": 0.42,
	"offset": [0.58, 1.48, 0.2],
}

var _stance_window := 0.0


func _resolve_enemy_id() -> String:
	return "castle_knight"


func get_hp_bar_height() -> float:
	return 2.8


func get_lock_aim_point() -> Vector3:
	return global_position + Vector3(0.0, 1.9, 0.0)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _stance_window <= 0.0:
		return
	if is_dead() or is_staggered():
		_stance_window = 0.0
		restore_phase_vulnerability()
		return
	_stance_window -= delta
	if _stance_window <= 0.0:
		restore_phase_vulnerability()


func _end_attack() -> void:
	var attack_id := str(_current_attack_data.get("id", ""))
	super._end_attack()
	# Combo links immediately enter their next windup. Only the final recovery is an honest stance
	# commitment; exposing a weak point between a linked pair would advertise a punish that cannot
	# actually be taken.
	if _state != State.RECOVERY:
		return
	var duration := float(COMMITTED_STANCE_WINDOWS.get(attack_id, 0.0))
	if duration <= 0.0:
		return
	_stance_window = duration
	apply_temporary_vulnerability(STANCE_VULNERABILITY)


func _on_arena_reset() -> void:
	_stance_window = 0.0
	restore_phase_vulnerability()
