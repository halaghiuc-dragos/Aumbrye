extends Node3D

## A loop the lattice seated flush against another room, built as a real barred doorway instead of
## a plain open one. It only ever opens from the side reached the hard way -- the far side of the
## loop, the one with the longer walk from the entrance. Pulled from there, it stays open for the
## rest of the floor, same as any other persistent gate. Tried from the near side, it does not
## budge; there is nothing to solve, just a longer route to take first.

const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _gate_id := ""
var _gate_flag_id := ""
var _barrier: StaticBody3D
var _label: Label3D
var _interact_area: Area3D
var _near_player := false
var _opened := false


## The caller always spawns this on the locked-side room with the socket facing its open-side
## neighbour (see `RoomContentSpawner.spawn_shortcut_gates`), so the socket's own forward direction
## -- local -Z, `DoorwaySocket`'s `get_world_facing()` after `_align_socket_rotations()` -- always
## points at the open side. There is nothing biome- or room-specific to configure for that; it holds
## for every wall the door could be cut into.
func configure(gate: Dictionary, _from_room: RoomTemplate, _to_room: RoomTemplate) -> void:
	_gate_id = str(gate.get("gateId", ""))
	_gate_flag_id = WorldFlags.door_opened(_gate_id) if _gate_id != "" else ""
	_build_at_socket()
	_refresh_state()
	if _gate_flag_id != "":
		WorldState.namespace_changed.connect(_on_namespace_changed)


func _build_at_socket() -> void:
	var socket := RoomContentSpawner.door_socket(self)
	if socket:
		position = socket.position
		rotation.y = socket.rotation.y
	else:
		position = Vector3(0.0, 0.0, -4.0)

	_barrier = StaticBody3D.new()
	_barrier.name = "ShortcutGateBarrier"
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		CastleRoomConstants.DOOR_WIDTH,
		CastleRoomConstants.DOOR_HEIGHT,
		CastleRoomConstants.WALL_THICKNESS
	)
	shape_node.shape = box
	shape_node.position = Vector3(0.0, CastleRoomConstants.DOOR_HEIGHT * 0.5, 0.0)
	_barrier.add_child(shape_node)
	add_child(_barrier)

	var mesh := MeshInstance3D.new()
	var gate_mesh := BoxMesh.new()
	gate_mesh.size = box.size
	mesh.mesh = gate_mesh
	mesh.position = shape_node.position
	mesh.material_override = DIORAMA_SKIN.make_telegraph_material(Color(0.3, 0.3, 0.34, 0.95))
	_barrier.add_child(mesh)

	_interact_area = Area3D.new()
	_interact_area.name = "InteractArea"
	_interact_area.collision_layer = 0
	_interact_area.collision_mask = 2
	_interact_area.monitoring = true
	var interact_shape := CollisionShape3D.new()
	var interact_box := BoxShape3D.new()
	interact_box.size = Vector3(5.0, 4.0, 4.0)
	interact_shape.shape = interact_box
	interact_shape.position = Vector3(0.0, 2.0, 0.0)
	_interact_area.add_child(interact_shape)
	add_child(_interact_area)
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)

	_label = Label3D.new()
	_label.name = "Label3D"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 24
	_label.outline_size = 11
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.position = Vector3(0.0, 3.6, 0.0)
	_label.modulate = Color(0.75, 0.8, 0.9, 1.0)
	add_child(_label)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true
		_update_label()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if _opened or not _near_player:
		return
	if not PlayerInput.interact_just_pressed(event):
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	if not _player_on_open_side(player):
		if RunFlow:
			RunFlow.emit_run_warning(tr("SHORTCUT_WRONG_SIDE"))
		get_viewport().set_input_as_handled()
		return
	if _gate_flag_id != "":
		WorldState.set_flag(_gate_flag_id, true)
	_open()
	get_viewport().set_input_as_handled()


func _player_on_open_side(player: Node3D) -> bool:
	return to_local(player.global_position).z < 0.0


func _on_namespace_changed(flag_namespace: String, flag_id: String, _value: Variant) -> void:
	if flag_namespace == WorldFlags.NS_DOOR and flag_id == _gate_flag_id:
		_refresh_state()


func _refresh_state() -> void:
	if _gate_flag_id != "" and WorldState.is_flag_true(_gate_flag_id):
		_open()
	else:
		_update_label()


func _open() -> void:
	_opened = true
	if _barrier:
		DIORAMA_SKIN.animate_gate_open(_barrier)
	if _label:
		_label.visible = false


func _update_label() -> void:
	if _label == null:
		return
	if _opened:
		_label.visible = false
		return
	_label.visible = _near_player
	if not _near_player:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and _player_on_open_side(player):
		_label.text = tr("SHORTCUT_OPEN_PROMPT")
	else:
		_label.text = tr("SHORTCUT_BARRED")


func _exit_tree() -> void:
	if _gate_flag_id != "" and WorldState.namespace_changed.is_connected(_on_namespace_changed):
		WorldState.namespace_changed.disconnect(_on_namespace_changed)
