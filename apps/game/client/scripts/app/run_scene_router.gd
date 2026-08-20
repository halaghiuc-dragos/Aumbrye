class_name RunSceneRouter
extends RefCounted

## Scene paths and deferred scene changes extracted from RunFlow.

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const CASTLE_RUN_SCENE := "res://scenes/dungeon/castle_run.tscn"
const WAVES_RUN_SCENE := "res://scenes/dungeon/waves_run.tscn"
const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const RESULTS_SCENE := "res://scenes/ui/results_screen.tscn"


static func goto_scene(tree: SceneTree, path: String) -> void:
	SceneTransition.goto(tree, path, _status_for(path))


static func _status_for(path: String) -> String:
	if path == HUB_SCENE:
		return "Returning to the hub..."
	if path == CASTLE_RUN_SCENE or path == WAVES_RUN_SCENE:
		return "Descending..."
	if path == RESULTS_SCENE:
		return "Tallying the run..."
	return "Loading..."
