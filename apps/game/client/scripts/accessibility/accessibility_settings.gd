extends RefCounted
class_name AccessibilitySettings

const DebouncedSaveScript := preload("res://scripts/app/debounced_save.gd")


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

const MOTION_INTENSITY_MIN := 0.0
const MOTION_INTENSITY_MAX := 1.0
const MOTION_INTENSITY_DEFAULT := 1.0
const MOTION_OFF_EPSILON := 0.001

static var reduce_camera_shake: bool = false
static var reduce_hitstop: bool = false

static var camera_shake_intensity: float = MOTION_INTENSITY_DEFAULT
static var hitstop_intensity: float = MOTION_INTENSITY_DEFAULT
static var screen_pulse_intensity: float = MOTION_INTENSITY_DEFAULT
static var reduced_motion: bool = false
static var show_control_hints: bool = true
static var colorblind_mode: String = "default"
static var subtitle_scale: float = 1.0
static var vibration_intensity: float = 1.0

static var camera_mouse_sensitivity: float = CAMERA_MOUSE_DEFAULT
static var camera_stick_sensitivity: float = CAMERA_STICK_DEFAULT
static var camera_invert_y: bool = false
static var camera_fov: float = CAMERA_FOV_DEFAULT
static var camera_stick_curve: float = CAMERA_STICK_CURVE_DEFAULT
static var camera_stick_deadzone: float = CAMERA_STICK_DEADZONE_DEFAULT

static var assist_damage_taken: float = ASSIST_DAMAGE_TAKEN_DEFAULT
static var assist_iframe_generosity: float = ASSIST_IFRAME_DEFAULT
static var assist_lock_on_range: float = ASSIST_LOCK_ON_DEFAULT
static var assist_telegraph_emphasis: bool = false

static var _settings_changed_listeners: Array[Callable] = []
const ASSIST_DAMAGE_TAKEN_MIN := 0.5
const ASSIST_DAMAGE_TAKEN_MAX := 1.0
const ASSIST_DAMAGE_TAKEN_DEFAULT := 1.0
const ASSIST_IFRAME_MIN := 1.0
const ASSIST_IFRAME_MAX := 1.5
const ASSIST_IFRAME_DEFAULT := 1.0
const ASSIST_LOCK_ON_MIN := 1.0
const ASSIST_LOCK_ON_MAX := 1.6
const ASSIST_LOCK_ON_DEFAULT := 1.0

const SAVE_DEBOUNCE_SEC := 0.5
static var _pending_commit := false


static func set_camera_shake_intensity(value: float) -> void:
	camera_shake_intensity = clampf(value, MOTION_INTENSITY_MIN, MOTION_INTENSITY_MAX)
	reduce_camera_shake = camera_shake_intensity <= MOTION_OFF_EPSILON
	_refresh_reduced_motion()


static func set_hitstop_intensity(value: float) -> void:
	hitstop_intensity = clampf(value, MOTION_INTENSITY_MIN, MOTION_INTENSITY_MAX)
	reduce_hitstop = hitstop_intensity <= MOTION_OFF_EPSILON
	_refresh_reduced_motion()


static func set_screen_pulse_intensity(value: float) -> void:
	screen_pulse_intensity = clampf(value, MOTION_INTENSITY_MIN, MOTION_INTENSITY_MAX)
	_refresh_reduced_motion()


static func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	var target := MOTION_INTENSITY_MIN if value else MOTION_INTENSITY_DEFAULT
	camera_shake_intensity = target
	hitstop_intensity = target
	screen_pulse_intensity = target
	reduce_camera_shake = value
	reduce_hitstop = value


static func _refresh_reduced_motion() -> void:
	reduced_motion = (
		camera_shake_intensity <= MOTION_OFF_EPSILON
		and hitstop_intensity <= MOTION_OFF_EPSILON
		and screen_pulse_intensity <= MOTION_OFF_EPSILON
	)


static func scale_incoming_player_damage(amount: float) -> float:
	if amount <= 0.0 or is_equal_approx(assist_damage_taken, ASSIST_DAMAGE_TAKEN_DEFAULT):
		return amount
	return amount * assist_damage_taken


static func lock_on_range_scale() -> float:
	return maxf(0.01, assist_lock_on_range)


const TELEGRAPH_EMPHASIS_RADIUS_SCALE := 1.12


static func emphasise_telegraph_tint(tint: Color) -> Color:
	if not assist_telegraph_emphasis:
		return tint
	var boosted := tint.lightened(0.28)
	boosted.a = maxf(tint.a, 0.92)
	return boosted


