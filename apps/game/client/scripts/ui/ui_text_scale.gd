extends RefCounted
class_name UITextScale

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")


static var _registered: Array[WeakRef] = []


static func apply_all() -> void:
	var display_scale := DisplayService.ui_text_scale if DisplayService else 1.0
	var scale := AccessibilitySettings.subtitle_scale * display_scale
	for ref in _registered:
		var label := ref.get_ref() as Label
		if label != null and is_instance_valid(label):
			_apply_to_label(label, scale)


static func _apply_to_label(label: Label, scale: float = -1.0) -> void:
	if scale < 0.0:
		var display_scale := DisplayService.ui_text_scale if DisplayService else 1.0
		scale = AccessibilitySettings.subtitle_scale * display_scale
	var base_size := int(label.get_meta("_ui_text_base_size", GameUISkinScript.FONT_SIZE_BODY))
	label.add_theme_font_size_override("font_size", int(base_size * scale))
