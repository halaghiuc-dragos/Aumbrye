extends Node3D

const FloorKeyringScript := preload("res://scripts/dungeon/floor_keyring.gd")


const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const InteractPromptScript := preload("res://scripts/ui/interact_prompt.gd")

var _key_id := ""
var _lock_id := ""
var _lock_flag_id := ""
var _to_room_id := ""
var _keys_required := 1
var _barrier: StaticBody3D
var _label: InteractPrompt
var _interact_area: Area3D
var _near_player := false
var _unlocked := false


func configure(lock: Dictionary, _from_room: RoomTemplate, _to_room: RoomTemplate) -> void:
	_key_id = str(lock.get("keyId", ""))
	_lock_id = str(lock.get("lockId", ""))
	_keys_required = maxi(1, int(lock.get("keysRequired", 1)))
	_lock_flag_id = WorldFlags.lock_opened(_lock_id) if _lock_id != "" else ""
	_to_room_id = str(lock.get("to", ""))
	_build_at_socket()
	_refresh_state()
	if _lock_flag_id != "":
		WorldState.namespace_changed.connect(_on_namespace_changed)


func _build_at_socket() -> void:
	# The socket sits on the wall's centre plane, which is exactly where the opening was cut. The
	# slab used to be pushed 0.4 further into the room, so it read as a plank standing in front of
	# the doorway instead of filling it -- and you could see daylight past its edge.
	var socket := RoomContentSpawner.door_socket(self)
	if socket:
		position = socket.position
		rotation.y = socket.rotation.y
	else:
		position = Vector3(0.0, 0.0, -4.0)

	_barrier = StaticBody3D.new()
	_barrier.name = "LockedDoorBarrier"
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

	# RM-05: a door shape (jambs, lintel, keyhole inset tinted to the key's colour) instead of a
	# plain telegraph slab -- the same shape a puzzle gate or shortcut gate uses, which is exactly
	# what made every locked door illegible before.
	var key_tint := FloorKeyringScript.tint_for(_key_id)
	if key_tint == Color.WHITE:
		key_tint = Color(0.85, 0.75, 0.4)
	DIORAMA_SKIN.build_locked_door_frame(_barrier, RunFlow.current_biome_id, key_tint)

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

	_label = InteractPromptScript.build(self)


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
	# Held, not spent. The card stays on the ring, so a second door of the same colour opens on
	# sight rather than sending the player back for another key.
	if not FloorKeyringScript.is_held(_key_id):
		if RunFlow:
			RunFlow.emit_run_warning(
				tr("LOCK_NEEDS_KEY").format({"key": FloorKeyringScript.label_for(_key_id)})
			)
		get_viewport().set_input_as_handled()
		return
	WorldState.set_flag(_lock_flag_id, true)
	# AU-03: only the live open fires the stinger -- `_unlock()` is also reached from
	# `_refresh_state()` on a floor reload, where the lock is already open and nothing happened.
	AudioDirector.play_stinger("lock_opened")
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
		DIORAMA_SKIN.animate_gate_open(_barrier)
	if _label:
		_label.hide_prompt()


func _update_label() -> void:
	if _label == null:
		return
	if _unlocked or not _near_player:
		_label.hide_prompt()
		return
	# Name the colour either way. A door that says which card it wants turns a dead end into a
	# direction, which is the whole reason the keys are coloured.
	var key_label := FloorKeyringScript.label_for(_key_id)
	if FloorKeyringScript.is_held(_key_id):
		_label.show_action(tr("LOCK_UNLOCK_ACTION").format({"key": key_label}))
	else:
		_label.show_text(tr("LOCK_NEEDS_KEY").format({"key": key_label}))


func _exit_tree() -> void:
	if _lock_flag_id != "" and WorldState.namespace_changed.is_connected(_on_namespace_changed):
		WorldState.namespace_changed.disconnect(_on_namespace_changed)
