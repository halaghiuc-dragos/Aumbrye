extends Control

## HD-01: the HUD is owned by this script; a run scene (`castle_run.gd`, `waves_run.gd`) may only
## call its public methods, never draw its own status panel. The mode-neutral contract every run
## scene owes a call to, so the same information appears in the same place in every mode:
##   configure_for_mode(run_mode)         -- once, right after instancing the HUD
##   configure_keys(lock_count)           -- once the floor/wave definition is known (0 if none)
##   set_objective_text(text)             -- whenever the current objective changes
##   show_region_title(title, subtitle)   -- entering a region/floor/wave
##   show_run_warning(message)            -- any error a player-facing panel would have shown
##   show_respawn_outcome(results)        -- on a respawn/death outcome
##   bind_boss(boss, is_miniboss)         -- whenever a boss-type enemy spawns
## `configure_minimap`/`mark_room_visited`/`set_current_room`/`mark_room_cleared`/
## `set_minimap_fog_of_war`/`set_branch_previews`/`set_objective_world_position` are dungeon-only
## (no map in Waves) and are skipped rather than called with placeholder data in modes without one.
## `enable_arena_radar(half_extent)`/`set_radar_spawn_markers(markers)` are the Waves-only inverse
## -- an arena has no room graph for the dungeon minimap, so it gets a radar instead (HD-05).

const FloorKeyringScript := preload("res://scripts/dungeon/floor_keyring.gd")

const StatusIconAtlasScript := preload("res://scripts/ui/status_icon_atlas.gd")
const StatusPipScene := preload("res://scenes/ui/status_pip.tscn")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")
const HudIconAtlasScript := preload("res://scripts/ui/hud_icon_atlas.gd")
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const HealChargeMeterScript := preload("res://scripts/ui/heal_charge_meter.gd")
const ArrowChargeMeterScript := preload("res://scripts/ui/arrow_charge_meter.gd")
const GuardIndicatorScript := preload("res://scripts/ui/guard_indicator.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const QuickSlotBarScript := preload("res://scripts/ui/quick_slot_bar.gd")
const ScreenEdgeScript := preload("res://scripts/ui/screen_edge.gd")
const DamageDirectionArcScript := preload("res://scripts/ui/damage_direction_arc.gd")
const BowReticleScript := preload("res://scripts/ui/bow_reticle.gd")

const BAR_WIDTH := 330.0
const HEALTH_BAR_HEIGHT := 30.0
const STAMINA_BAR_HEIGHT := 22.0
const MANA_BAR_HEIGHT := 22.0
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

const POISE_BAR_HEIGHT := 14.0
const POISE_FILL := Color(0.82, 0.74, 0.45, 1.0)
const POISE_BG := Color(0.14, 0.12, 0.07, 0.92)
const POISE_BROKEN_FILL := Color(0.9, 0.35, 0.25, 1.0)

const IFRAME_FILL := Color(0.86, 0.95, 1.0, 1.0)

## The XP bar never went through `_apply_bar_style` at all, so it rendered in Godot's default
## theme -- rounded end caps, no fill texture -- next to four bars built out of the same pixel-block
## style. Gold ties it to the UI's own accent colour (menu titles, the gold key, the level-up text)
## rather than inventing a new one just for this bar.
const XP_FILL := Color(0.85, 0.68, 0.28, 1.0)
const XP_BG := Color(0.12, 0.10, 0.05, 0.92)

const XP_BANNER_MIN := 25
const LOCK_RETICLE_OCCLUDED := Color(1.0, 0.62, 0.55, 1.0)

@export var player_path: NodePath
@export var lock_on_path: NodePath

@onready var _health_bar: ProgressBar = $ResourcePanel/VBox/HealthBar
@onready var _stamina_bar: ProgressBar = $ResourcePanel/VBox/StaminaBar

var _poise_bar: ProgressBar
var _health_trail: ProgressBar
var _health_trail_hold := 0.0
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
@onready var _modifier_strip: HBoxContainer = $ModifierStrip
@onready var _controls_hint: HBoxContainer = $ControlsHint
@onready var _warning_banner: Label = $WarningBanner
@onready var _inline_warning: Label = $InlineWarning
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
## `BS-06`: set when the bound boss is a miniboss -- suppresses the phase pip row and shrinks the
## health bar, so the HUD itself reads as "this is not the floor boss" without extra copy.
var _boss_bar_is_mini := false
const BOSS_BAR_SIZE := Vector2(460, 26)
const MINIBOSS_BAR_SIZE := Vector2(300, 18)
var _lock_reticle_alpha := 0.0
var _bow_reticle: BowReticle
var _status_pips: Dictionary = {}
var _status_refresh_timer := 0.0
var _build_up_box: VBoxContainer
var _heal_charge_row: HBoxContainer
var _arrow_charge_row: HBoxContainer
var _quick_slot_bar: Control
var _lock_target_occluded := false
var _riposte_prompt_timer := 0.0
var _build_up_rows: Dictionary = {}
## CB-08: the last 20% before a build-up meter hits its threshold gets a warning -- previously the
## meter just filled with no signal that poison/bleed/etc. was about to land.
var _build_up_warned: Dictionary = {}
const BUILD_UP_WARNING_RATIO := 0.8
var _key_row: HBoxContainer
var _key_pips: Dictionary = {}

## HD-06: readouts the combat model already computes but never showed -- what the next swing
## costs, the two-hand/infusion stance, and where you are in the light-attack combo.
var _stamina_ghost: ColorRect
var _stance_row: HBoxContainer
var _two_hand_swatch: ColorRect
var _infusion_swatch: ColorRect
var _art_cooldown_bar: ProgressBar
var _combo_pip_row: HBoxContainer
var _combo_pips_ui: Array[TextureRect] = []
const COMBO_PIP_COUNT := 3

## HD-07: which side a hit came from, since a vignette pulse alone gives no bearing.
var _damage_arc: Control
const ELEMENT_COLORS := {
	"fire": Color(0.86, 0.35, 0.12, 1.0),
	"frost": Color(0.45, 0.72, 0.92, 1.0),
	"poison": Color(0.42, 0.72, 0.28, 1.0),
	"lightning": Color(0.85, 0.78, 0.25, 1.0),
	"arcane": Color(0.62, 0.4, 0.92, 1.0),
}
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
var _region_banner: VBoxContainer
var _region_title_label: Label
var _region_subtitle_label: Label

## HD-02: `RegionBanner`, `WarningBanner` and (formerly) a run scene's own status panel all claimed
## the top-centre band and could overlap. A queue owns that band now: one message on screen at a
## time, priority `region (3) > warning (2)`, draining rather than stacking. Branch previews are
## ambient, not an event, so they get a persistent slot below the queue instead of a turn in it.
const BANNER_PRIORITY_REGION := 3
const BANNER_PRIORITY_WARNING := 2
const BANNER_MIN_DISPLAY := 1.2
var _banner_queue: Array[Dictionary] = []
var _banner_draining := false

## UX-10: the banner lane is for run-level events (region titles, records, milestones); the inline
## lane is its own small always-in-place slot for gameplay errors that happen at the point of
## failure ("inventory full", a save that could not write) so they never compete with or get
## clobbered by a region title mid-drain.
const INLINE_MIN_DISPLAY := 2.0
var _inline_queue: Array[String] = []
var _inline_draining := false
var _guard_indicator_active := false
var _slow_update_timer := 0.0
var _danger_chevrons: Array[TextureRect] = []

const SLOW_UPDATE_INTERVAL := 0.1
## `EN-09`: same shape the existing arrow already solves for the objective marker, reused rather
## than adding a second asset -- a small class-tinted chevron clamped to the screen edge.
const DANGER_CHEVRON_TEXTURE := preload("res://assets/ui/hud_objective.png")
const MAX_DANGER_CHEVRONS := 3


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
	_ensure_key_row()
	_ensure_combat_readouts()
	if WorldState and not WorldState.namespace_changed.is_connected(_on_world_flag_changed):
		WorldState.namespace_changed.connect(_on_world_flag_changed)
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
		_bind_arrow_charges()
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
	_build_danger_chevrons()
	_build_bow_reticle()


func _build_bow_reticle() -> void:
	_bow_reticle = BowReticleScript.new()
	_bow_reticle.name = "BowReticle"
	_bow_reticle.visible = false
	_bow_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bow_reticle)


