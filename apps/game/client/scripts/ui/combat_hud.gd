extends Control

const StatusIconAtlasScript := preload("res://scripts/ui/status_icon_atlas.gd")
const StatusPipScene := preload("res://scenes/ui/status_pip.tscn")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")
const HudIconAtlasScript := preload("res://scripts/ui/hud_icon_atlas.gd")
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const HealChargeMeterScript := preload("res://scripts/ui/heal_charge_meter.gd")
const GuardIndicatorScript := preload("res://scripts/ui/guard_indicator.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const QuickSlotBarScript := preload("res://scripts/ui/quick_slot_bar.gd")

const BAR_WIDTH := 280.0
const HEALTH_BAR_HEIGHT := 22.0
const STAMINA_BAR_HEIGHT := 16.0
const MANA_BAR_HEIGHT := 16.0
const LOW_HP_RATIO := 0.25
const VIGNETTE_COOLDOWN := 0.8
const HINT_AUTO_HIDE_SECONDS := 60.0
const STATUS_REFRESH_INTERVAL := 0.1
const HEALTH_FILL := Color(0.71, 0.17, 0.19, 1.0)
const HEALTH_BG := Color(0.14, 0.05, 0.06, 0.92)
const STAMINA_FILL := Color(0.52, 0.68, 0.34, 1.0)
const STAMINA_BG := Color(0.08, 0.11, 0.06, 0.92)
const MANA_FILL := Color(0.44, 0.42, 0.85, 1.0)
const MANA_BG := Color(0.06, 0.06, 0.14, 0.92)

const POISE_BAR_HEIGHT := 10.0
const POISE_FILL := Color(0.82, 0.74, 0.45, 1.0)
const POISE_BG := Color(0.14, 0.12, 0.07, 0.92)
const POISE_BROKEN_FILL := Color(0.9, 0.35, 0.25, 1.0)

const IFRAME_FILL := Color(0.86, 0.95, 1.0, 1.0)

const XP_BANNER_MIN := 25
const LOCK_RETICLE_OCCLUDED := Color(1.0, 0.62, 0.55, 1.0)

@export var player_path: NodePath
@export var lock_on_path: NodePath

@onready var _health_bar: ProgressBar = $ResourcePanel/VBox/HealthBar
@onready var _stamina_bar: ProgressBar = $ResourcePanel/VBox/StaminaBar

var _poise_bar: ProgressBar
var _poise_broken_shown := false
@onready var _mana_bar: ProgressBar = $ResourcePanel/VBox/ManaBar
@onready var _xp_bar: ProgressBar = $ResourcePanel/VBox/XpBar
@onready var _level_label: Label = $ResourcePanel/VBox/LevelLabel
@onready var _status_row: HBoxContainer = $ResourcePanel/VBox/StatusRow
@onready var _lock_reticle: Control = $LockReticle
@onready var _parry_bar: ProgressBar = $GuardIndicators/ParryBar
@onready var _block_bar: ProgressBar = $GuardIndicators/BlockBar
@onready var _parry_label: Label = $GuardIndicators/ParryLabel
@onready var _boss_panel: VBoxContainer = $BossBar
@onready var _boss_name_label: Label = $BossBar/BossName
@onready var _boss_health_bar: ProgressBar = $BossBar/BossHealthBar
@onready var _boss_phase_row: HBoxContainer = $BossBar/BossPhaseRow
@onready var _branch_banner: Label = $BranchBanner
@onready var _objective_marker: TextureRect = $ObjectiveMarker
@onready var _minimap_anchor: MarginContainer = $MinimapAnchor
@onready var _minimap: Control = $MinimapAnchor/Minimap
@onready var _controls_hint: HBoxContainer = $ControlsHint
@onready var _warning_banner: Label = $WarningBanner
@onready var _respawn_overlay: Control = $RespawnOutcomeOverlay

var _player: Node3D
var _lock_on: LockOn
var _guard: Guard
var _weapon_controller: WeaponController
var _camera: Camera3D
var _status_controller: StatusController
var _objective_world_pos: Vector3 = Vector3.INF
var _boss_node: Node
var _boss_health: Health
var _boss_phase_count := 2
var _boss_current_phase := 1
var _lock_reticle_alpha := 0.0
var _status_pips: Dictionary = {}
var _status_refresh_timer := 0.0
var _build_up_box: VBoxContainer
var _heal_charge_row: HBoxContainer
var _quick_slot_bar: Control
var _lock_target_occluded := false
var _riposte_prompt_timer := 0.0
var _build_up_rows: Dictionary = {}
var _last_health := -1.0
var _vignette_cooldown := 0.0
var _hint_session_start := 0.0
var _hint_actions_used: Dictionary = {
	"dodge": false,
	"jump": false,
	"lock_on": false,
	"inventory": false,
}
var _hint_hidden_by_usage := false
var _map_overlay: Control
var _map_overlay_minimap: Control
var _region_banner: Label
var _guard_indicator_active := false
var _slow_update_timer := 0.0

const SLOW_UPDATE_INTERVAL := 0.1


func _ready() -> void:
	GameUISkinScript.apply_pixel_theme(self)
	_style_resource_bars()
	_rebuild_controls_hint()
	_apply_controls_hint_visibility()
	_hint_session_start = Time.get_ticks_msec() / 1000.0
	var symbol_bus := get_node_or_null("/root/UISymbolBus")
	if symbol_bus and not symbol_bus.symbols_invalidated.is_connected(_on_symbols_invalidated):
		symbol_bus.symbols_invalidated.connect(_on_symbols_invalidated)
	InputGlyphServiceScript.connect_device_family_changed(_rebuild_controls_hint)
	AccessibilitySettings.connect_settings_changed(_on_accessibility_settings_changed)
	if DisplayService and not DisplayService.display_changed.is_connected(_on_display_changed):
		DisplayService.display_changed.connect(_on_display_changed)
	_apply_hud_safe_area()
	if player_path:
		_player = get_node(player_path) as Node3D
		_guard = _player.get_node_or_null("Guard") as Guard
		if _guard:
			_guard.block_state_changed.connect(_on_guard_block_state_changed)
			_guard.guard_broken.connect(_on_guard_broken)
			if not _guard.riposte_ready.is_connected(_on_riposte_ready):
				_guard.riposte_ready.connect(_on_riposte_ready)
		_weapon_controller = _player.get_node_or_null("WeaponController") as WeaponController
		_status_controller = _player.get_node_or_null("StatusController") as StatusController
		_bind_player_resources()
		_bind_heal_charges()
		_bind_quick_slots()
		_bind_minimap_player()
		if _status_controller:
			_status_controller.statuses_changed.connect(_refresh_status_icons)
			_ensure_build_up_box()
			_status_controller.build_up_changed.connect(_refresh_build_up_meters)
			_refresh_status_icons()
			_refresh_build_up_meters()
	if lock_on_path:
		_lock_on = get_node_or_null(lock_on_path) as LockOn
		if _lock_on:
			_lock_on.lock_changed.connect(_on_lock_changed)
			if not _lock_on.lock_occluded.is_connected(_on_lock_occluded):
				_lock_on.lock_occluded.connect(_on_lock_occluded)
	if ProgressionService:
		ProgressionService.progression_changed.connect(_on_progression_changed)
		if not ProgressionService.xp_granted.is_connected(_on_xp_granted):
			ProgressionService.xp_granted.connect(_on_xp_granted)
		if not ProgressionService.endless_depth_record.is_connected(_on_endless_depth_record):
			ProgressionService.endless_depth_record.connect(_on_endless_depth_record)
		if not ProgressionService.endless_milestone_reached.is_connected(
			_on_endless_milestone_reached
		):
			ProgressionService.endless_milestone_reached.connect(_on_endless_milestone_reached)
		_on_progression_changed()
	if RunFlow and not RunFlow.run_warning.is_connected(_on_run_warning):
		RunFlow.run_warning.connect(_on_run_warning)
	if InventoryService and not InventoryService.inventory_rejected.is_connected(_on_inventory_rejected):
		InventoryService.inventory_rejected.connect(_on_inventory_rejected)
	if LocalSave and not LocalSave.save_failed.is_connected(_on_save_failed):
		LocalSave.save_failed.connect(_on_save_failed)
	GameUISkinScript.make_backdrop(_respawn_overlay)
	var panel := _respawn_overlay.get_node("Panel") as PanelContainer
	if panel:
		panel.custom_minimum_size = Vector2(460, 220)
	if _minimap_anchor:
		_minimap_anchor.visible = false


func _exit_tree() -> void:
	var symbol_bus := get_node_or_null("/root/UISymbolBus")
	if symbol_bus and symbol_bus.symbols_invalidated.is_connected(_on_symbols_invalidated):
		symbol_bus.symbols_invalidated.disconnect(_on_symbols_invalidated)
	InputGlyphServiceScript.disconnect_device_family_changed(_rebuild_controls_hint)
	AccessibilitySettings.disconnect_settings_changed(_on_accessibility_settings_changed)
	if DisplayService and DisplayService.display_changed.is_connected(_on_display_changed):
		DisplayService.display_changed.disconnect(_on_display_changed)


func _style_resource_bars() -> void:
	_health_bar.custom_minimum_size = Vector2(BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_apply_bar_style(_health_bar, HEALTH_FILL, HEALTH_BG)
	_stamina_bar.custom_minimum_size = Vector2(BAR_WIDTH, STAMINA_BAR_HEIGHT)
	_apply_bar_style(_stamina_bar, STAMINA_FILL, STAMINA_BG)
	_mana_bar.custom_minimum_size = Vector2(BAR_WIDTH, MANA_BAR_HEIGHT)
	_apply_bar_style(_mana_bar, MANA_FILL, MANA_BG)
	if _poise_bar:
		_poise_bar.custom_minimum_size = Vector2(BAR_WIDTH, POISE_BAR_HEIGHT)
		_apply_bar_style(_poise_bar, POISE_FILL, POISE_BG)
	_boss_health_bar.custom_minimum_size = Vector2(420, 18)
	_apply_bar_style(_boss_health_bar, Color(0.72, 0.12, 0.1, 1.0), Color(0.08, 0.04, 0.04, 0.95))
	_boss_name_label.add_theme_color_override("font_color", Color(0.95, 0.86, 0.72))
	_branch_banner.add_theme_color_override("font_color", Color(0.86, 0.83, 0.76))
	_warning_banner.add_theme_color_override("font_color", Color(0.98, 0.86, 0.55))


func _apply_bar_style(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	GameUISkinScript.style_progress_bar(bar, fill_color, bg_color)


const BUILD_UP_METER_WIDTH := 84


func _ensure_build_up_box() -> void:
	if _build_up_box != null or _status_row == null:
		return
	var parent := _status_row.get_parent() as Control
	if parent == null:
		return
	_build_up_box = VBoxContainer.new()
	_build_up_box.name = "BuildUpMeters"
	_build_up_box.add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT)
	_build_up_box.visible = false
	parent.add_child(_build_up_box)
	parent.move_child(_build_up_box, _status_row.get_index() + 1)


func _make_build_up_row(status_id: String) -> Control:
	var def := StatusCatalog.get_definition(status_id)
	var tint := Color.from_string(str(def.get("iconColor", "")), Color(0.63, 0.38, 0.25))
	var row := HBoxContainer.new()
	row.name = "BuildUp_%s" % status_id
	row.add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT * 2)
	var icon := GameUISkinScript.make_symbol_rect(
		StatusIconAtlasScript.get_icon(status_id), StatusIconAtlasScript.icon_size()
	)
	row.add_child(icon)
	var bar := GameUISkinScript.make_meter_bar(tint, BUILD_UP_METER_WIDTH)
	row.add_child(bar)
	row.set_meta("bar", bar)
	return row


func _refresh_build_up_meters() -> void:
	if _build_up_box == null or _status_controller == null:
		return
	var seen: Dictionary = {}
	for meter in _status_controller.get_build_up_meters():
		var status_id: String = str(meter.get("id", ""))
		if status_id == "":
			continue
		var ratio := clampf(float(meter.get("ratio", 0.0)), 0.0, 1.0)
		if ratio <= 0.0:
			continue
		seen[status_id] = true
		var row: Control
		if _build_up_rows.has(status_id):
			row = _build_up_rows[status_id] as Control
		else:
			row = _make_build_up_row(status_id)
			_build_up_box.add_child(row)
			_build_up_rows[status_id] = row
		var bar := row.get_meta("bar") as ProgressBar
		if bar:
			bar.value = ratio
	for status_id in _build_up_rows.keys():
		if seen.has(status_id):
			continue
		var stale: Control = _build_up_rows[status_id]
		if is_instance_valid(stale):
			stale.queue_free()
		_build_up_rows.erase(status_id)
	_build_up_box.visible = not _build_up_rows.is_empty()


func _refresh_status_icons() -> void:
	if _status_row == null or _status_controller == null:
		return
	var active_ids: Dictionary = {}
	for entry in _status_controller.get_active_statuses():
		var status_id: String = entry.get("id", "")
		if status_id == "":
			continue
		active_ids[status_id] = entry
		var pip: Control
		if _status_pips.has(status_id):
			pip = _status_pips[status_id] as Control
		else:
			pip = StatusPipScene.instantiate() as Control
			_status_row.add_child(pip)
			_status_pips[status_id] = pip
		var def := StatusCatalog.get_definition(status_id)
		var stacks: int = int(entry.get("stacks", 1))
		var polarity := str(def.get("polarity", "debuff"))
		var icon_dim := StatusIconAtlasScript.icon_size()
		pip.custom_minimum_size = Vector2(icon_dim + 4, icon_dim + 8)
		pip.call(
			"configure",
			status_id,
			stacks,
			StatusIconAtlasScript.get_icon(status_id),
			polarity
		)
		pip.call("update_timer", float(entry.get("remaining", 0.0)), float(entry.get("duration", 0.0)))
	for status_id in _status_pips.keys():
		if not active_ids.has(status_id):
			var stale: Control = _status_pips[status_id]
			if is_instance_valid(stale):
				stale.queue_free()
			_status_pips.erase(status_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		set_process(false)
		return
	_vignette_cooldown = maxf(0.0, _vignette_cooldown - delta)
	_update_lock_reticle()
	if _riposte_prompt_timer > 0.0:
		_riposte_prompt_timer = maxf(0.0, _riposte_prompt_timer - delta)
	if _guard_indicator_active or _riposte_prompt_timer > 0.0:
		_update_guard_indicators()
	_update_status_timers(delta)
	_track_controls_hint_usage()
	_slow_update_timer -= delta
	if _slow_update_timer <= 0.0:
		_slow_update_timer = SLOW_UPDATE_INTERVAL
		_update_objective_marker()
		_update_controls_hint_visibility(delta)


func _update_status_timers(delta: float) -> void:
	if _status_controller == null or _status_pips.is_empty():
		return
	_status_refresh_timer -= delta
	if _status_refresh_timer > 0.0:
		return
	_status_refresh_timer = STATUS_REFRESH_INTERVAL
	for entry in _status_controller.get_active_statuses():
		var status_id: String = entry.get("id", "")
		if not _status_pips.has(status_id):
			continue
		var pip: Control = _status_pips[status_id]
		pip.call("set_stacks", int(entry.get("stacks", 1)))
		pip.call("update_timer", float(entry.get("remaining", 0.0)), float(entry.get("duration", 0.0)))


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
	var title := str(def.get("title", def.get("name", tr("HUD_BOSS_FALLBACK"))))
	_boss_name_label.text = title
	_on_boss_health_changed(_boss_health.current, _boss_health.max_health)
	_refresh_boss_phase_pips()
	_boss_panel.visible = true


func unbind_boss() -> void:
	_unbind_boss()


func _unbind_boss() -> void:
	if _boss_node == null and _boss_health == null:
		return
	var boss := _boss_node
	var boss_health := _boss_health
	_boss_node = null
	_boss_health = null

	if boss_health and boss_health.health_changed.is_connected(_on_boss_health_changed):
		boss_health.health_changed.disconnect(_on_boss_health_changed)
	if boss and is_instance_valid(boss):
		if (
			boss.has_signal("phase_changed")
			and boss.phase_changed.is_connected(_on_boss_phase_changed)
		):
			boss.phase_changed.disconnect(_on_boss_phase_changed)
		if boss.has_signal("boss_defeated") and boss.boss_defeated.is_connected(unbind_boss):
			boss.boss_defeated.disconnect(unbind_boss)
		if boss.has_signal("enemy_died") and boss.enemy_died.is_connected(unbind_boss):
			boss.enemy_died.disconnect(unbind_boss)
	if _boss_panel:
		_boss_panel.visible = false


func _on_boss_health_changed(current: float, max_value: float) -> void:
	_boss_health_bar.max_value = max_value
	_boss_health_bar.value = current


func _on_boss_phase_changed(phase: int) -> void:
	_boss_current_phase = phase
	_refresh_boss_phase_pips()


func _resolve_boss_phase_count(boss: Node) -> int:
	var boss_id := ""
	if boss.has_method("get_enemy_id"):
		boss_id = str(boss.call("get_enemy_id"))
	if boss_id == "":
		return 1
	return maxi(1, int(EnemyCatalog.get_definition(boss_id).get("phaseCount", 1)))


func _refresh_boss_phase_pips() -> void:
	for child in _boss_phase_row.get_children():
		child.queue_free()
	var pip_size := StatusIconAtlasScript.icon_size()
	for i in _boss_phase_count:
		var active := i < _boss_current_phase
		var pip := GameUISkinScript.make_symbol_rect(
			HudIconAtlasScript.get_pip_filled() if active else HudIconAtlasScript.get_pip_empty(),
			pip_size
		)
		pip.custom_minimum_size = Vector2(14, 8)
		_boss_phase_row.add_child(pip)


func _unhandled_input(event: InputEvent) -> void:
	if _map_overlay and _map_overlay.visible:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_close_map_overlay()
			return
	if event.is_action_pressed("map"):
		if _minimap and _minimap.has_method("has_graph") and _minimap.call("has_graph"):
			get_viewport().set_input_as_handled()
			if _map_overlay and _map_overlay.visible:
				_close_map_overlay()
			else:
				_open_map_overlay()
			return
	if _respawn_overlay and _respawn_overlay.visible:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
			_dismiss_respawn_overlay()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if OS.is_debug_build() and event.keycode == KEY_F8 and _status_controller:
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
	var poise := _player.get_node_or_null("Poise") as Poise
	if poise:
		_ensure_poise_bar()
		poise.poise_changed.connect(_on_poise_changed)
		poise.poise_broken.connect(_on_poise_broken)
		_on_poise_changed(poise.current, poise.max_poise)
	var dodge := _player.get_node_or_null("Dodge")
	if dodge and dodge.has_signal("iframes_changed"):
		dodge.iframes_changed.connect(_on_iframes_changed)
	if health:
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.current, health.max_health)
	if stamina:
		stamina.stamina_changed.connect(_on_stamina_changed)
		stamina.insufficient.connect(_on_stamina_insufficient)
		stamina.depleted.connect(_on_stamina_depleted)
		if stamina.has_signal("recovered"):
			stamina.recovered.connect(_on_stamina_recovered)
		_on_stamina_changed(stamina.current, stamina.max_stamina)
	if mana:
		mana.mana_changed.connect(_on_mana_changed)
		mana.insufficient.connect(_on_mana_insufficient)
		_on_mana_changed(mana.current, mana.max_mana)


func _ensure_poise_bar() -> void:
	if _poise_bar != null and is_instance_valid(_poise_bar):
		return
	if _mana_bar == null:
		return
	var host := _mana_bar.get_parent() as Control
	if host == null:
		return
	_poise_bar = ProgressBar.new()
	_poise_bar.name = "PoiseBar"
	_poise_bar.show_percentage = false
	_poise_bar.custom_minimum_size = Vector2(BAR_WIDTH, POISE_BAR_HEIGHT)
	_apply_bar_style(_poise_bar, POISE_FILL, POISE_BG)
	host.add_child(_poise_bar)
	host.move_child(_poise_bar, _mana_bar.get_index() + 1)


func _on_xp_granted(amount: int, reason: String) -> void:
	if amount < XP_BANNER_MIN or reason == "kill":
		return
	show_run_warning(tr("HUD_XP_GRANTED").format({"xp": amount}))


func _on_endless_depth_record(_previous_best: int, new_best: int, tokens_awarded: int) -> void:
	if tokens_awarded > 0:
		show_run_warning(
			tr("HUD_DEPTH_RECORD_TOKENS").format({"floor": new_best, "tokens": tokens_awarded})
		)
	else:
		show_run_warning(tr("HUD_DEPTH_RECORD").format({"floor": new_best}))


func _on_endless_milestone_reached(milestone: Dictionary) -> void:
	var label := str(milestone.get("name", milestone.get("id", "")))
	if label == "":
		return
	show_run_warning(tr("HUD_MILESTONE").format({"name": label}))


func _on_iframes_changed(active: bool) -> void:
	if _stamina_bar == null or not is_instance_valid(_stamina_bar):
		return
	if active:
		_apply_bar_style(_stamina_bar, IFRAME_FILL, STAMINA_BG)
	else:
		_apply_bar_style(_stamina_bar, STAMINA_FILL, STAMINA_BG)


func _on_poise_changed(current: float, max_value: float) -> void:
	if _poise_bar == null or not is_instance_valid(_poise_bar):
		return
	_poise_bar.max_value = maxf(1.0, max_value)
	_poise_bar.value = current
	if current > 0.0 and _poise_broken_shown:
		_poise_broken_shown = false
		_apply_bar_style(_poise_bar, POISE_FILL, POISE_BG)


func _on_poise_broken() -> void:
	if _poise_bar == null or not is_instance_valid(_poise_bar):
		return
	_poise_broken_shown = true
	_apply_bar_style(_poise_bar, POISE_BROKEN_FILL, POISE_BG)
	_flash_resource_bar(_poise_bar, POISE_BROKEN_FILL)


func _bind_quick_slots() -> void:
	if _quick_slot_bar != null and is_instance_valid(_quick_slot_bar):
		return
	var host := get_node_or_null("QuickSlotAnchor") as Control
	if host == null:
		host = _status_row.get_parent() as Control if _status_row != null else null
	if host == null:
		return
	_quick_slot_bar = QuickSlotBarScript.new()
	host.add_child(_quick_slot_bar)


func _bind_heal_charges() -> void:
	if _heal_charge_row == null and _status_row != null:
		_heal_charge_row = HealChargeMeterScript.bind(
			_player, _status_row, _on_heal_charges_changed, _on_heal_interrupted
		)


func _on_heal_charges_changed(current: int, max_value: int) -> void:
	HealChargeMeterScript.refresh(_heal_charge_row, current, max_value)


func _on_heal_interrupted() -> void:
	HealChargeMeterScript.flash_interrupt(_heal_charge_row)


func _on_progression_changed() -> void:
	if not ProgressionService:
		return
	_level_label.text = tr("HUD_LEVEL") % ProgressionService.level
	_xp_bar.max_value = 1.0
	_xp_bar.value = ProgressionService.xp_progress_ratio()


func _update_lock_reticle() -> void:
	if not _lock_reticle or not _lock_on or not _lock_on.is_locked:
		if _lock_reticle:
			_lock_reticle.visible = false
			_lock_reticle_alpha = 0.0
		return
	var target := _lock_on.current_target
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
	var occluded_tint := LOCK_RETICLE_OCCLUDED if _lock_target_occluded else Color.WHITE
	_lock_reticle.modulate.r = occluded_tint.r
	_lock_reticle.modulate.g = occluded_tint.g
	_lock_reticle.modulate.b = occluded_tint.b
	if not on_screen or camera.is_position_behind(aim_point):
		var center := viewport_size * 0.5
		var dir := (screen_pos - center).normalized()
		screen_pos = center + dir * minf(viewport_size.x, viewport_size.y) * 0.42
	screen_pos.x = floor(screen_pos.x)
	screen_pos.y = floor(screen_pos.y)
	_lock_reticle.position = screen_pos - _lock_reticle.size * 0.5


func _on_lock_occluded(occluded: bool) -> void:
	_lock_target_occluded = occluded


func _on_riposte_ready() -> void:
	if _parry_label == null:
		return
	_parry_label.text = tr("HUD_RIPOSTE_READY")
	_parry_label.visible = true
	_riposte_prompt_timer = Guard.RIPOSTE_WINDOW


func _on_guard_block_state_changed(blocking: bool) -> void:
	_guard_indicator_active = blocking
	if blocking:
		_update_guard_indicators()
	else:
		_parry_bar.visible = false
		_block_bar.visible = false
		_parry_label.visible = false


func _on_guard_broken() -> void:
	_guard_indicator_active = false
	_parry_bar.visible = false
	_block_bar.visible = false
	_parry_label.visible = false


func _update_guard_indicators() -> void:
	_riposte_prompt_timer = GuardIndicatorScript.update(
		_guard, _parry_bar, _block_bar, _parry_label, _riposte_prompt_timer
	)


func _get_camera() -> Camera3D:
	if _camera and is_instance_valid(_camera):
		return _camera
	_camera = PixelDioramaViewport.get_gameplay_camera()
	return _camera


func _on_health_changed(current: float, max_value: float) -> void:
	_health_bar.max_value = max_value
	_health_bar.value = current
	if (
		_last_health > 0.0
		and current < _last_health
		and max_value > 0.0
		and current / max_value <= LOW_HP_RATIO
		and _vignette_cooldown <= 0.0
	):
		if PixelDioramaViewport and PixelDioramaViewport.has_method("pulse_screen"):
			PixelDioramaViewport.pulse_screen(
				PixelDioramaViewport.ScreenPulse.DAMAGE, 0.22 / 0.72
			)
			_vignette_cooldown = VIGNETTE_COOLDOWN
	_last_health = current


func _on_stamina_changed(current: float, max_value: float) -> void:
	_stamina_bar.max_value = max_value
	_stamina_bar.value = current


func _on_mana_changed(current: float, max_value: float) -> void:
	_mana_bar.max_value = max_value
	_mana_bar.value = current


func _on_stamina_insufficient() -> void:
	_flash_resource_bar(_stamina_bar, Color(0.9, 0.3, 0.25))


func _on_stamina_depleted() -> void:
	_stamina_bar.modulate = Color(0.55, 0.22, 0.18)
	AudioDirector.play_sfx("exhausted")


func _on_stamina_recovered() -> void:
	_stamina_bar.modulate = Color.WHITE


func _on_mana_insufficient() -> void:
	_flash_resource_bar(_mana_bar, Color(0.35, 0.45, 0.95))


func _flash_resource_bar(bar: ProgressBar, flash_color: Color) -> void:
	if bar == null:
		return
	var tween := create_tween()
	tween.tween_property(bar, "modulate", flash_color, 0.09)
	tween.tween_property(bar, "modulate", Color.WHITE, 0.18)
	AudioDirector.play_sfx("resource_denied")


func _on_lock_changed(_target: Node3D, locked: bool) -> void:
	if not locked and _lock_reticle:
		_lock_reticle.visible = false


func configure_minimap(definition: Dictionary) -> void:
	if _minimap and _minimap.has_method("configure"):
		_minimap.call("configure", definition)
		if _minimap.has_method("has_graph"):
			var show_map: bool = _minimap.call("has_graph")
			if _minimap_anchor:
				_minimap_anchor.visible = show_map
		_bind_minimap_player()


func mark_room_visited(room_id: String) -> void:
	if _minimap and _minimap.has_method("mark_visited"):
		_minimap.call("mark_visited", room_id)


func set_current_room(room_id: String) -> void:
	if _minimap and _minimap.has_method("set_current_room"):
		_minimap.call("set_current_room", room_id)


func mark_room_cleared(room_id: String) -> void:
	if _minimap and _minimap.has_method("mark_cleared"):
		_minimap.call("mark_cleared", room_id)


func set_minimap_fog_of_war(enabled: bool) -> void:
	if _minimap and _minimap.has_method("set_fog_of_war"):
		_minimap.call("set_fog_of_war", enabled)


func show_region_title(title: String, subtitle: String = "") -> void:
	if title == "":
		return
	_ensure_region_banner()
	_region_banner.text = title if subtitle == "" else "%s\n%s" % [title, subtitle]
	_region_banner.visible = true
	_region_banner.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_region_banner, "modulate:a", 1.0, 0.6)
	tween.tween_interval(3.2)
	tween.tween_property(_region_banner, "modulate:a", 0.0, 0.8)
	tween.tween_callback(
		func() -> void:
			if _region_banner:
				_region_banner.visible = false
	)


