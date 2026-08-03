extends Node3D

const ArenaDioramaScript := preload("res://scripts/debug/arena_diorama.gd")

const DUMMY_SPAWNS := [
	Vector3(7.0, 0.0, -4.5),
	Vector3(9.5, 0.0, 0.0),
	Vector3(7.0, 0.0, 4.5),
	Vector3(-7.0, 0.0, -4.5),
	Vector3(-9.5, 0.0, 0.0),
	Vector3(-7.0, 0.0, 4.5),
]
const PLAYER_SPAWN := Vector3(-0.02, 0.0, 9.50)
const PLAYER_SPAWN_LOOK_DIR := Vector3(0.0, -0.10, -1.0)

@export var player_path: NodePath
@export var enemy_path: NodePath
@export var overlay_path: NodePath
@export var hub_return_area_path: NodePath = NodePath("HubReturn/InteractArea")

var _overlay: Node
var _hub_return_area: Area3D
var _near_hub_return := false


func _ready() -> void:
	ArenaDioramaScript.apply(self)
	if overlay_path:
		_overlay = get_node(overlay_path)
	if hub_return_area_path:
		_hub_return_area = get_node_or_null(hub_return_area_path) as Area3D
		if _hub_return_area:
			_hub_return_area.body_entered.connect(_on_hub_return_enter)
			_hub_return_area.body_exited.connect(_on_hub_return_exit)
	call_deferred("_orient_player_deferred")
	PlayerControls.sync_player_loadout()


func _orient_player_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	orient_player_to_hub_return()


func orient_player_to_hub_return() -> void:
	var player := get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		return
	player.global_position = PLAYER_SPAWN
	var facing := player.get_node_or_null("Facing") as Node3D
	var flat_look := PLAYER_SPAWN_LOOK_DIR
	flat_look.y = 0.0
	if facing and flat_look.length_squared() > 0.0001:
		flat_look = flat_look.normalized()
		facing.rotation.y = atan2(flat_look.x, flat_look.z)
	var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D")
	if spring_arm and spring_arm.has_method("snap_camera_forward"):
		spring_arm.call("snap_camera_forward", PLAYER_SPAWN_LOOK_DIR)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_duel") and _overlay and _overlay.has_method("reset_duel"):
		_overlay.call("reset_duel")
	if not event.is_action_pressed("interact") or not _near_hub_return:
		return
	var vp := get_viewport()
	if vp == null:
		return
	vp.set_input_as_handled()
	_near_hub_return = false
	RunFlow.return_to_hub("Returned from the training arena.")


func _on_hub_return_enter(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_hub_return = true


func _on_hub_return_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_hub_return = false