func _build_danger_chevrons() -> void:
	for i in MAX_DANGER_CHEVRONS:
		var chevron := TextureRect.new()
		chevron.name = "DangerChevron%d" % i
		chevron.texture = DANGER_CHEVRON_TEXTURE
		chevron.texture_filter = TEXTURE_FILTER_NEAREST
		chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chevron.stretch_mode = TextureRect.STRETCH_SCALE
		chevron.size = Vector2(18.0, 18.0)
		chevron.pivot_offset = chevron.size * 0.5
		chevron.visible = false
		chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(chevron)
		_danger_chevrons.append(chevron)


func _exit_tree() -> void:
	var symbol_bus := get_node_or_null("/root/UISymbolBus")
	if symbol_bus and symbol_bus.symbols_invalidated.is_connected(_on_symbols_invalidated):
		symbol_bus.symbols_invalidated.disconnect(_on_symbols_invalidated)
	InputGlyphServiceScript.disconnect_device_family_changed(_rebuild_controls_hint)
	AccessibilitySettings.disconnect_settings_changed(_on_accessibility_settings_changed)
	if DisplayService and DisplayService.display_changed.is_connected(_on_display_changed):
		DisplayService.display_changed.disconnect(_on_display_changed)
	# CB-08: a status screen grade (e.g. still burning at the moment the run ends) must not leak
	# into whatever scene loads next.
	PixelDioramaSettings.apply_status_screen_grade([])


## How fast the ghost behind the health bar catches up, in bar-fractions per second.
const HEALTH_TRAIL_DRAIN := 0.55
const HEALTH_TRAIL_DELAY := 0.35
const HEALTH_TRAIL_FILL := Color(0.98, 0.55, 0.52, 1.0)


## A pale ghost that lags behind the health bar after a hit and then drains away.
##
## A bar that simply jumps to its new value tells the player their health changed but not by how
## much. The trail leaves the old reading visible for a beat, so the size of the hit is legible in
## peripheral vision — which is the whole job of a soulslike health bar during a fight.
##
## This has to overlap the real bar exactly, not sit next to it. Adding it as a plain sibling next
## to `_health_bar` inside the VBox that stacks the resource bars did not do that: a VBoxContainer
## lays every child into its own row regardless of z_index (z_index only reorders drawing between
## controls that already share a rect, it does not make a container overlap them), so the "ghost"
## rendered as a second, permanently-visible health bar sitting right above the real one -- read as
## two health bars, because on screen that is exactly what it was. Wrapping both bars in a plain
## Control and anchoring them to fill it is what makes them occupy the same rect, with the real bar
## added second so it draws on top and only the trailing difference peeks out from behind it.
func _ensure_health_trail() -> void:
	if _health_trail != null and is_instance_valid(_health_trail):
		return
	var parent := _health_bar.get_parent() as Control
	if parent == null:
		return
	var slot_index := _health_bar.get_index()
	var wrapper := Control.new()
	wrapper.name = "HealthBarStack"
	wrapper.custom_minimum_size = Vector2(BAR_WIDTH, HEALTH_BAR_HEIGHT)
	wrapper.size_flags_horizontal = _health_bar.size_flags_horizontal
	parent.add_child(wrapper)
	parent.move_child(wrapper, slot_index)
	parent.remove_child(_health_bar)
	_health_trail = ProgressBar.new()
	_health_trail.name = "HealthTrail"
	_health_trail.show_percentage = false
	_health_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_trail.set_anchors_preset(Control.PRESET_FULL_RECT)
	GameUISkinScript.style_progress_bar(_health_trail, HEALTH_TRAIL_FILL, HEALTH_BG)
	wrapper.add_child(_health_trail)
	wrapper.add_child(_health_bar)
	_health_bar.set_anchors_preset(Control.PRESET_FULL_RECT)


