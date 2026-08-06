extends Node3D

## Illusory wall that dissolves on interact and opens the secret room doorway.

const MaterialDissolveScript := preload("res://scripts/art/characters/material_dissolve.gd")

var _secret_room_id: String = ""
var _builder: DungeonBuilder = null
var _revealed := false
var _interact_area: Area3D
var _barrier: StaticBody3D
var _near_player := false


func configure(secret_room_id: String, builder: DungeonBuilder) -> void:
	_secret_room_id = secret_room_id
	_builder = builder


func mark_revealed() -> void:
	_revealed = true
	_disable_barrier()
	if _interact_area:
		_interact_area.monitoring = false
	visible = false


func _ready() -> void:
	_barrier = get_node_or_null("StaticBody3D") as StaticBody3D
	_interact_area = get_node_or_null("InteractArea") as Area3D
	if _interact_area:
		_interact_area.body_entered.connect(_on_body_entered)
		_interact_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false


func _unhandled_input(event: InputEvent) -> void:
	if _revealed or not _near_player:
		return
	if event.is_action_pressed("interact"):
		_reveal()
		get_viewport().set_input_as_handled()


func _reveal() -> void:
	if _revealed:
		return
	_revealed = true
	MaterialDissolveScript.dissolve(self)
	_disable_barrier()
	if _builder:
		_builder.reveal_secret(_secret_room_id)


func _disable_barrier() -> void:
	if _barrier:
		_barrier.collision_layer = 0
		_barrier.visible = false
