extends Node

## What a built dungeon floor actually submits, and what the shadow pass costs on top of it.
##
## The perf audit says castle_run is the heaviest scene in the game and that its worst frames
## already sit on the 60fps budget -- on an RTX 4070, which is not what most people will play on.
## This says where that goes: how many meshes are drawn, how many of them are also drawn a second
## time into the shadow map, and what the frame time does if the small ones stop being.
##
## Measures the castle_run subtree only. An earlier version counted everything under the scene tree
## root and picked up the hub as well, which change_scene_to_file had loaded beside it -- that was
## the probe's fault, not the game's, and it made the dungeon look twice as expensive as it is.

const SETTLE_FRAMES := 300
const SAMPLE_FRAMES := 240

## Below this diagonal, in metres, a prop's shadow is a couple of pixels at the game's camera
## distance. Above it the shadow is doing real work and stays.
const SMALL_PROP_DIAGONAL := 1.2


func _ready() -> void:
	if CharacterService != null and CharacterService.get_class_id() == "":
		CharacterService.set_class_id("knight")
	if LocalSave != null:
		LocalSave.set_character_profile("Perf Warden", CharacterService.get_class_id())
	# castle_run refuses to build without a dungeon definition, and an empty dungeon measures
	# nothing. Same fixture the capture harness uses, for the same reason.
	if RunFlow == null or RunFlow.current_dungeon_definition.is_empty():
		var fixture := ContentLoader.load_json(
			"content/fixtures/dungeon_definition_v2_gdscript.json"
		)
		if fixture.is_empty():
			print("DRAW no dungeon fixture; numbers would be meaningless")
			get_tree().quit(1)
			return
		get_tree().root.set_meta("dungeon_definition", fixture)
	var packed := load("res://scenes/dungeon/castle_run.tscn") as PackedScene
	var root := packed.instantiate()
	get_tree().root.add_child.call_deferred(root)
	await get_tree().process_frame
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	var meshes: Array[MeshInstance3D] = []
	var casters := 0
	var small_casters := 0
	var small: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		meshes.append(mi)
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		casters += 1
		var extent := mi.mesh.get_aabb().size * mi.global_transform.basis.get_scale()
		if extent.length() < SMALL_PROP_DIAGONAL:
			small_casters += 1
			small.append(mi)

	var multimesh := 0
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := node as MultiMeshInstance3D
		if mm and mm.multimesh:
			multimesh += mm.multimesh.instance_count

	print("DRAW castle_run: %d visible meshes, %d cast shadows (%d of them small), %d multimesh instances"
		% [meshes.size(), casters, small_casters, multimesh])

	# --- A/B: occlusion culling
	#
	# CastleBlockout builds an OccluderInstance3D for every room ceiling and one the size of the
	# room itself, and the project never enables occlusion culling -- so the engine has been
	# ignoring all of them. In a dungeon made of sealed rooms that is exactly the feature that
	# should stop the floor rendering rooms the player cannot see.
	var viewport := _render_viewport()
	if viewport == null:
		print("DRAW could not find the render viewport")
		get_tree().quit(1)
		return
	var occluders := root.find_children("*", "OccluderInstance3D", true, false).size()
	print("DRAW occluders in the floor: %d" % occluders)

	RenderingServer.viewport_set_use_occlusion_culling(viewport.get_viewport_rid(), false)
	for _i in 60:
		await get_tree().process_frame
	var without := await _sample()
	var drawn_without := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)

	RenderingServer.viewport_set_use_occlusion_culling(viewport.get_viewport_rid(), true)
	for _i in 60:
		await get_tree().process_frame
	var with_culling := await _sample()
	var drawn_with := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)

	print("DRAW occlusion off: %.2fms, %d objects drawn" % [without, drawn_without])
	print("DRAW occlusion on : %.2fms, %d objects drawn" % [with_culling, drawn_with])
	print("DRAW change: %.1f%% frame time, %.1f%% objects" % [
		(without - with_culling) / maxf(without, 0.001) * 100.0,
		(float(drawn_without) - float(drawn_with)) / maxf(float(drawn_without), 1.0) * 100.0])
	get_tree().quit(0)


## The game draws into its own SubViewport for the pixel pipeline, so that is the viewport whose
## culling matters -- not the window's.
func _render_viewport() -> Viewport:
	var sub := get_tree().root.find_child("PixelSubViewport", true, false) as Viewport
	return sub if sub != null else get_viewport()


func _sample() -> float:
	var last := Time.get_ticks_usec()
	var total := 0.0
	for _i in SAMPLE_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		total += float(now - last) / 1000.0
		last = now
	return total / float(SAMPLE_FRAMES)