func _update_health_trail(delta: float) -> void:
	if _health_trail == null or not is_instance_valid(_health_trail):
		return
	_health_trail.max_value = _health_bar.max_value
	if _health_trail.value < _health_bar.value:
		_health_trail.value = _health_bar.value
		_health_trail_hold = 0.0
		return
	if _health_trail.value <= _health_bar.value:
		return
	if _health_trail_hold > 0.0:
		_health_trail_hold -= delta
		return
	var span := maxf(1.0, _health_bar.max_value)
	_health_trail.value = maxf(
		_health_bar.value, _health_trail.value - span * HEALTH_TRAIL_DRAIN * delta
	)


func _style_resource_bars() -> void:
	_health_bar.custom_minimum_size = Vector2(BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_apply_bar_style(_health_bar, HEALTH_FILL, HEALTH_BG)
	_ensure_health_trail()
	_label_bar(_health_bar, "HP")
	_stamina_bar.custom_minimum_size = Vector2(BAR_WIDTH, STAMINA_BAR_HEIGHT)
	_apply_bar_style(_stamina_bar, STAMINA_FILL, STAMINA_BG)
	_label_bar(_stamina_bar, "SP")
	_mana_bar.custom_minimum_size = Vector2(BAR_WIDTH, MANA_BAR_HEIGHT)
	_apply_bar_style(_mana_bar, MANA_FILL, MANA_BG)
	_label_bar(_mana_bar, "MP")
	if _poise_bar:
		_poise_bar.custom_minimum_size = Vector2(BAR_WIDTH, POISE_BAR_HEIGHT)
		_apply_bar_style(_poise_bar, POISE_FILL, POISE_BG)
		_label_bar(_poise_bar, "PO")
	_apply_bar_style(_xp_bar, XP_FILL, XP_BG)
	_label_bar(_xp_bar, "XP")
	_boss_health_bar.custom_minimum_size = Vector2(460, 26)
	_apply_bar_style(_boss_health_bar, Color(0.72, 0.12, 0.1, 1.0), Color(0.08, 0.04, 0.04, 0.95))
	_boss_name_label.add_theme_color_override("font_color", Color(0.95, 0.86, 0.72))
	_branch_banner.add_theme_color_override("font_color", Color(0.86, 0.83, 0.76))
	_warning_banner.add_theme_color_override("font_color", Color(0.98, 0.86, 0.55))


func _apply_bar_style(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	GameUISkinScript.style_progress_bar(bar, fill_color, bg_color)


## Health, stamina, mana and poise stack directly on top of each other in the corner, told apart by
## fill colour alone -- fine for a player who has already learned "the blue one is mana", useless
## on the first ten minutes, and a real problem for colourblind players the rest of the way, since
## this is exactly the kind of same-shape/different-hue row the game already ships a colourblind
## mode to account for elsewhere. A short outlined initialism costs almost no space on a bar this
## thin and reads regardless of which colour the fill actually renders as.
func _label_bar(bar: ProgressBar, text: String) -> void:
	if bar == null:
		return
	var existing := bar.get_node_or_null("BarLabel") as Label
	var label := existing if existing else Label.new()
	if existing == null:
		label.name = "BarLabel"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 6
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.add_theme_font_size_override("font_size", GameUISkinScript.FONT_SIZE_SMALL)
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		label.add_theme_constant_override("outline_size", 3)
		bar.add_child(label)
	label.text = text


const BUILD_UP_METER_WIDTH := 84


## The keycard row.
##
## Doom put the keys on the status bar and never explained them, because a lit red card next to a
## red door explains itself. Held keys are `WorldState` flags, so the row just redraws whenever the
## key namespace changes -- picking one up, and the ring being emptied on the stairs.
func _ensure_key_row() -> void:
	if _key_row != null or _status_row == null:
		return
	_key_row = HBoxContainer.new()
	_key_row.name = "KeyRow"
	_key_row.add_theme_constant_override("separation", 4)
	_status_row.add_child(_key_row)
	for color in FloorKeyringScript.COLOR_ORDER:
		var pip := ColorRect.new()
		pip.name = "Key_%s" % color
		pip.custom_minimum_size = Vector2(10, 14)
		pip.tooltip_text = tr(str(FloorKeyringScript.COLORS[color]["label"]))
		_key_row.add_child(pip)
		_key_pips[color] = pip
	_refresh_key_row()


## RM-05: how many of the row's three pips are actually this floor's locks -- a floor with one
## lock showed all three cards before, which reads as "you're missing two keys" on a floor that
## only ever had one. `-1` (the default, before `configure_keys` runs once) shows all three, since
## that is the least-wrong guess before the definition is known.
var _lock_count := -1


func configure_keys(lock_count: int) -> void:
	_lock_count = lock_count
	_refresh_key_row()


func _refresh_key_row() -> void:
	if _key_row == null:
		return
	var held := FloorKeyringScript.held_colors()
	var any := false
	for i in FloorKeyringScript.COLOR_ORDER.size():
		var color: String = FloorKeyringScript.COLOR_ORDER[i]
		var pip: ColorRect = _key_pips[color]
		if _lock_count >= 0 and i >= _lock_count:
			pip.visible = false
			continue
		pip.visible = true
		var carried: bool = held.has(color)
		# Unheld cards stay on the bar as dim outlines, so the player can see how many the floor
		# has before they have found any of them.
		var tint: Color = FloorKeyringScript.COLORS[color]["tint"]
		pip.color = tint if carried else Color(tint.r, tint.g, tint.b, 0.18)
		any = any or carried
	_key_row.visible = true


func _on_world_flag_changed(flag_namespace: String, _flag_id: String, _value: Variant) -> void:
	if flag_namespace == WorldFlags.NS_KEY:
		_refresh_key_row()


## HD-06: built once, alongside `_ensure_key_row()`. The stamina ghost is a direct child of the
## stamina bar (a `ProgressBar`, not a `Container`, so a manually-positioned child sits on top of
## its fill without fighting layout); the stance row and combo pips join `_status_row` the same way
## the key row does.
func _ensure_combat_readouts() -> void:
	if _stamina_ghost == null and _stamina_bar:
		_stamina_ghost = ColorRect.new()
		_stamina_ghost.name = "StaminaCostGhost"
		_stamina_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stamina_ghost.color = Color(0.9, 0.85, 0.2, 0.55)
		_stamina_ghost.visible = false
		_stamina_bar.add_child(_stamina_ghost)
	if _stance_row == null and _status_row:
		_stance_row = HBoxContainer.new()
		_stance_row.name = "StanceRow"
		_stance_row.add_theme_constant_override("separation", 4)
		_status_row.add_child(_stance_row)
		_two_hand_swatch = ColorRect.new()
		_two_hand_swatch.name = "TwoHand"
		_two_hand_swatch.custom_minimum_size = Vector2(10, 14)
		_two_hand_swatch.color = Color(0.8, 0.78, 0.7, 1.0)
		_two_hand_swatch.tooltip_text = "Two-handed"
		_two_hand_swatch.visible = false
		_stance_row.add_child(_two_hand_swatch)
		_infusion_swatch = ColorRect.new()
		_infusion_swatch.name = "Infusion"
		_infusion_swatch.custom_minimum_size = Vector2(10, 14)
		_infusion_swatch.visible = false
		_stance_row.add_child(_infusion_swatch)
		_art_cooldown_bar = ProgressBar.new()
		_art_cooldown_bar.name = "ArtCooldown"
		_art_cooldown_bar.custom_minimum_size = Vector2(28, 6)
		_art_cooldown_bar.show_percentage = false
		_apply_bar_style(_art_cooldown_bar, Color(0.7, 0.62, 0.3, 1.0), Color(0.1, 0.09, 0.05, 0.9))
		_art_cooldown_bar.visible = false
		_stance_row.add_child(_art_cooldown_bar)
	if _combo_pip_row == null and _status_row:
		_combo_pip_row = HBoxContainer.new()
		_combo_pip_row.name = "ComboPips"
		_combo_pip_row.add_theme_constant_override("separation", 2)
		_status_row.add_child(_combo_pip_row)
		var pip_size := StatusIconAtlasScript.icon_size()
		for i in COMBO_PIP_COUNT:
			var pip := GameUISkinScript.make_symbol_rect(HudIconAtlasScript.get_pip_empty(), pip_size)
			pip.custom_minimum_size = Vector2(8, 8)
			_combo_pip_row.add_child(pip)
			_combo_pips_ui.append(pip)
		_combo_pip_row.visible = false


## HD-06: run on the same slow tick as the danger chevrons -- none of these need per-frame
## precision, and `_weapon_controller` is only resolved once the player is bound.
func _update_combat_readouts() -> void:
	if _weapon_controller == null or not is_instance_valid(_weapon_controller):
		return
	_update_stamina_ghost()
	_update_stance_row()
	_update_combo_pips()


func _update_stamina_ghost() -> void:
	if _stamina_ghost == null or _stamina_bar == null:
		return
	var cost: float = _weapon_controller.call("get_next_attack_cost")
	if cost <= 0.0 or _stamina_bar.max_value <= 0.0:
		_stamina_ghost.visible = false
		return
	var ratio := clampf(cost / _stamina_bar.max_value, 0.0, 1.0)
	var current_ratio := clampf(_stamina_bar.value / _stamina_bar.max_value, 0.0, 1.0)
	var bar_size := _stamina_bar.size
	var ghost_width := bar_size.x * ratio
	var ghost_start := bar_size.x * maxf(0.0, current_ratio - ratio)
	_stamina_ghost.position = Vector2(ghost_start, 0.0)
	_stamina_ghost.size = Vector2(ghost_width, bar_size.y)
	_stamina_ghost.color = (
		Color(0.86, 0.3, 0.24, 0.6) if cost > _stamina_bar.value else Color(0.9, 0.85, 0.2, 0.55)
	)
	_stamina_ghost.visible = true


func _update_stance_row() -> void:
	if _stance_row == null:
		return
	var two_handed: bool = _weapon_controller.call("is_two_handed")
	_two_hand_swatch.visible = two_handed
	var infusion: String = _weapon_controller.call("get_infusion")
	if infusion != "" and ELEMENT_COLORS.has(infusion):
		_infusion_swatch.color = ELEMENT_COLORS[infusion]
		_infusion_swatch.tooltip_text = infusion.capitalize()
		_infusion_swatch.visible = true
	else:
		_infusion_swatch.visible = false
	var cooldown_total: float = _weapon_controller.call("get_weapon_art_cooldown_duration")
	var cooldown_left: float = _weapon_controller.call("get_art_cooldown_remaining")
	if cooldown_total > 0.0 and cooldown_left > 0.0:
		_art_cooldown_bar.max_value = cooldown_total
		_art_cooldown_bar.value = cooldown_left
		_art_cooldown_bar.visible = true
	else:
		_art_cooldown_bar.visible = false


func _update_combo_pips() -> void:
	if _combo_pip_row == null:
		return
	var index: int = _weapon_controller.call("get_combo_index")
	_combo_pip_row.visible = index > 0
	for i in _combo_pips_ui.size():
		var lit := i < index
		(_combo_pips_ui[i] as TextureRect).texture = (
			HudIconAtlasScript.get_pip_filled() if lit else HudIconAtlasScript.get_pip_empty()
		)


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
			_update_build_up_warning(status_id, bar, ratio)
	for status_id in _build_up_rows.keys():
		if seen.has(status_id):
			continue
		var stale: Control = _build_up_rows[status_id]
		if is_instance_valid(stale):
			stale.queue_free()
		_build_up_rows.erase(status_id)
		_build_up_warned.erase(status_id)
	_build_up_box.visible = not _build_up_rows.is_empty()


## CB-08: flashes on crossing the threshold rather than every frame past it -- a continuous flash
## once in the danger zone would drown itself out; the moment of crossing is the useful signal.
func _update_build_up_warning(status_id: String, bar: ProgressBar, ratio: float) -> void:
	var in_warning := ratio >= BUILD_UP_WARNING_RATIO
	var was_warning := bool(_build_up_warned.get(status_id, false))
	if in_warning and not was_warning:
		_build_up_warned[status_id] = true
		var tween := create_tween()
		tween.set_loops(3)
		tween.tween_property(bar, "modulate", Color(1.4, 0.5, 0.4), 0.12)
		tween.tween_property(bar, "modulate", Color.WHITE, 0.12)
		# Reuses the same rising-tension cue a telegraphed attack's wind-up already plays, rather
		# than inventing a new placeholder sound this project's audio bank otherwise has none of.
		AudioDirector.play_sfx("windup")
	elif not in_warning and was_warning:
		_build_up_warned.erase(status_id)
		bar.modulate = Color.WHITE


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
	# CB-08: a distinct, persistent screen treatment per debuff -- burn/freeze/poison should be
	# visible without reading the status row.
	PixelDioramaSettings.apply_status_screen_grade(active_ids.keys())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_update_health_trail(delta)
	if not is_visible_in_tree():
		set_process(false)
		return
	_vignette_cooldown = maxf(0.0, _vignette_cooldown - delta)
	_update_lock_reticle()
	_update_bow_reticle()
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
		_update_danger_chevrons()
		_update_controls_hint_visibility(delta)
		_update_combat_readouts()


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


## `is_miniboss`: `BS-06`'s smaller bar with no phase pips, for a miniboss rather than the floor
## boss -- see the field comment on `_boss_bar_is_mini`.
func bind_boss(boss: Node, is_miniboss: bool = false) -> void:
	_unbind_boss()
	if boss == null or not is_instance_valid(boss):
		return
	_boss_node = boss
	_boss_health = boss.get_node_or_null("Health") as Health
	if _boss_health == null:
		return
	_boss_bar_is_mini = is_miniboss
	_boss_health_bar.custom_minimum_size = MINIBOSS_BAR_SIZE if is_miniboss else BOSS_BAR_SIZE
	_boss_phase_count = 1 if is_miniboss else _resolve_boss_phase_count(boss)
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
	GameUISkinScript.sync_progress_bar_step(_boss_health_bar)
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
	if _boss_bar_is_mini:
		return
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
	var hurtbox := _player.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox and not hurtbox.hurt_received.is_connected(_on_player_hurt_direction):
		hurtbox.hurt_received.connect(_on_player_hurt_direction)
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
	_label_bar(_poise_bar, "PO")


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
	GameUISkinScript.sync_progress_bar_step(_poise_bar)
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


func _bind_arrow_charges() -> void:
	if _arrow_charge_row != null or _heal_charge_row == null:
		return
	_arrow_charge_row = ArrowChargeMeterScript.bind(
		_player, _heal_charge_row, _on_arrow_charges_changed
	)


func _on_arrow_charges_changed(current: int, max_value: int) -> void:
	ArrowChargeMeterScript.refresh(_arrow_charge_row, current, max_value)


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


const BOW_RETICLE_MAX_RANGE := 40.0
const BOW_RETICLE_ORIGIN_HEIGHT := 1.2


## `RG-01`: a raycast along the aim direction rather than the `PH-04` ballistic solve -- the arrow's
## own arc is shallow enough at bow range that a straight line reads as "where it will land" without
## needing to duplicate `Projectile._solved_launch_velocity()` here.
func _update_bow_reticle() -> void:
	if _bow_reticle == null:
		return
	if _weapon_controller == null or not _weapon_controller.is_bow_aiming:
		_bow_reticle.visible = false
		return
	if _player == null or not is_instance_valid(_player):
		_bow_reticle.visible = false
		return
	var camera := _get_camera()
	if camera == null:
		_bow_reticle.visible = false
		return
	var origin := _player.global_position + Vector3(0.0, BOW_RETICLE_ORIGIN_HEIGHT, 0.0)
	var direction: Vector3 = _weapon_controller.get_soft_lock_aim_direction()
	var target_point := origin + direction * BOW_RETICLE_MAX_RANGE
	var space := _player.get_world_3d().direct_space_state if _player.get_world_3d() else null
	if space:
		var params := PhysicsRayQueryParameters3D.create(origin, target_point)
		params.collision_mask = CombatLayers.WORLD_OCCLUDERS
		params.collide_with_areas = false
		params.collide_with_bodies = true
		var result := space.intersect_ray(params)
		if not result.is_empty():
			target_point = result.get("position", target_point)
	if camera.is_position_behind(target_point):
		_bow_reticle.visible = false
		return
	_bow_reticle.visible = true
	var screen_pos := camera.unproject_position(target_point)
	_bow_reticle.position = screen_pos - _bow_reticle.size * 0.5
	_bow_reticle.set_charge(_weapon_controller.get_draw_charge())


func _get_camera() -> Camera3D:
	if _camera and is_instance_valid(_camera):
		return _camera
	_camera = PixelDioramaViewport.get_gameplay_camera()
	return _camera


func _on_health_changed(current: float, max_value: float) -> void:
	_health_bar.max_value = max_value
	GameUISkinScript.sync_progress_bar_step(_health_bar)
	_health_bar.value = current
	if _health_trail != null and is_instance_valid(_health_trail):
		_health_trail.max_value = max_value
		GameUISkinScript.sync_progress_bar_step(_health_trail)
		if current > _health_trail.value:
			_health_trail.value = current
		elif current < _last_health:
			_health_trail_hold = HEALTH_TRAIL_DELAY
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
	GameUISkinScript.sync_progress_bar_step(_stamina_bar)
	_stamina_bar.value = current


func _on_mana_changed(current: float, max_value: float) -> void:
	_mana_bar.max_value = max_value
	GameUISkinScript.sync_progress_bar_step(_mana_bar)
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


func set_minimap_floor_number(floor_number: int) -> void:
	if _minimap and _minimap.has_method("set_floor_number"):
		_minimap.call("set_floor_number", floor_number)


## AD-03: the generator already varies floors meaningfully (a floor theme from `room_pacing.json`
## plus whatever `RunModifierService` modifiers are active this run); this is the persistent
## legibility for it that used to only exist for 3.2s in the region banner subtitle. Each chip is a
## short abbreviation rather than a real icon -- no per-modifier art exists yet -- with the full
## description on hover/focus via the engine's own tooltip.
func set_floor_modifiers(theme_label: String, modifier_ids: Array, theme_description: String = "") -> void:
	if _modifier_strip == null:
		return
	for child in _modifier_strip.get_children():
		child.queue_free()
	if theme_label != "":
		_modifier_strip.add_child(_make_modifier_chip(theme_label, theme_description))
	for modifier_id in modifier_ids:
		var id := str(modifier_id)
		_modifier_strip.add_child(_make_modifier_chip(id, RunModifierService.describe(id)))


func _make_modifier_chip(id: String, tooltip: String) -> Control:
	var panel := PanelContainer.new()
	panel.tooltip_text = tooltip if tooltip != "" else id
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.08, 0.85)
	style.set_content_margin_all(3.0)
	style.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	var glyph := id.replace("_", " ")
	label.text = glyph.substr(0, 1).to_upper() if glyph.length() <= 1 else glyph.split(" ")[0].substr(0, 3).to_upper()
	label.add_theme_font_size_override("font_size", 10)
	panel.add_child(label)
	return panel


## HD-05: the Vigil arena has no room graph, so it gets a radar (arena bounds, live enemies,
## pending spawns) instead of the dungeon minimap -- called once by `waves_run.gd`, overriding the
## anchor visibility `configure_for_mode("waves")` hid.
func enable_arena_radar(half_extent: float) -> void:
	if _minimap and _minimap.has_method("enable_radar_mode"):
		_minimap.call("enable_radar_mode", half_extent)
	if _minimap_anchor:
		_minimap_anchor.visible = true
	_bind_minimap_player()


func set_radar_spawn_markers(markers: Array) -> void:
	if _minimap and _minimap.has_method("set_radar_spawn_markers"):
		_minimap.call("set_radar_spawn_markers", markers)


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
	_enqueue_banner({
		"kind": "region",
		"priority": BANNER_PRIORITY_REGION,
		"title": title,
		"subtitle": subtitle,
	})


## HD-02: inserts by priority (higher priority drains first), FIFO within the same priority.
func _enqueue_banner(entry: Dictionary) -> void:
	var insert_at := _banner_queue.size()
	for i in _banner_queue.size():
		if int(_banner_queue[i]["priority"]) < int(entry["priority"]):
			insert_at = i
			break
	_banner_queue.insert(insert_at, entry)
	if not _banner_draining:
		_drain_banner_queue()


func _drain_banner_queue() -> void:
	_banner_draining = true
	while not _banner_queue.is_empty():
		var entry: Dictionary = _banner_queue.pop_front()
		match str(entry["kind"]):
			"region":
				await _play_region_banner(str(entry["title"]), str(entry.get("subtitle", "")))
			"warning":
				await _play_warning_banner(str(entry["message"]))
	_banner_draining = false


func _play_region_banner(title: String, subtitle: String) -> void:
	_ensure_region_banner()
	_region_title_label.text = title
	_region_subtitle_label.text = subtitle
	_region_subtitle_label.visible = subtitle != ""
	_region_banner.visible = true
	_region_banner.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_region_banner, "modulate:a", 1.0, 0.6)
	tween.tween_interval(maxf(BANNER_MIN_DISPLAY, 3.2))
	tween.tween_property(_region_banner, "modulate:a", 0.0, 0.8)
	await tween.finished
	if _region_banner:
		_region_banner.visible = false


