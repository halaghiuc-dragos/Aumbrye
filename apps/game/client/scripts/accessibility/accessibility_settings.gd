extends RefCounted
class_name AccessibilitySettings

## M6 accessibility baseline (A11Y-6.1).

const SAVE_KEY := "accessibility"

static var ui_scale: float = 1.0
static var reduce_camera_shake: bool = false
static var colorblind_mode: String = "default"
static var subtitle_scale: float = 1.0
static var vibration_intensity: float = 1.0


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	ui_scale = float(data.get("ui_scale", 1.0))
	reduce_camera_shake = bool(data.get("reduce_camera_shake", false))
	colorblind_mode = str(data.get("colorblind_mode", "default"))
	subtitle_scale = float(data.get("subtitle_scale", 1.0))
	vibration_intensity = float(data.get("vibration_intensity", 1.0))


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {
		"ui_scale": ui_scale,
		"reduce_camera_shake": reduce_camera_shake,
		"colorblind_mode": colorblind_mode,
		"subtitle_scale": subtitle_scale,
		"vibration_intensity": vibration_intensity,
	}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()


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
		"fire": return Color(1.0, 0.4, 0.1)
		"frost": return Color(0.4, 0.7, 1.0)
		"poison": return Color(0.4, 0.9, 0.3)
		"arcane": return Color(0.7, 0.4, 1.0)
		_: return Color(1.0, 0.2, 0.2)


static func _cb_damage_color(damage_type: String, tritanopia: bool = false) -> Color:
	if tritanopia:
		match damage_type:
			"fire": return Color(1.0, 0.6, 0.0)
			"frost": return Color(0.0, 0.7, 0.9)
			"poison": return Color(0.9, 0.9, 0.2)
			"arcane": return Color(0.8, 0.3, 0.8)
			_: return Color(0.9, 0.5, 0.0)
	match damage_type:
		"fire": return Color(1.0, 0.7, 0.0)
		"frost": return Color(0.0, 0.6, 0.9)
		"poison": return Color(0.9, 0.9, 0.1)
		"arcane": return Color(0.7, 0.3, 0.9)
		_: return Color(1.0, 0.55, 0.0)
