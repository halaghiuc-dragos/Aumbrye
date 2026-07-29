extends Node

const POISE_STAGGER_DURATION := 0.85

signal stagger_started
signal stagger_ended
signal player_died

var is_staggered := false
var is_dead := false

var _body: CharacterBody3D
var _mesh: MeshInstance3D
var _health: Health
var _poise: Poise
var _guard: Node
var _stagger_timer := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_mesh = _body.get_node_or_null("Facing/MeshInstance3D") as MeshInstance3D
	_health = _body.get_node_or_null("Health") as Health
	_poise = _body.get_node_or_null("Poise") as Poise
	_guard = _body.get_node_or_null("Guard")
	if _health:
		_health.died.connect(_on_died)
	if _poise:
		_poise.poise_broken.connect(_on_poise_broken)
	if _guard and _guard.has_signal("parry_success"):
		_guard.parry_success.connect(_on_parry_success)
	if _guard and _guard.has_signal("guard_broken"):
		_guard.guard_broken.connect(_on_guard_broken)


func _physics_process(delta: float) -> void:
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			is_staggered = false
			stagger_ended.emit()


func can_act() -> bool:
	return not is_dead and not is_staggered


func is_movement_locked() -> bool:
	if is_dead or is_staggered:
		return true
	if _guard and _guard.has_method("locks_movement"):
		return _guard.call("locks_movement")
	return false


func reset_combat_state() -> void:
	is_dead = false
	is_staggered = false
	_stagger_timer = 0.0
	if _mesh:
		_mesh.scale = Vector3.ONE


func _apply_stagger(duration: float) -> void:
	is_staggered = true
	_stagger_timer = duration
	stagger_started.emit()
	_pulse_mesh()


func _on_poise_broken() -> void:
	_apply_stagger(POISE_STAGGER_DURATION)


func _on_guard_broken() -> void:
	_pulse_mesh()


func _on_parry_success(_target: Node) -> void:
	_pulse_mesh(1.14)


func _on_died() -> void:
	is_dead = true
	player_died.emit()
	if _mesh:
		var tween := create_tween()
		tween.tween_property(_mesh, "scale", Vector3(0.25, 0.08, 0.25), 0.35)


func _pulse_mesh(scale_peak: float = 1.1) -> void:
	if not _mesh:
		return
	var tween := create_tween()
	_mesh.scale = Vector3(scale_peak, scale_peak, scale_peak)
	tween.tween_property(_mesh, "scale", Vector3.ONE, 0.12)
