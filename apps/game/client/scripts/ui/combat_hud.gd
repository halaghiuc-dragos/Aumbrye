extends Control

const StatusIconAtlasScript := preload("res://scripts/ui/status_icon_atlas.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const QuestTrackerUIScene := preload("res://scenes/ui/quest_tracker_ui.tscn")

const BAR_WIDTH := 280.0
const HEALTH_BAR_HEIGHT := 22.0
const STAMINA_BAR_HEIGHT := 16.0
const MANA_BAR_HEIGHT := 16.0
const ATTACK_BAR_HEIGHT := 10.0
const HUD_MARGIN := 20.0
const HEALTH_FILL := Color(0.82, 0.14, 0.12, 1.0)
const HEALTH_BG := Color(0.12, 0.05, 0.05, 0.92)
const STAMINA_FILL := Color(0.22, 0.78, 0.28, 1.0)
const STAMINA_BG := Color(0.05, 0.12, 0.06, 0.92)
const MANA_FILL := Color(0.22, 0.42, 0.92, 1.0)
const MANA_BG := Color(0.04, 0.06, 0.14, 0.92)
const ATTACK_STARTUP_FILL := Color(0.95, 0.55, 0.18, 1.0)
const ATTACK_ACTIVE_FILL := Color(0.85, 0.18, 0.12, 1.0)
const ATTACK_RECOVERY_FILL := Color(0.45, 0.45, 0.48, 1.0)
const BAR_BORDER := Color(0.04, 0.04, 0.04, 0.95)

@export var player_path: NodePath
@export var lock_on_path: NodePath

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _mana_bar: ProgressBar
var _attack_bar: ProgressBar
var _xp_bar: ProgressBar
var _level_label: Label
var _lock_reticle: Control
var _parry_bar: ProgressBar
var _block_bar: ProgressBar
var _parry_label: Label
var _player: Node3D
var _lock_on: Node
var _guard: Node
var _weapon_controller: Node
var _camera: Camera3D
var _status_row: HBoxContainer
var _status_controller: StatusController
var _minimap: Control
var _quest_tracker: Control
var _branch_banner: Label
var _objective_marker: Control
var _objective_world_pos: Vector3 = Vector3.INF
var _boss_panel: VBoxContainer
var _boss_name_label: Label
var _boss_health_bar: ProgressBar
var _boss_phase_row: HBoxContainer
var _boss_node: Node
var _boss_health: Health
var _boss_phase_count := 2
var _boss_current_phase := 1
var _lock_reticle_alpha := 0.0
var _warning_banner: Label
var _respawn_overlay: Control


func _ready() -> void:
	GameUISkinScript.apply_pixel_theme(self)
	_health_bar = get_node_or_null("Margin/VBox/HealthBar") as ProgressBar
	_stamina_bar = get_node_or_null("Margin/VBox/StaminaBar") as ProgressBar
	_mana_bar = get_node_or_null("Margin/VBox/ManaBar") as ProgressBar
	_attack_bar = get_node_or_null("Margin/VBox/AttackBar") as ProgressBar
	_xp_bar = get_node_or_null("Margin/VBox/XpBar") as ProgressBar
	_level_label = get_node_or_null("Margin/VBox/LevelLabel") as Label
	_apply_screen_layout()
	_ensure_mana_bar()
	_ensure_attack_bar()
	_style_resource_bars()
	_ensure_progression_widgets()
	_ensure_controls_hint()
	_ensure_minimap()
	_ensure_quest_tracker()
	_ensure_objective_marker()
	_ensure_boss_bar()
	_lock_reticle = get_node_or_null("LockReticle") as Control
	_parry_bar = get_node_or_null("GuardIndicators/ParryBar") as ProgressBar
	_block_bar = get_node_or_null("GuardIndicators/BlockBar") as ProgressBar
	_parry_label = get_node_or_null("GuardIndicators/ParryLabel") as Label
	if player_path:
		_player = get_node(player_path) as Node3D
		_guard = _player.get_node_or_null("Guard")
		_weapon_controller = _player.get_node_or_null("WeaponController")
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
	if RunFlow and not RunFlow.run_warning.is_connected(_on_run_warning):
		RunFlow.run_warning.connect(_on_run_warning)
	if InventoryService and not InventoryService.inventory_rejected.is_connected(_on_inventory_rejected):
		InventoryService.inventory_rejected.connect(_on_inventory_rejected)


func _ensure_status_row() -> void:
	_status_row = get_node_or_null("StatusRow") as HBoxContainer
	if _status_row == null:
		_status_row = HBoxContainer.new()
		_status_row.name = "StatusRow"
		add_child(_status_row)
	_refresh_status_icons()
	_update_status_row_position()


func _apply_screen_layout() -> void:
	var margin := get_node_or_null("Margin") as MarginContainer
	if margin == null:
		return
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = HUD_MARGIN
	margin.offset_top = HUD_MARGIN
	margin.offset_right = HUD_MARGIN + BAR_WIDTH
	margin.offset_bottom = (
		HUD_MARGIN
		+ HEALTH_BAR_HEIGHT
		+ STAMINA_BAR_HEIGHT
		+ MANA_BAR_HEIGHT
		+ ATTACK_BAR_HEIGHT
		+ 34.0
	)
	margin.grow_horizontal = Control.GROW_DIRECTION_END
	margin.grow_vertical = Control.GROW_DIRECTION_END
	var vbox := margin.get_node_or_null("VBox") as VBoxContainer
	if vbox:
		vbox.add_theme_constant_override("separation", 6)


func _style_resource_bars() -> void:
	if _health_bar:
		_health_bar.custom_minimum_size = Vector2(BAR_WIDTH, HEALTH_BAR_HEIGHT)
		_apply_bar_style(_health_bar, HEALTH_FILL, HEALTH_BG)
	if _stamina_bar:
		_stamina_bar.custom_minimum_size = Vector2(BAR_WIDTH, STAMINA_BAR_HEIGHT)
		_apply_bar_style(_stamina_bar, STAMINA_FILL, STAMINA_BG)
	if _mana_bar:
		_mana_bar.custom_minimum_size = Vector2(BAR_WIDTH, MANA_BAR_HEIGHT)
		_apply_bar_style(_mana_bar, MANA_FILL, MANA_BG)
	if _attack_bar:
		_attack_bar.custom_minimum_size = Vector2(BAR_WIDTH, ATTACK_BAR_HEIGHT)
		_apply_bar_style(_attack_bar, ATTACK_STARTUP_FILL, STAMINA_BG)


func _ensure_mana_bar() -> void:
	if _mana_bar != null:
		return
	var vbox := get_node_or_null("Margin/VBox") as VBoxContainer
	if vbox == null:
		return
	_mana_bar = ProgressBar.new()
	_mana_bar.name = "ManaBar"
	_mana_bar.show_percentage = false
	var stamina := vbox.get_node_or_null("StaminaBar")
	if stamina:
		vbox.add_child(_mana_bar)
		vbox.move_child(_mana_bar, stamina.get_index() + 1)
	else:
		vbox.add_child(_mana_bar)


func _ensure_attack_bar() -> void:
	if _attack_bar != null:
		return
	var vbox := get_node_or_null("Margin/VBox") as VBoxContainer
	if vbox == null:
		return
	_attack_bar = ProgressBar.new()
	_attack_bar.name = "AttackBar"
	_attack_bar.show_percentage = false
	_attack_bar.visible = false
	vbox.add_child(_attack_bar)


func _apply_bar_style(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	GameUISkinScript.style_progress_bar(bar, fill_color, bg_color)


func _update_status_row_position() -> void:
	if _status_row == null:
		return
	_status_row.position = Vector2(
		HUD_MARGIN,
		(
			HUD_MARGIN
			+ HEALTH_BAR_HEIGHT
			+ STAMINA_BAR_HEIGHT
			+ MANA_BAR_HEIGHT
			+ ATTACK_BAR_HEIGHT
			+ 22.0
		)
	)


func _refresh_status_icons() -> void:
	if _status_row == null:
		return
	for child in _status_row.get_children():
		child.queue_free()
	if _status_controller == null:
		return
	for entry in _status_controller.get_active_statuses():
		var def := StatusCatalog.get_definition(entry.get("id", ""))
		var status_id: String = entry.get("id", "")
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(
			StatusIconAtlasScript.icon_size(), StatusIconAtlasScript.icon_size()
		)
		icon.texture = StatusIconAtlasScript.get_icon(status_id)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = "%s x%d" % [def.get("name", status_id), entry.get("stacks", 1)]
		var damage_type := str(def.get("damageType", ""))
		if damage_type != "":
			var tint := AccessibilitySettings.get_damage_color(damage_type)
			icon.modulate = tint
			var border := PanelContainer.new()
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
			style.set_border_width_all(2)
			style.border_color = tint
			border.add_theme_stylebox_override("panel", style)
			border.add_child(icon)
			_status_row.add_child(border)
		else:
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


func _ensure_controls_hint() -> void:
	if get_node_or_null("ControlsHint") != null:
		return
	var hint := Label.new()
	hint.name = "ControlsHint"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -32.0
	hint.offset_bottom = -6.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.86, 0.83, 0.76))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.72))
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	hint.text = (
		"%s  |  %s  |  %s  |  %s"
		% [
			InputGlyphServiceScript.format_action_hint("dodge"),
			InputGlyphServiceScript.format_action_hint("jump"),
			InputGlyphServiceScript.format_action_hint("lock_on"),
			InputGlyphServiceScript.format_action_hint("inventory"),
		]
	)
	add_child(hint)


