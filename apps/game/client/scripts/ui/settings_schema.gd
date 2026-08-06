extends RefCounted
class_name SettingsSchema

## Declarative settings rows for the tabbed settings UI (SET-01, SET-13, SET-14).

const PAGES: PackedStringArray = [
	"gameplay",
	"display",
	"audio",
	"controls",
	"accessibility",
	"advanced",
]


static func entries() -> Array[Dictionary]:
	return [
		# Gameplay
		_language_row(),
		_leaderboard_row(),
		# Display
		_window_mode_row(),
		_monitor_row(),
		_vsync_row(),
		_max_fps_row(),
		_ui_scale_row(),
		# Audio
		_volume_row("master_volume", "master"),
		_volume_row("music_volume", "music"),
		_volume_row("sfx_volume", "sfx"),
		_volume_row("ambience_volume", "ambience"),
		_volume_row("ui_volume", "ui"),
		# Accessibility
		_toggle_row(
			"reduce_camera_shake",
			"accessibility",
			func() -> bool: return AccessibilitySettings.reduce_camera_shake,
			func(v: bool) -> void:
				AccessibilitySettings.reduce_camera_shake = v
				AccessibilitySettings.apply_live("reduce_camera_shake", v)
				AccessibilitySettings.request_commit()
		),
		_toggle_row(
			"show_control_hints",
			"accessibility",
			func() -> bool: return AccessibilitySettings.show_control_hints,
			func(v: bool) -> void:
				AccessibilitySettings.show_control_hints = v
				AccessibilitySettings.apply_live("show_control_hints", v)
				AccessibilitySettings.request_commit()
		),
		_slider_row(
			"subtitle_scale",
			"accessibility",
			0.8,
			1.6,
			0.05,
			"multiplier",
			func() -> float: return AccessibilitySettings.subtitle_scale,
			func(v: float) -> void:
				AccessibilitySettings.subtitle_scale = v
				AccessibilitySettings.apply_live("subtitle_scale", v)
				_refresh_dialogue(),
			func() -> void: AccessibilitySettings.request_commit()
		),
		_slider_row(
			"vibration_intensity",
			"accessibility",
			0.0,
			1.0,
			0.05,
			"percent",
			func() -> float: return AccessibilitySettings.vibration_intensity,
			func(v: float) -> void:
				AccessibilitySettings.vibration_intensity = v
				AccessibilitySettings.apply_live("vibration_intensity", v),
			func() -> void: AccessibilitySettings.request_commit()
		),
		_colorblind_row(),
		_slider_row(
			"camera_mouse_sensitivity",
			"accessibility",
			AccessibilitySettings.CAMERA_MOUSE_MIN,
			AccessibilitySettings.CAMERA_MOUSE_MAX,
			0.05,
			"multiplier",
			func() -> float: return AccessibilitySettings.camera_mouse_sensitivity,
			func(v: float) -> void:
				AccessibilitySettings.camera_mouse_sensitivity = v
				AccessibilitySettings.apply_live("camera_mouse_sensitivity", v),
			func() -> void: AccessibilitySettings.request_commit()
		),
		_slider_row(
			"camera_stick_sensitivity",
			"accessibility",
			AccessibilitySettings.CAMERA_STICK_MIN,
			AccessibilitySettings.CAMERA_STICK_MAX,
			0.05,
			"multiplier",
			func() -> float: return AccessibilitySettings.camera_stick_sensitivity,
			func(v: float) -> void:
				AccessibilitySettings.camera_stick_sensitivity = v
				AccessibilitySettings.apply_live("camera_stick_sensitivity", v),
			func() -> void: AccessibilitySettings.request_commit()
		),
		_slider_row(
			"camera_fov",
			"accessibility",
			AccessibilitySettings.CAMERA_FOV_MIN,
			AccessibilitySettings.CAMERA_FOV_MAX,
			1.0,
			"decimal1",
			func() -> float: return AccessibilitySettings.camera_fov,
			func(v: float) -> void:
				AccessibilitySettings.camera_fov = v
				AccessibilitySettings.apply_live("camera_fov", v),
			func() -> void: AccessibilitySettings.request_commit()
		),
		_toggle_row(
			"camera_invert_y",
			"accessibility",
			func() -> bool: return AccessibilitySettings.camera_invert_y,
			func(v: bool) -> void:
				AccessibilitySettings.camera_invert_y = v
				AccessibilitySettings.apply_live("camera_invert_y", v)
				AccessibilitySettings.request_commit()
		),
	]


