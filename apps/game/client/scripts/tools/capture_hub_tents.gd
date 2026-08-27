extends Node


const OUTPUT_DIR := "user://ui_captures"
const SETTLE_FRAMES := 420

const SUBJECTS: Array[Dictionary] = [
	{"name": "blacksmith", "at": Vector3(-18.0, 0.0, -2.0)},
	{"name": "merchant", "at": Vector3(18.0, 0.0, -2.0)},
	{"name": "storage", "at": Vector3(-18.0, 0.0, 8.0)},
	{"name": "quest_board", "at": Vector3(18.0, 0.0, 8.0)},
]
const STAND_OFF := 9.0
const PITCH := -0.22


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	get_tree().current_scene = null
	_ensure_character()
	var packed := load("res://scenes/hub/hub.tscn") as PackedScene
	if packed == null:
		print("TENTS: hub scene missing")
		get_tree().quit(1)
		return
	var known := {}
	for child in get_tree().root.get_children():
		known[child] = true
	var hub := packed.instantiate()
	get_tree().root.add_child.call_deferred(hub)
	await get_tree().process_frame
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await _clear_intruders(known, hub)

	var player := hub.get_node_or_null("Player") as Node3D
	var pivot := hub.get_node_or_null("Player/CameraPivot") as Node3D
	var arm := hub.get_node_or_null("Player/CameraPivot/SpringArm3D")
	if player == null or pivot == null:
		print("TENTS: no player to move")
		get_tree().quit(1)
		return
	for subject in SUBJECTS:
		var at: Vector3 = subject["at"]
		var out := Vector3(-at.x, 0.0, -at.z)
		if out.length_squared() < 0.001:
			out = Vector3(0.0, 0.0, 1.0)
		out = out.normalized()
		player.global_position = at + out * STAND_OFF
		pivot.rotation.y = atan2(out.x, out.z)
		if arm != null:
			arm.set("_pitch", PITCH)
		for i in 90:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		var path := (
			ProjectSettings.globalize_path(OUTPUT_DIR)
			.path_join("tent_%s.png" % str(subject["name"]))
		)
		if image.save_png(path) == OK:
			print("captured tent %s -> %s" % [subject["name"], path])
	get_tree().quit(0)


func _ensure_character() -> void:
	if CharacterService == null or LocalSave == null:
		return
	if CharacterService.get_class_id() == "":
		CharacterService.set_class_id("knight")
	LocalSave.set_character_profile("Capture Warden", CharacterService.get_class_id())
	LocalSave.autosave()


func _clear_intruders(known: Dictionary, keep: Node) -> void:
	var removed := false
	for child in get_tree().root.get_children():
		if known.has(child) or child == keep or child == self:
			continue
		child.queue_free()
		removed = true
	if removed:
		await get_tree().process_frame
