extends Node3D

@export var player_path: NodePath
@export var enemy_path: NodePath
@export var overlay_path: NodePath

var _overlay: Node


func _ready() -> void:
	if overlay_path:
		_overlay = get_node(overlay_path)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_duel") and _overlay and _overlay.has_method("reset_duel"):
		_overlay.call("reset_duel")
