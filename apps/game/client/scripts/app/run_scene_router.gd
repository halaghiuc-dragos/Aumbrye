class_name RunSceneRouter
extends RefCounted

## Scene paths and deferred scene changes extracted from RunFlow.

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const CASTLE_RUN_SCENE := "res://scenes/dungeon/castle_run.tscn"
const WAVES_RUN_SCENE := "res://scenes/dungeon/waves_run.tscn"
const ARENA_SCENE := "res://scenes/debug/combat_arena.tscn"
const RESULTS_SCENE := "res://scenes/ui/results_screen.tscn"


static func goto_scene(tree: SceneTree, path: String) -> void:
	tree.call_deferred("change_scene_to_file", path)
