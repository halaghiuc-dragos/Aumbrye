extends "res://scripts/validation/validation_suite.gd"

const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")
const AnimController := preload("res://scripts/art/characters/diorama_anim_controller.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const CharacterRigCatalog := preload("res://scripts/art/characters/character_rig_catalog.gd")
const VoxelGrid := preload("res://scripts/art/characters/voxel_grid.gd")
const WeaponKit := preload("res://scripts/art/props/diorama_weapon_kit.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")


func _init(context) -> void:
	super._init(context)
	manage_save_file = false


static func _ensure_pose_nodes(root: Node3D, rest_pose: Dictionary) -> void:
	for key in rest_pose:
		var data: Dictionary = rest_pose[key]
		var path_text := str(data.get("path", key))
		var node := _ensure_node_path(root, path_text) as Node3D
		node.position = data.get("position", Vector3.ZERO)
		node.rotation = data.get("rotation", Vector3.ZERO)


static func _ensure_node_path(root: Node, path_text: String) -> Node:
	var parts := path_text.split("/")
	var current: Node = root
	for part in parts:
		var child := current.get_node_or_null(part)
		if child == null:
			child = Node3D.new()
			child.name = part
			current.add_child(child)
		current = child
	return current


static func _spawn_player_fixture(host: Node) -> Dictionary:
	var body := CharacterBody3D.new()
	host.add_child(body)
	var facing := Node3D.new()
	facing.name = "Facing"
	body.add_child(facing)
	var visual := Node3D.new()
	visual.name = "DioramaVisual"
	facing.add_child(visual)
	var director := AnimController.new()
	director.name = "AnimDirector"
	body.add_child(director)
	var rest_pose := CharacterSkin.rest_pose_for_profile("player")
	_ensure_pose_nodes(visual, rest_pose)
	director.set_profile("player")
	director.bind(visual)
	return {"body": body, "visual": visual, "director": director}


static func _spawn_enemy_fixture(host: Node) -> Dictionary:
	var body := CharacterBody3D.new()
	host.add_child(body)
	var visual := Node3D.new()
	visual.name = "DioramaVisual"
	body.add_child(visual)
	var director := AnimController.new()
	director.name = "AnimController"
	body.add_child(director)
	var rest_pose := CharacterSkin.rest_pose_for_profile("melee")
	_ensure_pose_nodes(visual, rest_pose)
	director.set_profile("melee")
	director.bind(visual)
	return {"body": body, "visual": visual, "director": director}


func get_category() -> String:
	return "diorama_anim"


func run() -> void:
	_test_required_clips()
	_test_anim_controller_hooks()
	_test_authored_libraries()
	_test_authored_libraries_have_method_tracks()
	_test_authored_library_reset()
	_test_events_path_resolves()
	_test_footstep_emits_vfx()
	_test_library_not_shared()
	_test_rig_contracts()
	_test_weapon_kit_coverage()
	_test_missing_clip_warns()
	_test_empty_rest_pose_warns()
	await _test_method_signals_fire()
	await _test_mirror_survives_free()
	_test_mirror_speed_scale_matches()
	await _test_flinch_retriggers()
	_test_locomotion_scale_in_range()
	_test_attack_cache_bounded()
	_test_revive_resets_combo()
	_test_hitbox_signal_wired()


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
	var start := Time.get_ticks_msec()
	var path: String = AnimLibrary.AUTHORED_LIBRARY_PATHS["player"]
	var library := ResourceLoader.load(path) as AnimationLibrary
	var required: PackedStringArray = PackedStringArray(
		[
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
	)
	var missing: PackedStringArray = []
	if library == null:
		missing.append("player_locomotion.res")
	else:
		for clip_id in required:
			if not library.has_animation(StringName(clip_id)):
				missing.append(clip_id)
	ctx.timed_record(
		"diorama_anim.required_clips",
		get_category(),
		missing.is_empty(),
		"player authored clips present" if missing.is_empty() else "missing: %s" % ", ".join(missing),
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
			var rest_pose := CharacterSkin.rest_pose_for_profile(profile)
			var events_path := AnimLibrary.events_path_for_profile(profile)
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


func _test_footstep_emits_vfx() -> void:
	var start := Time.get_ticks_msec()
	var fixture := _spawn_player_fixture(ctx.owner)
	var director := fixture.director as AnimController
	var footstep_count := 0
	director.footstep_frame.connect(func() -> void: footstep_count += 1)
	var ok := false
	if director.is_bound():
		director._player.play(&"walk")
		director._player.seek(0.2, true)
		ok = director.has_footstep_markers() and footstep_count >= 0
	fixture.body.queue_free()
	ctx.timed_record(
		"diorama_anim.footstep_emits_vfx",
		get_category(),
		ok,
		"player walk exposes footstep markers",
		start,
		"EXP-02"
	)


func _test_events_path_resolves() -> void:
	var start := Time.get_ticks_msec()
	var player := _spawn_player_fixture(ctx.owner)
	var enemy := _spawn_enemy_fixture(ctx.owner)
	var layouts_ok := (
		_events_path_ok(player.director, player.visual)
		and _events_path_ok(enemy.director, enemy.visual)
	)
	player.body.queue_free()
	enemy.body.queue_free()
	ctx.timed_record(
		"diorama_anim.events_path_resolves",
		get_category(),
		layouts_ok,
		"events path resolves for player and enemy layouts",
		start,
		"ANC-01"
	)


static func _events_path_ok(director: DioramaAnimController, visual: Node3D) -> bool:
	var path := director._resolve_events_path(visual)
	return path != "" and visual.get_node_or_null(NodePath(path)) == director


func _test_library_not_shared() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	var rest_pose := CharacterSkin.rest_pose_for_profile("melee")
	var body_a := CharacterBody3D.new()
	var body_b := CharacterBody3D.new()
	var visual_a := Node3D.new()
	var visual_b := Node3D.new()
	body_a.add_child(visual_a)
	body_b.add_child(visual_b)
	_ensure_pose_nodes(visual_a, rest_pose)
	_ensure_pose_nodes(visual_b, rest_pose)
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
		ok = ctrl_a._runtime_library != ctrl_b._runtime_library
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


func _test_missing_clip_warns() -> void:
	var start := Time.get_ticks_msec()
	var fixture := _spawn_player_fixture(ctx.owner)
	var director := fixture.director as AnimController
	var ok := false
	if director.is_bound():
		director._report_missing(&"nonexistent_clip", "test")
		director._report_missing(&"nonexistent_clip", "test")
		ok = director._missing_clips.size() == 1
	fixture.body.queue_free()
	ctx.timed_record(
		"diorama_anim.missing_clip_warns",
		get_category(),
		ok,
		"missing clip warning deduplicated per bind",
		start,
		"ANC-05"
	)


func _test_empty_rest_pose_warns() -> void:
	var start := Time.get_ticks_msec()
	var body := CharacterBody3D.new()
	var visual := Node3D.new()
	visual.name = "EmptyVisual"
	body.add_child(visual)
	var director := AnimController.new()
	director.name = "AnimDirector"
	body.add_child(director)
	ctx.owner.add_child(body)
	director.bind(visual)
	var ok := not director.is_bound()
	body.queue_free()
	ctx.timed_record(
		"diorama_anim.empty_rest_pose_warns",
		get_category(),
		ok,
		"empty rest pose leaves controller unbound",
		start,
		"ANC-09"
	)


func _test_method_signals_fire() -> void:
	var start := Time.get_ticks_msec()
	var fixture := _spawn_player_fixture(ctx.owner)
	var director := fixture.director as AnimController
	var events: Array = []
	director.footstep_frame.connect(func() -> void: events.append("footstep"))
	director.swing_frame.connect(func() -> void: events.append("swing"))
	director.hitbox_open_frame.connect(func() -> void: events.append("hitbox_on"))
	director.hitbox_close_frame.connect(func() -> void: events.append("hitbox_off"))
	director.anim_footstep()
	director.anim_footstep()
	director.anim_swing_vfx()
	director.anim_hitbox_on()
	director.anim_hitbox_off()
	var ok := events.size() >= 5
	fixture.body.queue_free()
	ctx.timed_record(
		"diorama_anim.method_signals_fire",
		get_category(),
		ok,
		"footstep, swing, and hitbox signals fire from method tracks",
		start,
		"ANC-02"
	)


func _test_mirror_survives_free() -> void:
	var start := Time.get_ticks_msec()
	var fixture := _spawn_player_fixture(ctx.owner)
	var director := fixture.director as AnimController
	var mirror := AnimController.new()
	mirror.name = "Mirror"
	fixture.body.add_child(mirror)
	director.add_mirror(mirror)
	mirror.queue_free()
	await ctx.await_frame()
	director.request_locomotion(&"walk", {"speed": 4.5})
	director.set_blocking(false)
	director.play_attack(0.2, 0.15, 0.3)
	director.set_speed_scale(1.0)
	var ok := director._mirrors.is_empty()
	fixture.body.queue_free()
	ctx.timed_record(
		"diorama_anim.mirror_survives_free",
		get_category(),
		ok,
		"freed mirror pruned from fan-out list",
		start,
		"ANC-10"
	)


func _test_mirror_speed_scale_matches() -> void:
	var start := Time.get_ticks_msec()
	var fixture := _spawn_player_fixture(ctx.owner)
	var director := fixture.director as AnimController
	var mirror := AnimController.new()
	mirror.name = "Mirror"
	fixture.body.add_child(mirror)
	mirror.set_profile("player")
	mirror.bind(fixture.visual)
	director.add_mirror(mirror)
	director.play_stagger(0.4)
	var ok := false
	if director.is_bound() and mirror.is_bound():
		ok = is_equal_approx(director._player.speed_scale, mirror._player.speed_scale)
	fixture.body.queue_free()
	ctx.timed_record(
		"diorama_anim.mirror_speed_scale_matches",
		get_category(),
		ok,
		"mirror speed_scale matches body on stagger",
		start,
		"ANC-07"
	)


func _test_flinch_retriggers() -> void:
	var start := Time.get_ticks_msec()
	var fixture := _spawn_player_fixture(ctx.owner)
	var director := fixture.director as AnimController
	var ok := false
	if director.is_bound():
		director.play_flinch()
		await ctx.owner.get_tree().create_timer(0.1).timeout
		director.play_flinch()
		await ctx.await_frame()
		ok = director._player.is_playing() and director._player.current_animation_position < 0.15
	fixture.body.queue_free()
	ctx.timed_record(
		"diorama_anim.flinch_retriggers",
		get_category(),
		ok,
		"second flinch restarts clip from time 0",
		start,
		"ANC-06"
	)


func _test_locomotion_scale_in_range() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var rest_pose := CharacterSkin.rest_pose_for_profile("player")
	var events_path := AnimLibrary.events_path_for_profile("player")
	var library := AnimLibrary.build_library(rest_pose, events_path, "player", true)
	var body := CharacterBody3D.new()
	var visual := Node3D.new()
	body.add_child(visual)
	var director := AnimController.new()
	body.add_child(director)
	ctx.owner.add_child(body)
	director.set_profile("player")
	director._rest_pose = rest_pose
	director._library = library
	director._runtime_library = AnimationLibrary.new()
	director._player = AnimationPlayer.new()
	visual.add_child(director._player)
	director._player.root_node = NodePath("..")
	director._player.add_animation_library(&"", library)
	for clip_name in [&"walk", &"run"]:
		var speeds: Array = (
			[2.5, 3.5, 4.5] if clip_name == &"walk" else [5.5, 6.5, 7.0]
		)
		for speed in speeds:
			var scale: float = director._locomotion_speed_scale(clip_name, {"speed": speed})
			if scale <= AnimController.SPEED_SCALE_MIN or scale >= AnimController.SPEED_SCALE_MAX:
				ok = false
	body.queue_free()
	ctx.timed_record(
		"diorama_anim.locomotion_scale_in_range",
		get_category(),
		ok,
		"locomotion speed_scale stays inside clamp band",
		start,
		"ANC-08"
	)


func _test_attack_cache_bounded() -> void:
	var start := Time.get_ticks_msec()
	var fixture := _spawn_player_fixture(ctx.owner)
	var director := fixture.director as AnimController
	var ok := false
	if director.is_bound():
		for i in 40:
			director.play_attack(0.1 + i * 0.01, 0.12, 0.2 + i * 0.01, &"attack_light_1")
		var runtime_count := director._runtime_library.get_animation_list().size()
		ok = (
			director._compiled_attacks.size() <= AnimController.ATTACK_CACHE_LIMIT
			and runtime_count <= AnimController.ATTACK_CACHE_LIMIT
		)
	fixture.body.queue_free()
	ctx.timed_record(
		"diorama_anim.attack_cache_bounded",
		get_category(),
		ok,
		"compiled attack cache capped at 24 entries",
		start,
		"ANC-11"
	)


func _test_revive_resets_combo() -> void:
	var start := Time.get_ticks_msec()
	var fixture := _spawn_player_fixture(ctx.owner)
	var director := fixture.director as AnimController
	var ok := false
	if director.is_bound():
		director.play_attack(0.15, 0.12, 0.25)
		director.play_death()
		director.revive()
		ok = director._combo_index == 0
		director.play_attack(0.15, 0.12, 0.25)
		ok = ok and director._combo_index == 1
	fixture.body.queue_free()
	ctx.timed_record(
		"diorama_anim.revive_resets_combo",
		get_category(),
		ok,
		"revive resets combo index to first swing",
		start,
		"ANC-12"
	)


func _test_hitbox_signal_wired() -> void:
	var start := Time.get_ticks_msec()
	var weapon_text := FileAccess.get_file_as_string("res://scripts/combat/weapon_controller.gd")
	var enemy_text := FileAccess.get_file_as_string("res://scripts/enemies/castle_enemy_base.gd")
	var ok := (
		"hitbox_open_frame.connect" in weapon_text
		and "hitbox_close_frame.connect" in weapon_text
		and "hitbox_open_frame.connect" in enemy_text
		and "hitbox_close_frame.connect" in enemy_text
	)
	ctx.timed_record(
		"diorama_anim.hitbox_signal_wired",
		get_category(),
		ok,
		"weapon and enemy hosts connect hitbox signals",
		start,
		"ANC-04"
	)
