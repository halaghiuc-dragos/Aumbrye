extends SceneTree

## Headless theme exporter — no autoloads required.
##   godot --path . --headless --script res://scripts/tools/build_ui_theme.gd

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const OUTPUT_PATH := "res://assets/ui/aumbrye_ui.tres"


func _initialize() -> void:
	call_deferred("_export_theme")


func _export_theme() -> void:
	var theme := GameUISkinScript.build_theme()
	var err := ResourceSaver.save(theme, OUTPUT_PATH)
	if err != OK:
		printerr("build_ui_theme: failed to save %s (%s)" % [OUTPUT_PATH, error_string(err)])
		quit(1)
		return
	print("Saved %s" % OUTPUT_PATH)
	quit(0)
