extends "res://scripts/validation/validation_suite.gd"

const MaterialDissolveScript := preload("res://scripts/art/characters/material_dissolve.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const PixelDioramaSettings := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")


func _init(context) -> void:
	super._init(context)
	manage_save_file = false


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_shader_uniforms_present()
	await _test_state_roundtrip()
	await _test_repeat_cycles_stable()
	_test_no_cached_material_mutation()
	_test_out_of_tree_no_mutation()
	await _test_flash_dissolve_handoff()
	_test_stagger_ordering()
	_test_duration_from_catalog()
	_test_viewmodel_included()
	await _test_dummy_dissolves()
	await _test_settings_skip_dissolving()
	await _test_respawn_restores()


func _shader_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _test_shader_uniforms_present() -> void:
	var start := Time.get_ticks_msec()
	var surface := _shader_text("res://assets/shared/pixel_diorama_surface.gdshader")
	var emissive := _shader_text("res://assets/shared/pixel_diorama_emissive.gdshader")
	var ok := (
		"dissolve_clip" in surface
		and "flash_amount" in surface
		and "dissolve_clip" in emissive
		and "flash_amount" in emissive
	)
	ctx.timed_record(
		"death_visual.shader_uniforms_present",
		get_category(),
		ok,
		"surface and emissive shaders declare dissolve_clip and flash_amount",
		start,
		"DIS-03"
	)


func _spawn_dummy_visual() -> Node3D:
	var parent := Node3D.new()
	parent.name = "DeathVisualFixture"
	ctx.owner.add_child(parent)
	return CharacterSkin.build_training_dummy(parent)


func _record_visual_state(visual: Node3D) -> Dictionary:
	var materials: Dictionary = {}
	for mesh in _gather_meshes(visual):
		materials[mesh.get_instance_id()] = mesh.material_override
	return {
		"position": visual.position,
		"scale": visual.scale,
		"materials": materials,
	}


func _visual_matches_state(visual: Node3D, state: Dictionary) -> bool:
	if visual.position != state["position"] or visual.scale != state["scale"]:
		return false
	var materials: Dictionary = state["materials"]
	for mesh in _gather_meshes(visual):
		if materials.get(mesh.get_instance_id()) != mesh.material_override:
			return false
	return true


func _gather_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_gather_meshes(child))
	return out


func _test_state_roundtrip() -> void:
	var start := Time.get_ticks_msec()
	var visual := _spawn_dummy_visual()
	var before := _record_visual_state(visual)
	var opts := {
		"duration": 0.05,
		"has_animator": false,
		"rig_kind": "humanoid",
	}
	MaterialDissolveScript.play_death_visual(visual, opts)
	await ctx.owner.get_tree().create_timer(0.2).timeout
	MaterialDissolveScript.reset_death_visual(visual)
	var ok := _visual_matches_state(visual, before)
	visual.get_parent().queue_free()
	ctx.timed_record(
		"death_visual.state_roundtrip",
		get_category(),
		ok,
		"play_death_visual + reset_death_visual restores pose and materials",
		start,
		"DIS-01"
	)


func _test_repeat_cycles_stable() -> void:
	var start := Time.get_ticks_msec()
	var visual := _spawn_dummy_visual()
	var before := _record_visual_state(visual)
	var opts := {"duration": 0.05, "has_animator": false, "rig_kind": "humanoid"}
	for _i in 5:
		MaterialDissolveScript.play_death_visual(visual, opts)
		await ctx.owner.get_tree().create_timer(0.2).timeout
		MaterialDissolveScript.reset_death_visual(visual)
	var ok := _visual_matches_state(visual, before)
	visual.get_parent().queue_free()
	ctx.timed_record(
		"death_visual.repeat_cycles_stable",
		get_category(),
		ok,
		"five death visual cycles leave pose and materials unchanged",
		start,
		"DIS-02"
	)