static func entries_for_page(page: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries():
		if str(entry.get("page", "")) == page:
			out.append(entry)
	return out


static func validate() -> Array[String]:
	var errors: PackedStringArray = []
	for entry in entries():
		var id := str(entry.get("id", ""))
		var name_key := str(entry.get("name_key", ""))
		var desc_key := str(entry.get("desc_key", ""))
		if name_key.is_empty() or desc_key.is_empty():
			errors.append("settings entry %s missing name_key or desc_key" % id)
	return errors


static func page_name_key(page: String) -> String:
	return "SETTINGS_PAGE_%s" % page.to_upper()


static func format_value(format_id: String, value: Variant) -> String:
	match format_id:
		"percent":
			return "%d%%" % int(roundf(float(value) * 100.0))
		"multiplier":
			return "%.2fx" % float(value)
		"decimal1":
			return "%.1f" % float(value)
		"decimal2":
			return "%.2f" % float(value)
		"enum":
			return str(value)
		"fps":
			var fps := int(value)
			return "Uncapped" if fps <= 0 else str(fps)
		_:
			return str(value)


static func _language_row() -> Dictionary:
	return {
		"id": "language",
		"page": "gameplay",
		"kind": "option",
		"name_key": "SETTINGS_LANGUAGE_NAME",
		"desc_key": "SETTINGS_LANGUAGE_DESC",
		"format": "enum",
		"default": "en",
		"options": ["en", "ro"],
		"option_labels": ["SETTINGS_LANGUAGE_EN", "SETTINGS_LANGUAGE_RO"],
		"getter": func() -> int: return 0 if LocaleSettings.locale == "en" else 1,
		"setter":
		func(idx: int) -> void: LocaleSettings.set_locale_code("en" if idx == 0 else "ro"),
	}


static func _leaderboard_row() -> Dictionary:
	return {
		"id": "leaderboard_opt_in",
		"page": "gameplay",
		"kind": "toggle",
		"name_key": "SETTINGS_LEADERBOARD_OPT_IN_NAME",
		"desc_key": "SETTINGS_LEADERBOARD_OPT_IN_DESC",
		"format": "enum",
		"default": false,
		"getter": func() -> bool: return LeaderboardSettings.opt_in,
		"setter":
		func(v: bool) -> void:
			LeaderboardSettings.opt_in = v
			LeaderboardSettings.save(),
	}


static func _window_mode_row() -> Dictionary:
	return {
		"id": "window_mode",
		"page": "display",
		"kind": "option",
		"name_key": "SETTINGS_WINDOW_MODE_NAME",
		"desc_key": "SETTINGS_WINDOW_MODE_DESC",
		"format": "enum",
		"default": "windowed",
		"options": ["windowed", "borderless", "fullscreen"],
		"option_labels": [
			"SETTINGS_WINDOW_MODE_WINDOWED",
			"SETTINGS_WINDOW_MODE_BORDERLESS",
			"SETTINGS_WINDOW_MODE_FULLSCREEN",
		],
		"getter":
		func() -> int:
			match DisplayService.window_mode:
				DisplayService.WINDOW_MODE_BORDERLESS:
					return 1
				DisplayService.WINDOW_MODE_FULLSCREEN:
					return 2
				_:
					return 0,
		"setter":
		func(idx: int) -> void:
			match idx:
				1:
					DisplayService.set_window_mode(DisplayService.WINDOW_MODE_BORDERLESS)
				2:
					DisplayService.set_window_mode(DisplayService.WINDOW_MODE_FULLSCREEN)
				_:
					DisplayService.set_window_mode(DisplayService.WINDOW_MODE_WINDOWED),
	}


static func _monitor_row() -> Dictionary:
	return {
		"id": "monitor_index",
		"page": "display",
		"kind": "option",
		"name_key": "SETTINGS_MONITOR_NAME",
		"desc_key": "SETTINGS_MONITOR_DESC",
		"format": "enum",
		"default": 0,
		"options": _monitor_option_labels(),
		"getter": func() -> int: return DisplayService.monitor_index,
		"setter": func(idx: int) -> void: DisplayService.set_monitor_index(idx),
	}


static func _monitor_option_labels() -> Array:
	var labels: Array = []
	for i in DisplayServer.get_screen_count():
		labels.append(DisplayServer.get_screen_name(i))
	return labels


static func _vsync_row() -> Dictionary:
	return {
		"id": "vsync_mode",
		"page": "display",
		"kind": "option",
		"name_key": "SETTINGS_VSYNC_NAME",
		"desc_key": "SETTINGS_VSYNC_DESC",
		"format": "enum",
		"default": "enabled",
		"options": ["disabled", "enabled", "adaptive"],
		"option_labels": [
			"SETTINGS_VSYNC_DISABLED",
			"SETTINGS_VSYNC_ENABLED",
			"SETTINGS_VSYNC_ADAPTIVE",
		],
		"getter":
		func() -> int:
			match DisplayService.vsync_mode:
				DisplayService.VSYNC_DISABLED:
					return 0
				DisplayService.VSYNC_ADAPTIVE:
					return 2
				_:
					return 1,
		"setter":
		func(idx: int) -> void:
			match idx:
				0:
					DisplayService.set_vsync_mode(DisplayService.VSYNC_DISABLED)
				2:
					DisplayService.set_vsync_mode(DisplayService.VSYNC_ADAPTIVE)
				_:
					DisplayService.set_vsync_mode(DisplayService.VSYNC_ENABLED),
	}


static func _max_fps_row() -> Dictionary:
	return {
		"id": "max_fps",
		"page": "display",
		"kind": "option",
		"name_key": "SETTINGS_MAX_FPS_NAME",
		"desc_key": "SETTINGS_MAX_FPS_DESC",
		"format": "fps",
		"default": 0,
		"options": [0, 30, 60, 120, 144, 240],
		"option_labels": [
			"SETTINGS_MAX_FPS_UNCAPPED",
			"SETTINGS_MAX_FPS_30",
			"SETTINGS_MAX_FPS_60",
			"SETTINGS_MAX_FPS_120",
			"SETTINGS_MAX_FPS_144",
			"SETTINGS_MAX_FPS_240",
		],
		"getter":
		func() -> int:
			var opts: Array = [0, 30, 60, 120, 144, 240]
			return opts.find(DisplayService.max_fps),
		"setter":
		func(idx: int) -> void:
			var opts: Array = [0, 30, 60, 120, 144, 240]
			DisplayService.set_max_fps(int(opts[idx])),
	}


static func _ui_scale_row() -> Dictionary:
	return {
		"id": "ui_scale",
		"page": "display",
		"kind": "slider",
		"name_key": "SETTINGS_UI_SCALE_NAME",
		"desc_key": "SETTINGS_UI_SCALE_DESC",
		"format": "percent",
		"default": 1.0,
		"range": {
			"min": DisplayService.SCALE_MIN,
			"max": DisplayService.SCALE_MAX,
			"step": DisplayService.SCALE_STEP,
		},
		"getter": func() -> float: return DisplayService.ui_scale,
		"setter": func(v: float) -> void: DisplayService.set_ui_scale(v),
		"commit": Callable(),
	}


static func _volume_row(id: String, bus_key: String) -> Dictionary:
	return {
		"id": id,
		"page": "audio",
		"kind": "slider",
		"name_key": "SETTINGS_%s_VOLUME_NAME" % bus_key.to_upper(),
		"desc_key": "SETTINGS_%s_VOLUME_DESC" % bus_key.to_upper(),
		"format": "percent",
		"default": 1.0,
		"range": {"min": 0.0, "max": 1.0, "step": 0.05},
		"getter":
		func() -> float:
			match bus_key:
				"master":
					return AudioSettings.master_volume
				"music":
					return AudioSettings.music_volume
				"sfx":
					return AudioSettings.sfx_volume
				"ambience":
					return AudioSettings.ambience_volume
				"ui":
					return AudioSettings.ui_volume
				_:
					return 1.0,
		"setter":
		func(v: float) -> void:
			match bus_key:
				"master":
					AudioSettings.master_volume = v
				"music":
					AudioSettings.music_volume = v
				"sfx":
					AudioSettings.sfx_volume = v
				"ambience":
					AudioSettings.ambience_volume = v
				"ui":
					AudioSettings.ui_volume = v
			AudioSettings.apply_live(id, v),
		"commit": func() -> void: AudioSettings.request_commit(),
	}


static func _colorblind_row() -> Dictionary:
	return {
		"id": "colorblind_mode",
		"page": "accessibility",
		"kind": "option",
		"name_key": "SETTINGS_COLORBLIND_MODE_NAME",
		"desc_key": "SETTINGS_COLORBLIND_MODE_DESC",
		"format": "enum",
		"default": "default",
		"options": ["default", "protanopia", "deuteranopia", "tritanopia"],
		"option_labels": [
			"SETTINGS_COLORBLIND_DEFAULT",
			"SETTINGS_COLORBLIND_PROTANOPIA",
			"SETTINGS_COLORBLIND_DEUTERANOPIA",
			"SETTINGS_COLORBLIND_TRITANOPIA",
		],
		"getter":
		func() -> int:
			var modes := ["default", "protanopia", "deuteranopia", "tritanopia"]
			return modes.find(AccessibilitySettings.colorblind_mode),
		"setter":
		func(idx: int) -> void:
			var modes := ["default", "protanopia", "deuteranopia", "tritanopia"]
			AccessibilitySettings.colorblind_mode = modes[idx]
			AccessibilitySettings.apply_live("colorblind_mode", modes[idx])
			AccessibilitySettings.request_commit(),
	}


static func _slider_row(
	id: String,
	page: String,
	min_v: float,
	max_v: float,
	step: float,
	format_id: String,
	getter: Callable,
	setter: Callable,
	commit: Callable
) -> Dictionary:
	return {
		"id": id,
		"page": page,
		"kind": "slider",
		"name_key": "SETTINGS_%s_NAME" % id.to_upper(),
		"desc_key": "SETTINGS_%s_DESC" % id.to_upper(),
		"format": format_id,
		"default": getter.call() if getter.is_valid() else min_v,
		"range": {"min": min_v, "max": max_v, "step": step},
		"getter": getter,
		"setter": setter,
		"commit": commit,
	}


static func _toggle_row(
	id: String, page: String, getter: Callable, setter: Callable
) -> Dictionary:
	return {
		"id": id,
		"page": page,
		"kind": "toggle",
		"name_key": "SETTINGS_%s_NAME" % id.to_upper(),
		"desc_key": "SETTINGS_%s_DESC" % id.to_upper(),
		"format": "enum",
		"default": false,
		"getter": getter,
		"setter": setter,
	}


static func _refresh_dialogue() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var dialogue_ui := tree.get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.has_method("refresh_accessibility"):
		dialogue_ui.call("refresh_accessibility")