func _ensure_region_banner() -> void:
	if _region_banner != null and is_instance_valid(_region_banner):
		return
	_region_banner = Label.new()
	_region_banner.name = "RegionBanner"
	_region_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_region_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_region_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_region_banner.visible = false
	GameUISkinScript.style_body_label(_region_banner)
	add_child(_region_banner)


func _bind_minimap_player() -> void:
	if _player == null or _minimap == null or not _minimap.has_method("bind_player"):
		return
	_minimap.call("bind_player", _player)


func _open_map_overlay() -> void:
	if _minimap == null or not _minimap.has_method("export_state"):
		return
	_init_map_overlay()
	var state: Dictionary = _minimap.call("export_state")
	_map_overlay.visible = true
	_map_overlay_minimap.call("import_state", state)
	if _player and _map_overlay_minimap.has_method("bind_player"):
		_map_overlay_minimap.call("bind_player", _player)
	MenuStack.push(_map_overlay, true)


func _close_map_overlay() -> void:
	if _map_overlay == null or not _map_overlay.visible:
		return
	_map_overlay.visible = false
	MenuStack.pop(_map_overlay)


func _init_map_overlay() -> void:
	if _map_overlay != null:
		return
	_map_overlay = Control.new()
	_map_overlay.name = "MapOverlay"
	_map_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_overlay.visible = false
	_map_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_map_overlay)
	var shell: Dictionary = MenuShellScript.build_modal(
		_map_overlay, tr("MAP_TITLE"), GameUISkinScript.MENU_HALF_W + 120.0, GameUISkinScript.MENU_HALF_H + 160.0
	)
	var content: VBoxContainer = shell["content_vbox"]
	_map_overlay_minimap = MinimapScript.new()
	_map_overlay_minimap.name = "FullMap"
	_map_overlay_minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_overlay_minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_overlay_minimap.custom_minimum_size = Vector2(520, 360)
	_map_overlay_minimap.call("enable_overlay_mode")
	content.add_child(_map_overlay_minimap)
	MenuShellScript.add_hint(content, tr("MAP_HINT"))