func _process(_delta: float) -> void:
	_update_lock_reticle()
	_update_guard_indicators()
	_update_objective_marker()
	_update_attack_bar()


func bind_boss(boss: Node) -> void:
	_unbind_boss()
	if boss == null or not is_instance_valid(boss):
		return
	_boss_node = boss
	_boss_health = boss.get_node_or_null("Health") as Health
	if _boss_health == null:
		return
	_boss_phase_count = _resolve_boss_phase_count(boss)
	_boss_current_phase = 1
	_boss_health.health_changed.connect(_on_boss_health_changed)
	if (
		boss.has_signal("phase_changed")
		and not boss.phase_changed.is_connected(_on_boss_phase_changed)
	):
		boss.phase_changed.connect(_on_boss_phase_changed)
	if boss.has_signal("boss_defeated") and not boss.boss_defeated.is_connected(unbind_boss):
		boss.boss_defeated.connect(unbind_boss)
	if boss.has_signal("enemy_died") and not boss.enemy_died.is_connected(unbind_boss):
		boss.enemy_died.connect(unbind_boss)
	var boss_id := ""
	if boss.has_method("get_enemy_id"):
		boss_id = str(boss.call("get_enemy_id"))
	var def := EnemyCatalog.get_definition(boss_id) if boss_id != "" else {}
	_boss_name_label.text = str(def.get("title", def.get("name", "Boss")))
	_on_boss_health_changed(_boss_health.current, _boss_health.max_health)
	_refresh_boss_phase_pips()
	_boss_panel.visible = true


