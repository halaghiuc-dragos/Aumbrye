extends Node

## Autoload — window, vsync, monitor, frame cap, UI scale, and HUD safe area.

signal display_changed(field: StringName, value: Variant)
signal fullscreen_confirm_needed

const SAVE_KEY := "display"

const SCALE_MIN := 0.75
const SCALE_MAX := 1.75
const SCALE_STEP := 0.05

const WINDOW_MODE_WINDOWED := "windowed"
const WINDOW_MODE_BORDERLESS := "borderless"
const WINDOW_MODE_FULLSCREEN := "fullscreen"

const VSYNC_DISABLED := "disabled"
const VSYNC_ENABLED := "enabled"
const VSYNC_ADAPTIVE := "adaptive"

const FPS_MIN := 30
const MAX_FPS_MAX := 360

const HUD_SAFE_AREA_MAX := 0.1
const FULLSCREEN_CONFIRM_SEC := 10.0

const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(3840, 2160),
	Vector2i(2560, 1440),
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
	Vector2i(960, 540),
]

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

var window_mode: String = WINDOW_MODE_WINDOWED
var window_size: Vector2i = Vector2i(1920, 1080)
var monitor_index: int = 0
var vsync_mode: String = VSYNC_ENABLED
var max_fps: int = 0
var ui_scale: float = 1.0
var hud_safe_area: float = 0.0

var ui_text_scale: float = 1.0
var fullscreen_confirm_sec: float = FULLSCREEN_CONFIRM_SEC

var _fullscreen_revert_mode: String = WINDOW_MODE_WINDOWED
var _pending_fullscreen_confirm := false
var _fullscreen_timer: SceneTreeTimer
var _fullscreen_token := 0
var _scaled_theme: Theme


func _ready() -> void:
	load_from_save()
	apply_all()


func load_from_save() -> void:
	var meta := LocalSave.get_meta_data()
	var data: Variant = meta.get(SAVE_KEY, {})
	if data is Dictionary and not data.is_empty():
		_deserialize(data)
	else:
		_migrate_ui_scale_from_accessibility(meta)
	sanitize_persisted_settings()


func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = serialize()
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()


func serialize() -> Dictionary:
	return {
		"window_mode": window_mode,
		"window_size": [window_size.x, window_size.y],
		"monitor_index": monitor_index,
		"vsync_mode": vsync_mode,
		"max_fps": max_fps,
		"ui_scale": ui_scale,
		"hud_safe_area": hud_safe_area,
	}


func apply_all() -> void:
	_apply_monitor()
	_apply_window_mode()
	_apply_window_size()
	_apply_vsync()
	_apply_max_fps()
	_apply_ui_scale()
	display_changed.emit(&"all", null)


func set_window_mode(mode: String) -> void:
	mode = _parse_window_mode(mode)
	if mode == WINDOW_MODE_FULLSCREEN and window_mode != WINDOW_MODE_FULLSCREEN:
		_fullscreen_revert_mode = window_mode
		_pending_fullscreen_confirm = true
		window_mode = mode
		apply_all()
		_start_fullscreen_timer()
		fullscreen_confirm_needed.emit()
		display_changed.emit(&"window_mode", window_mode)
		return
	_cancel_fullscreen_timer()
	_pending_fullscreen_confirm = false
	window_mode = mode
	apply_all()
	save()
	display_changed.emit(&"window_mode", window_mode)


func confirm_fullscreen() -> void:
	if not _pending_fullscreen_confirm:
		return
	_pending_fullscreen_confirm = false
	_cancel_fullscreen_timer()
	save()


## Goes straight back to the mode in use before fullscreen was chosen, without waiting out the
## countdown. This is what the settings prompt calls when the player says the mode is unusable.
func revert_fullscreen() -> void:
	if not _pending_fullscreen_confirm:
		return
	_pending_fullscreen_confirm = false
	_cancel_fullscreen_timer()
	window_mode = _fullscreen_revert_mode if _fullscreen_revert_mode != "" else WINDOW_MODE_WINDOWED
	apply_all()
	save()
	display_changed.emit(&"window_mode", window_mode)


func set_monitor_index(index: int) -> void:
	monitor_index = index
	apply_all()
	save()
	display_changed.emit(&"monitor_index", monitor_index)