func set_branch_previews(hints: Array) -> void:
	if hints.is_empty():
		_branch_banner.visible = false
		return
	var reward_count := 0
	var danger_count := 0
	for hint in hints:
		if not hint is Dictionary:
			continue
		match str(hint.get("hint", "")):
			"reward":
				reward_count += 1
			"danger":
				danger_count += 1
	var parts: PackedStringArray = []
	if reward_count > 0:
		parts.append(tr("HUD_BRANCH_REWARD") % reward_count)
	if danger_count > 0:
		parts.append(tr("HUD_BRANCH_DANGER") % danger_count)
	_branch_banner.text = tr("HUD_BRANCH_AHEAD") % ", ".join(parts)
	_branch_banner.visible = true


func set_objective_world_position(world_pos: Vector3) -> void:
	_objective_world_pos = world_pos
	_update_objective_marker()


func _update_objective_marker() -> void:
	if _objective_world_pos == Vector3.INF or _player == null:
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
	var screen_pos := camera.unproject_position(_objective_world_pos)
	var viewport_size := get_viewport_rect().size
	var center := viewport_size * 0.5
	var behind := camera.is_position_behind(_objective_world_pos)
	if behind or not Rect2(Vector2.ZERO, viewport_size).has_point(screen_pos):
		var dir := (screen_pos - center).normalized()
		if behind:
			dir = -dir
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		screen_pos = center + dir * minf(viewport_size.x, viewport_size.y) * 0.42
	_objective_marker.visible = true
	_objective_marker.position = (screen_pos - _objective_marker.size * 0.5).floor()
	_objective_marker.rotation = (screen_pos - center).angle() + PI * 0.5


