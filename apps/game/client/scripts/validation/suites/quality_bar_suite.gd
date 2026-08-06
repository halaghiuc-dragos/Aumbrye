extends "res://scripts/validation/validation_suite.gd"

## Automatable checks from 00-QUALITY-BAR.md and 00-PLACEHOLDER-INVENTORY.md.

const PixelDioramaSettings := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")

const KNOWN_CI_GODOT_VERSION := "4.7.0"


func get_category() -> String:
	return "quality"


func run() -> void:
	_test_main_scene()
	_test_platform_gates()
	_test_character_authoring()
	_test_combat_honesty_signals()
	_test_loot_ui_signals()
	_test_audio_combat_sfx()


func _test_main_scene() -> void:
	var start := Time.get_ticks_msec()
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var allowed := (
		main_scene
		in [
			"res://scenes/ui/title_screen.tscn",
			"res://scenes/hub/hub.tscn",
		]
	)
	ctx.timed_record(
		"quality.main_scene_configured",
		get_category(),
		allowed,
		"main scene is title or hub (%s)" % main_scene,
		start,
		"M1.hub.main_scene"
	)

	start = Time.get_ticks_msec()
	var loads := false
	if ResourceLoader.exists(main_scene):
		var packed: PackedScene = load(main_scene)
		if packed:
			var instance := packed.instantiate()
			loads = instance != null
			if instance:
				instance.free()
	ctx.timed_record(
		"quality.main_scene_loads",
		get_category(),
		loads,
		"main scene instantiates headless",
		start,
		"M1.hub.main_scene"
	)


func _test_platform_gates() -> void:
	var start := Time.get_ticks_msec()
	var offline_default := ctx.file_contains(
		"res://scripts/app/run_flow.gd", "const USE_ONLINE_PROCgen := false"
	)
	ctx.timed_record(
		"quality.platform.online_procgen_gated",
		get_category(),
		offline_default,
		"USE_ONLINE_PROCgen remains false until parity suites green",
		start,
		"M5.net.offline"
	)

	start = Time.get_ticks_msec()
	var workflow_path := ctx.repo_root().path_join(".github/workflows/ci.yml")
	var workflow_text := ""
	if FileAccess.file_exists(workflow_path):
		workflow_text = FileAccess.get_file_as_string(workflow_path)
	var godot_version_path := ctx.repo_root().path_join("apps/game/client/.godot-version")
	var pinned := ""
	if FileAccess.file_exists(godot_version_path):
		pinned = FileAccess.get_file_as_string(godot_version_path).strip_edges()
	var features: PackedStringArray = ProjectSettings.get_setting(
		"application/config/features", PackedStringArray()
	)
	var project_version := ""
	for feature in features:
		if str(feature).is_valid_float():
			project_version = str(feature)
			break
	var ci_ok := pinned == KNOWN_CI_GODOT_VERSION and pinned in workflow_text
	ctx.timed_record(
		"quality.platform.ci_godot_version_tracked",
		get_category(),
		ci_ok and project_version == pinned.split(".")[0] + "." + pinned.split(".")[1],
		"CI Godot version pinned to %s (project %s)" % [pinned, project_version],
		start,
		"CI-7.1"
	)


