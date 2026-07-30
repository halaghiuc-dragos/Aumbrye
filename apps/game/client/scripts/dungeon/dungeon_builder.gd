extends Node3D
class_name DungeonBuilder

## Loads a DungeonDefinition fixture and instances room templates (BUILDER-2.1).

const FIXTURE_RELATIVE := "content/fixtures/forgotten_castle_slice.json"

const ROOM_SCENES := {
	"castle_entrance": preload("res://scenes/rooms/castle/castle_entrance.tscn"),
	"castle_stairs": preload("res://scenes/rooms/castle/castle_stairs.tscn"),
	"castle_courtyard": preload("res://scenes/rooms/castle/castle_courtyard.tscn"),
	"castle_hall": preload("res://scenes/rooms/castle/castle_hall.tscn"),
	"castle_treasure": preload("res://scenes/rooms/castle/castle_treasure.tscn"),
	"castle_secret": preload("res://scenes/rooms/castle/castle_secret.tscn"),
	"castle_arena": preload("res://scenes/rooms/castle/castle_arena.tscn"),
	"castle_boss": preload("res://scenes/rooms/castle/castle_boss.tscn"),
}

const ENEMY_SCENES := {
	"castle_grunt": preload("res://scenes/enemies/castle_grunt.tscn"),
	"castle_archer": preload("res://scenes/enemies/castle_archer.tscn"),
	"castle_shield": preload("res://scenes/enemies/castle_shield.tscn"),
	"castle_knight": preload("res://scenes/enemies/castle_knight.tscn"),
}

const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")
const SPIKE_TRAP_SCENE := preload("res://scenes/traps/spike_trap.tscn")
const FALLING_TRAP_SCENE := preload("res://scenes/traps/falling_trap.tscn")
const EXIT_PORTAL_SCRIPT := preload("res://scripts/dungeon/exit_portal.gd")
const BOSS_DOOR_SCRIPT := preload("res://scripts/dungeon/boss_room_door.gd")

signal build_complete
signal boss_defeated

var definition: Dictionary = {}
var _rooms: Dictionary = {}
var _player: CharacterBody3D
var _entities: Node3D
var _boss: Node


func build(parent: Node3D, player: CharacterBody3D, fixture_path: String = FIXTURE_RELATIVE) -> void:
	_player = player
	_entities = Node3D.new()
	_entities.name = "Entities"
	parent.add_child(_entities)
	definition = ContentLoader.load_json(fixture_path)
	if definition.is_empty():
		push_error("DungeonBuilder: failed to load %s" % fixture_path)
		return
	_build_rooms(parent)
	_build_shortcut_corridors(parent)
	_spawn_player()
	_place_enemies()
	_place_loot()
	_place_traps()
	_setup_boss()
	_setup_exit_portal()
	_setup_boss_door(parent)
	build_complete.emit()


func get_room(room_id: String) -> RoomTemplate:
	return _rooms.get(room_id) as RoomTemplate


func get_room_ids() -> Array:
	return _rooms.keys()


func open_exit_portal() -> void:
	var exit_room_id: String = definition.get("placements", {}).get("exit", "boss")
	var room := get_room(exit_room_id)
	if room == null:
		return
	var portal := room.get_node_or_null("Props/ExitPortal") as Area3D
	if portal == null:
		portal = _create_exit_portal(room)
	if portal:
		portal.monitoring = true
		portal.visible = true


func _build_rooms(parent: Node3D) -> void:
	var rooms_root := Node3D.new()
	rooms_root.name = "Rooms"
	parent.add_child(rooms_root)
	for room_def in definition.get("rooms", []):
		var template_id: String = room_def.get("templateId", "")
		if not ROOM_SCENES.has(template_id):
			push_warning("DungeonBuilder: unknown template %s" % template_id)
			continue
		var scene: PackedScene = ROOM_SCENES[template_id]
		var instance := scene.instantiate() as RoomTemplate
		var t: Dictionary = room_def.get("transform", {})
		var yaw: float = deg_to_rad(t.get("yaw", 0.0))
		instance.position = Vector3(t.get("x", 0.0), t.get("y", 0.0), t.get("z", 0.0))
		instance.rotation.y = yaw
		instance.name = room_def.get("id", template_id).capitalize()
		instance.room_id = room_def.get("id", "")
		instance.template_id = template_id
		rooms_root.add_child(instance)
		_rooms[room_def.get("id", "")] = instance


