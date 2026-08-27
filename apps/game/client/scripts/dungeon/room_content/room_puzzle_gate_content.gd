extends Node3D


const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _flag_id := ""
var _barrier: StaticBody3D
var _unlocked := false


func configure(puzzle: Dictionary, from_room: RoomTemplate, to_room: RoomTemplate) -> void:
	_flag_id = str(puzzle.get("flagId", ""))
	_build_at_socket(from_room, to_room)
	_refresh_state()
	if _flag_id != "":
		WorldState.namespace_changed.connect(_on_namespace_changed)


func _build_at_socket(from_room: RoomTemplate, to_room: RoomTemplate) -> void:
	var socket := from_room.socket_toward(to_room)
	if socket:
		position = socket.position
		rotation.y = socket.rotation.y
		position += Vector3(0.0, 0.0, -0.4).rotated(Vector3.UP, rotation.y)
	else:
		position = Vector3(0.0, 0.0, -4.0)

	_barrier = StaticBody3D.new()
	_barrier.name = "PuzzleGateBarrier"
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CastleRoomConstants.DOOR_WIDTH, CastleRoomConstants.DOOR_HEIGHT, 0.65)
	shape_node.shape = box
	shape_node.position = Vector3(0.0, CastleRoomConstants.DOOR_HEIGHT * 0.5, 0.0)
	_barrier.add_child(shape_node)
	add_child(_barrier)

	var mesh := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = box.size
	mesh.mesh = door_mesh
	mesh.position = shape_node.position
	mesh.material_override = DIORAMA_SKIN.make_telegraph_material(Color(0.35, 0.55, 0.85, 0.85))
	_barrier.add_child(mesh)


func _on_namespace_changed(flag_namespace: String, flag_id: String, _value: Variant) -> void:
	if flag_namespace == WorldFlags.NS_LEVER and flag_id == WorldFlags.lever_pulled(_flag_id):
		_refresh_state()


func _refresh_state() -> void:
	if _flag_id != "" and WorldState.is_flag_true(WorldFlags.lever_pulled(_flag_id)):
		_unlock()


func is_unlocked() -> bool:
	return _unlocked


func _unlock() -> void:
	_unlocked = true
	if _barrier:
		_barrier.collision_layer = 0
		_barrier.visible = false
