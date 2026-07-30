extends Control

@export var player_path: NodePath
@export var lock_on_path: NodePath

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _xp_bar: ProgressBar
var _level_label: Label
var _lock_reticle: Control
var _parry_bar: ProgressBar
var _block_bar: ProgressBar
var _parry_label: Label
var _player: Node3D
var _lock_on: Node
var _guard: Node
var _camera: Camera3D
var _status_row: HBoxContainer
var _status_controller: StatusController


func _ready() -> void:
	_health_bar = get_node_or_null("Margin/VBox/HealthBar") as ProgressBar
	_stamina_bar = get_node_or_null("Margin/VBox/StaminaBar") as ProgressBar
	_xp_bar = get_node_or_null("Margin/VBox/XpBar") as ProgressBar
	_level_label = get_node_or_null("Margin/VBox/LevelLabel") as Label
	_ensure_progression_widgets()
	_lock_reticle = get_node_or_null("LockReticle") as Control
	_parry_bar = get_node_or_null("GuardIndicators/ParryBar") as ProgressBar
	_block_bar = get_node_or_null("GuardIndicators/BlockBar") as ProgressBar
	_parry_label = get_node_or_null("GuardIndicators/ParryLabel") as Label
	if player_path:
		_player = get_node(player_path) as Node3D
		_guard = _player.get_node_or_null("Guard")
		_status_controller = _player.get_node_or_null("StatusController") as StatusController
		_bind_player_resources()
		_ensure_status_row()
		if _status_controller:
			_status_controller.statuses_changed.connect(_refresh_status_icons)
	if lock_on_path:
		_lock_on = get_node(lock_on_path)
		if _lock_on.has_signal("lock_changed"):
			_lock_on.lock_changed.connect(_on_lock_changed)
	if ProgressionService:
		ProgressionService.progression_changed.connect(_on_progression_changed)
		_on_progression_changed()


func _ensure_status_row() -> void:
	_status_row = get_node_or_null("StatusRow") as HBoxContainer
	if _status_row == null:
		_status_row = HBoxContainer.new()
		_status_row.name = "StatusRow"
		_status_row.position = Vector2(24, 120)
		add_child(_status_row)
	_refresh_status_icons()


func _refresh_status_icons() -> void:
	if _status_row == null:
		return
	for child in _status_row.get_children():
		child.queue_free()
	if _status_controller == null:
		return
	for entry in _status_controller.get_active_statuses():
		var def := StatusCatalog.get_definition(entry.get("id", ""))
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(22, 22)
		icon.color = Color.from_string(def.get("iconColor", "#ffffff"), Color.WHITE)
		icon.tooltip_text = "%s x%d" % [def.get("name", entry.get("id", "")), entry.get("stacks", 1)]
		_status_row.add_child(icon)


func _ensure_progression_widgets() -> void:
	var vbox := get_node_or_null("Margin/VBox") as VBoxContainer
	if vbox == null:
		return
	if _xp_bar == null:
		_xp_bar = ProgressBar.new()
		_xp_bar.name = "XpBar"
		_xp_bar.custom_minimum_size = Vector2(280, 12)
		_xp_bar.show_percentage = false
		vbox.add_child(_xp_bar)
	if _level_label == null:
		_level_label = Label.new()
		_level_label.name = "LevelLabel"
		vbox.add_child(_level_label)


func _process(_delta: float) -> void:
	_update_lock_reticle()
	_update_guard_indicators()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8 and _status_controller:
			_status_controller.debug_apply("burn")
			_refresh_status_icons()
			get_viewport().set_input_as_handled()


func _bind_player_resources() -> void:
	var health := _player.get_node_or_null("Health") as Health
	var stamina := _player.get_node_or_null("Stamina") as Stamina
	if health:
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.current, Health.MAX_HEALTH)
	if stamina:
		stamina.stamina_changed.connect(_on_stamina_changed)
		_on_stamina_changed(stamina.current, Stamina.MAX_STAMINA)


func _on_progression_changed() -> void:
	if not ProgressionService:
		return
	if _level_label:
		_level_label.text = "Lv %d" % ProgressionService.level
	if _xp_bar:
		_xp_bar.max_value = 1.0
		_xp_bar.value = ProgressionService.xp_progress_ratio()


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
	var aim_point := LockOn.get_target_aim_point(target)
	if camera.is_position_behind(aim_point):
		_lock_reticle.visible = false
		return
	var screen_pos := camera.unproject_position(aim_point)
	_lock_reticle.visible = true
	_lock_reticle.position = screen_pos - _lock_reticle.size * 0.5


func _update_guard_indicators() -> void:
	if not _parry_bar or not _block_bar or not _parry_label:
		return
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
	if not _health_bar:
		return
	_health_bar.max_value = max_value
	_health_bar.value = current


func _on_stamina_changed(current: float, max_value: float) -> void:
	if not _stamina_bar:
		return
	_stamina_bar.max_value = max_value
	_stamina_bar.value = current


func _on_lock_changed(_target: Node3D, locked: bool) -> void:
	if not locked and _lock_reticle:
		_lock_reticle.visible = false