func unbind_boss() -> void:
	_unbind_boss()


func _unbind_boss() -> void:
	if _boss_health and _boss_health.health_changed.is_connected(_on_boss_health_changed):
		_boss_health.health_changed.disconnect(_on_boss_health_changed)
	if _boss_node and is_instance_valid(_boss_node):
		if (
			_boss_node.has_signal("phase_changed")
			and _boss_node.phase_changed.is_connected(_on_boss_phase_changed)
		):
			_boss_node.phase_changed.disconnect(_on_boss_phase_changed)
		if (
			_boss_node.has_signal("boss_defeated")
			and _boss_node.boss_defeated.is_connected(unbind_boss)
		):
			_boss_node.boss_defeated.disconnect(unbind_boss)
		if _boss_node.has_signal("enemy_died") and _boss_node.enemy_died.is_connected(unbind_boss):
			_boss_node.enemy_died.disconnect(unbind_boss)
	_boss_node = null
	_boss_health = null
	if _boss_panel:
		_boss_panel.visible = false


func _on_boss_health_changed(current: float, max_value: float) -> void:
	if _boss_health_bar == null:
		return
	_boss_health_bar.max_value = max_value
	_boss_health_bar.value = current


func _on_boss_phase_changed(phase: int) -> void:
	_boss_current_phase = phase
	_refresh_boss_phase_pips()


func _resolve_boss_phase_count(boss: Node) -> int:
	if boss.get_script() and str(boss.get_script().resource_path).contains("final_boss"):
		return 3
	return 2