func _build_shortcut_corridors(parent: Node3D) -> void:
	var has_one_way := false
	for edge in definition.get("edges", []):
		if edge.get("kind", "") == "one_way":
			has_one_way = true
			break
	if not has_one_way:
		return
	# L-shaped shortcut mirrors DUNGEON-2.1 hand layout: hall south → corridor → vertical → stairs.
	var floor_mat := load("res://assets/castle/mat_floor.tres")
	var wall_mat := load("res://assets/castle/mat_wall.tres")
	var vertical := _create_shortcut_blockout(8.0, 18.0, true, true, false, false, floor_mat, wall_mat)
	vertical.name = "ShortcutVertical"
	vertical.position = Vector3(0.0, 0.0, 31.0)
	parent.add_child(vertical)
	var horizontal := _create_shortcut_blockout(18.0, 6.0, true, false, false, true, floor_mat, wall_mat)
	horizontal.name = "ShortcutCorridor"
	horizontal.position = Vector3(9.0, 0.0, 43.0)
	parent.add_child(horizontal)


func _create_shortcut_blockout(
	width: float,
	depth: float,
	door_north: bool,
	door_south: bool,
	door_east: bool,
	door_west: bool,
	floor_mat: Material,
	wall_mat: Material
) -> Node3D:
	var blockout_script := preload("res://scripts/dungeon/castle/castle_blockout.gd")
	var corridor := Node3D.new()
	var blockout := Node3D.new()
	blockout.set_script(blockout_script)
	blockout.set("room_width", width)
	blockout.set("room_depth", depth)
	blockout.set("door_north", door_north)
	blockout.set("door_south", door_south)
	blockout.set("door_east", door_east)
	blockout.set("door_west", door_west)
	blockout.set("floor_material", floor_mat)
	blockout.set("wall_material", wall_mat)
	corridor.add_child(blockout)
	return corridor


func _spawn_player() -> void:
	if _player == null:
		return
	var entrance_id: String = definition.get("placements", {}).get("entrance", "entrance")
	var entrance := get_room(entrance_id)
	if entrance:
		_player.global_position = entrance.get_player_spawn_global()
	_player.add_to_group("player")


func _place_enemies() -> void:
	for placement in definition.get("placements", {}).get("enemies", []):
		_spawn_enemy(placement)


func _spawn_enemy(placement: Dictionary) -> void:
	var enemy_id: String = placement.get("enemyId", "")
	if not ENEMY_SCENES.has(enemy_id):
		return
	var room := get_room(placement.get("roomId", ""))
	if room == null:
		return
	var enemy: Node3D = ENEMY_SCENES[enemy_id].instantiate() as Node3D
	var pos: Dictionary = placement.get("position", {})
	enemy.position = Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0))
	if enemy.has_method("set_player"):
		enemy.call("set_player", _player)
	room.add_child(enemy)


func _place_loot() -> void:
	for placement in definition.get("placements", {}).get("loot", []):
		var room := get_room(placement.get("roomId", ""))
		if room == null:
			continue
		var chest: Node3D = CHEST_SCENE.instantiate() as Node3D
		var pos: Dictionary = placement.get("position", {})
		chest.position = Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0))
		if chest.has_method("configure"):
			chest.call("configure", placement)
		room.add_child(chest)


func _place_traps() -> void:
	for placement in definition.get("placements", {}).get("traps", []):
		var room := get_room(placement.get("roomId", ""))
		if room == null:
			continue
		var trap_id: String = placement.get("trapId", "")
		var scene: PackedScene = SPIKE_TRAP_SCENE if trap_id == "spike_trap" else FALLING_TRAP_SCENE
		var trap: Node3D = scene.instantiate() as Node3D
		var pos: Dictionary = placement.get("position", {})
		trap.position = Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0))
		room.add_child(trap)


func _setup_boss() -> void:
	var boss_placement: Variant = definition.get("placements", {}).get("boss")
	if boss_placement == null or not boss_placement is Dictionary:
		return
	var room := get_room(boss_placement.get("roomId", "boss"))
	if room == null:
		return
	var enemy_id: String = boss_placement.get("enemyId", "castle_knight")
	if not ENEMY_SCENES.has(enemy_id):
		return
	_boss = ENEMY_SCENES[enemy_id].instantiate() as Node
	room.add_child(_boss)
	var spawn := room.get_node_or_null("Props/BossSpawn") as Node3D
	if spawn:
		_boss.global_position = spawn.global_position
	else:
		_boss.position = Vector3.ZERO
	if _boss.has_method("set_player"):
		_boss.call("set_player", _player)
	if _boss.has_signal("boss_defeated"):
		_boss.boss_defeated.connect(_on_boss_defeated)