## A floor entry used to be one plain line of body text -- legible, but no different from a hint
## the game shows anywhere else, and a new floor is the one moment the run stops to say "this is
## where you are now." The gold flourish bars either side of the title borrow the same accent used
## on the pause menu's "RUN INFO" plaque, so the announcement reads as an inscription rather than a
## toast, and the title carries an outline so it stays legible over whatever the floor looks like.
func _ensure_region_banner() -> void:
	if _region_banner != null and is_instance_valid(_region_banner):
		return
	_region_banner = VBoxContainer.new()
	_region_banner.name = "RegionBanner"
	_region_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_region_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_region_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_region_banner.add_theme_constant_override("separation", 4)
	_region_banner.visible = false
	add_child(_region_banner)

	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 10)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_region_banner.add_child(title_row)

	var left_flourish := ColorRect.new()
	left_flourish.custom_minimum_size = Vector2(28, 3)
	left_flourish.color = GameUISkinScript.GOLD
	left_flourish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(left_flourish)

	_region_title_label = Label.new()
	_region_title_label.name = "Title"
	_region_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.style_menu_title(_region_title_label)
	_region_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_region_title_label.add_theme_constant_override("outline_size", 5)
	title_row.add_child(_region_title_label)

	var right_flourish := ColorRect.new()
	right_flourish.custom_minimum_size = Vector2(28, 3)
	right_flourish.color = GameUISkinScript.GOLD
	right_flourish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(right_flourish)

	_region_subtitle_label = Label.new()
	_region_subtitle_label.name = "Subtitle"
	_region_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_region_subtitle_label.visible = false
	GameUISkinScript.style_hint_label(_region_subtitle_label)
	_region_subtitle_label.add_theme_color_override(
		"font_outline_color", Color(0.0, 0.0, 0.0, 0.85)
	)
	_region_subtitle_label.add_theme_constant_override("outline_size", 4)
	_region_banner.add_child(_region_subtitle_label)


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
	var viewport_size := get_viewport_rect().size
	var center := viewport_size * 0.5
	var screen_pos := ScreenEdgeScript.edge_position(
		camera.unproject_position(_objective_world_pos),
		viewport_size,
		camera.is_position_behind(_objective_world_pos)
	)
	_objective_marker.visible = true
	_objective_marker.position = (screen_pos - _objective_marker.size * 0.5).floor()
	_objective_marker.rotation = (screen_pos - center).angle() + PI * 0.5


