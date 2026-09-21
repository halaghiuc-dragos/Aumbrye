extends RefCounted
class_name UITextScale

static var _registered: Array[WeakRef] = []


static func register(control: Control) -> void:
	if control == null:
		return
	for ref in _registered:
		if ref.get_ref() == control:
			return
	if control is Label or control is RichTextLabel or control is Button:
		if not control.has_meta("_ui_text_base_size"):
			control.set_meta("_ui_text_base_size", control.get_theme_font_size("font_size"))
		_registered.append(weakref(control))
		_apply_to_control(control)


static func unregister(control: Control) -> void:
	for index in range(_registered.size() - 1, -1, -1):
		var current: Variant = _registered[index].get_ref()
		if current == null or current == control:
			_registered.remove_at(index)


static func apply_all() -> void:
	var display_scale: float = DisplayService.ui_text_scale if DisplayService else 1.0
	var scale := AccessibilitySettings.subtitle_scale * display_scale
	for ref in _registered:
		var control := ref.get_ref() as Control
		if control != null and is_instance_valid(control):
			_apply_to_control(control, scale)


static func _apply_to_control(control: Control, scale: float = -1.0) -> void:
	if scale < 0.0:
		var display_scale: float = DisplayService.ui_text_scale if DisplayService else 1.0
		scale = AccessibilitySettings.subtitle_scale * display_scale
	var base_size := int(control.get_meta("_ui_text_base_size", 16))
	control.add_theme_font_size_override("font_size", int(base_size * scale))
