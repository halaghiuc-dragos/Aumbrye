extends Node

## Waits for a RunFlow-driven scene to open, lets it run, then ends the phase.
##
## Lives on the tree root so it survives the scene changes it is watching: `RunSceneRouter` replaces
## the current scene, and a coroutine awaiting inside a freed node never resumes.

## Frames to let a floor build, navigation bake and the first enemies act.
const SETTLE_FRAMES := 150
## Frames after the follow-up step, for whatever that opens in turn.
const FOLLOW_UP_FRAMES := 120
const TIMEOUT_SECONDS := 75.0

var phase_name := ""
var follow_up := Callable()

var _elapsed := 0.0
var _settled := 0
var _seen := ""
var _followed := false


func _process(delta: float) -> void:
	_elapsed += delta
	var current := get_tree().current_scene
	var path := str(current.scene_file_path) if current else ""
	if path == "" or path.ends_with("phase_walk.tscn"):
		if _elapsed > TIMEOUT_SECONDS:
			print("PHASE-TIMEOUT %s never left the walker scene" % phase_name)
			get_tree().quit(3)
		return
	if _seen != path:
		_seen = path
		print("  opened %s" % path)
	_settled += 1
	if not _followed and _settled >= SETTLE_FRAMES:
		_followed = true
		if follow_up.is_valid():
			follow_up.call()
			_settled = maxi(0, SETTLE_FRAMES - FOLLOW_UP_FRAMES)
			return
	if _settled >= SETTLE_FRAMES:
		print("PHASE-END %s" % phase_name)
		get_tree().quit(0)
	elif _elapsed > TIMEOUT_SECONDS:
		print("PHASE-TIMEOUT %s on %s" % [phase_name, path])
		get_tree().quit(3)