func set_window_size(size: Vector2i) -> void:
	window_size = size
	window_mode = WINDOW_MODE_WINDOWED
	apply_all()
	save()
	display_changed.emit(&"window_size", window_size)


func set_vsync_mode(mode: String) -> void:
	vsync_mode = _parse_vsync_mode(mode)
	apply_all()
	save()
	display_changed.emit(&"vsync_mode", vsync_mode)


func set_max_fps(cap: int) -> void:
	max_fps = cap
	apply_all()
	save()
	display_changed.emit(&"max_fps", max_fps)


func set_ui_scale(scale: float) -> void:
	ui_scale = clampf(scale, SCALE_MIN, SCALE_MAX)
	_apply_ui_scale()
	save()
	display_changed.emit(&"ui_scale", ui_scale)


func set_hud_safe_area(value: float) -> void:
	hud_safe_area = clampf(value, 0.0, HUD_SAFE_AREA_MAX)
	apply_all()
	save()
	display_changed.emit(&"hud_safe_area", hud_safe_area)


func set_field(field: String, value: Variant) -> void:
	match field:
		"window_mode":
			set_window_mode(str(value))
		"window_size":
			if value is Vector2i:
				set_window_size(value)
			elif value is Array and value.size() >= 2:
				set_window_size(Vector2i(int(value[0]), int(value[1])))
		"monitor_index":
			set_monitor_index(int(value))
		"vsync_mode":
			set_vsync_mode(str(value))
		"max_fps":
			set_max_fps(int(value))
		"ui_scale":
			set_ui_scale(float(value))
		"hud_safe_area":
			set_hud_safe_area(float(value))
		_:
			pass


func sanitize_persisted_settings_for_test() -> void:
	sanitize_persisted_settings()


func sanitize_persisted_settings() -> void:
	var screen_count := DisplayServer.get_screen_count()
	if monitor_index < 0 or monitor_index >= screen_count:
		monitor_index = 0
	if not window_size_fits_any_monitor(window_size):
		window_size = _largest_fitting_16_9()
		window_mode = WINDOW_MODE_WINDOWED
		push_warning(
			"DisplayService: persisted window size does not fit any monitor; using %dx%d windowed"
			% [window_size.x, window_size.y]
		)


func window_size_fits_any_monitor(size: Vector2i) -> bool:
	for screen in DisplayServer.get_screen_count():
		var rect := DisplayServer.screen_get_usable_rect(screen)
		if size.x <= int(rect.size.x) and size.y <= int(rect.size.y):
			return true
	return false


## Headless has no screens: `screen_get_usable_rect()` crashes the engine there rather than
## returning an empty rect, which aborted the whole validation run inside m6_suite
## (settings_schema.entries() -> _monitor_row() -> _monitor_option_labels()).
func get_monitor_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	var count := DisplayServer.get_screen_count()
	if count <= 0 or DisplayServer.get_name() == "headless":
		return labels
	for i in count:
		var rect := DisplayServer.screen_get_usable_rect(i)
		labels.append("Monitor %d (%dx%d)" % [i + 1, rect.size.x, rect.size.y])
	return labels


func current_resolution_preset() -> int:
	for i in RESOLUTION_PRESETS.size():
		if RESOLUTION_PRESETS[i] == window_size:
			return i
	return -1


func defaults() -> Dictionary:
	return serialize()


static func _parse_window_mode(value: Variant) -> String:
	var mode := str(value)
	match mode:
		WINDOW_MODE_BORDERLESS, WINDOW_MODE_FULLSCREEN:
			return mode
		_:
			return WINDOW_MODE_WINDOWED


static func _parse_vsync_mode(value: Variant) -> String:
	var mode := str(value)
	match mode:
		VSYNC_DISABLED, VSYNC_ADAPTIVE:
			return mode
		_:
			return VSYNC_ENABLED


