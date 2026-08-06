extends RefCounted
class_name AccessibilitySettings

## M6 accessibility baseline (A11Y-6.1).

const SAVE_KEY := "accessibility"

const CAMERA_MOUSE_MIN := 0.2
const CAMERA_MOUSE_MAX := 3.0
const CAMERA_MOUSE_DEFAULT := 1.0
const CAMERA_STICK_MIN := 0.2
const CAMERA_STICK_MAX := 3.0
const CAMERA_STICK_DEFAULT := 1.0
const CAMERA_FOV_MIN := 60.0
const CAMERA_FOV_MAX := 100.0
const CAMERA_FOV_DEFAULT := 70.0
const CAMERA_STICK_CURVE_MIN := 1.0
const CAMERA_STICK_CURVE_MAX := 3.0
const CAMERA_STICK_CURVE_DEFAULT := 2.0
const CAMERA_STICK_DEADZONE_MIN := 0.05
const CAMERA_STICK_DEADZONE_MAX := 0.35
const CAMERA_STICK_DEADZONE_DEFAULT := 0.15

static var ui_scale: float = 1.0
static var reduce_camera_shake: bool = false
static var reduce_hitstop: bool = false
static var colorblind_mode: String = "default"
static var subtitle_scale: float = 1.0
static var vibration_intensity: float = 1.0

static var camera_mouse_sensitivity: float = CAMERA_MOUSE_DEFAULT
static var camera_stick_sensitivity: float = CAMERA_STICK_DEFAULT
static var camera_invert_y: bool = false
static var camera_fov: float = CAMERA_FOV_DEFAULT
static var camera_stick_curve: float = CAMERA_STICK_CURVE_DEFAULT
static var camera_stick_deadzone: float = CAMERA_STICK_DEADZONE_DEFAULT

static var _settings_changed_listeners: Array[Callable] = []


static func connect_settings_changed(callback: Callable) -> void:
	if not _settings_changed_listeners.has(callback):
		_settings_changed_listeners.append(callback)


static func disconnect_settings_changed(callback: Callable) -> void:
	_settings_changed_listeners.erase(callback)


static func settings_changed_notify() -> void:
	for callback in _settings_changed_listeners:
		if callback.is_valid():
			callback.call()


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	ui_scale = float(data.get("ui_scale", 1.0))
	reduce_camera_shake = bool(data.get("reduce_camera_shake", false))
	reduce_hitstop = bool(data.get("reduce_hitstop", false))
	colorblind_mode = str(data.get("colorblind_mode", "default"))
	subtitle_scale = float(data.get("subtitle_scale", 1.0))
	vibration_intensity = float(data.get("vibration_intensity", 1.0))
	_migrate_camera_keys(data)
	camera_mouse_sensitivity = clampf(
		float(data.get("cameraMouseSensitivity", CAMERA_MOUSE_DEFAULT)),
		CAMERA_MOUSE_MIN,
		CAMERA_MOUSE_MAX
	)
	camera_stick_sensitivity = clampf(
		float(data.get("cameraStickSensitivity", CAMERA_STICK_DEFAULT)),
		CAMERA_STICK_MIN,
		CAMERA_STICK_MAX
	)
	camera_invert_y = bool(data.get("cameraInvertY", false))
	camera_fov = clampf(
		float(data.get("cameraFov", CAMERA_FOV_DEFAULT)), CAMERA_FOV_MIN, CAMERA_FOV_MAX
	)
	camera_stick_curve = clampf(
		float(data.get("cameraStickCurve", CAMERA_STICK_CURVE_DEFAULT)),
		CAMERA_STICK_CURVE_MIN,
		CAMERA_STICK_CURVE_MAX
	)
	camera_stick_deadzone = clampf(
		float(data.get("cameraStickDeadzone", CAMERA_STICK_DEADZONE_DEFAULT)),
		CAMERA_STICK_DEADZONE_MIN,
		CAMERA_STICK_DEADZONE_MAX
	)


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {
		"ui_scale": ui_scale,
		"reduce_camera_shake": reduce_camera_shake,
		"reduce_hitstop": reduce_hitstop,
		"colorblind_mode": colorblind_mode,
		"subtitle_scale": subtitle_scale,
		"vibration_intensity": vibration_intensity,
		"cameraMouseSensitivity": camera_mouse_sensitivity,
		"cameraStickSensitivity": camera_stick_sensitivity,
		"cameraInvertY": camera_invert_y,
		"cameraFov": camera_fov,
		"cameraStickCurve": camera_stick_curve,
		"cameraStickDeadzone": camera_stick_deadzone,
	}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()
	settings_changed_notify()


static func camera_settings_defaults() -> Dictionary:
	return {
		"cameraMouseSensitivity": CAMERA_MOUSE_DEFAULT,
		"cameraStickSensitivity": CAMERA_STICK_DEFAULT,
		"cameraInvertY": false,
		"cameraFov": CAMERA_FOV_DEFAULT,
		"cameraStickCurve": CAMERA_STICK_CURVE_DEFAULT,
		"cameraStickDeadzone": CAMERA_STICK_DEADZONE_DEFAULT,
	}


static func apply_camera_defaults_to_dict(data: Dictionary) -> void:
	var defaults := camera_settings_defaults()
	for key in defaults:
		if not data.has(key):
			data[key] = defaults[key]


static func _migrate_camera_keys(data: Dictionary) -> void:
	if data.has("mouse_sensitivity") and not data.has("cameraMouseSensitivity"):
		data["cameraMouseSensitivity"] = clampf(
			float(data.get("mouse_sensitivity", CAMERA_MOUSE_DEFAULT)),
			CAMERA_MOUSE_MIN,
			CAMERA_MOUSE_MAX
		)
	if data.has("stick_sensitivity") and not data.has("cameraStickSensitivity"):
		data["cameraStickSensitivity"] = clampf(
			float(data.get("stick_sensitivity", CAMERA_STICK_DEFAULT)),
			CAMERA_STICK_MIN,
			CAMERA_STICK_MAX
		)
	if data.has("invert_look_y") and not data.has("cameraInvertY"):
		data["cameraInvertY"] = bool(data.get("invert_look_y", false))


static func get_damage_color(damage_type: String = "physical") -> Color:
	match colorblind_mode:
		"protanopia", "deuteranopia":
			return _cb_damage_color(damage_type)
		"tritanopia":
			return _cb_damage_color(damage_type, true)
		_:
			return _default_damage_color(damage_type)


static func _default_damage_color(damage_type: String) -> Color:
	match damage_type:
		"fire":
			return Color(1.0, 0.4, 0.1)
		"frost":
			return Color(0.4, 0.7, 1.0)
		"poison":
			return Color(0.4, 0.9, 0.3)
		"arcane":
			return Color(0.7, 0.4, 1.0)
		_:
			return Color(1.0, 0.2, 0.2)


static func _cb_damage_color(damage_type: String, tritanopia: bool = false) -> Color:
	if tritanopia:
		match damage_type:
			"fire":
				return Color(1.0, 0.6, 0.0)
			"frost":
				return Color(0.0, 0.7, 0.9)
			"poison":
				return Color(0.9, 0.9, 0.2)
			"arcane":
				return Color(0.8, 0.3, 0.8)
			_:
				return Color(0.9, 0.5, 0.0)
	match damage_type:
		"fire":
			return Color(1.0, 0.7, 0.0)
		"frost":
			return Color(0.0, 0.6, 0.9)
		"poison":
			return Color(0.9, 0.9, 0.1)
		"arcane":
			return Color(0.7, 0.3, 0.9)
		_:
			return Color(1.0, 0.55, 0.0)