## `EN-09`: the archer winding up behind you gets a chevron on the screen edge a beat before the
## arrow arrives, the same way the objective marker already tells you where to walk. Runs on the
## HUD's existing slow tick (0.1 s) rather than a new per-frame process -- a wind-up lasts
## 0.4-1.5 s, so that cadence is imperceptible here.
func _update_danger_chevrons() -> void:
	if _player == null or _danger_chevrons.is_empty():
		return
	var camera := _get_camera()
	if camera == null:
		return
	var telegraphing := get_tree().get_nodes_in_group("telegraphing")
	var player_pos := _player.global_position
	var entries: Array = []
	for node in telegraphing:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if not node.has_method("telegraphed_attack_class"):
			continue
		var dist_sq := player_pos.distance_squared_to((node as Node3D).global_position)
		entries.append({"node": node, "dist_sq": dist_sq})
	entries.sort_custom(func(a, b): return float(a["dist_sq"]) < float(b["dist_sq"]))

	var viewport_size := get_viewport_rect().size
	var center := viewport_size * 0.5
	var shown := 0
	for entry in entries:
		if shown >= MAX_DANGER_CHEVRONS:
			break
		var enemy: Node3D = entry["node"]
		var world_pos := enemy.global_position
		var screen_pos := camera.unproject_position(world_pos)
		var behind := camera.is_position_behind(world_pos)
		if not behind and Rect2(Vector2.ZERO, viewport_size).has_point(screen_pos):
			# On-screen threats are already covered by the ground telegraph and the intent glyph
			# over the enemy's own head -- the chevron is only for what you cannot already see.
			continue
		screen_pos = ScreenEdgeScript.edge_position(screen_pos, viewport_size, behind)
		var chevron := _danger_chevrons[shown]
		var attack_class := str(enemy.call("telegraphed_attack_class"))
		chevron.modulate = AccessibilitySettings.get_telegraph_class_color(attack_class)
		chevron.visible = true
		chevron.position = (screen_pos - chevron.size * 0.5).floor()
		chevron.rotation = (screen_pos - center).angle() + PI * 0.5
		shown += 1
	for i in range(shown, _danger_chevrons.size()):
		_danger_chevrons[i].visible = false


