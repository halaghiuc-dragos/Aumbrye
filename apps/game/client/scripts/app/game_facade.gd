extends Node

## Thin facade grouping autoloads by concern. Prefer injecting dependencies in new code;
## use these accessors when crossing subsystem boundaries from UI or debug tooling.
##
## Groups (see docs/design/AUTOLOAD_FACADES.md):
##   persistence — LocalSave, CharacterService
##   progression — ProgressionService, QuestService, AchievementService
##   inventory   — InventoryService, StorageService
##   run         — RunFlow, WavesRunService, DungeonTierService
##   presentation — AudioDirector, VfxService, PixelDioramaViewport
##   platform    — SteamService, CrashLogger, ApiConfig


func persistence() -> Dictionary:
	return {"save": LocalSave, "character": CharacterService}


func progression() -> Dictionary:
	return {
		"progression": ProgressionService,
		"quests": QuestService,
		"achievements": AchievementService,
	}


func inventory() -> Dictionary:
	return {"inventory": InventoryService, "storage": StorageService}


func run() -> Dictionary:
	return {
		"flow": RunFlow,
		"waves": WavesRunService,
		"dungeon_tiers": DungeonTierService,
	}


func presentation() -> Dictionary:
	return {
		"audio": AudioDirector,
		"vfx": VfxService,
		"pixel_viewport": PixelDioramaViewport,
	}


func platform() -> Dictionary:
	return {"steam": SteamService, "crash": CrashLogger, "api": ApiConfig}


func _ready() -> void:
	_verify_content_loaded()
	if OS.get_cmdline_args().has("--smoke-test") or OS.get_cmdline_user_args().has("--smoke-test"):
		_run_smoke_test()


## Fails loudly instead of degrading silently when the content catalogues resolve empty —
## see BUG-01. A blank catalogue otherwise presents as missing enemies, items and dialogue
## with no diagnostic, which is nearly impossible to distinguish from an authoring mistake.
func _verify_content_loaded() -> void:
	var probe := EnemyCatalog.get_definition("castle_grunt")
	if not probe.is_empty():
		return
	var details := {"content_root": ContentLoader.content_root()}
	if CrashLogger:
		CrashLogger.log_error("content.boot_check_failed", details)
	var msg := (
		(
			"Aumbrye: content catalogue failed to load (content_root=%s). The game cannot run "
			+ "without content/ — check that content_root resolves inside res:// in exported builds."
		)
		% details["content_root"]
	)
	push_error(msg)
	if OS.has_feature("editor"):
		return
	OS.alert(msg, "Aumbrye — content missing")
	get_tree().quit(1)


## QA-05: boots every subsystem an exported build needs and quits with a status code, so CI can
## catch the class of failure that only exists outside the editor (BUG-01, BUG-02) instead of
## uploading a release that has never actually run. Invoked with `--smoke-test` on the command
## line; see the `godot-export` / `smoke-test` jobs in .github/workflows/.
func _run_smoke_test() -> void:
	print("SMOKE-TEST: booting")
	var failures: Array[String] = []

	if ItemCatalog.get_definition("castle_sword").is_empty():
		failures.append("ItemCatalog.get_definition(castle_sword) is empty")
	if EnemyCatalog.get_definition("castle_grunt").is_empty():
		failures.append("EnemyCatalog.get_definition(castle_grunt) is empty")
	if ClassCatalog.get_definition("knight").is_empty():
		failures.append("ClassCatalog.get_definition(knight) is empty")

	var rig_parent := Node3D.new()
	add_child(rig_parent)
	var enemy_data := EnemyCatalog.get_definition("castle_grunt")
	var visual := DioramaCharacterSkin.build_enemy_body(
		rig_parent, "melee", 0, "castle_grunt", enemy_data
	)
	if visual == null or not is_instance_valid(visual):
		failures.append("DioramaCharacterSkin.build_enemy_body produced no rig")
	rig_parent.queue_free()

	var floor_gen: Dictionary = LocalProcgen.generate("forgotten_castle", 12345)
	if floor_gen.is_empty():
		failures.append("LocalProcgen.generate(forgotten_castle) returned empty")

	DirAccess.make_dir_recursive_absolute(LocalSave.CHARACTERS_DIR)
	LocalSave._active_character_id = "__smoke_test__"
	var payload: Dictionary = LocalSave._build_save_payload()
	var wrote: bool = LocalSave._write_save(payload, false)
	if not wrote:
		failures.append("LocalSave failed to write the smoke-test save")
	else:
		var save_path: String = LocalSave._active_save_path()
		var reread = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if not (reread is Dictionary):
			failures.append("LocalSave save could not be re-read after writing")
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(save_path)
	LocalSave._active_character_id = ""

	var exit_code := 0
	if failures.is_empty():
		print("SMOKE-TEST: OK")
	else:
		exit_code = 1
		for failure in failures:
			printerr("SMOKE-TEST FAIL: %s" % failure)
	get_tree().quit(exit_code)