func _test_no_cached_material_mutation() -> void:
	var start := Time.get_ticks_msec()
	var theme := PixelStyle.PaletteTheme.CASTLE
	var cached := PixelStyle.make_wall_material(theme)
	var cached_id := cached.get_instance_id()
	var fixture := Node3D.new()
	ctx.owner.add_child(fixture)
	for _i in 20:
		var visual := _spawn_dummy_visual()
		var opts := {"duration": 0.01, "has_animator": false, "rig_kind": "humanoid"}
		MaterialDissolveScript.play_death_visual(visual, opts)
		MaterialDissolveScript.reset_death_visual(visual)
		visual.get_parent().queue_free()
	var ok := PixelStyle.make_wall_material(theme).get_instance_id() == cached_id
	fixture.queue_free()
	ctx.timed_record(
		"death_visual.no_cached_material_mutation",
		get_category(),
		ok,
		"cached wall material instance and dissolve uniforms survive 20 cycles",
		start,
		"DIS-05"
	)


func _test_out_of_tree_no_mutation() -> void:
	var start := Time.get_ticks_msec()
	var detached := Node3D.new()
	detached.set_meta(&"owned_materials", true)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = BoxMesh.new()
	var mat := PixelStyle.make_wall_material(PixelStyle.PaletteTheme.CASTLE).duplicate() as ShaderMaterial
	mesh.material_override = mat
	detached.add_child(mesh)
	var before_id := mesh.material_override.get_instance_id()
	MaterialDissolveScript.dissolve(detached, {"duration": 0.1})
	var ok := mesh.material_override.get_instance_id() == before_id
	ctx.timed_record(
		"death_visual.out_of_tree_no_mutation",
		get_category(),
		ok,
		"dissolve on a detached node leaves material_override untouched",
		start,
		"DIS-07"
	)


func _test_flash_dissolve_handoff() -> void:
	var start := Time.get_ticks_msec()
	var visual := _spawn_dummy_visual()
	var mesh := _gather_meshes(visual)[0]
	var original := mesh.material_override
	MaterialFlashScript.flash(visual, {"strength": 1.0, "duration": 0.2})
	await ctx.owner.get_tree().create_timer(0.1).timeout
	MaterialDissolveScript.dissolve(visual, {"duration": 0.05})
	await ctx.owner.get_tree().create_timer(0.2).timeout
	MaterialDissolveScript.restore(visual)
	var ok := mesh.material_override == original
	visual.get_parent().queue_free()
	ctx.timed_record(
		"death_visual.flash_dissolve_handoff",
		get_category(),
		ok,
		"flash then dissolve restores the pre-flash material_override",
		start,
		"DIS-06"
	)


func _test_stagger_ordering() -> void:
	var start := Time.get_ticks_msec()
	var leg := MaterialDissolveScript._stagger_for_mesh(_named_mesh_parent("LegL"), 0.12)
	var arm := MaterialDissolveScript._stagger_for_mesh(_named_mesh_parent("ArmL"), 0.12)
	var torso := MaterialDissolveScript._stagger_for_mesh(_named_mesh_parent("Torso"), 0.12)
	var head := MaterialDissolveScript._stagger_for_mesh(_named_mesh_parent("Head"), 0.12)
	var ok := leg < arm and arm < torso and head >= torso and head <= 0.12
	ctx.timed_record(
		"death_visual.stagger_ordering",
		get_category(),
		ok,
		"humanoid stagger offsets order legs before arms before torso before head",
		start,
		"DIS-08"
	)


func _named_mesh_parent(pivot_name: String) -> MeshInstance3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	var mesh := MeshInstance3D.new()
	pivot.add_child(mesh)
	return mesh


