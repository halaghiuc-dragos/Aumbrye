extends Control

@export var player_path: NodePath
@export var lock_on_path: NodePath

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _lock_reticle: Control
var _player: Node3D
var _lock_on: Node


func _ready() -> void:
	_health_bar = $Margin/VBox/HealthBar
	_stamina_bar = $Margin/VBox/StaminaBar
	_lock_reticle = $LockReticle
	if player_path:
		_player = get_node(player_path) as Node3D
		_bind_player_resources()
	if lock_on_path:
		_lock_on = get_node(lock_on_path)
		if _lock_on.has_signal("lock_changed"):
			_lock_on.lock_changed.connect(_on_lock_changed)


func _bind_player_resources() -> void:
	var health := _player.get_node_or_null("Health") as Health
	var stamina := _player.get_node_or_null("Stamina") as Stamina
	if health:
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.current, Health.MAX_HEALTH)
	if stamina:
		stamina.stamina_changed.connect(_on_stamina_changed)
		_on_stamina_changed(stamina.current, Stamina.MAX_STAMINA)


func _on_health_changed(current: float, max_value: float) -> void:
	_health_bar.max_value = max_value
	_health_bar.value = current


func _on_stamina_changed(current: float, max_value: float) -> void:
	_stamina_bar.max_value = max_value
	_stamina_bar.value = current


func _on_lock_changed(_target: Node3D, locked: bool) -> void:
	_lock_reticle.visible = locked
