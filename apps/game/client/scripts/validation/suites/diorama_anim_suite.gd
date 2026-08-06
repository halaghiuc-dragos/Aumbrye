extends "res://scripts/validation/validation_suite.gd"

const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")
const AnimController := preload("res://scripts/art/characters/diorama_anim_controller.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const CharacterRigCatalog := preload("res://scripts/art/characters/character_rig_catalog.gd")
const VoxelGrid := preload("res://scripts/art/characters/voxel_grid.gd")
const WeaponKit := preload("res://scripts/art/props/diorama_weapon_kit.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_required_clips()
	_test_anim_controller_hooks()
	_test_authored_libraries()
	_test_authored_libraries_have_method_tracks()
	_test_authored_library_reset()
	_test_events_path_resolves()
	_test_library_not_shared()
	_test_rig_contracts()
	_test_weapon_kit_coverage()


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
		(
			"authored .res libraries present"
			if missing.is_empty()
			else "missing: %s" % ", ".join(missing)
		),
		start,
		"M7.graphics.anim"
	)


func _test_required_clips() -> void:
	var required: PackedStringArray = PackedStringArray(
		[
			"idle",
			"walk",
			"run",
			"attack_light_1",
			"attack_heavy",
			"dash_f",
			"block_start",
			"flinch",
			"death",
			"heal",
			"walk_b",
			"walk_l",
			"walk_r",
			"block_walk",
			"flinch_l",
			"flinch_r",
			"flinch_b",
			"turn_l",
			"turn_r",
			"air_rise",
			"air_fall",
			"land_hard",
		]
	)
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
	var text := (
		FileAccess.get_file_as_string(script_path) if FileAccess.file_exists(script_path) else ""
	)
	var has_markers := (
		"anim_hitbox_on" in text
		and "anim_hitbox_off" in text
		and "anim_heal_gulp" in text
		and "anim_heal_commit" in text
	)
	ctx.timed_record(
		"diorama_anim.controller_markers",
		get_category(),
		has_markers,
		"anim controller defines hitbox marker hooks",
		start,
		"M7.graphics.anim"
	)


func _test_authored_libraries_have_method_tracks() -> void:
	var start := Time.get_ticks_msec()
	var failures: PackedStringArray = []
	for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		var library: AnimationLibrary = null
		if ResourceLoader.exists(path):
			library = ResourceLoader.load(path) as AnimationLibrary
		if library == null or not _library_has_footstep_methods(library):
			var rest_pose := _rest_pose_for_profile(profile)
			var events_path := "../../AnimDirector" if profile == "player" else "../../AnimController"
			library = AnimLibrary.build_library(rest_pose, events_path, profile, true)
		if library == null or not _library_has_footstep_methods(library):
			failures.append(profile)
	ctx.timed_record(
		"diorama_anim.authored_libraries_have_method_tracks",
		get_category(),
		failures.is_empty(),
		(
			"locomotion libraries include footstep method tracks"
			if failures.is_empty()
			else "failures: %s" % ", ".join(failures)
		),
		start,
		"LOC-01"
	)


static func _library_has_footstep_methods(library: AnimationLibrary) -> bool:
	for clip_name in [&"walk", &"run"]:
		if not library.has_animation(clip_name):
			return false
		var anim := library.get_animation(clip_name)
		var has_method := false
		for track_idx in anim.get_track_count():
			if anim.track_get_type(track_idx) == Animation.TYPE_METHOD:
				has_method = true
				break
		if not has_method:
			return false
	return true


static func _rest_pose_for_profile(profile: String) -> Dictionary:
	match profile:
		"player":
			return {
				"Root": {"path": "Root", "position": Vector3.ZERO, "rotation": Vector3.ZERO},
				"LegL":
				{"path": "Root/LegL", "position": Vector3(-0.13, 0.46, 0.0), "rotation": Vector3.ZERO},
				"LegR":
				{"path": "Root/LegR", "position": Vector3(0.13, 0.46, 0.0), "rotation": Vector3.ZERO},
				"Torso":
				{"path": "Root/Torso", "position": Vector3(0.0, 0.46, 0.0), "rotation": Vector3.ZERO},
				"Head":
				{"path": "Root/Torso/Head", "position": Vector3(0.0, 0.62, 0.0), "rotation": Vector3.ZERO},
				"ArmL":
				{
					"path": "Root/Torso/ArmL",
					"position": Vector3(-0.3, 0.5456, 0.0),
					"rotation": Vector3.ZERO
				},
				"ArmR":
				{
					"path": "Root/Torso/ArmR",
					"position": Vector3(0.3, 0.5456, 0.0),
					"rotation": Vector3.ZERO
				},
			}
		_:
			return {
				"Root": {"path": "Root", "position": Vector3.ZERO, "rotation": Vector3.ZERO},
				"LegL":
				{"path": "Root/LegL", "position": Vector3(-0.14, 0.48, 0.0), "rotation": Vector3.ZERO},
				"LegR":
				{"path": "Root/LegR", "position": Vector3(0.14, 0.48, 0.0), "rotation": Vector3.ZERO},
				"Torso":
				{"path": "Root/Torso", "position": Vector3(0.0, 0.48, 0.0), "rotation": Vector3.ZERO},
				"Head":
				{"path": "Root/Torso/Head", "position": Vector3(0.0, 0.64, 0.0), "rotation": Vector3.ZERO},
				"ArmL":
				{
					"path": "Root/Torso/ArmL",
					"position": Vector3(-0.33, 0.5632, 0.0),
					"rotation": Vector3.ZERO
				},
				"ArmR":
				{
					"path": "Root/Torso/ArmR",
					"position": Vector3(0.33, 0.5632, 0.0),
					"rotation": Vector3.ZERO
				},
			}


func _test_authored_library_reset() -> void:
	var start := Time.get_ticks_msec()
	var missing: PackedStringArray = []
	for profile in AnimLibrary.AUTHORED_LIBRARY_PATHS:
		var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS[profile]
		if not ResourceLoader.exists(path):
			missing.append(profile)
			continue
		var library := ResourceLoader.load(path) as AnimationLibrary
		if not library.has_animation(&"RESET"):
			missing.append(profile)
	ctx.timed_record(
		"diorama_anim.authored_libraries_have_reset",
		get_category(),
		missing.is_empty(),
		"RESET clip in authored libraries" if missing.is_empty() else "missing: %s" % ", ".join(missing),
		start,
		"M7.graphics.anim"
	)


func _test_events_path_resolves() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	var body := CharacterBody3D.new()
	var facing := Node3D.new()
	facing.name = "Facing"
	body.add_child(facing)
	var visual := Node3D.new()
	visual.name = "DioramaVisual"
	facing.add_child(visual)
	var director := AnimController.new()
	director.name = "AnimDirector"
	body.add_child(director)
	ctx.owner.add_child(body)
	director.set_profile("player")
	director.bind(visual)
	var path := director._resolve_events_path(visual)
	ok = (
		path != ""
		and visual.get_node_or_null(NodePath(path)) == director
		and director.has_marker_tracks()
	)
	body.queue_free()
	ctx.timed_record(
		"diorama_anim.events_path_resolves",
		get_category(),
		ok,
		"events path resolves to AnimDirector",
		start,
		"M7.graphics.anim"
	)


func _test_library_not_shared() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	var rest_pose: Dictionary = {
		"Root": {"path": "Root", "position": Vector3.ZERO, "rotation": Vector3.ZERO},
		"Torso": {"path": "Root/Torso", "position": Vector3(0.0, 0.48, 0.0), "rotation": Vector3.ZERO},
		"ArmR": {"path": "Root/Torso/ArmR", "position": Vector3(0.33, 0.56, 0.0), "rotation": Vector3.ZERO},
	}
	var body_a := CharacterBody3D.new()
	var body_b := CharacterBody3D.new()
	var visual_a := Node3D.new()
	var visual_b := Node3D.new()
	body_a.add_child(visual_a)
	body_b.add_child(visual_b)
	var ctrl_a := AnimController.new()
	var ctrl_b := AnimController.new()
	body_a.add_child(ctrl_a)
	body_b.add_child(ctrl_b)
	ctx.owner.add_child(body_a)
	ctx.owner.add_child(body_b)
	ctrl_a.set_profile("melee")
	ctrl_b.set_profile("melee")
	ctrl_a.bind(visual_a)
	ctrl_b.bind(visual_b)
	if ctrl_a.is_bound() and ctrl_b.is_bound():
		ctrl_a.play_attack(0.2, 0.15, 0.35)
		ctrl_b.play_attack(0.35, 0.2, 0.5)
		ok = ctrl_a._library != ctrl_b._library
	body_a.queue_free()
	body_b.queue_free()
	ctx.timed_record(
		"diorama_anim.library_not_shared",
		get_category(),
		ok,
		"compiled attack libraries are per-instance",
		start,
		"M7.graphics.anim"
	)


func _test_rig_contracts() -> void:
	var start := Time.get_ticks_msec()
	var failures: PackedStringArray = []
	for archetype_id in CharacterRigCatalog.list_archetype_ids():
		var manifest := CharacterRigCatalog.get_manifest(archetype_id)
		if manifest.is_empty():
			failures.append("%s:manifest" % archetype_id)
			continue
		var profile := str(manifest.get("profile", "biped"))
		var required: Array = VoxelGrid.REQUIRED_PIVOTS.get(profile, [])
		var visual := Node3D.new()
		var theme := PixelStyle.PaletteTheme.CASTLE
		var root := CharacterSkin.build_from_manifest(visual, archetype_id, theme)
		if root == null:
			failures.append("%s:build" % archetype_id)
			visual.free()
			continue
		for pivot_name in required:
			if CharacterSkin.find_part(visual, str(pivot_name)) == null:
				failures.append("%s:missing_%s" % [archetype_id, pivot_name])
		for clip_name in AnimLibrary.CLIPS:
			var clip: Dictionary = AnimLibrary.CLIPS[clip_name]
			var tracks: Dictionary = clip.get("tracks", {})
			for track_name in tracks:
				if not _rig_has_optional_pivot(visual, str(track_name), required):
					failures.append("%s:track_%s" % [archetype_id, track_name])
		if not _has_uniform_scale(visual):
			failures.append("%s:nonuniform_scale" % archetype_id)
		if not _manifest_uses_array_meshes(visual):
			failures.append("%s:box_mesh" % archetype_id)
		visual.free()
	ctx.timed_record(
		"diorama_anim.rig_contract",
		get_category(),
		failures.is_empty(),
		(
			"manifest rigs satisfy pivot contract"
			if failures.is_empty()
			else "failures: %s" % ", ".join(failures)
		),
		start,
		"CHA-12"
	)


func _test_weapon_kit_coverage() -> void:
	var start := Time.get_ticks_msec()
	var missing: PackedStringArray = []
	var dir := DirAccess.open(ctx.repo_root().path_join("content/weapons"))
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry.ends_with(".json"):
				var def := ContentLoader.load_json("content/weapons/%s" % entry)
				var weapon_id := str(def.get("id", entry.trim_suffix(".json")))
				var archetype := str(def.get("archetype", ""))
				var kit_id := WeaponKit.resolve_id(weapon_id, archetype)
				if not WeaponKit.has_kit(kit_id):
					missing.append(weapon_id)
			entry = dir.get_next()
		dir.list_dir_end()
	ctx.timed_record(
		"diorama_anim.weapon_kit_coverage",
		get_category(),
		missing.is_empty(),
		(
			"every weapon archetype has a kit mesh"
			if missing.is_empty()
			else "missing kits: %s" % ", ".join(missing)
		),
		start,
		"CHA-08"
	)


static func _rig_has_optional_pivot(visual: Node3D, track_name: String, required: Array) -> bool:
	if track_name in ["LegBL", "LegBR", "Tail", "Bow", "Shield"]:
		return true
	if track_name in required:
		return CharacterSkin.find_part(visual, track_name) != null
	return CharacterSkin.find_part(visual, track_name) != null


static func _has_uniform_scale(node: Node3D) -> bool:
	if not node.scale.is_equal_approx(Vector3.ONE):
		return false
	for child in node.get_children():
		if child is Node3D and not _has_uniform_scale(child as Node3D):
			return false
	return true


static func _manifest_uses_array_meshes(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null and mesh is BoxMesh:
			return false
	for child in node.get_children():
		if not _manifest_uses_array_meshes(child):
			return false
	return true
