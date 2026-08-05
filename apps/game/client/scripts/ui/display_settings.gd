extends RefCounted
class_name DisplaySettings

## Applies accessibility display prefs (ui scale) at runtime.


static func apply() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	tree.root.content_scale_factor = clampf(AccessibilitySettings.ui_scale, 0.75, 1.75)
