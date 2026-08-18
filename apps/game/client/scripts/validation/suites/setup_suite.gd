extends "res://scripts/validation/validation_suite.gd"

const InputRebindServiceScript := preload("res://scripts/app/input_rebind_service.gd")
const InputBindingsScript := preload("res://scripts/app/input_bindings.gd")

const REQUIRED_AUTOLOADS := [
	"RunFlow",
	"ApiConfig",
	"LocalSave",
	"CharacterService",
	"ProgressionService",
	"RunBuffs",
	"InventoryService",
	"StorageService",
	"QuestService",
	"AudioDirector",
	"AchievementService",
	"SteamService",
	"CrashLogger",
	"WavesRunService",
	"DungeonTierService",
	"VfxService",
	"DisplayService",
	"PlayerControls",
	"MenuStack",
	"WorldState",
	"PixelDioramaViewport",
	"AttackTokenService",
	"GameFacade",
	"InputRebindService",
	"DebugConsole",
]


func get_category() -> String:
	return "setup"


func run() -> void:
	_test_project_setup()
	_test_readme_main_scene()
	_test_input_map()
	_test_engine_version_pin()
	_test_display_settings_explicit()
	_test_input_no_intra_group_conflicts()
	_test_input_no_binding_conflicts()
	_test_input_gamepad_coverage()
	_test_input_rebindable_actions_exist()
	_test_input_bindings_roundtrip()
	_test_input_rebind_roundtrip()
	_test_input_rebind_conflict_reported()