## HD-07: a short arc at the screen edge, in the bearing the hit came from, fading over 0.6 s. The
## bearing is computed by treating the hit direction as pointing at a synthetic world point behind
## the player and reusing `ScreenEdge.edge_position()` -- the same clamp the objective marker and
## danger chevrons use, rather than a bespoke camera-forward/right dot-product calculation. This
## also naturally computes the bearing against the camera, not the player's facing, since the
## clamp already projects through `camera.unproject_position()`.
func _on_player_hurt_direction(_amount: float, _poise_damage: float, direction: Vector3) -> void:
	if direction.length_squared() < 0.01 or _player == null:
		return
	var camera := _get_camera()
	if camera == null:
		return
	_ensure_damage_arc()
	var source_pos := _player.global_position - direction.normalized() * 10.0
	var viewport_size := get_viewport_rect().size
	var center := viewport_size * 0.5
	var screen_pos := ScreenEdgeScript.edge_position(
		camera.unproject_position(source_pos), viewport_size, camera.is_position_behind(source_pos)
	)
	_damage_arc.position = center
	_damage_arc.radius = minf(viewport_size.x, viewport_size.y) * 0.42
	_damage_arc.bearing = (screen_pos - center).angle()
	_damage_arc.alpha = 1.0
	_damage_arc.queue_redraw()
	var arc := _damage_arc
	var tween := create_tween()
	var set_alpha := func(a: float) -> void:
		if arc:
			arc.alpha = a
			arc.queue_redraw()
	tween.tween_method(set_alpha, 1.0, 0.0, 0.6)


