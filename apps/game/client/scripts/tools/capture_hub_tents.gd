extends Node

## A contact sheet of the four hub service tents, each framed from the front.
##
## The world capture points its camera wherever the player happens to spawn, which is away from the
## service row — so every question about the tents ("what is that blue box inside?", "are they big
## enough?") was being answered from memory rather than from a picture.
##
## Must run windowed — a headless run has no rendering device and produces blank images.
##
## **This writes the save.** It boots `hub.tscn`, and the hub bounces a classless save straight back
## to the main menu, so a character has to exist first — exactly as `capture_world_screens` does it.
## Snapshot `characters/`, `backups/` and `character_roster.json` before running it, and restore
## after.
##
## Usage:
##   godot --path apps/game/client --resolution 1280x720 res://scenes/debug/capture_hub_tents.tscn

const OUTPUT_DIR := "user://ui_captures"
const SETTLE_FRAMES := 420

## Each service and where its tent stands, from `hub.tscn`.
const SUBJECTS: Array[Dictionary] = [
	{"name": "blacksmith", "at": Vector3(-18.0, 0.0, -2.0)},
	{"name": "merchant", "at": Vector3(18.0, 0.0, -2.0)},
	{"name": "storage", "at": Vector3(-18.0, 0.0, 8.0)},
	{"name": "quest_board", "at": Vector3(18.0, 0.0, 8.0)},
]
## Where the warden is put to look at each tent: in front of it, out in the plaza.
const STAND_OFF := 13.0
## Looking slightly down, so the shot shows the inside of the stall and not the sky above it.
const PITCH := -0.22


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	# Disowning the current-scene slot leaves a scene change with nothing to free, so this node
	# survives to finish the sweep. See `capture_world_screens`, which learnt it the hard way.
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
	# Deferred: the root is mid-setup while this coroutine runs and a direct add_child() fails
	# outright, which renders as an empty grey frame.
	get_tree().root.add_child.call_deferred(hub)
	await get_tree().process_frame
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await _clear_intruders(known, hub)

	# The player, not a camera of our own. Everything renders through the pixel-diorama viewport,
	# which mirrors the gameplay camera — a second `current` Camera3D takes the screen away from
	# that pipeline and produces a flat grey frame.
	var player := hub.get_node_or_null("Player") as Node3D
	var pivot := hub.get_node_or_null("Player/CameraPivot") as Node3D
	var arm := hub.get_node_or_null("Player/CameraPivot/SpringArm3D")
	if player == null or pivot == null:
		print("TENTS: no player to move")
		get_tree().quit(1)
		return
	for subject in SUBJECTS:
		var at: Vector3 = subject["at"]
		player.global_position = at + Vector3(0.0, 0.0, STAND_OFF)
		# Face the tent. The camera sits behind the warden, looking the way the pivot points.
		pivot.rotation.y = 0.0
		if arm != null:
			arm.set("_pitch", PITCH)
		# Long enough for the teleport to settle: the arm springs out from wherever it was, and a
		# shot taken while it is still travelling is a picture of the inside of a tent pole.
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


## Frees anything a booting world pulled into the root behind our back — the main menu in
## particular, which otherwise sits over every shot with a full-rect backdrop.
func _clear_intruders(known: Dictionary, keep: Node) -> void:
	var removed := false
	for child in get_tree().root.get_children():
		if known.has(child) or child == keep or child == self:
			continue
		child.queue_free()
		removed = true
	if removed:
		await get_tree().process_frame
