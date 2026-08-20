extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

const INTERACT_RADIUS := 1.6

var _configured := false
var _rest_area: Area3D
var _player: Node3D


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	if _configured:
		return
	_configured = true
	var root := _content_root()
	var bonfire := Node3D.new()
	bonfire.name = "BonfireVisual"
	bonfire.position = _anchor(0).position
	DIORAMA_SKIN.build_bonfire(bonfire, DIORAMA_SKIN.resolve_biome(self))
	root.add_child(bonfire)
	_rest_area = Area3D.new()
	_rest_area.name = "RestArea"
	# The player is on collision_layer 2 (scenes/player/player.tscn). Without these the area kept
	# Godot's default mask of 1, never reported the player, and every rest path below was dead —
	# taking the heal, the flask refill, the enemy respawn and the whole death-checkpoint system
	# with it. Matches the convention every sibling in room_content/ already uses.
	_rest_area.collision_layer = 0
	_rest_area.collision_mask = 2
	_rest_area.monitoring = true
	_rest_area.position = _anchor(0).position + Vector3(0.0, 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = INTERACT_RADIUS
	shape.shape = sphere
	_rest_area.add_child(shape)
	root.add_child(_rest_area)
	_rest_area.body_entered.connect(_on_body_entered)
	_rest_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null


## Mirrors room_lore_content / room_merchant_content: proximity flag + _unhandled_input, so a press
## already consumed by a menu cannot rest here. Polling Input directly (the previous shape) ignored
## input consumption entirely and could respawn every enemy on the floor from the inventory screen.
func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not PlayerInput.interact_just_pressed(event):
		return
	get_viewport().set_input_as_handled()
	_trigger_rest(_player)


func _trigger_rest(player: Node3D) -> void:
	if RunFlow and RunFlow.has_method("rest_at_bonfire"):
		RunFlow.rest_at_bonfire(player)