func _ensure_damage_arc() -> void:
	if _damage_arc != null:
		return
	_damage_arc = Control.new()
	_damage_arc.name = "DamageDirectionArc"
	_damage_arc.set_script(DamageDirectionArcScript)
	_damage_arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_arc)


func show_run_warning(message: String) -> void:
	if message == "":
		return
	_enqueue_banner({
		"kind": "warning",
		"priority": BANNER_PRIORITY_WARNING,
		"message": message,
	})


func show_inline_warning(message: String) -> void:
	if message == "" or _inline_warning == null:
		return
	_inline_queue.append(message)
	if not _inline_draining:
		_drain_inline_queue()


func _drain_inline_queue() -> void:
	_inline_draining = true
	while not _inline_queue.is_empty():
		var message: String = _inline_queue.pop_front()
		_inline_warning.text = message
		_inline_warning.visible = true
		_inline_warning.modulate.a = 1.0
		var tween := create_tween()
		tween.tween_interval(INLINE_MIN_DISPLAY)
		tween.tween_property(_inline_warning, "modulate:a", 0.0, 0.4)
		await tween.finished
	_inline_draining = false
	if _inline_warning:
		_inline_warning.visible = false


func _play_warning_banner(message: String) -> void:
	_warning_banner.text = message
	_warning_banner.visible = true
	_warning_banner.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(maxf(BANNER_MIN_DISPLAY, 4.0))
	tween.tween_property(_warning_banner, "modulate:a", 0.0, 0.5)
	await tween.finished
	if _warning_banner:
		_warning_banner.visible = false