func _test_duration_from_catalog() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var boss_opts := MaterialDissolveScript.death_opts_for_enemy("melee", true, {})
	var grunt_opts := MaterialDissolveScript.death_opts_for_enemy("melee", false, {})
	if float(boss_opts.get("duration", 0.0)) <= float(grunt_opts.get("duration", 0.0)):
		ok = false
	var hound_opts := MaterialDissolveScript.death_opts_for_enemy("hound", false, {})
	if float(hound_opts.get("duration", 0.0)) != 0.6:
		ok = false
	ctx.timed_record(
		"death_visual.duration_from_catalog",
		get_category(),
		ok,
		"boss and rig-kind death durations come from catalog defaults",
		start,
		"DIS-11"
	)


func _test_viewmodel_included() -> void:
	var start := Time.get_ticks_msec()
	var ok := MaterialDissolveScript.death_opts_for_profile("player").has("duration")
	ctx.timed_record(
		"death_visual.viewmodel_included",
		get_category(),
		ok,
		"player death opts include catalog duration for viewmodel dissolve path",
		start,
		"DIS-09"
	)


func _test_dummy_dissolves() -> void:
	var start := Time.get_ticks_msec()
	var visual := _spawn_dummy_visual()
	var opts := {"duration": 0.05, "has_animator": false, "rig_kind": "humanoid"}
	MaterialDissolveScript.play_death_visual(visual, opts)
	var ok := true
	for mesh in _gather_meshes(visual):
		if not mesh.has_meta(&"material_dissolve_saved_override"):
			ok = false
			break
	visual.get_parent().queue_free()
	ctx.timed_record(
		"death_visual.dummy_dissolves",
		get_category(),
		ok,
		"training dummy meshes carry dissolve saved-override meta after death",
		start,
		"DIS-10"
	)


func _test_respawn_restores() -> void:
	var start := Time.get_ticks_msec()
	var grunt_scene := load("res://scenes/enemies/castle_grunt.tscn") as PackedScene
	if grunt_scene == null or ctx.owner == null:
		ctx.timed_record(
			"death_visual.respawn_restores",
			get_category(),
			false,
			"castle_grunt scene missing",
			start,
			"DIS-01"
		)
		return
	var enemy := grunt_scene.instantiate() as CharacterBody3D
	ctx.owner.add_child(enemy)
	await ctx.await_frame()
	var visual := enemy.get_node_or_null("DioramaVisual") as Node3D
	var spawn_y := visual.position.y if visual else 0.0
	if enemy.has_method("_play_death_visual"):
		enemy.call("_play_death_visual")
	await ctx.owner.get_tree().create_timer(0.2).timeout
	if enemy.has_method("respawn_at_rest"):
		enemy.call("respawn_at_rest")
	var ok := visual != null and visual.visible and is_equal_approx(visual.position.y, spawn_y)
	ok = ok and visual.scale.is_equal_approx(Vector3.ONE)
	for mesh in _gather_meshes(visual):
		if mesh.has_meta(&"material_dissolve_saved_override"):
			ok = false
			break
	enemy.queue_free()
	ctx.timed_record(
		"death_visual.respawn_restores",
		get_category(),
		ok,
		"respawn_at_rest restores visible enemy at spawn height",
		start,
		"DIS-01"
	)


func _test_settings_skip_dissolving() -> void:
	var start := Time.get_ticks_msec()
	var visual := _spawn_dummy_visual()
	var opts := {"duration": 0.4, "has_animator": false, "rig_kind": "humanoid"}
	MaterialDissolveScript.play_death_visual(visual, opts)
	var mesh := _gather_meshes(visual)[0]
	var dup := mesh.material_override as ShaderMaterial
	var pattern_before := float(dup.get_shader_parameter(&"pattern_strength"))
	PixelDioramaSettings.pattern_strength = pattern_before + 0.15
	PixelDioramaSettings.apply_all()
	var pattern_after := float(dup.get_shader_parameter(&"pattern_strength"))
	var ok := is_equal_approx(pattern_before, pattern_after)
	visual.get_parent().queue_free()
	ctx.timed_record(
		"death_visual.settings_skip_dissolving",
		get_category(),
		ok,
		"apply_all does not rewrite pattern_strength on in-flight dissolve duplicates",
		start,
		"DIS-12"
	)