func _test_character_authoring() -> void:
	var start := Time.get_ticks_msec()
	var repo := ctx.repo_root()
	var manifest_ok := (
		FileAccess.file_exists(repo.path_join("content/characters/player_warden.json"))
		and ResourceLoader.exists("res://assets/characters/player_warden/torso.mesh")
	)
	ctx.timed_record(
		"quality.character.voxel_manifest",
		get_category(),
		manifest_ok,
		"player_warden voxel manifest and meshes present",
		start,
		"CHA-01"
	)

	start = Time.get_ticks_msec()
	var uses_manifest := ctx.file_contains(
		"res://scripts/art/characters/diorama_character_skin.gd", "build_from_manifest"
	)
	ctx.timed_record(
		"quality.character.manifest_loader",
		get_category(),
		uses_manifest,
		"DioramaCharacterSkin loads authored manifests",
		start,
		"CHA-01"
	)

	start = Time.get_ticks_msec()
	var grid_ok := ctx.file_contains("res://scripts/art/characters/voxel_grid.gd", "EDGE := 0.04")
	ctx.timed_record(
		"quality.character.voxel_grid",
		get_category(),
		grid_ok,
		"VoxelGrid.EDGE declared at 0.04 m",
		start,
		"CHA-02"
	)

	start = Time.get_ticks_msec()
	var palette_ok := (
		ctx.file_contains("res://scripts/art/characters/voxel_mesh_builder.gd", "_snap_to_palette")
		and ctx.file_contains(
			"res://scripts/art/characters/diorama_character_skin.gd", "use_vertex_color"
		)
	)
	ctx.timed_record(
		"quality.character.palette_snap",
		get_category(),
		palette_ok,
		"voxel meshes snap vertex colours to theme palettes",
		start,
		"CHA-03"
	)

	start = Time.get_ticks_msec()
	var equip_ok := (
		ctx.file_contains(
			"res://scripts/art/characters/diorama_character_skin.gd", "func apply_equipment"
		)
		and ctx.file_contains(
			"res://scripts/inventory/inventory_service.gd", "_apply_equipment_visuals"
		)
	)
	ctx.timed_record(
		"quality.character.equipment_visuals",
		get_category(),
		equip_ok,
		"equipment visual blocks wired from inventory",
		start,
		"CHA-05"
	)

	start = Time.get_ticks_msec()
	var skin_text := FileAccess.get_file_as_string(
		"res://scripts/art/characters/diorama_character_skin.gd"
	)
	var no_scale := (
		"root.scale = Vector3(bulk" not in skin_text
		and "Vector3(bulk, height, bulk)" not in skin_text
	)
	ctx.timed_record(
		"quality.character.uniform_scale",
		get_category(),
		no_scale,
		"player appearance avoids Root.scale for height/bulk",
		start,
		"CHA-07"
	)

	start = Time.get_ticks_msec()
	var weapon_ok := (
		ctx.file_contains("res://scripts/art/props/diorama_weapon_kit.gd", "_build_unknown")
		and ctx.file_contains("res://scripts/art/props/diorama_weapon_kit.gd", "_build_axe")
		and ctx.file_contains("res://scripts/art/props/diorama_weapon_kit.gd", "_build_staff")
	)
	ctx.timed_record(
		"quality.character.weapon_kit_expanded",
		get_category(),
		weapon_ok,
		"weapon kit covers axe, staff, and unknown fallback",
		start,
		"CHA-08"
	)

	start = Time.get_ticks_msec()
	var custom_ok := (
		ctx.file_contains("res://scripts/save/character_appearance.gd", "skinTone")
		and ctx.file_contains("res://scripts/save/character_appearance.gd", "hair")
		and ctx.file_contains(
			"res://scripts/art/characters/diorama_character_skin.gd", "_apply_class_armor"
		)
	)
	ctx.timed_record(
		"quality.character.customization_axes",
		get_category(),
		custom_ok,
		"appearance supports skin tone, hair, face, and class armour",
		start,
		"CHA-09"
	)

	start = Time.get_ticks_msec()
	var default_chunky := (
		PixelDioramaSettings.DEFAULT_VIEWPORT_WIDTH == 480
		and PixelDioramaSettings.DEFAULT_VIEWPORT_HEIGHT == 270
	)
	ctx.timed_record(
		"quality.character.chunky_default_preset",
		get_category(),
		default_chunky,
		"default viewport preset is 480x270",
		start,
		"CHA-10"
	)

	start = Time.get_ticks_msec()
	var comments_ok := (
		not ctx.file_contains("res://scripts/art/props/diorama_weapon_kit.gd", "0.02 m grid")
		and ctx.file_contains(
			"res://assets/shared/pixel_diorama_surface.gdshader", "use_vertex_color"
		)
	)
	ctx.timed_record(
		"quality.character.comment_cleanup",
		get_category(),
		comments_ok,
		"voxel/grid comments match VoxelGrid.EDGE implementation",
		start,
		"CHA-11"
	)

	start = Time.get_ticks_msec()
	var rig_validation := (
		ResourceLoader.exists("res://scripts/validation/suites/voxel_grid_suite.gd")
		and ctx.file_contains(
			"res://scripts/validation/suites/diorama_anim_suite.gd", "_test_rig_contracts"
		)
	)
	ctx.timed_record(
		"quality.character.rig_validation",
		get_category(),
		rig_validation,
		"rig-contract validation suites registered",
		start,
		"CHA-12"
	)


