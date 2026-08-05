extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "setup"


func run() -> void:
	_test_project_setup()
	_test_input_map()


func _test_project_setup() -> void:
	var start := Time.get_ticks_msec()
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	ctx.timed_record(
		"setup.main_scene_hub",
		get_category(),
		main_scene == "res://scenes/ui/title_screen.tscn" or main_scene == "res://scenes/hub/hub.tscn",
		"main scene is title or hub (%s)" % main_scene,
		start,
		"M1.hub.main_scene"
	)

	start = Time.get_ticks_msec()
	var autoloads := [
		"RunFlow", "LocalSave", "WorldState", "InventoryService", "AudioDirector", "ApiConfig", "VfxService", "PlayerControls",
	]
	var missing: PackedStringArray = []
	for name in autoloads:
		if not ProjectSettings.has_setting("autoload/%s" % name):
			missing.append(name)
	ctx.timed_record(
		"setup.autoloads",
		get_category(),
		missing.is_empty(),
		"autoloads present" if missing.is_empty() else "missing: %s" % ", ".join(missing),
		start,
		"M1.setup.autoloads"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"setup.mcp_plugin_present",
		get_category(),
		FileAccess.file_exists("res://addons/godot_mcp/plugin.cfg"),
		"godot_mcp plugin.cfg exists",
		start
	)

	for scene_path in TC.KEY_SCENES:
		start = Time.get_ticks_msec()
		var id: String = scene_path.get_file().get_basename()
		ctx.timed_record(
			"setup.scene_%s" % id,
			get_category(),
			ResourceLoader.exists(scene_path),
			"scene exists: %s" % scene_path,
			start
		)


func _test_input_map() -> void:
	var start := Time.get_ticks_msec()
	var missing: PackedStringArray = []
	for action in TC.REQUIRED_INPUT_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(action)
	ctx.timed_record(
		"input.required_actions",
		get_category(),
		missing.is_empty(),
		"all combat/hub actions mapped" if missing.is_empty() else "missing: %s" % ", ".join(missing),
		start,
		"M1.input.actions"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"input.arena_reset",
		get_category(),
		InputMap.has_action("reset_duel"),
		"reset_duel action mapped for training arena",
		start,
		"M1.arena.reset"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"input.dodge_action",
		get_category(),
		InputMap.has_action("dodge"),
		"dodge action mapped",
		start,
		"M1.combat.dodge"
	)
