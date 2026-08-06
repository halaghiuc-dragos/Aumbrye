extends SceneTree

## Headless exporter — no autoloads required.
##   godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd
##   godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd -- --verify
##   godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd -- --profile player
##   godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd -- --digests

const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")

const DEFAULT_OUTPUT_DIR := "res://assets/animations/diorama/"


func _initialize() -> void:
	var args := _parse_args()
	if args.has("error"):
		printerr(args["error"])
		quit(1)
		return

	var output_dir: String = args.get("out", DEFAULT_OUTPUT_DIR)
	if not output_dir.ends_with("/"):
		output_dir += "/"

	var profiles: PackedStringArray = args.get("profiles", PackedStringArray())
	if profiles.is_empty():
		printerr("no export profiles resolved")
		quit(1)
		return

	var path_errors := _validate_profile_paths(profiles, output_dir)
	if not path_errors.is_empty():
		for err in path_errors:
			printerr(err)
		quit(1)
		return

	var failures: PackedStringArray = []
	var digests: Dictionary = {}

	for profile_key in profiles:
		var rest_pose := CharacterSkin.rest_pose_for_profile(profile_key)
		if rest_pose.is_empty():
			failures.append("%s: empty rest pose" % profile_key)
			continue
		var events_path := AnimLibrary.events_path_for_profile(profile_key)
		var library := AnimLibrary.compile_authored_library(rest_pose, events_path, profile_key)
		var expected := AnimLibrary.expected_exported_clip_count(rest_pose)
		var actual := library.get_animation_list().size()
		if actual < expected:
			failures.append(
				"%s: compiled %d clips, expected at least %d" % [profile_key, actual, expected]
			)
			continue
		var digest := AnimLibrary.library_digest(library)
		digests[profile_key] = digest
		if args.get("verify", false):
			failures.append_array(_verify_profile_resource(profile_key, output_dir, digest))
			continue
		if args.get("digests_only", false):
			continue
		var out_path := "%s%s_locomotion.res" % [output_dir, profile_key]
		var err := ResourceSaver.save(library, out_path)
		if err != OK:
			failures.append("%s: %s" % [out_path, error_string(err)])
		else:
			print("Saved %s (%d clips)" % [out_path, actual])

	if args.get("verify", false):
		failures.append_array(_verify_committed_digests(digests))
	elif not args.get("digests_only", false):
		failures.append_array(_write_digests(digests, output_dir))
	else:
		failures.append_array(_write_digests(digests, output_dir))

	if not failures.is_empty():
		for failure in failures:
			printerr("export failed: %s" % failure)
		quit(1)
		return

	if args.get("verify", false):
		print("Diorama anim export verify passed.")
	else:
		print("Diorama anim export complete.")
	quit(0)


static func _parse_args() -> Dictionary:
	var user_args := OS.get_cmdline_user_args()
	if user_args.is_empty():
		user_args = PackedStringArray()
		var cmdline := OS.get_cmdline_args()
		var index := 0
		while index < cmdline.size():
			var arg := String(cmdline[index])
			if arg == "--verify" or arg == "--digests":
				user_args.append(arg)
			elif arg == "--profile" or arg == "--out":
				user_args.append(arg)
				if index + 1 < cmdline.size():
					index += 1
					user_args.append(String(cmdline[index]))
			index += 1
	var result := {
		"verify": false,
		"digests_only": false,
		"out": DEFAULT_OUTPUT_DIR,
		"profiles": PackedStringArray(),
	}
	var index := 0
	while index < user_args.size():
		var arg := String(user_args[index])
		match arg:
			"--verify":
				result["verify"] = true
			"--digests":
				result["digests_only"] = true
			"--out":
				index += 1
				if index >= user_args.size():
					return {"error": "--out requires a directory"}
				result["out"] = String(user_args[index])
			"--profile":
				index += 1
				if index >= user_args.size():
					return {"error": "--profile requires a profile key"}
				result["profiles"].append(String(user_args[index]))
			_:
				return {"error": "unknown argument: %s" % arg}
		index += 1

	if result["profiles"].is_empty():
		for profile_key in AnimLibrary.AUTHORED_LIBRARY_PATHS:
			result["profiles"].append(profile_key)
	return result


static func _validate_profile_paths(profiles: PackedStringArray, output_dir: String) -> PackedStringArray:
	var errors: PackedStringArray = []
	var authored: PackedStringArray = PackedStringArray(AnimLibrary.AUTHORED_LIBRARY_PATHS.keys())
	authored.sort()
	var expected := profiles.duplicate()
	expected.sort()
	if authored != expected:
		errors.append(
			"profile keys %s do not match AUTHORED_LIBRARY_PATHS %s"
			% [str(expected), str(authored)]
		)
	for profile_key in profiles:
		var expected_path := "%s%s_locomotion.res" % [output_dir, profile_key]
		var authored_path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS.get(profile_key, "")
		if authored_path != expected_path:
			errors.append(
				"%s output path %s does not match AUTHORED_LIBRARY_PATHS %s"
				% [profile_key, expected_path, authored_path]
			)
	return errors


static func _verify_profile_resource(
	profile_key: String, output_dir: String, digest: String
) -> PackedStringArray:
	var failures: PackedStringArray = []
	var out_path := "%s%s_locomotion.res" % [output_dir, profile_key]
	if not ResourceLoader.exists(out_path):
		return PackedStringArray(["%s: missing committed resource %s" % [profile_key, out_path]])
	var committed := ResourceLoader.load(out_path) as AnimationLibrary
	if committed == null:
		return PackedStringArray(["%s: failed to load %s" % [profile_key, out_path]])
	if AnimLibrary.library_digest(committed) != digest:
		failures.append("%s: resource digest drift" % profile_key)
	return failures


static func _write_digests(digests: Dictionary, output_dir: String) -> PackedStringArray:
	var global_dir := ProjectSettings.globalize_path(output_dir)
	if not DirAccess.dir_exists_absolute(global_dir):
		DirAccess.make_dir_recursive_absolute(global_dir)
	var payload := {
		"generator": "export_diorama_anim_libraries.gd",
		"godot": Engine.get_version_info().get("string", ""),
		"profiles": digests,
	}
	var json_text := JSON.stringify(payload, "\t") + "\n"
	var digest_path := output_dir + "digests.json"
	var file := FileAccess.open(digest_path, FileAccess.WRITE)
	if file == null:
		return PackedStringArray(["failed to open %s for writing" % digest_path])
	file.store_string(json_text)
	return PackedStringArray()


static func _verify_committed_digests(digests: Dictionary) -> PackedStringArray:
	var failures: PackedStringArray = []
	if not ResourceLoader.exists(AnimLibrary.DIGESTS_PATH):
		return PackedStringArray(["missing committed digests.json"])
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AnimLibrary.DIGESTS_PATH))
	if not parsed is Dictionary:
		return PackedStringArray(["digests.json is not an object"])
	var committed: Dictionary = parsed.get("profiles", {})
	for profile_key in digests:
		if str(committed.get(profile_key, "")) != str(digests[profile_key]):
			failures.append("%s: digests.json drift" % profile_key)
	return failures
