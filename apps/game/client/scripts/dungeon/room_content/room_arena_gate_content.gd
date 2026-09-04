extends Node3D

## RM-07: the one combat room per floor the assigner marks `"lockIn": true` (the room right before
## the boss -- see `RoomContentAssigner._mark_pre_boss_lock_in()`). Every doorway starts open so the
## player walks in normally; the first time they cross into the room's interior every doorway gates
## shut behind them, and they open again once `DungeonBuilder` fires `room_cleared` for this room.
## A save resumed inside an already-cleared arena must come back open, not sealed -- see `configure()`.

const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _room_id := ""
var _flag_id := ""
var _gate_shapes: Array[CollisionShape3D] = []
var _gate_fogs: Array[MeshInstance3D] = []
var _entry_area: Area3D
var _closed := false
var _cleared := false


func configure(entry: Dictionary, _definition: Dictionary) -> void:
	_room_id = str(entry.get("roomId", ""))
	_flag_id = WorldFlags.room_cleared(_room_id) if _room_id != "" else ""
	var room := get_parent() as RoomTemplate
	if room == null:
		return
	var blockout := room.get_blockout() if room.has_method("get_blockout") else null
	if blockout == null:
		return
	_cleared = _flag_id != "" and WorldState.is_flag_true(_flag_id)
	var biome_id := str(get_meta("biome_id", BiomeRegistry.BIOME_CASTLE))
	for socket in room.get_sockets():
		if not _door_open(blockout, socket.direction):
			continue
		_build_gate(socket, biome_id)
	_build_entry_area(blockout)
	_apply_state()
	if _flag_id != "":
		WorldState.namespace_changed.connect(_on_namespace_changed)


func _door_open(blockout: CastleBlockout, direction: CastleRoomConstants.Direction) -> bool:
	match direction:
		CastleRoomConstants.Direction.NORTH:
			return blockout.door_north
		CastleRoomConstants.Direction.SOUTH:
			return blockout.door_south
		CastleRoomConstants.Direction.EAST:
			return blockout.door_east
		_:
			return blockout.door_west


func _build_gate(socket: DoorwaySocket, biome_id: String) -> void:
	var barrier := StaticBody3D.new()
	barrier.name = "ArenaGate_%s" % CastleRoomConstants.SOCKET_NAMES.get(socket.direction, "gate")
	barrier.collision_layer = 1
	barrier.collision_mask = 0
	barrier.position = socket.position
	barrier.rotation.y = socket.rotation.y
	add_child(barrier)
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		CastleRoomConstants.DOOR_WIDTH,
		CastleRoomConstants.DOOR_HEIGHT,
		CastleRoomConstants.WALL_THICKNESS
	)
	shape_node.shape = box
	shape_node.position = Vector3(0.0, CastleRoomConstants.DOOR_HEIGHT * 0.5, 0.0)
	barrier.add_child(shape_node)
	_gate_shapes.append(shape_node)
	var theme := PixelDioramaStyle.theme_from_biome(biome_id)
	var tint := PixelDioramaStyle.get_palette_color(theme, PixelDioramaStyle.PaletteSlot.EMISSIVE)
	tint.a = 0.6
	var fog := DIORAMA_SKIN.build_fog_gate(
		barrier, CastleRoomConstants.DOOR_WIDTH, CastleRoomConstants.DOOR_HEIGHT, tint
	)
	fog.position += Vector3(0.0, 0.0, 0.05)
	_gate_fogs.append(fog)


func _build_entry_area(blockout: CastleBlockout) -> void:
	if _cleared:
		return
	_entry_area = Area3D.new()
	_entry_area.name = "ArenaTrigger"
	_entry_area.collision_layer = 0
	_entry_area.collision_mask = 2
	_entry_area.monitoring = true
	add_child(_entry_area)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Inset from the walls so the trigger fires once the player is genuinely inside, not the
	# instant they touch the doorway threshold from the room they came from.
	var margin := CastleRoomConstants.DOOR_WIDTH
	box.size = Vector3(
		maxf(1.0, blockout.room_width - margin),
		CastleRoomConstants.WALL_HEIGHT,
		maxf(1.0, blockout.room_depth - margin)
	)
	shape.shape = box
	shape.position = Vector3(0.0, CastleRoomConstants.WALL_HEIGHT * 0.5, 0.0)
	_entry_area.add_child(shape)
	_entry_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or _cleared or _closed:
		return
	_closed = true
	_apply_state()
	AudioDirector.play_cue(&"door_seal", global_position)


func _on_namespace_changed(flag_namespace: String, flag_id: String, _value: Variant) -> void:
	if flag_namespace == WorldFlags.NS_ROOM and flag_id == _flag_id:
		_cleared = WorldState.is_flag_true(_flag_id)
		_apply_state()


func _apply_state() -> void:
	var solid := _closed and not _cleared
	for shape in _gate_shapes:
		shape.disabled = not solid
	for fog in _gate_fogs:
		fog.visible = solid


func _exit_tree() -> void:
	if _flag_id != "" and WorldState.namespace_changed.is_connected(_on_namespace_changed):
		WorldState.namespace_changed.disconnect(_on_namespace_changed)