static func telegraph_radius_scale() -> float:
	return TELEGRAPH_EMPHASIS_RADIUS_SCALE if assist_telegraph_emphasis else 1.0


static func camera_shake_scale() -> float:
	return 0.0 if reduce_camera_shake else camera_shake_intensity


static func hitstop_scale() -> float:
	return 0.0 if reduce_hitstop else hitstop_intensity


static func screen_pulse_scale() -> float:
	return 0.0 if reduced_motion else screen_pulse_intensity


static func connect_settings_changed(callback: Callable) -> void:
	if not _settings_changed_listeners.has(callback):
		_settings_changed_listeners.append(callback)


static func disconnect_settings_changed(callback: Callable) -> void:
	_settings_changed_listeners.erase(callback)


static func settings_changed_notify() -> void:
	for callback in _settings_changed_listeners:
		if callback.is_valid():
			callback.call()


static func changed_notify(setting_id: String, value: Variant) -> void:
	settings_changed_notify()
	for callback in _settings_changed_listeners:
		if callback.is_valid() and callback.get_argument_count() >= 2:
			callback.call(setting_id, value)


static func apply_live(setting_id: String = "", value: Variant = null) -> void:
	if setting_id != "":
		changed_notify(setting_id, value)
	if setting_id == "colorblind_mode":
		StatusIconAtlas.reload()
	DisplayService.apply_all()
	UITextScale.apply_all()


static func request_commit() -> void:
	_pending_commit = true
	DebouncedSaveScript.request(&"accessibility_settings", SAVE_DEBOUNCE_SEC, _on_commit_timeout)


static func commit() -> void:
	_pending_commit = false
	save()


static func _on_commit_timeout() -> void:
	if _pending_commit:
		commit()


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	_load_motion_keys(data)
	show_control_hints = bool(data.get("show_control_hints", true))
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
	assist_damage_taken = clampf(
		float(data.get("assistDamageTaken", ASSIST_DAMAGE_TAKEN_DEFAULT)),
		ASSIST_DAMAGE_TAKEN_MIN,
		ASSIST_DAMAGE_TAKEN_MAX
	)
	assist_iframe_generosity = clampf(
		float(data.get("assistIframeGenerosity", ASSIST_IFRAME_DEFAULT)),
		ASSIST_IFRAME_MIN,
		ASSIST_IFRAME_MAX
	)
	assist_lock_on_range = clampf(
		float(data.get("assistLockOnRange", ASSIST_LOCK_ON_DEFAULT)),
		ASSIST_LOCK_ON_MIN,
		ASSIST_LOCK_ON_MAX
	)
	assist_telegraph_emphasis = bool(data.get("assistTelegraphEmphasis", false))


static func _load_motion_keys(data: Dictionary) -> void:
	var legacy_shake := bool(data.get("reduce_camera_shake", false))
	var legacy_hitstop := bool(data.get("reduce_hitstop", false))
	var shake_fallback := MOTION_INTENSITY_MIN if legacy_shake else MOTION_INTENSITY_DEFAULT
	var hitstop_fallback := MOTION_INTENSITY_MIN if legacy_hitstop else MOTION_INTENSITY_DEFAULT
	var pulse_fallback := (
		MOTION_INTENSITY_MIN
		if (legacy_shake and legacy_hitstop)
		else MOTION_INTENSITY_DEFAULT
	)
	camera_shake_intensity = clampf(
		float(data.get("cameraShakeIntensity", shake_fallback)),
		MOTION_INTENSITY_MIN,
		MOTION_INTENSITY_MAX
	)
	hitstop_intensity = clampf(
		float(data.get("hitstopIntensity", hitstop_fallback)),
		MOTION_INTENSITY_MIN,
		MOTION_INTENSITY_MAX
	)
	screen_pulse_intensity = clampf(
		float(data.get("screenPulseIntensity", pulse_fallback)),
		MOTION_INTENSITY_MIN,
		MOTION_INTENSITY_MAX
	)
	reduce_camera_shake = camera_shake_intensity <= MOTION_OFF_EPSILON
	reduce_hitstop = hitstop_intensity <= MOTION_OFF_EPSILON
	_refresh_reduced_motion()


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {
		"reduce_camera_shake": reduce_camera_shake,
		"reduce_hitstop": reduce_hitstop,
		"cameraShakeIntensity": camera_shake_intensity,
		"hitstopIntensity": hitstop_intensity,
		"screenPulseIntensity": screen_pulse_intensity,
		"reducedMotion": reduced_motion,
		"show_control_hints": show_control_hints,
		"colorblind_mode": colorblind_mode,
		"subtitle_scale": subtitle_scale,
		"vibration_intensity": vibration_intensity,
		"cameraMouseSensitivity": camera_mouse_sensitivity,
		"cameraStickSensitivity": camera_stick_sensitivity,
		"cameraInvertY": camera_invert_y,
		"cameraFov": camera_fov,
		"cameraStickCurve": camera_stick_curve,
		"cameraStickDeadzone": camera_stick_deadzone,
		"assistDamageTaken": assist_damage_taken,
		"assistIframeGenerosity": assist_iframe_generosity,
		"assistLockOnRange": assist_lock_on_range,
		"assistTelegraphEmphasis": assist_telegraph_emphasis,
	}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()
	changed_notify("all", null)