func _refresh_boss_phase_pips() -> void:
	if _boss_phase_row == null:
		return
	for child in _boss_phase_row.get_children():
		child.queue_free()
	for i in _boss_phase_count:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 8)
		var active := i < _boss_current_phase
		pip.color = Color(0.95, 0.78, 0.25, 0.95) if active else Color(0.2, 0.18, 0.16, 0.9)
		_boss_phase_row.add_child(pip)


func _ensure_boss_bar() -> void:
	if _boss_panel != null:
		return
	_boss_panel = VBoxContainer.new()
	_boss_panel.name = "BossBar"
	_boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.offset_top = 52.0
	_boss_panel.custom_minimum_size = Vector2(420, 48)
	_boss_panel.visible = false
	add_child(_boss_panel)
	_boss_name_label = Label.new()
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_color_override("font_color", Color(0.95, 0.86, 0.72))
	_boss_panel.add_child(_boss_name_label)
	_boss_health_bar = ProgressBar.new()
	_boss_health_bar.custom_minimum_size = Vector2(420, 18)
	_boss_health_bar.show_percentage = false
	_apply_bar_style(_boss_health_bar, Color(0.72, 0.12, 0.1, 1.0), Color(0.08, 0.04, 0.04, 0.95))
	_boss_panel.add_child(_boss_health_bar)
	_boss_phase_row = HBoxContainer.new()
	_boss_phase_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_boss_phase_row.add_theme_constant_override("separation", 6)
	_boss_panel.add_child(_boss_phase_row)


func _unhandled_input(event: InputEvent) -> void:
	if _respawn_overlay and _respawn_overlay.visible:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
			_dismiss_respawn_overlay()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8 and _status_controller:
			_status_controller.debug_apply("burn")
			_refresh_status_icons()
			get_viewport().set_input_as_handled()


func _dismiss_respawn_overlay() -> void:
	if _respawn_overlay == null or not _respawn_overlay.visible:
		return
	var tween := create_tween()
	tween.tween_property(_respawn_overlay, "modulate:a", 0.0, 0.25)
	tween.tween_callback(
		func() -> void:
			if _respawn_overlay:
				_respawn_overlay.visible = false
	)


func _bind_player_resources() -> void:
	var health := _player.get_node_or_null("Health") as Health
	var stamina := _player.get_node_or_null("Stamina") as Stamina
	var mana := _player.get_node_or_null("Mana") as Mana
	if health:
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.current, Health.MAX_HEALTH)
	if stamina:
		stamina.stamina_changed.connect(_on_stamina_changed)
		stamina.insufficient.connect(_on_stamina_insufficient)
		stamina.depleted.connect(_on_stamina_depleted)
		_on_stamina_changed(stamina.current, Stamina.MAX_STAMINA)
	if mana:
		mana.mana_changed.connect(_on_mana_changed)
		mana.insufficient.connect(_on_mana_insufficient)
		_on_mana_changed(mana.current, Mana.MAX_MANA)


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
			_lock_reticle_alpha = 0.0
		return
	var target := _lock_on.get("current_target") as Node3D
	if target == null or not is_instance_valid(target):
		_lock_reticle.visible = false
		_lock_reticle_alpha = 0.0
		return
	var camera := _get_camera()
	if camera == null:
		return
	var aim_point := LockOn.get_target_aim_point(target)
	var screen_pos := camera.unproject_position(aim_point)
	var viewport_size := get_viewport_rect().size
	var on_screen := (
		screen_pos.x >= 0.0
		and screen_pos.y >= 0.0
		and screen_pos.x <= viewport_size.x
		and screen_pos.y <= viewport_size.y
	)
	var target_alpha := 1.0 if on_screen and not camera.is_position_behind(aim_point) else 0.35
	_lock_reticle_alpha = lerpf(_lock_reticle_alpha, target_alpha, 0.22)
	_lock_reticle.visible = _lock_reticle_alpha > 0.05
	_lock_reticle.modulate.a = _lock_reticle_alpha
	if not on_screen:
		var center := viewport_size * 0.5
		var dir := (screen_pos - center).normalized()
		screen_pos = center + dir * minf(viewport_size.x, viewport_size.y) * 0.42
	screen_pos.x = floor(screen_pos.x)
	screen_pos.y = floor(screen_pos.y)
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
	_camera = PixelDioramaViewport.get_gameplay_camera()
	return _camera


