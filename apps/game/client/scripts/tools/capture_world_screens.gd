extends Node


const OUTPUT_DIR := "user://ui_captures"
const DUNGEON_FIXTURE_PATH := "content/fixtures/dungeon_definition_v2_gdscript.json"

const SCENES: Array[String] = [
	"res://scenes/hub/hub.tscn",
	"res://scenes/combat/combat_arena.tscn",
	"res://scenes/dungeon/forgotten_castle_slice.tscn",
	"res://scenes/dungeon/castle_run.tscn",
]

const SETTLE_FRAMES := 600


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	get_tree().current_scene = null
	_ensure_character()
	_ensure_dungeon_definition()
	await _capture_all()
	get_tree().quit(0)


func _ensure_dungeon_definition() -> void:
	if RunFlow and not RunFlow.current_dungeon_definition.is_empty():
		return
	var fixture := ContentLoader.load_json(DUNGEON_FIXTURE_PATH)
	if fixture.is_empty():
		push_warning("capture_world_screens: fixture missing at %s" % DUNGEON_FIXTURE_PATH)
		return
	get_tree().root.set_meta("dungeon_definition", fixture)


func _ensure_character() -> void:
	if CharacterService == null or LocalSave == null:
		return
	if CharacterService.get_class_id() == "":
		CharacterService.set_class_id("knight")
	LocalSave.set_character_profile("Capture Warden", CharacterService.get_class_id())
	LocalSave.autosave()


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