func show_run_warning(message: String) -> void:
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
	var xp_gained: int = int(results.get("xp_gained", 0))
	var xp_deferred: int = int(results.get("xp_deferred", 0))
	var loot_lost: Array = results.get("loot_lost", [])
	var lines: PackedStringArray = [
		tr("RESPAWN_XP_GAINED").format({"xp": xp_gained}),
	]
	if xp_deferred > 0:
		lines.append(tr("RESPAWN_XP_DEFERRED").format({"xp": xp_deferred}))
	if loot_lost.size() > 0:
		lines.append(tr("RESPAWN_LOOT_STRIPPED").format({"items": ", ".join(loot_lost)}))
	else:
		lines.append(tr("RESPAWN_LOOT_KEPT"))
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
		show_run_warning(tr("WARN_INVENTORY_FULL"))


func _on_save_failed(reason: String) -> void:
	match reason:
		"write_failed":
			show_run_warning(tr("WARN_SAVE_WRITE_FAILED"))
		"save_from_newer_build":
			show_run_warning(tr("WARN_SAVE_FROM_NEWER_BUILD"))
		_:
			show_run_warning(tr("WARN_SAVE_FAILED_REASON").format({"reason": reason}))


func _rebuild_controls_hint() -> void:
	if _controls_hint == null:
		return
	for child in _controls_hint.get_children():
		child.queue_free()
	var actions := ["dodge", "jump", "lock_on", "inventory"]
	var size_px := StatusIconAtlasScript.icon_size()
	for i in actions.size():
		if i > 0:
			var sep := Label.new()
			sep.text = "  |  "
			sep.theme_type_variation = GameUISkinScript.VAR_HINT_TEXT
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_controls_hint.add_child(sep)
		_controls_hint.add_child(
			GameUISkinScript.make_symbol_icon_caption_row(
				InputGlyphServiceScript.get_action_glyph_texture(actions[i]),
				InputGlyphServiceScript.get_action_display_name(actions[i]),
				size_px
			)
		)