static func assists_active() -> bool:
	return (
		assist_damage_taken < ASSIST_DAMAGE_TAKEN_DEFAULT
		or assist_iframe_generosity > ASSIST_IFRAME_DEFAULT
		or assist_lock_on_range > ASSIST_LOCK_ON_DEFAULT
		or assist_telegraph_emphasis
	)


static func active_assist_summary() -> Array[String]:
	var lines: Array[String] = []
	if assist_damage_taken < ASSIST_DAMAGE_TAKEN_DEFAULT:
		lines.append("Damage taken x%.2f" % assist_damage_taken)
	if assist_iframe_generosity > ASSIST_IFRAME_DEFAULT:
		lines.append("Dodge window x%.2f" % assist_iframe_generosity)
	if assist_lock_on_range > ASSIST_LOCK_ON_DEFAULT:
		lines.append("Lock-on reach x%.2f" % assist_lock_on_range)
	if assist_telegraph_emphasis:
		lines.append("Telegraphs emphasised")
	return lines


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
		"lightning":
			return Color(1.0, 0.9, 0.35)
		"arcane":
			return Color(0.7, 0.4, 1.0)
		_:
			return Color(1.0, 0.2, 0.2)


## Attack telegraphs are the one read in the game where getting the colour wrong costs the player
## the hit: blockable, unblockable and parryable are told apart by tint alone, since the shape of a
## telegraph says where the attack lands rather than what kind it is. The default triad is amber,
## red and blue, and amber against red is exactly the pair that collapses under protanopia and
## deuteranopia -- so the same colourblind setting that remaps damage numbers remaps these too.
static func get_telegraph_class_color(attack_class: String) -> Color:
	match colorblind_mode:
		"protanopia", "deuteranopia":
			return _cb_telegraph_class_color(attack_class)
		"tritanopia":
			return _cb_telegraph_class_color(attack_class, true)
		_:
			return _default_telegraph_class_color(attack_class)


static func _default_telegraph_class_color(attack_class: String) -> Color:
	match attack_class:
		"unblockable":
			return Color(0.96, 0.24, 0.18)
		"parryable":
			return Color(0.42, 0.76, 1.0)
		_:
			return Color(0.98, 0.68, 0.20)


static func _cb_telegraph_class_color(attack_class: String, tritanopia: bool = false) -> Color:
	if tritanopia:
		# Blue and yellow collapse here, so the triad runs red -- white -- cyan instead.
		match attack_class:
			"unblockable":
				return Color(1.0, 0.96, 0.96)
			"parryable":
				return Color(0.13, 0.85, 0.95)
			_:
				return Color(1.0, 0.36, 0.24)
	# Red and amber collapse here, so the triad separates on the blue-yellow axis and on
	# lightness: a saturated amber, a near-white, and a deep blue.
	match attack_class:
		"unblockable":
			return Color(1.0, 0.97, 0.92)
		"parryable":
			return Color(0.16, 0.44, 0.98)
		_:
			return Color(0.98, 0.80, 0.10)


static func _cb_damage_color(damage_type: String, tritanopia: bool = false) -> Color:
	if tritanopia:
		match damage_type:
			"fire":
				return Color(1.0, 0.6, 0.0)
			"frost":
				return Color(0.0, 0.7, 0.9)
			"poison":
				return Color(0.9, 0.9, 0.2)
			"lightning":
				return Color(0.55, 0.85, 1.0)
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
		"lightning":
			return Color(0.4, 0.8, 1.0)
		"arcane":
			return Color(0.7, 0.3, 0.9)
		_:
			return Color(1.0, 0.55, 0.0)
