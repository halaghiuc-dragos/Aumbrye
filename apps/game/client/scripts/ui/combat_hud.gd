extends Control

@export var player_path: NodePath
@export var lock_on_path: NodePath

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _lock_reticle: Control
var _parry_bar: ProgressBar
var _block_bar: ProgressBar
var _parry_label: Label
var _player: Node3D
var _lock_on: Node
var _guard: Node
var _camera: Camera3D


func _ready() -> void:
	_health_bar = $Margin/VBox/HealthBar
	_stamina_bar = $Margin/VBox/StaminaBar
	_lock_reticle = $LockReticle
	_parry_bar = $GuardIndicators/ParryBar
	_block_bar = $GuardIndicators/BlockBar
	_parry_label = $GuardIndicators/ParryLabel
	if player_path:
		_player = get_node(player_path) as Node3D
		_guard = _player.get_node_or_null("Guard")
		_bind_player_resources()
	if lock_on_path:
		_lock_on = get_node(lock_on_path)
		if _lock_on.has_signal("lock_changed"):
			_lock_on.lock_changed.connect(_on_lock_changed)


func _process(_delta: float) -> void:
	_update_lock_reticle()
	_update_guard_indicators()


func _bind_player_resources() -> void:
	var health := _player.get_node_or_null("Health") as Health
	var stamina := _player.get_node_or_null("Stamina") as Stamina
	if health:
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.current, Health.MAX_HEALTH)
	if stamina:
		stamina.stamina_changed.connect(_on_stamina_changed)
		_on_stamina_changed(stamina.current, Stamina.MAX_STAMINA)


func _update_lock_reticle() -> void:
	if not _lock_reticle or not _lock_on or not _lock_on.get("is_locked"):
		if _lock_reticle:
			_lock_reticle.visible = false
		return
	var target := _lock_on.get("current_target") as Node3D
	if target == null or not is_instance_valid(target):
		_lock_reticle.visible = false
		return
	var camera := _get_camera()
	if camera == null:
		return
	var aim_point := target.global_position + Vector3(0.0, 1.5, 0.0)
	if camera.is_position_behind(aim_point):
		_lock_reticle.visible = false
		return
	var screen_pos := camera.unproject_position(aim_point)
	_lock_reticle.visible = true
	_lock_reticle.position = screen_pos - _lock_reticle.size * 0.5


func _update_guard_indicators() -> void:
	if not _guard:
		_parry_bar.visible = false
		_block_bar.visible = false
		_parry_label.visible = false
		return
	var parry_left := 0.0
	var block_left := 0.0
	if _guard.has_method("get_parry_time_remaining"):
		parry_left = _guard.call("get_parry_time_remaining")
	if _guard.has_method("get_block_time_remaining"):
		block_left = _guard.call("get_block_time_remaining")
	if parry_left > 0.0:
		_parry_bar.visible = true
		_parry_bar.max_value = 0.18
		_parry_bar.value = parry_left
		_parry_label.visible = true
		_parry_label.text = "PARRY"
	else:
		_parry_bar.visible = false
		_parry_label.visible = false
	if block_left > 0.0:
		_block_bar.visible = true
		_block_bar.max_value = 0.65
		_block_bar.value = block_left
	else:
		_block_bar.visible = false


func _get_camera() -> Camera3D:
	if _camera and is_instance_valid(_camera):
		return _camera
	_camera = get_viewport().get_camera_3d()
	return _camera


func _on_health_changed(current: float, max_value: float) -> void:
	_health_bar.max_value = max_value
	_health_bar.value = current


func _on_stamina_changed(current: float, max_value: float) -> void:
	_stamina_bar.max_value = max_value
	_stamina_bar.value = current


func _on_lock_changed(_target: Node3D, locked: bool) -> void:
	if not locked:
		_lock_reticle.visible = false