func _on_symbols_invalidated(reason: StringName) -> void:
	if reason == &"colorblind":
		_refresh_status_icons()
	if reason in [&"device", &"rebind", &"preset"]:
		_rebuild_controls_hint()


func _apply_controls_hint_visibility() -> void:
	if _controls_hint:
		_controls_hint.visible = AccessibilitySettings.show_control_hints and not _hint_hidden_by_usage


func _on_accessibility_settings_changed() -> void:
	StatusIconAtlasScript.reload()
	_refresh_status_icons()
	_apply_controls_hint_visibility()


func _on_display_changed(field: StringName, _value: Variant) -> void:
	if field == &"hud_safe_area":
		_apply_hud_safe_area()


func _apply_hud_safe_area() -> void:
	var margin: float = DisplayService.hud_safe_area if DisplayService else 0.0
	var viewport_size := get_viewport_rect().size
	var margin_px := viewport_size * margin
	offset_left = margin_px.x
	offset_top = margin_px.y
	offset_right = -margin_px.x
	offset_bottom = -margin_px.y


func _track_controls_hint_usage() -> void:
	if _controls_hint == null or not AccessibilitySettings.show_control_hints:
		return
	if _hint_hidden_by_usage:
		return
	for action in _hint_actions_used.keys():
		if PlayerInput.just_pressed(action):
			_hint_actions_used[action] = true


func _update_controls_hint_visibility(_delta: float) -> void:
	if _controls_hint == null or not AccessibilitySettings.show_control_hints:
		return
	if _hint_hidden_by_usage:
		return
	var all_used := true
	for used in _hint_actions_used.values():
		if not used:
			all_used = false
			break
	if all_used:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - _hint_session_start
		if elapsed >= HINT_AUTO_HIDE_SECONDS:
			_hint_hidden_by_usage = true
			_apply_controls_hint_visibility()