func _on_health_changed(current: float, max_value: float) -> void:
	if not _health_bar:
		return
	_health_bar.max_value = max_value
	_health_bar.value = current
	if max_value > 0.0 and current / max_value <= 0.25:
		if PixelDioramaViewport and PixelDioramaViewport.has_method("pulse_screen"):
			PixelDioramaViewport.pulse_screen(
				PixelDioramaViewport.ScreenPulse.DAMAGE, 0.22 / 0.72
			)


func _on_stamina_changed(current: float, max_value: float) -> void:
	if not _stamina_bar:
		return
	_stamina_bar.max_value = max_value
	_stamina_bar.value = current


func _on_mana_changed(current: float, max_value: float) -> void:
	if not _mana_bar:
		return
	_mana_bar.max_value = max_value
	_mana_bar.value = current


func _on_stamina_insufficient() -> void:
	_flash_resource_bar(_stamina_bar, Color(0.9, 0.3, 0.25))


func _on_stamina_depleted() -> void:
	if _stamina_bar:
		_stamina_bar.modulate = Color(0.55, 0.22, 0.18)
	AudioDirector.play_sfx("exhausted")


func _on_mana_insufficient() -> void:
	_flash_resource_bar(_mana_bar, Color(0.35, 0.45, 0.95))


func _flash_resource_bar(bar: ProgressBar, flash_color: Color) -> void:
	if bar == null:
		return
	var tween := create_tween()
	tween.tween_property(bar, "modulate", flash_color, 0.09)
	tween.tween_property(bar, "modulate", Color.WHITE, 0.18)
	AudioDirector.play_sfx("resource_denied")


func _update_attack_bar() -> void:
	if _attack_bar == null or _weapon_controller == null:
		return
	if not bool(_weapon_controller.get("is_attacking")):
		_attack_bar.visible = false
		return
	var phase_info: Dictionary = {}
	if _weapon_controller.has_method("get_attack_phase_progress"):
		phase_info = _weapon_controller.call("get_attack_phase_progress")
	var progress: float = float(phase_info.get("progress", 0.0))
	var phase: String = str(phase_info.get("phase", "startup"))
	_attack_bar.visible = true
	_attack_bar.max_value = 1.0
	_attack_bar.value = progress
	var fill := ATTACK_STARTUP_FILL
	match phase:
		"active":
			fill = ATTACK_ACTIVE_FILL
		"recovery":
			fill = ATTACK_RECOVERY_FILL
	_apply_bar_style(_attack_bar, fill, STAMINA_BG)


func _on_lock_changed(_target: Node3D, locked: bool) -> void:
	if not locked and _lock_reticle:
		_lock_reticle.visible = false


func configure_minimap(definition: Dictionary) -> void:
	_ensure_minimap()
	if _minimap and _minimap.has_method("configure"):
		_minimap.call("configure", definition)


func mark_room_visited(room_id: String) -> void:
	if _minimap and _minimap.has_method("mark_visited"):
		_minimap.call("mark_visited", room_id)


func set_current_room(room_id: String) -> void:
	if _minimap and _minimap.has_method("set_current_room"):
		_minimap.call("set_current_room", room_id)


func set_branch_previews(hints: Array) -> void:
	_ensure_branch_banner()
	if hints.is_empty():
		_branch_banner.visible = false
		return
	var reward_count := 0
	var danger_count := 0
	for hint in hints:
		if not hint is Dictionary:
			continue
		if str(hint.get("hint", "")) == "reward":
			reward_count += 1
		else:
			danger_count += 1
	var parts: PackedStringArray = []
	if reward_count > 0:
		parts.append("%d reward path(s)" % reward_count)
	if danger_count > 0:
		parts.append("%d danger path(s)" % danger_count)
	_branch_banner.text = "Branch ahead — " + ", ".join(parts)
	_branch_banner.visible = true


func set_objective_world_position(world_pos: Vector3) -> void:
	_objective_world_pos = world_pos
	_update_objective_marker()


func _ensure_minimap() -> void:
	if _minimap != null:
		return
	_minimap = MinimapScript.new()
	_minimap.name = "Minimap"
	_minimap.position = Vector2(size.x - 156.0, HUD_MARGIN)
	add_child(_minimap)


