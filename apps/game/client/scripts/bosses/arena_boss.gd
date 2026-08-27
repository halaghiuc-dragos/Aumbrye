extends CastleEnemyBase


## Shared behaviour for a boss that owns an arena: it remembers where its arena is, stays inside it,
## announces its own defeat, and restores to a full-health first phase when a save is reloaded with
## it still alive. Castle Knight, Crystal Sovereign and Swamp Hydra each carried their own copy.
signal boss_defeated

var _arena_center := Vector3.ZERO


func _ready() -> void:
	super._ready()
	_arena_center = global_position


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _state != State.DEAD:
		_clamp_to_arena()


func _clamp_to_arena() -> void:
	clamp_to_arena(_arena_center)


func _on_died() -> void:
	super._on_died()
	boss_defeated.emit()


func apply_state(state: Dictionary) -> void:
	if not state.get("alive", true):
		super.apply_state(state)
		return
	_on_arena_reset()
	if is_dead():
		respawn_at_rest()
		return
	if _health:
		_health.reset_health()
	restart_phases()
	_state = State.PATROL


## Hook for a boss that keeps arena state of its own beyond health and phase.
func _on_arena_reset() -> void:
	pass
