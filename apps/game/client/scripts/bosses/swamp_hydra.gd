extends "res://scripts/bosses/arena_boss.gd"


const CLEANSE_SCENE := preload("res://scenes/bosses/swamp_cleanse_zone.tscn")
const CLEANSE_INTERVAL := 8.0

var _cleanse_zones: Array[Node3D] = []
var _cleanse_cooldown := 0.0
var _cleanse_active := false


func _resolve_enemy_id() -> String:
	return "swamp_hydra"


func get_hp_bar_height() -> float:
	return 3.0


func get_lock_aim_point() -> Vector3:
	return global_position + Vector3(0.0, 2.4, 0.0)


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.25, 0.4, 0.15, 1.0))
	scale = Vector3(1.35, 1.1, 1.35)
	if not boss_phase_entered.is_connected(_on_boss_phase_entered):
		boss_phase_entered.connect(_on_boss_phase_entered)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _state == State.DEAD:
		return
	if not _cleanse_active:
		return
	_cleanse_cooldown -= delta
	if _cleanse_cooldown <= 0.0:
		_cleanse_cooldown = CLEANSE_INTERVAL
		_spawn_cleanse_window()


func _on_boss_phase_entered(_index: int, phase: Dictionary) -> void:
	var wants_cleanse := bool(phase.get("cleanseWindows", false))
	if wants_cleanse and not _cleanse_active:
		_cleanse_cooldown = 2.0
		_spawn_cleanse_window()
	_cleanse_active = wants_cleanse


func _spawn_cleanse_window() -> void:
	var zone := CLEANSE_SCENE.instantiate() as Node3D
	if zone == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	var offset := Vector3(
		_enemy_rng.randf_range(-5.0, 5.0), 0.02, _enemy_rng.randf_range(-5.0, 5.0)
	)
	zone.position = _local_spawn_point(parent, _arena_center + offset)
	parent.add_child(zone)
	_cleanse_zones.append(zone)


func _on_died() -> void:
	super._on_died()
	_cleanse_active = false
	for zone in _cleanse_zones:
		if is_instance_valid(zone):
			zone.queue_free()
	_cleanse_zones.clear()


func _on_arena_reset() -> void:
	_cleanse_active = false