func _test_project_setup() -> void:
	var start := Time.get_ticks_msec()
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	ctx.timed_record(
		"setup.main_scene_hub",
		get_category(),
		(
			main_scene == "res://scenes/ui/title_screen.tscn"
			or main_scene == "res://scenes/hub/hub.tscn"
		),
		"main scene is title or hub (%s)" % main_scene,
		start,
		"M1.hub.main_scene"
	)

	start = Time.get_ticks_msec()
	var missing: PackedStringArray = []
	for name in REQUIRED_AUTOLOADS:
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

	start = Time.get_ticks_msec()
	var plugin_enabled := false
	if ProjectSettings.has_setting("editor_plugins/enabled"):
		var enabled_plugins: PackedStringArray = ProjectSettings.get_setting(
			"editor_plugins/enabled"
		)
		plugin_enabled = "res://addons/godot_mcp/plugin.cfg" in enabled_plugins
	ctx.timed_record(
		"setup.mcp_plugin_disabled",
		get_category(),
		not plugin_enabled,
		"godot_mcp not enabled in project.godot",
		start,
		"CFG-09"
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


func _test_readme_main_scene() -> void:
	var start := Time.get_ticks_msec()
	var repo_root := ProjectSettings.globalize_path("res://").path_join("../../..")
	var readme_path := repo_root.path_join("README.md")
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var scene_rel := main_scene.replace("res://", "")
	var readme_text := (
		FileAccess.get_file_as_string(readme_path) if FileAccess.file_exists(readme_path) else ""
	)
	var ok := readme_text.contains(scene_rel)
	ctx.timed_record(
		"setup.readme_main_scene",
		get_category(),
		ok,
		(
			"README.md mentions main scene %s" % scene_rel
			if ok
			else "README.md missing main scene %s" % scene_rel
		),
		start,
		"REP.readme_main_scene"
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
		(
			"all combat/hub actions mapped"
			if missing.is_empty()
			else "missing: %s" % ", ".join(missing)
		),
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

	start = Time.get_ticks_msec()
	# Every one of these ships as .ogg; the list asked for .wav, so this assertion could not pass
	# and reported all seven missing on every run. Both extensions are accepted now — AudioDirector
	# itself resolves either (see its `.wav`/`.ogg` candidate fallback) — so the test verifies the
	# cue exists rather than which container it happens to be in.
	var combat_sfx := [
		"res://assets/audio/sfx/hit",
		"res://assets/audio/sfx/hit_armor",
		"res://assets/audio/sfx/block",
		"res://assets/audio/sfx/parry",
		"res://assets/audio/sfx/heal_raise",
		"res://assets/audio/sfx/heal_gulp",
		"res://assets/audio/sfx/heal_commit",
	]
	var missing_combat_sfx: PackedStringArray = []
	for path in combat_sfx:
		if not ResourceLoader.exists(path + ".ogg") and not ResourceLoader.exists(path + ".wav"):
			missing_combat_sfx.append(path.get_file())
	ctx.timed_record(
		"setup.combat_sfx_assets",
		get_category(),
		missing_combat_sfx.is_empty(),
		(
			"combat SFX assets present"
			if missing_combat_sfx.is_empty()
			else "missing: %s" % ", ".join(missing_combat_sfx)
		),
		start,
		"M1.combat.audio"
	)


func _test_engine_version_pin() -> void:
	var start := Time.get_ticks_msec()
	var repo_root := ProjectSettings.globalize_path("res://").path_join("../../..")
	var version_path := repo_root.path_join("apps/game/client/.godot-version")
	var pinned := (
		FileAccess.get_file_as_string(version_path).strip_edges()
		if FileAccess.file_exists(version_path)
		else ""
	)
	var features: PackedStringArray = ProjectSettings.get_setting(
		"application/config/features", PackedStringArray()
	)
	var feature_major := features[0] if features.size() > 0 else ""
	var ok := pinned.begins_with(feature_major + ".")
	ctx.timed_record(
		"setup.engine_version_pin",
		get_category(),
		ok,
		(
			".godot-version %s matches feature tag %s" % [pinned, feature_major]
			if ok
			else "version pin mismatch (%s vs %s)" % [pinned, feature_major]
		),
		start,
		"CFG-01"
	)


func _test_display_settings_explicit() -> void:
	var start := Time.get_ticks_msec()
	var keys := [
		"display/window/vsync/vsync_mode",
		"display/window/size/mode",
		"rendering/anti_aliasing/quality/msaa_3d",
		"rendering/anti_aliasing/quality/screen_space_aa",
	]
	var missing: PackedStringArray = []
	for key in keys:
		if not ProjectSettings.has_setting(key):
			missing.append(key)
	ctx.timed_record(
		"setup.display_settings_explicit",
		get_category(),
		missing.is_empty(),
		"display settings explicit" if missing.is_empty() else "missing: %s" % ", ".join(missing),
		start,
		"CFG-06"
	)


func _test_input_no_intra_group_conflicts() -> void:
	var start := Time.get_ticks_msec()
	var service := InputRebindServiceScript.new()
	var groups: Dictionary = service.get_context_groups()
	var conflicts: PackedStringArray = []
	for group_name in groups.keys():
		var seen: Dictionary = {}
		for action in groups[group_name]:
			for event in InputMap.action_get_events(action):
				var signature := event.as_text()
				if signature in seen:
					conflicts.append("%s:%s vs %s" % [group_name, action, seen[signature]])
				else:
					seen[signature] = action
	ctx.timed_record(
		"input.no_intra_group_conflicts",
		get_category(),
		conflicts.is_empty(),
		(
			"no intra-group input conflicts"
			if conflicts.is_empty()
			else "conflicts: %s" % ", ".join(conflicts)
		),
		start,
		"CFG-03"
	)


func _test_input_no_binding_conflicts() -> void:
	var start := Time.get_ticks_msec()
	var conflicts: Dictionary = InputBindingsScript.conflicts()
	ctx.timed_record(
		"input.no_binding_conflicts",
		get_category(),
		conflicts.is_empty(),
		(
			"no rebindable binding conflicts"
			if conflicts.is_empty()
			else "conflicts: %s" % str(conflicts)
		),
		start,
		"PCT-04"
	)


func _test_input_gamepad_coverage() -> void:
	var start := Time.get_ticks_msec()
	var missing: PackedStringArray = []
	for action in InputBindingsScript.REBINDABLE:
		if action in InputBindingsScript.KEYBOARD_ONLY:
			continue
		if not InputBindingsScript.has_gamepad_event(action):
			missing.append(str(action))
	ctx.timed_record(
		"input.gamepad_coverage",
		get_category(),
		missing.is_empty(),
		(
			"gamepad coverage complete"
			if missing.is_empty()
			else "missing gamepad: %s" % ", ".join(missing)
		),
		start,
		"PCT-07"
	)


func _test_input_rebindable_actions_exist() -> void:
	var start := Time.get_ticks_msec()
	var missing: PackedStringArray = []
	for action in InputBindingsScript.REBINDABLE:
		if not InputMap.has_action(action):
			missing.append(str(action))
	ctx.timed_record(
		"input.rebindable_actions_exist",
		get_category(),
		missing.is_empty(),
		(
			"rebindable actions registered"
			if missing.is_empty()
			else "missing actions: %s" % ", ".join(missing)
		),
		start,
		"PCT-08"
	)


func _test_input_bindings_roundtrip() -> void:
	var start := Time.get_ticks_msec()
	var meta_backup: Dictionary = LocalSave.get_meta_data().duplicate(true)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	var result: Dictionary = InputBindingsScript.rebind(&"dodge", key)
	var has_c := false
	for event in InputMap.action_get_events(&"dodge"):
		if event is InputEventKey and event.physical_keycode == KEY_C:
			has_c = true
	InputBindingsScript.reset_action(&"dodge")
	LocalSave.set_meta_data(meta_backup)
	var ok := bool(result.get("ok", false)) and has_c
	ctx.timed_record(
		"input.bindings_roundtrip",
		get_category(),
		ok,
		"bindings roundtrip via LocalSave" if ok else "bindings roundtrip failed",
		start,
		"PCT-08"
	)


func _test_input_rebind_roundtrip() -> void:
	var start := Time.get_ticks_msec()
	var service: Node = Engine.get_main_loop().root.get_node_or_null("/root/InputRebindService")
	if service == null:
		ctx.timed_record(
			"input.rebind_roundtrip",
			get_category(),
			false,
			"InputRebindService autoload missing",
			start,
			"CFG-02"
		)
		return
	var original_mouse := false
	for event in InputMap.action_get_events(&"light_attack"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			original_mouse = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	var result: Dictionary = service.rebind(&"light_attack", key)
	var has_j := InputMap.action_has_event(&"light_attack", key)
	service.reset_all()
	var restored_mouse := false
	for restored in InputMap.action_get_events(&"light_attack"):
		if restored is InputEventMouseButton and restored.button_index == MOUSE_BUTTON_LEFT:
			restored_mouse = true
	var save_deleted := not FileAccess.file_exists("user://input_bindings.json")
	var ok := (
		bool(result.get("ok", false))
		and has_j
		and restored_mouse
		and save_deleted
		and original_mouse
	)
	ctx.timed_record(
		"input.rebind_roundtrip",
		get_category(),
		ok,
		"rebind roundtrip restores defaults" if ok else "rebind roundtrip failed",
		start,
		"CFG-02"
	)


func _test_input_rebind_conflict_reported() -> void:
	var start := Time.get_ticks_msec()
	var service: Node = Engine.get_main_loop().root.get_node_or_null("/root/InputRebindService")
	if service == null:
		ctx.timed_record(
			"input.rebind_conflict_reported",
			get_category(),
			false,
			"InputRebindService autoload missing",
			start,
			"CFG-02"
		)
		return
	var sprint_event: InputEvent = null
	for event in InputMap.action_get_events(&"sprint"):
		if event is InputEventKey:
			sprint_event = event
			break
	var ok := false
	if sprint_event != null:
		var result: Dictionary = service.rebind(&"dodge", sprint_event)
		ok = not bool(result.get("ok", true)) and str(result.get("conflict", "")) == "sprint"
		service.reset_all()
	ctx.timed_record(
		"input.rebind_conflict_reported",
		get_category(),
		ok,
		"rebind conflict reported for sprint" if ok else "rebind conflict not reported",
		start,
		"CFG-02"
	)