func _ensure_quest_tracker() -> void:
	if _quest_tracker != null:
		return
	_quest_tracker = QuestTrackerUIScene.instantiate() as Control
	_quest_tracker.name = "QuestTrackerUI"
	add_child(_quest_tracker)


func _ensure_branch_banner() -> void:
	if _branch_banner != null:
		return
	_branch_banner = Label.new()
	_branch_banner.name = "BranchBanner"
	_branch_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_branch_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_branch_banner.offset_top = 8.0
	_branch_banner.offset_bottom = 36.0
	_branch_banner.visible = false
	add_child(_branch_banner)


func _ensure_objective_marker() -> void:
	if _objective_marker != null:
		return
	_objective_marker = Control.new()
	_objective_marker.name = "ObjectiveMarker"
	_objective_marker.custom_minimum_size = Vector2(18, 18)
	_objective_marker.visible = false
	var glyph := ColorRect.new()
	glyph.color = Color(0.95, 0.78, 0.25, 0.95)
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_objective_marker.add_child(glyph)
	add_child(_objective_marker)


func _update_objective_marker() -> void:
	if _objective_marker == null or _objective_world_pos == Vector3.INF or _player == null:
		if _objective_marker:
			_objective_marker.visible = false
		return
	var camera := _get_camera()
	if camera == null:
		return
	var to_target := _objective_world_pos - _player.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 4.0:
		_objective_marker.visible = false
		return
	var screen_center := get_viewport_rect().size * 0.5
	var screen_edge := screen_center + Vector2(to_target.x, -to_target.z).normalized() * 120.0
	_objective_marker.visible = true
	_objective_marker.position = screen_edge - _objective_marker.size * 0.5


func show_run_warning(message: String) -> void:
	_ensure_warning_banner()
	_warning_banner.text = message
	_warning_banner.visible = true
	_warning_banner.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(_warning_banner, "modulate:a", 0.0, 0.5)
	tween.tween_callback(
		func() -> void:
			if _warning_banner:
				_warning_banner.visible = false
	)


func show_respawn_outcome(results: Dictionary) -> void:
	_ensure_respawn_overlay()
	var xp_gained: int = int(results.get("xp_gained", 0))
	var xp_deferred: int = int(results.get("xp_deferred", 0))
	var loot_lost: Array = results.get("loot_lost", [])
	var lines: PackedStringArray = [
		"XP gained: %d" % xp_gained,
	]
	if xp_deferred > 0:
		lines.append("XP deferred to shard: %d" % xp_deferred)
	if loot_lost.size() > 0:
		lines.append("Loot stripped: %s" % ", ".join(loot_lost))
	else:
		lines.append("No loot stripped since bonfire.")
	var body: Label = _respawn_overlay.get_node("Panel/Margin/VBox/Body")
	body.text = "\n".join(lines)
	_respawn_overlay.visible = true
	_respawn_overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_respawn_overlay, "modulate:a", 1.0, 0.35)


func _on_run_warning(message: String) -> void:
	show_run_warning(message)


func _on_inventory_rejected(reason: String) -> void:
	if reason == "full":
		show_run_warning("Inventory full")


func _ensure_warning_banner() -> void:
	if _warning_banner != null:
		return
	_warning_banner = Label.new()
	_warning_banner.name = "WarningBanner"
	_warning_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_warning_banner.offset_top = 44.0
	_warning_banner.offset_bottom = 72.0
	_warning_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_banner.add_theme_color_override("font_color", Color(0.98, 0.86, 0.55))
	_warning_banner.visible = false
	add_child(_warning_banner)


func _ensure_respawn_overlay() -> void:
	if _respawn_overlay != null:
		return
	_respawn_overlay = Control.new()
	_respawn_overlay.name = "RespawnOutcomeOverlay"
	_respawn_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_respawn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_respawn_overlay.visible = false
	add_child(_respawn_overlay)
	GameUISkinScript.make_backdrop(_respawn_overlay)
	var panel := GameUISkinScript.make_center_panel(_respawn_overlay, 460.0, 220.0)
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "Echo Returned"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(title)
	vbox.add_child(title)
	var body := Label.new()
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)
	var hint := Label.new()
	hint.text = "Enter to dismiss"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(hint)
	vbox.add_child(hint)