## HD-04: hides what a mode does not have rather than leaving it unconfigured, against exactly
## this table --
##
## | Element                       | castle           | endless        | waves              |
## |--------------------------------|------------------|----------------|--------------------|
## | HP / SP / MP / Poise / XP      | shown            | shown          | shown              |
## | Status pips + build-up meters  | shown            | shown          | shown              |
## | Heal charges                   | shown            | shown          | shown              |
## | Quick slots                    | shown            | shown          | shown              |
## | Lock reticle / guard bars      | shown            | shown          | shown              |
## | Boss bar + phase pips          | shown            | shown          | shown (boss waves) |
## | Minimap + map overlay          | shown            | shown          | hidden (one arena) |
## | Objective marker               | stairs/boss      | stairs         | cresset / portal   |
## | Objective text                 | "Floor N -- ..."  | "Depth N -- .."| "Wave N -- M left" |
## | Key row                        | shown            | shown          | hidden             |
## | Branch previews                | shown            | shown          | hidden             |
## | Region title                   | floor + theme    | biome + depth  | wave banner        |
## | Warning banner                 | shown            | shown          | shown              |
## | Respawn outcome                | shown            | shown          | shown              |
##
## "waves" has no floor/map to show a minimap, branch preview or key ring for; "castle" and
## "endless" share the dungeon HUD wiring already and need nothing hidden here.
func configure_for_mode(run_mode: String) -> void:
	if run_mode != "waves":
		return
	if _minimap_anchor:
		_minimap_anchor.visible = false
	if _branch_banner:
		_branch_banner.visible = false
	if _key_row:
		_key_row.visible = false


var _objective_label: Label


## HD-01: a text objective line, distinct from `set_objective_world_position()`'s direction arrow
## -- Waves has no floor to point an arrow across, but "Wave 7 of 10" or "Defeat the warden" is
## still worth a line. Reuses the same dynamically-created-once pattern as `_ensure_key_row()`.
func set_objective_text(text: String) -> void:
	if _objective_label == null:
		_objective_label = Label.new()
		_objective_label.name = "ObjectiveLabel"
		GameUISkinScript.style_body_label(_objective_label)
		var vbox: Node = _status_row.get_parent() if _status_row else null
		if vbox:
			vbox.add_child(_objective_label)
		else:
			add_child(_objective_label)
	_objective_label.text = text
	_objective_label.visible = text != ""


func show_respawn_outcome(results: Dictionary) -> void:
	var xp_gained: int = int(results.get("xp_gained", 0))
	var xp_deferred: int = int(results.get("xp_deferred", 0))
	var loot_lost: Array = results.get("loot_lost", [])
	var lines: PackedStringArray = []
	var recap: Dictionary = results.get("death_recap", {})
	var recap_sentence := str(recap.get("sentence", ""))
	if recap_sentence != "":
		lines.append(recap_sentence)
	lines.append(tr("RESPAWN_XP_GAINED").format({"xp": xp_gained}))
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
		show_inline_warning(tr("WARN_INVENTORY_FULL"))


func _on_save_failed(reason: String) -> void:
	match reason:
		"write_failed":
			show_inline_warning(tr("WARN_SAVE_WRITE_FAILED"))
		"save_from_newer_build":
			show_inline_warning(tr("WARN_SAVE_FROM_NEWER_BUILD"))
		_:
			show_inline_warning(tr("WARN_SAVE_FAILED_REASON").format({"reason": reason}))


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
