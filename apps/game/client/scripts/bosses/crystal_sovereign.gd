extends CastleEnemyBase

## Crystal Sovereign boss shell — arena containment and presentation. Phases, move sets
## and the pillar mechanic live in `content/bosses/boss_crystal_sovereign.json`.

signal boss_defeated
var _arena_center := Vector3.ZERO


func _resolve_enemy_id() -> String:
	return "crystal_sovereign"


func get_hp_bar_height() -> float:
	return 3.0


func get_lock_aim_point() -> Vector3:
	return global_position + Vector3(0.0, 2.2, 0.0)


func _ready() -> void:
	super._ready()
	_arena_center = global_position
	_apply_mesh_tint(Color(0.5, 0.75, 1.0, 1.0))
	scale = Vector3(1.3, 1.3, 1.3)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _state != State.DEAD:
		_clamp_to_arena()



func _on_died() -> void:
	super._on_died()
	boss_defeated.emit()


## Re-entering the arena restarts the fight from phase one rather than resuming a
## partially worn-down boss.
func apply_state(state: Dictionary) -> void:
	if not state.get("alive", true):
		super.apply_state(state)
		return
	if is_dead():
		respawn_at_rest()
		return
	if _health:
		_health.reset_health()
	restart_phases()
	_state = State.PATROL


func _clamp_to_arena() -> void:
	# C-81: bounds come from the boss definition now — see `CastleEnemyBase.clamp_to_arena`.
	clamp_to_arena(_arena_center)
