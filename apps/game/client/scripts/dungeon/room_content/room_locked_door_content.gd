extends Node3D


const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _key_id := ""
var _lock_id := ""
var _lock_flag_id := ""
var _to_room_id := ""
var _keys_required := 1
var _barrier: StaticBody3D
var _label: Label3D
var _interact_area: Area3D
var _near_player := false
var _unlocked := false


func configure(lock: Dictionary, from_room: RoomTemplate, to_room: RoomTemplate) -> void:
	_key_id = str(lock.get("keyId", ""))
	_lock_id = str(lock.get("lockId", ""))
	_keys_required = maxi(1, int(lock.get("keysRequired", 1)))
	_lock_flag_id = WorldFlags.lock_opened(_lock_id) if _lock_id != "" else ""
	_to_room_id = str(lock.get("to", ""))
	_build_at_socket(from_room, to_room)
	_refresh_state()
	if _lock_flag_id != "":
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
	_barrier.name = "LockedDoorBarrier"
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
	mesh.material_override = DIORAMA_SKIN.make_telegraph_material(Color(0.55, 0.35, 0.12, 0.95))
	_barrier.add_child(mesh)

	_interact_area = Area3D.new()
	_interact_area.name = "InteractArea"
	_interact_area.collision_layer = 0
	_interact_area.collision_mask = 2
	_interact_area.monitoring = true
	var interact_shape := CollisionShape3D.new()
	var interact_box := BoxShape3D.new()
	interact_box.size = Vector3(5.0, 4.0, 3.0)
	interact_shape.shape = interact_box
	interact_shape.position = Vector3(0.0, 2.0, -1.5)
	_interact_area.add_child(interact_shape)
	add_child(_interact_area)
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)

	_label = Label3D.new()
	_label.name = "Label3D"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 24
	_label.position = Vector3(0.0, 3.6, -1.5)
	_label.modulate = Color(1.0, 0.85, 0.35, 1.0)
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
	if _unlocked or not _near_player:
		return
	if not PlayerInput.interact_just_pressed(event):
		return
	if InventoryService.count_dungeon_keys(_key_id) < _keys_required:
		if RunFlow:
			RunFlow.emit_run_warning(
				tr("LOCK_NEEDS_KEYS").format({"count": _keys_required})
			)
		get_viewport().set_input_as_handled()
		return
	for _i in _keys_required:
		InventoryService.consume_dungeon_key(_key_id)
	WorldState.set_flag(_lock_flag_id, true)
	_unlock()
	get_viewport().set_input_as_handled()


func _on_namespace_changed(flag_namespace: String, flag_id: String, _value: Variant) -> void:
	if flag_namespace == WorldFlags.NS_LOCK and flag_id == _lock_flag_id:
		_refresh_state()


func _refresh_state() -> void:
	if _lock_flag_id != "" and WorldState.is_flag_true(_lock_flag_id):
		_unlock()
	else:
		_update_label()


func _unlock() -> void:
	_unlocked = true
	if _barrier:
		_barrier.collision_layer = 0
		_barrier.visible = false
	if _label:
		_label.visible = false


func _update_label() -> void:
	if _label == null:
		return
	if _unlocked:
		_label.visible = false
		return
	_label.visible = _near_player
	if InventoryService.has_dungeon_key(_key_id):
		if _keys_required > 1:
			_label.text = "E — Unlock door (%d keys)" % _keys_required
		else:
			_label.text = "E — Unlock door"
	else:
		_label.text = "Locked — find key"


func _exit_tree() -> void:
	if _lock_flag_id != "" and WorldState.namespace_changed.is_connected(_on_namespace_changed):
		WorldState.namespace_changed.disconnect(_on_namespace_changed)
