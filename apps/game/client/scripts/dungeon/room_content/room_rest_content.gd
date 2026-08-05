extends "res://scripts/dungeon/room_content/room_content_base.gd"

const INTERACT_RADIUS := 1.6

var _configured := false
var _rest_area: Area3D


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	if _configured:
		return
	_configured = true
	var root := _content_root()
	var bonfire := MeshInstance3D.new()
	bonfire.name = "BonfireVisual"
	bonfire.position = Vector3(0.0, 0.35, 0.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.7, 0.5)
	bonfire.mesh = mesh
	root.add_child(bonfire)
	_rest_area = Area3D.new()
	_rest_area.name = "RestArea"
	_rest_area.position = Vector3(0.0, 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = INTERACT_RADIUS
	shape.shape = sphere
	_rest_area.add_child(shape)
	root.add_child(_rest_area)
	_rest_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if not Input.is_action_pressed("interact"):
		return
	_trigger_rest(body)


func _physics_process(_delta: float) -> void:
	if _rest_area == null:
		return
	for body in _rest_area.get_overlapping_bodies():
		if body.is_in_group("player") and Input.is_action_just_pressed("interact"):
			_trigger_rest(body as Node3D)
			break


func _trigger_rest(player: Node3D) -> void:
	if RunFlow and RunFlow.has_method("rest_at_bonfire"):
		RunFlow.rest_at_bonfire(player)
