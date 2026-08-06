extends "res://scripts/validation/validation_suite.gd"

const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const AnimController := preload("res://scripts/art/characters/diorama_anim_controller.gd")

const REQUIRED_PLAYER_CLIPS := [
	"idle",
	"walk",
	"run",
	"dash_f",
	"block_start",
	"flinch",
	"death",
	"heal",
	"walk_b",
	"walk_l",
	"walk_r",
	"block_walk",
]


func get_category() -> String:
	return "tools"


func run() -> void:
	_test_paths_match_authored_constant()
	_test_resources_load()
	_test_resources_clip_coverage()
	_test_resources_no_attack_clips()
	_test_resources_reset_covers_every_pivot()
	_test_method_tracks_footstep_present()
	_test_method_tracks_parry_swing_present()
	_test_digest_matches_committed()
	_test_digest_deterministic()
	_test_pose_marker_present()
	_test_pose_marker_rejects_mismatch()
	_test_pose_marker_accepts_match()
	_test_rest_pose_derives_from_rig()


func _test_paths_match_authored_constant() -> void:
	var start := Time.get_ticks_msec()
	var exporter_profiles: PackedStringArray = PackedStringArray(AnimLibrary.AUTHORED_LIBRARY_PATHS.keys())
	exporter_profiles.sort()
	var authored: PackedStringArray = PackedStringArray(AnimLibrary.AUTHORED_LIBRARY_PATHS.keys())
	authored.sort()
	ctx.timed_record(
		"export.paths.match_authored_constant",
		get_category(),
		exporter_profiles == authored,
		"exporter profiles match AUTHORED_LIBRARY_PATHS",
		start,
		"EXP-10"
	)


func _test_resources_load() -> void:
	var start := Time.get_ticks_msec()
	var failures: PackedStringArray = []
	for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		var library := ResourceLoader.load(path) as AnimationLibrary
		if library == null:
			failures.append(profile)
	ctx.timed_record(
		"export.resources.load",
		get_category(),
		failures.is_empty(),
		"all authored libraries load" if failures.is_empty() else "failed: %s" % ", ".join(failures),
		start,
		"EXP-08"
	)


func _test_resources_clip_coverage() -> void:
	var start := Time.get_ticks_msec()
	var failures: PackedStringArray = []
	for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		var library := ResourceLoader.load(path) as AnimationLibrary
		if library == null:
			failures.append("%s:load" % profile)
			continue
		var rest_pose := CharacterSkin.rest_pose_for_profile(profile)
		var expected := AnimLibrary.expected_exported_clip_count(rest_pose)
		if library.get_animation_list().size() < expected:
			failures.append("%s:count" % profile)
			continue
		for clip_id in REQUIRED_PLAYER_CLIPS if profile == "player" else ["idle", "walk", "run", "death"]:
			if not library.has_animation(StringName(clip_id)):
				failures.append("%s:%s" % [profile, clip_id])
	ctx.timed_record(
		"export.resources.clip_coverage",
		get_category(),
		failures.is_empty(),
		"exported clip coverage ok" if failures.is_empty() else "missing: %s" % ", ".join(failures),
		start,
		"EXP-09"
	)


func _test_resources_no_attack_clips() -> void:
	var start := Time.get_ticks_msec()
	var failures: PackedStringArray = []
	for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		var library := ResourceLoader.load(path) as AnimationLibrary
		if library == null:
			continue
		for attack_name in AnimLibrary.ATTACKS:
			if library.has_animation(attack_name):
				failures.append("%s:%s" % [profile, attack_name])
	ctx.timed_record(
		"export.resources.no_attack_clips",
		get_category(),
		failures.is_empty(),
		"no attack clips in authored libraries" if failures.is_empty() else "found: %s" % ", ".join(failures),
		start,
		"EXP-16"
	)


func _test_resources_reset_covers_every_pivot() -> void:
	var start := Time.get_ticks_msec()
	var failures: PackedStringArray = []
	for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		var library := ResourceLoader.load(path) as AnimationLibrary
		var rest_pose := CharacterSkin.rest_pose_for_profile(profile)
		if library == null or not library.has_animation(&"RESET"):
			failures.append(profile)
			continue
		var reset := library.get_animation(&"RESET")
		for part_name in rest_pose:
			var rest: Dictionary = rest_pose[part_name]
			var node_path: String = rest.get("path", part_name)
			if not _reset_has_track(reset, "%s:position" % node_path):
				failures.append("%s:%s:pos" % [profile, part_name])
			if not _reset_has_track(reset, "%s:rotation" % node_path):
				failures.append("%s:%s:rot" % [profile, part_name])
	ctx.timed_record(
		"export.resources.reset_covers_every_pivot",
		get_category(),
		failures.is_empty(),
		"RESET covers every pivot" if failures.is_empty() else "missing: %s" % ", ".join(failures),
		start,
		"EXP-05"
	)


func _test_method_tracks_footstep_present() -> void:
	var start := Time.get_ticks_msec()
	var failures: PackedStringArray = []
	for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		var library := ResourceLoader.load(path) as AnimationLibrary
		if library == null:
			failures.append(profile)
			continue
		for clip_name in [&"walk", &"run"]:
			if not _clip_has_method(library, clip_name, "anim_footstep", 2):
				failures.append("%s:%s" % [profile, clip_name])
	ctx.timed_record(
		"export.method_tracks.footstep_present",
		get_category(),
		failures.is_empty(),
		"footstep method tracks present" if failures.is_empty() else "missing: %s" % ", ".join(failures),
		start,
		"EXP-02"
	)


