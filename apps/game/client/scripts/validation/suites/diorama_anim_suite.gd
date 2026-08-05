extends "res://scripts/validation/validation_suite.gd"

const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_required_clips()
	_test_anim_controller_hooks()
	_test_authored_libraries()


func _test_authored_libraries() -> void:
	var start := Time.get_ticks_msec()
	var missing: PackedStringArray = []
	for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		if not ResourceLoader.exists(path):
			missing.append(profile)
	ctx.timed_record(
		"diorama_anim.authored_libraries",
		get_category(),
		missing.is_empty(),
		"authored .res libraries present" if missing.is_empty() else "missing: %s" % ", ".join(missing),
		start,
		"M7.graphics.anim"
	)


func _test_required_clips() -> void:
	var required: PackedStringArray = PackedStringArray([
		"idle", "walk", "run", "attack_light_1", "attack_heavy", "dash_f", "block_start", "flinch", "death",
	])
	var missing: PackedStringArray = []
	for clip_id in required:
		var clip_name := StringName(clip_id)
		if not AnimLibrary.CLIPS.has(clip_name) and not AnimLibrary.ATTACKS.has(clip_name):
			missing.append(clip_id)
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"diorama_anim.required_clips",
		get_category(),
		missing.is_empty(),
		"core clips present" if missing.is_empty() else "missing: %s" % ", ".join(missing),
		start,
		"M7.graphics.anim"
	)


func _test_anim_controller_hooks() -> void:
	var script_path := "res://scripts/art/characters/diorama_anim_controller.gd"
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string(script_path) if FileAccess.file_exists(script_path) else ""
	var has_markers := "anim_hitbox_on" in text and "anim_hitbox_off" in text
	ctx.timed_record(
		"diorama_anim.controller_markers",
		get_category(),
		has_markers,
		"anim controller defines hitbox marker hooks",
		start,
		"M7.graphics.anim"
	)