func _test_combat_honesty_signals() -> void:
	var start := Time.get_ticks_msec()
	var heal_text := ""
	if FileAccess.file_exists("res://scripts/art/characters/diorama_anim_controller.gd"):
		heal_text = FileAccess.get_file_as_string(
			"res://scripts/art/characters/diorama_anim_controller.gd"
		)
	var heal_dedicated := (
		'&"heal"' in heal_text.split("func play_heal")[1].split("func ")[0]
		if "func play_heal" in heal_text
		else false
	)
	ctx.timed_record(
		"quality.combat.heal_presentation",
		get_category(),
		heal_dedicated,
		"dedicated heal animation clip" if heal_dedicated else "heal still aliases stagger",
		start,
		"M7.combat.shield_feel"
	)

	start = Time.get_ticks_msec()
	var lunge_ok := ctx.file_contains(
		"res://scripts/combat/weapon_controller.gd", "_lunge_distance"
	)
	ctx.timed_record(
		"quality.combat.lunge_implemented",
		get_category(),
		lunge_ok,
		"attack lunge velocity wired from weapon data",
		start,
		"M5.weapons.feel"
	)


func _test_loot_ui_signals() -> void:
	var start := Time.get_ticks_msec()
	var fetch_registered := (
		ctx.file_contains("res://scripts/quests/quest_service.gd", "func register_fetch")
		and _grep_tree_for("register_fetch", "res://scripts")
	)
	ctx.timed_record(
		"quality.quest.fetch_registration_wired",
		get_category(),
		fetch_registered,
		(
			"register_fetch has inventory/loot call site"
			if fetch_registered
			else "fetch quests still unwired from loot"
		),
		start,
		"M4.flow.economy"
	)

	start = Time.get_ticks_msec()
	var icons_ok := (
		ctx.file_contains("res://scripts/ui/inventory_ui.gd", "ItemIconAtlas")
		and not ctx.file_contains("res://scripts/ui/inventory_ui.gd", "⚔")
	)
	ctx.timed_record(
		"quality.ui.item_icons",
		get_category(),
		icons_ok,
		"inventory cells use item icon atlas",
		start,
		"INV-4.1"
	)


func _test_audio_combat_sfx() -> void:
	var start := Time.get_ticks_msec()
	var assets_ok := (
		ResourceLoader.exists("res://assets/audio/sfx/hit.wav")
		and ResourceLoader.exists("res://assets/audio/sfx/block.wav")
		and ResourceLoader.exists("res://assets/audio/sfx/parry.wav")
	)
	ctx.timed_record(
		"quality.audio.combat_sfx_assets",
		get_category(),
		assets_ok,
		"authored combat SFX under assets/audio/sfx",
		start,
		"AUD-01"
	)

	start = Time.get_ticks_msec()
	var bank_text := FileAccess.get_file_as_string("content/audio/sfx.json")
	var bank_wired := "res://assets/audio/sfx/hit.wav" in bank_text
	ctx.timed_record(
		"quality.audio.combat_sfx_bank",
		get_category(),
		bank_wired,
		"sfx.json references file-backed combat streams",
		start,
		"AUD-01"
	)


func _grep_tree_for(token: String, rel_root: String) -> bool:
	var abs := ProjectSettings.globalize_path(rel_root)
	var dir := DirAccess.open(abs)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := abs.path_join(entry)
		if dir.current_is_dir() and entry != ".godot":
			if _grep_tree_for(token, rel_root.path_join(entry)):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd") and not entry.ends_with("quest_service.gd"):
			var text := FileAccess.get_file_as_string(path)
			if "%s(" % token in text:
				dir.list_dir_end()
				return true
		entry = dir.get_next()
	dir.list_dir_end()
	return false