func _test_method_tracks_parry_swing_present() -> void:
	var start := Time.get_ticks_msec()
	var failures: PackedStringArray = []
	for profile in ["player", "melee", "shield", "brute", "ranged"]:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		var library := ResourceLoader.load(path) as AnimationLibrary
		if library == null or not _clip_has_method(library, &"parry_success", "anim_swing_vfx", 1):
			failures.append(profile)
	ctx.timed_record(
		"export.method_tracks.parry_swing_present",
		get_category(),
		failures.is_empty(),
		"parry swing marker present" if failures.is_empty() else "missing: %s" % ", ".join(failures),
		start,
		"EXP-02"
	)


func _test_digest_matches_committed() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	if ResourceLoader.exists(AnimLibrary.DIGESTS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AnimLibrary.DIGESTS_PATH))
		if parsed is Dictionary:
			var committed: Dictionary = parsed.get("profiles", {})
			ok = true
			for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
				var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
				var library := ResourceLoader.load(path) as AnimationLibrary
				if library == null:
					ok = false
					break
				if str(committed.get(profile, "")) != AnimLibrary.library_digest(library):
					ok = false
					break
	ctx.timed_record(
		"export.digest.matches_committed",
		get_category(),
		ok,
		"committed digests match loaded libraries",
		start,
		"EXP-03"
	)


func _test_digest_deterministic() -> void:
	var start := Time.get_ticks_msec()
	var rest_pose := CharacterSkin.rest_pose_for_profile("player")
	var events_path := AnimLibrary.events_path_for_profile("player")
	var first := AnimLibrary.library_digest(
		AnimLibrary.compile_authored_library(rest_pose, events_path, "player")
	)
	var second := AnimLibrary.library_digest(
		AnimLibrary.compile_authored_library(rest_pose, events_path, "player")
	)
	ctx.timed_record(
		"export.digest.deterministic",
		get_category(),
		first == second,
		"compile digest is deterministic",
		start,
		"EXP-03"
	)


func _test_pose_marker_present() -> void:
	var start := Time.get_ticks_msec()
	var failures: PackedStringArray = []
	for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		var library := ResourceLoader.load(path) as AnimationLibrary
		if library == null or not library.has_animation(AnimLibrary.POSE_MARKER):
			failures.append(profile)
	ctx.timed_record(
		"export.pose_marker.present",
		get_category(),
		failures.is_empty(),
		"__pose__ marker present" if failures.is_empty() else "missing: %s" % ", ".join(failures),
		start,
		"EXP-07"
	)


func _test_pose_marker_rejects_mismatch() -> void:
	var start := Time.get_ticks_msec()
	var pose := CharacterSkin.rest_pose_for_profile("player")
	var perturbed := pose.duplicate(true)
	perturbed["Torso"]["position"] = perturbed["Torso"]["position"] + Vector3(0.01, 0.0, 0.0)
	ctx.timed_record(
		"export.pose_marker.rejects_mismatch",
		get_category(),
		not AnimLibrary.can_use_authored_library(perturbed, "player"),
		"mismatched pose rejects authored library",
		start,
		"EXP-07"
	)


func _test_pose_marker_accepts_match() -> void:
	var start := Time.get_ticks_msec()
	var pose := CharacterSkin.rest_pose_for_profile("player")
	ctx.timed_record(
		"export.pose_marker.accepts_match",
		get_category(),
		AnimLibrary.can_use_authored_library(pose, "player"),
		"matching pose accepts authored library",
		start,
		"EXP-07"
	)


func _test_rest_pose_derives_from_rig() -> void:
	var start := Time.get_ticks_msec()
	var pose := CharacterSkin.rest_pose_for_profile("player")
	var required := [
		"Root",
		"Torso",
		"Head",
		"ArmL",
		"ArmR",
		"LegL",
		"LegR",
		"WeaponMount",
		"ShieldMount",
	]
	var ok := true
	for part_name in required:
		if not pose.has(part_name):
			ok = false
	for key in pose:
		if str(key).ends_with("Mesh"):
			ok = false
	ctx.timed_record(
		"export.rest_pose.derives_from_rig",
		get_category(),
		ok,
		"rest_pose_for_profile includes mount pivots",
		start,
		"EXP-04"
	)


static func _reset_has_track(reset: Animation, track_path: String) -> bool:
	for track_idx in reset.get_track_count():
		if String(reset.track_get_path(track_idx)) == track_path:
			return true
	return false


static func _clip_has_method(
	library: AnimationLibrary, clip_name: StringName, method_name: String, expected_count: int
) -> bool:
	if not library.has_animation(clip_name):
		return false
	var anim := library.get_animation(clip_name)
	var count := 0
	for track_idx in anim.get_track_count():
		if anim.track_get_type(track_idx) != Animation.TYPE_METHOD:
			continue
		for key_idx in anim.track_get_key_count(track_idx):
			var method_data: Dictionary = anim.track_get_key_value(track_idx, key_idx)
			if String(method_data.get("method", "")) == method_name:
				count += 1
	return count == expected_count