func _setup_exit_portal() -> void:
	var exit_room_id: String = definition.get("placements", {}).get("exit", "boss")
	var room := get_room(exit_room_id)
	if room == null:
		return
	if room.get_node_or_null("Props/ExitPortal"):
		return
	_create_exit_portal(room)


func _create_exit_portal(room: RoomTemplate) -> Area3D:
	var portal := Area3D.new()
	portal.name = "ExitPortal"
	portal.collision_layer = 0
	portal.collision_mask = 2
	portal.monitoring = false
	portal.visible = false
	portal.set_script(EXIT_PORTAL_SCRIPT)
	var marker := room.get_node_or_null("Props/ExitPortalMarker") as Node3D
	if marker:
		portal.position = marker.position
	else:
		portal.position = Vector3(0, 1.5, 12)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 1)
	shape.shape = box
	portal.add_child(shape)
	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3, 3, 0.4)
	mesh_inst.mesh = mesh
	mesh_inst.material_override = load("res://assets/castle/mat_accent.tres")
	portal.add_child(mesh_inst)
	var props := room.get_node_or_null("Props")
	if props:
		props.add_child(portal)
	return portal


func _on_boss_defeated() -> void:
	open_exit_portal()
	boss_defeated.emit()


func _setup_boss_door(castle_run: Node3D) -> void:
	var room := get_room("boss")
	if room == null:
		return
	var door := Node3D.new()
	door.name = "BossRoomDoor"
	var barrier := StaticBody3D.new()
	barrier.name = "Barrier"
	barrier.collision_layer = 1
	barrier.collision_mask = 0
	var barrier_shape := CollisionShape3D.new()
	var barrier_box := BoxShape3D.new()
	barrier_box.size = Vector3(
		CastleRoomConstants.DOOR_WIDTH,
		CastleRoomConstants.DOOR_HEIGHT,
		CastleRoomConstants.WALL_THICKNESS
	)
	barrier_shape.name = "BarrierShape"
	barrier_shape.shape = barrier_box
	barrier_shape.position = Vector3(0.0, CastleRoomConstants.DOOR_HEIGHT * 0.5, 0.0)
	barrier.add_child(barrier_shape)
	var barrier_mesh := MeshInstance3D.new()
	barrier_mesh.name = "MeshInstance3D"
	var mesh := BoxMesh.new()
	mesh.size = barrier_box.size
	barrier_mesh.mesh = mesh
	barrier_mesh.position = barrier_shape.position
	barrier_mesh.material_override = load("res://assets/castle/mat_wall.tres")
	barrier.add_child(barrier_mesh)
	door.add_child(barrier)

	var interact := Area3D.new()
	interact.name = "InteractArea"
	interact.collision_layer = 0
	interact.collision_mask = 2
	interact.monitoring = true
	var interact_shape := CollisionShape3D.new()
	var interact_box := BoxShape3D.new()
	interact_box.size = Vector3(5.0, 4.0, 3.0)
	interact_shape.shape = interact_box
	# North (-Z) of the barrier — arena side, where the player stops before opening.
	interact_shape.position = Vector3(0.0, 2.0, -2.0)
	interact.add_child(interact_shape)
	door.add_child(interact)

	var label := Label3D.new()
	label.name = "Label3D"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.position = Vector3(0.0, 4.0, -2.0)
	label.visible = false
	door.add_child(label)

	door.set_script(BOSS_DOOR_SCRIPT)

	var socket := room.find_socket(CastleRoomConstants.Direction.NORTH)
	if socket:
		door.position = socket.position + Vector3(0.0, 0.0, -0.25)
	else:
		var blockout := room.get_blockout()
		var depth := blockout.room_depth if blockout else 28.0
		door.position = Vector3(0.0, 0.0, -depth * 0.5 + 0.25)

	room.add_child(door)
	if castle_run.has_method("register_boss_door"):
		castle_run.call("register_boss_door", door)
