extends Node

## Boots the playable 3D scenes and writes a PNG of each, so the hub, the training arena and the
## in-run HUD can be reviewed the same way the menus are.
##
## The scenes are instanced under the root rather than swapped in with change_scene_to_file(),
## which frees the current scene — this capture node — and leaves the awaited frame never
## resuming, so the run hangs in the first world it loads. Adding them under the root still puts
## their Camera3D in the window's viewport, so they render normally.
##
## Must run windowed — a headless run has no rendering device and produces blank images.
##
## Usage:
##   godot --path apps/game/client --resolution 1920x1080 \
##     res://scenes/debug/capture_world_screens.tscn

const OUTPUT_DIR := "user://ui_captures"
const DUNGEON_FIXTURE_PATH := "content/fixtures/dungeon_definition_v2_gdscript.json"

## The debug arena is a bare test box, so it says nothing about how the game actually looks — the
## dungeon slices and the run scenes are the environments a player spends the game inside.
const SCENES: Array[String] = [
	"res://scenes/hub/hub.tscn",
	"res://scenes/combat/combat_arena.tscn",
	"res://scenes/dungeon/forgotten_castle_slice.tscn",
	"res://scenes/dungeon/castle_run.tscn",
]

## World scenes need far longer than a menu: navigation bakes, procedural dressing, streamed rooms
## and the first physics ticks all land after the initial frames. A full eighteen-room dungeon is
## the worst case — at 150 frames it was still building, which put a stalled 2 FPS in the debug
## overlay and made a scene that actually runs at ~129 FPS look like a performance disaster.
const SETTLE_FRAMES := 600


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	# A captured world can decide to change scenes on boot — the hub does exactly that when it does
	# not like the save it finds. `change_scene_to_file` frees whatever the tree calls the current
	# scene, which is this node, so the capture coroutine died mid-await and the run produced
	# nothing at all while leaving an earlier run's PNGs in place. Disowning the current-scene slot
	# leaves the scene change with nothing to free and keeps this node alive to finish the sweep.
	get_tree().current_scene = null
	_ensure_character()
	_ensure_dungeon_definition()
	await _capture_all()
	get_tree().quit(0)


## CastleRun refuses to build without a procgen definition, so a standalone capture of it produced
## an empty grey void and told us nothing about how a real dungeon is lit or dressed. It reads the
## definition from RunFlow or from a root meta; the committed fixture is a full eighteen-room
## castle floor, which is exactly what a capture wants.
func _ensure_dungeon_definition() -> void:
	if RunFlow and not RunFlow.current_dungeon_definition.is_empty():
		return
	var fixture := ContentLoader.load_json(DUNGEON_FIXTURE_PATH)
	if fixture.is_empty():
		push_warning("capture_world_screens: fixture missing at %s" % DUNGEON_FIXTURE_PATH)
		return
	get_tree().root.set_meta("dungeon_definition", fixture)


## The hub sends a classless boot straight back to the main menu, and that scene change frees this
## capture node mid-coroutine — so every world capture silently produced nothing and the stale PNGs
## from an earlier run sat there looking like fresh output.
##
## Setting the class on CharacterService alone is not enough: the hub boots by reloading the save
## over the top of the services, so the class has to exist in the save file too.
func _ensure_character() -> void:
	if CharacterService == null or LocalSave == null:
		return
	if CharacterService.get_class_id() == "":
		CharacterService.set_class_id("knight")
	LocalSave.set_character_profile("Capture Warden", CharacterService.get_class_id())
	LocalSave.autosave()


## Captures each scene twice — through the pixel pipeline and with it off — because when a world
## looks wrong it is rarely obvious whether the fault is in the scene's own materials and lighting
## or in the post-process on top of them.
func _capture_all() -> void:
	await _capture_pass("")
	PixelDioramaSettings.low_res_viewport_enabled = false
	PixelDioramaViewport.detach()
	await _capture_pass("_raw")


func _capture_pass(suffix: String) -> void:
	for scene_path in SCENES:
		if not ResourceLoader.exists(scene_path):
			push_warning("capture_world_screens: missing %s" % scene_path)
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_warning("capture_world_screens: could not load %s" % scene_path)
			continue
		var known := {}
		for child in get_tree().root.get_children():
			known[child] = true
		var instance := packed.instantiate()
		# Deferred: the root is mid-setup while this coroutine runs, and a direct add_child() there
		# fails outright — which is what left the hub rendering as an empty grey frame.
		get_tree().root.add_child.call_deferred(instance)
		await get_tree().process_frame
		for _i in SETTLE_FRAMES:
			await get_tree().process_frame
		await _clear_intruders(known, instance)
		var image := get_viewport().get_texture().get_image()
		var shot_name := scene_path.get_file().get_basename()
		var out_path := "%s/world_%s%s.png" % [OUTPUT_DIR, shot_name, suffix]
		if image.save_png(out_path) == OK:
			print("captured world_%s%s -> %s" % [shot_name, suffix, ProjectSettings.globalize_path(out_path)])
		else:
			push_warning("capture_world_screens: could not save %s" % shot_name)
		instance.queue_free()
		await get_tree().process_frame
		await _clear_intruders(known, null)


## Frees anything a booting world pulled into the root behind our back.
##
## The hub bounces to the main menu when it dislikes the save, and that menu stays parented to the
## root for the rest of the run — with a full-rect backdrop over the top of every subsequent
## capture. Both world shots came out as a picture of the main menu on a black field, which reads
## as "the arena renders nothing" rather than "something is standing in front of it".
func _clear_intruders(known: Dictionary, keep: Node) -> void:
	var removed := false
	for child in get_tree().root.get_children():
		if known.has(child) or child == keep or child == self:
			continue
		child.queue_free()
		removed = true
	if removed:
		await get_tree().process_frame
		await get_tree().process_frame
