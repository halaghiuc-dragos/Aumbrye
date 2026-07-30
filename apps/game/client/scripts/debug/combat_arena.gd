extends Node3D

@export var player_path: NodePath
@export var enemy_path: NodePath
@export var overlay_path: NodePath
@export var hub_return_area_path: NodePath = NodePath("HubReturn/InteractArea")

var _overlay: Node
var _hub_return_area: Area3D
var _near_hub_return := false


func _ready() -> void:
	if overlay_path:
		_overlay = get_node(overlay_path)
	if hub_return_area_path:
		_hub_return_area = get_node_or_null(hub_return_area_path) as Area3D
		if _hub_return_area:
			_hub_return_area.body_entered.connect(_on_hub_return_enter)
			_hub_return_area.body_exited.connect(_on_hub_return_exit)


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