func _deserialize(block: Dictionary) -> void:
	window_mode = _parse_window_mode(block.get("window_mode", WINDOW_MODE_WINDOWED))
	var size_value: Variant = block.get("window_size", [1920, 1080])
	if size_value is Array and size_value.size() >= 2:
		window_size = Vector2i(int(size_value[0]), int(size_value[1]))
	monitor_index = int(block.get("monitor_index", 0))
	vsync_mode = _parse_vsync_mode(block.get("vsync_mode", VSYNC_ENABLED))
	max_fps = int(block.get("max_fps", 0))
	ui_scale = clampf(float(block.get("ui_scale", 1.0)), SCALE_MIN, SCALE_MAX)
	hud_safe_area = clampf(float(block.get("hud_safe_area", 0.0)), 0.0, HUD_SAFE_AREA_MAX)


func _migrate_ui_scale_from_accessibility(meta: Dictionary) -> void:
	var a11y: Variant = meta.get("accessibility", {})
	if a11y is Dictionary and a11y.has("ui_scale"):
		ui_scale = clampf(float(a11y.get("ui_scale", 1.0)), SCALE_MIN, SCALE_MAX)


func _largest_fitting_16_9() -> Vector2i:
	var best := Vector2i(1280, 720)
	var best_area := 0
	for screen in DisplayServer.get_screen_count():
		var rect := DisplayServer.screen_get_usable_rect(screen)
		for preset in RESOLUTION_PRESETS:
			if preset.x <= int(rect.size.x) and preset.y <= int(rect.size.y):
				var area := preset.x * preset.y
				if area > best_area:
					best_area = area
					best = preset
	return best


func _apply_monitor() -> void:
	var screen_count := DisplayServer.get_screen_count()
	if monitor_index < 0 or monitor_index >= screen_count:
		monitor_index = 0
	DisplayServer.window_set_current_screen(monitor_index)


func _apply_window_mode() -> void:
	match window_mode:
		WINDOW_MODE_BORDERLESS:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_window_size() -> void:
	if window_mode != WINDOW_MODE_WINDOWED:
		return
	var clamped := _clamp_to_usable_rect(window_size)
	window_size = clamped
	DisplayServer.window_set_size(clamped)


func _clamp_to_usable_rect(size: Vector2i) -> Vector2i:
	var rect := DisplayServer.screen_get_usable_rect(monitor_index)
	var max_w := maxi(320, int(rect.size.x))
	var max_h := maxi(240, int(rect.size.y))
	return Vector2i(clampi(size.x, 320, max_w), clampi(size.y, 240, max_h))


func _apply_vsync() -> void:
	match vsync_mode:
		VSYNC_DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VSYNC_ADAPTIVE:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


func _apply_max_fps() -> void:
	if max_fps <= 0:
		Engine.max_fps = 0
	else:
		Engine.max_fps = clampi(max_fps, FPS_MIN, MAX_FPS_MAX)


func _apply_ui_scale() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var viewport_scale := 2 if ui_scale >= 2.0 else 1
	ui_text_scale = ui_scale / float(viewport_scale)
	tree.root.content_scale_factor = float(viewport_scale)
	_scaled_theme = GameUISkinScript.build_scaled_theme(ui_text_scale)
	tree.root.theme = _scaled_theme
	UITextScale.apply_all()
	display_changed.emit(&"ui_scale", ui_scale)


func _start_fullscreen_timer() -> void:
	_cancel_fullscreen_timer()
	if get_tree() == null:
		return
	_fullscreen_token += 1
	_fullscreen_timer = get_tree().create_timer(fullscreen_confirm_sec)
	_fullscreen_timer.timeout.connect(
		_on_fullscreen_confirm_timeout.bind(_fullscreen_token), CONNECT_ONE_SHOT
	)


## Dropping the SceneTreeTimer reference does not stop it — the timeout still fires. Each countdown
## therefore carries a token, and a stale one is ignored; otherwise a player who switched to
## fullscreen, back, and to fullscreen again could have the first countdown revert the second.
func _cancel_fullscreen_timer() -> void:
	_fullscreen_token += 1
	_fullscreen_timer = null


func _on_fullscreen_confirm_timeout(token: int) -> void:
	if token != _fullscreen_token:
		return
	if not _pending_fullscreen_confirm:
		return
	_pending_fullscreen_confirm = false
	window_mode = _fullscreen_revert_mode if _fullscreen_revert_mode != "" else WINDOW_MODE_WINDOWED
	apply_all()
	save()
	display_changed.emit(&"window_mode", window_mode)
