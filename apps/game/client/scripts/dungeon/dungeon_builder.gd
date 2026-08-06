extends Node3D
class_name DungeonBuilder

## Loads a DungeonDefinition fixture and instances room templates (BUILDER-2.1).

const FIXTURE_RELATIVE := "content/fixtures/forgotten_castle_slice.json"

const ENEMY_SCENES_FALLBACK := {
	"castle_grunt": preload("res://scenes/enemies/castle_grunt.tscn"),
	"castle_archer": preload("res://scenes/enemies/castle_archer.tscn"),
	"castle_shield": preload("res://scenes/enemies/castle_shield.tscn"),
	"castle_knight": preload("res://scenes/enemies/castle_knight.tscn"),
}

const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")
const SPIKE_TRAP_SCENE := preload("res://scenes/traps/spike_trap.tscn")
const FALLING_TRAP_SCENE := preload("res://scenes/traps/falling_trap.tscn")
const POISON_POOL_SCENE := preload("res://scenes/traps/poison_pool.tscn")
const EXIT_PORTAL_SCENE := preload("res://scenes/dungeon/exit_portal.tscn")
const BOSS_ROOM_DOOR_SCENE := preload("res://scenes/dungeon/boss_room_door.tscn")
const STAIR_LEVER_SCENE := preload("res://scenes/dungeon/stair_lever.tscn")
const STAIR_COLLISION := preload("res://scripts/dungeon/stair_collision_builder.gd")
const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const FINAL_BOSS_SCENE := preload("res://scenes/enemies/final_boss_forgotten_castle.tscn")
const ILLUSORY_WALL_SCENE := preload("res://scenes/dungeon/illusory_wall.tscn")
const HIDDEN_LEVER_SCENE := preload("res://scenes/dungeon/hidden_lever.tscn")
const EndlessDifficultyScript := preload("res://scripts/dungeon/endless_difficulty.gd")
const CastleTierDifficultyScript := preload("res://scripts/dungeon/castle_tier_difficulty.gd")
const WavesDifficultyScript := preload("res://scripts/dungeon/waves_difficulty.gd")
const FloorShellBuilderScript := preload("res://scripts/dungeon/floor_shell_builder.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")
const RoomContentSpawnerScript := preload(
	"res://scripts/dungeon/room_content/room_content_spawner.gd"
)

signal build_complete
signal boss_defeated
signal snapshot_dirty

var definition: Dictionary = {}
var biome_id: String = BiomeRegistry.BIOME_CASTLE
var _room_scenes: Dictionary = {}
var _rooms: Dictionary = {}
var _player: CharacterBody3D
var _entities: Node3D
var _dungeon_root: Node3D
var _nav_links_root: Node3D
var _floor_nav_map: RID = RID()
var _placement_rng: RandomNumberGenerator
var _boss: Node
var _enemy_by_id: Dictionary = {}
var _chest_by_id: Dictionary = {}
var _boss_door: Node3D
var _stair_levers: Dictionary = {}
var _is_final_floor := false

## In-run floor definition cache (paired with RunFlow.floor_definitions).
static var _floor_definition_cache: Dictionary = {}


static func store_floor_cache(floor_index: int, floor_definition: Dictionary) -> void:
	if floor_definition.is_empty():
		return
	_floor_definition_cache[str(floor_index)] = floor_definition.duplicate(true)


static func get_floor_cache(floor_index: int) -> Dictionary:
	var cached: Variant = _floor_definition_cache.get(str(floor_index), {})
	return cached.duplicate(true) if cached is Dictionary else {}


static func clear_floor_cache() -> void:
	_floor_definition_cache.clear()


func build(
	parent: Node3D, player: CharacterBody3D, fixture_path: String = FIXTURE_RELATIVE
) -> void:
	build_from_source(parent, player, fixture_path, {})


func build_from_definition(parent: Node3D, player: CharacterBody3D, def: Dictionary) -> void:
	build_from_source(parent, player, "", def)


func build_from_source(
	parent: Node3D, player: CharacterBody3D, fixture_path: String, def: Dictionary
) -> void:
	_player = player
	if not def.is_empty():
		definition = def
	elif fixture_path != "":
		definition = ContentLoader.load_json(fixture_path)
	else:
		definition = {}
	if definition.is_empty():
		push_error("DungeonBuilder: no definition provided")
		return
	biome_id = BiomeRegistry.resolve_biome_id(definition)
	_is_final_floor = (
		bool(definition.get("isFinalFloor", false))
		or (RunFlow.is_final_floor() and RunFlow.get_run_mode() != "endless")
	)
	_room_scenes = BiomeRegistry.get_room_scenes(biome_id)
	var rooms: Array = definition.get("rooms", [])
	if rooms.is_empty():
		push_error("DungeonBuilder: definition has no rooms")
		return
	_placement_rng = RandomNumberGenerator.new()
	_placement_rng.seed = int(definition.get("seed", 0)) ^ 0x50ACE01
	_dungeon_root = Node3D.new()
	_dungeon_root.name = "DungeonRoot"
	parent.add_child(_dungeon_root)
	_entities = Node3D.new()
	_entities.name = "Entities"
	_dungeon_root.add_child(_entities)
	if not _build_rooms():
		_abort_build(parent)
		return
	_setup_floor_nav_map()
	_sync_blockout_doors_from_edges()
	_wire_shortcut_edges()
	_build_doorway_bridges()
	_build_height_transitions()
	_build_floor_shell()
	_build_landmarks()
	_place_cover()
	_finalize_all_blockouts()
	_place_secret_mechanisms()
	_build_nav_links()
	_spawn_player()
	_place_enemies()
	_place_loot()
	_place_traps()
	_place_room_content()
	_setup_boss()
	if _is_final_floor:
		_setup_exit_portal()
	_setup_stair_levers()
	_setup_boss_door(parent)
	build_complete.emit()


func _abort_build(parent: Node3D) -> void:
	unload_from_parent(parent)


func get_room(room_id: String) -> RoomTemplate:
	return _rooms.get(room_id) as RoomTemplate


func get_room_ids() -> Array:
	return _rooms.keys()


func get_boss() -> Node:
	return _boss


func open_exit_portal() -> void:
	var exit_room_id: String = definition.get("placements", {}).get("exit", "boss")
	var room := get_room(exit_room_id)
	if room == null:
		return
	var portal := room.get_node_or_null("Props/ExitPortal") as Area3D
	if portal == null:
		portal = _create_exit_portal(room)
	if portal and portal.has_method("activate"):
		portal.call("activate")


func _build_rooms() -> bool:
	var unknown: Array[String] = []
	for room_def in definition.get("rooms", []):
		var template_id: String = room_def.get("templateId", "")
		if not _room_scenes.has(template_id):
			unknown.append(template_id)
	if not unknown.is_empty():
		push_error("DungeonBuilder: unknown template(s) %s — aborting build" % ", ".join(unknown))
		return false
	var rooms_root := Node3D.new()
	rooms_root.name = "Rooms"
	_dungeon_root.add_child(rooms_root)
	for room_def in definition.get("rooms", []):
		var template_id: String = room_def.get("templateId", "")
		var scene: PackedScene = _room_scenes[template_id]
		var instance := scene.instantiate() as RoomTemplate
		var t: Dictionary = room_def.get("transform", {})
		var yaw: float = deg_to_rad(t.get("yaw", 0.0))
		instance.position = Vector3(t.get("x", 0.0), t.get("y", 0.0), t.get("z", 0.0))
		instance.rotation.y = yaw
		instance.name = room_def.get("id", template_id).capitalize()
		instance.room_id = room_def.get("id", "")
		instance.template_id = template_id
		instance.room_type = str(room_def.get("type", instance.room_type))
		var blockout := instance.get_blockout()
		if blockout:
			blockout.skip_floor = false
		rooms_root.add_child(instance)
		_rooms[room_def.get("id", "")] = instance
		if RunFloorConfig.is_stairs_room({"templateId": str(room_def.get("templateId", ""))}):
			STAIR_COLLISION.ensure_stair_collision(instance)
	return true


func _setup_floor_nav_map() -> void:
	_floor_nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_floor_nav_map, true)
	NavigationServer3D.map_set_cell_size(_floor_nav_map, 0.25)
	NavigationServer3D.map_set_cell_height(_floor_nav_map, 0.25)
	for room_id in _rooms:
		var room := get_room(room_id)
		if room == null:
			continue
		var blockout := room.get_blockout()
		if blockout:
			blockout.set_navigation_map(_floor_nav_map)
		var nav_region := room.get_nav_region()
		if nav_region:
			nav_region.set_navigation_map(_floor_nav_map)


func _sync_blockout_doors_from_edges() -> void:
	for edge in definition.get("edges", []):
		var kind := str(edge.get("kind", "door"))
		if kind in ["secret", "shortcut"]:
			continue
		var from_room := get_room(str(edge.get("from", "")))
		var to_room := get_room(str(edge.get("to", "")))
		if from_room == null or to_room == null:
			continue
		_open_blockout_door_toward(from_room, to_room)
		_open_blockout_door_toward(to_room, from_room)


func _wire_shortcut_edges() -> void:
	for edge in definition.get("edges", []):
		if str(edge.get("kind", "")) != "shortcut":
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		var from_room := get_room(from_id)
		var to_room := get_room(to_id)
		if from_room == null or to_room == null:
			push_error(
				"DungeonBuilder: shortcut edge %s->%s references missing room" % [from_id, to_id]
			)
			continue
		_open_blockout_door_toward(from_room, to_room)
		_open_blockout_door_toward(to_room, from_room)


func _open_blockout_door_toward(from_room: RoomTemplate, to_room: RoomTemplate) -> void:
	var blockout := from_room.get_blockout()
	if blockout == null:
		return
	var socket := from_room.socket_toward(to_room)
	if socket == null:
		push_error(
			"DungeonBuilder: no socket from %s toward %s" % [from_room.room_id, to_room.room_id]
		)
		return
	match socket.direction:
		CastleRoomConstants.Direction.NORTH:
			blockout.door_north = true
		CastleRoomConstants.Direction.EAST:
			blockout.door_east = true
		CastleRoomConstants.Direction.SOUTH:
			blockout.door_south = true
		CastleRoomConstants.Direction.WEST:
			blockout.door_west = true


func _build_doorway_bridges() -> void:
	var bridges := Node3D.new()
	bridges.name = "DoorwayBridges"
	_dungeon_root.add_child(bridges)
	for edge in definition.get("edges", []):
		var kind := str(edge.get("kind", "door"))
		if kind == "secret":
			continue
		var from_room := get_room(str(edge.get("from", "")))
		var to_room := get_room(str(edge.get("to", "")))
		if from_room == null or to_room == null:
			continue
		var from_socket := from_room.socket_toward(to_room)
		var to_socket := to_room.socket_toward(from_room)
		if from_socket == null or to_socket == null:
			push_error(
				(
					"DungeonBuilder: missing socket on edge %s->%s"
					% [edge.get("from", ""), edge.get("to", "")]
				)
			)
			continue
		var from_pos := from_socket.global_position
		var to_pos := to_socket.global_position
		var offset := to_pos - from_pos
		offset.y = 0.0
		var span := offset.length()
		if span >= 0.5:
			push_error(
				(
					"DungeonBuilder: doorway span %.2f on %s->%s indicates a footprint mismatch"
					% [span, edge.get("from", ""), edge.get("to", "")]
				)
			)


func _add_doorway_bridge(
	parent: Node3D, center: Vector3, size: Vector3, material: Material
) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center + Vector3(0.0, size.y * 0.5, 0.0)
	parent.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	if material:
		mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


func _build_height_transitions() -> void:
	const STEP_HEIGHT := 0.5
	var max_height_level := int(definition.get("maxHeightLevel", 0))
	var flat_y: float = NAN
	for room_def in definition.get("rooms", []):
		var y := float(room_def.get("transform", {}).get("y", 0.0))
		if is_nan(flat_y):
			flat_y = y
		elif absf(y - flat_y) > 0.001:
			if max_height_level <= 0:
				push_error(
					(
						"DungeonBuilder: room '%s' at y=%.2f differs from y=%.2f while maxHeightLevel=0"
						% [room_def.get("id", ""), y, flat_y]
					)
				)
				return
	if max_height_level <= 0:
		return
	for edge in definition.get("edges", []):
		var kind := str(edge.get("kind", "door"))
		if kind == "secret":
			continue
		var from_room := get_room(str(edge.get("from", "")))
		var to_room := get_room(str(edge.get("to", "")))
		if from_room == null or to_room == null:
			continue
		var from_y := from_room.position.y
		var to_y := to_room.position.y
		if absf(from_y - to_y) < 0.001:
			continue
		var lower_room := from_room if from_y < to_y else to_room
		var higher_room := to_room if from_y < to_y else from_room
		var blockout := lower_room.get_blockout()
		if blockout == null:
			continue
		var door_mask := lower_room.door_mask_toward(higher_room)
		var direction := _door_mask_to_vector(door_mask)
		var step_count := ceili(absf(from_y - to_y) / STEP_HEIGHT)
		blockout.add_height_stairs(step_count, direction, STEP_HEIGHT)


func _door_mask_to_vector(door_mask: int) -> Vector2i:
	match door_mask:
		RoomGraphSlot.DOOR_NORTH:
			return Vector2i(0, -1)
		RoomGraphSlot.DOOR_EAST:
			return Vector2i(1, 0)
		RoomGraphSlot.DOOR_SOUTH:
			return Vector2i(0, 1)
		RoomGraphSlot.DOOR_WEST:
			return Vector2i(-1, 0)
	return Vector2i.ZERO


func _build_landmarks() -> void:
	var landmarks: Array = definition.get("landmarks", [])
	if landmarks.is_empty():
		return
	var root := Node3D.new()
	root.name = "Landmarks"
	_dungeon_root.add_child(root)
	var accent := BiomeRegistry.get_accent_material(biome_id)
	for hint in landmarks:
		var pos: Dictionary = hint.get("position", {})
		var scale_hint: Dictionary = hint.get("scale", {})
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(
			float(scale_hint.get("x", 2.0)),
			float(scale_hint.get("y", 16.0)),
			float(scale_hint.get("z", 2.0))
		)
		mesh_instance.mesh = box
		mesh_instance.position = Vector3(
			float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0))
		)
		if accent:
			mesh_instance.material_override = accent
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.name = str(hint.get("kind", "landmark"))
		root.add_child(mesh_instance)


func _place_cover() -> void:
	var cover_placements: Array = definition.get("placements", {}).get("cover", [])
	var wall_mat := BiomeRegistry.get_wall_material(biome_id)
	for placement in cover_placements:
		var room := get_room(placement.get("roomId", ""))
		if room == null:
			continue
		var blockout := room.get_blockout()
		if blockout == null:
			continue
		var offset: Dictionary = placement.get("offset", {})
		var size: Dictionary = placement.get("size", {})
		var kind: String = str(placement.get("kind", "pillar"))
		var size_vec := Vector3(
			float(size.get("x", 1.2)), float(size.get("y", 2.4)), float(size.get("z", 1.2))
		)
		blockout.add_cover_obstacle(
			Vector3(
				float(offset.get("x", 0.0)),
				float(offset.get("y", 0.0)),
				float(offset.get("z", 0.0))
			),
			size_vec,
			wall_mat if kind == "pillar" else wall_mat
		)


func _place_secret_mechanisms() -> void:
	for secret in definition.get("placements", {}).get("secrets", []):
		var mechanism: String = secret.get("mechanism", "illusory_wall")
		var secret_room_id: String = str(secret.get("roomId", ""))
		var parent_room := get_room(secret.get("parentRoomId", ""))
		var secret_room := get_room(secret_room_id)
		if parent_room == null or secret_room == null:
			continue
		var props := parent_room.get_node_or_null("Props")
		if props == null:
			push_error(
				(
					"DungeonBuilder: parent room '%s' has no Props for secret '%s'"
					% [parent_room.room_id, secret_room_id]
				)
			)
			continue
		var wall_dir := str(secret.get("wallDirection", ""))
		var socket := _resolve_secret_socket(parent_room, wall_dir)
		if socket == null:
			socket = parent_room.socket_toward(secret_room)
		var mechanism_node: Node3D
		if mechanism == "hidden_lever":
			mechanism_node = HIDDEN_LEVER_SCENE.instantiate() as Node3D
		else:
			mechanism_node = ILLUSORY_WALL_SCENE.instantiate() as Node3D
		if mechanism_node == null:
			continue
		if socket:
			mechanism_node.position = socket.position
			mechanism_node.rotation = socket.rotation
		if mechanism_node.has_method("configure"):
			mechanism_node.call("configure", secret_room_id, self)
		mechanism_node.set_meta("secret_room_id", secret_room_id)
		props.add_child(mechanism_node)
		var flag_id := WorldFlags.secret_opened(secret_room_id)
		if WorldState.has_flag(flag_id):
			reveal_secret(secret_room_id, false)


func reveal_secret(secret_room_id: String, set_flag: bool = true) -> void:
	var secret_room := get_room(secret_room_id)
	if secret_room == null:
		return
	if set_flag:
		WorldState.set_flag(WorldFlags.secret_opened(secret_room_id), true)
	for edge in definition.get("edges", []):
		if str(edge.get("kind", "")) != "secret":
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if from_id == secret_room_id or to_id == secret_room_id:
			var from_room := get_room(from_id)
			var to_room := get_room(to_id)
			if from_room and to_room:
				_open_blockout_door_toward(from_room, to_room)
				_open_blockout_door_toward(to_room, from_room)
	for room_id in _rooms:
		var room := get_room(room_id)
		if room == null:
			continue
		var props := room.get_node_or_null("Props")
		if props == null:
			continue
		for child in props.get_children():
			if str(child.get_meta("secret_room_id", "")) != secret_room_id:
				continue
			if child.has_method("mark_revealed"):
				child.call("mark_revealed")
			elif child.has_method("mark_used"):
				child.call("mark_used")


func _resolve_secret_socket(parent_room: RoomTemplate, wall_direction: String) -> DoorwaySocket:
	if wall_direction.is_empty():
		return null
	var direction := _wall_direction_to_enum(wall_direction)
	return parent_room.socket_for_direction(direction, true)


func _build_nav_links() -> void:
	_nav_links_root = Node3D.new()
	_nav_links_root.name = "NavLinks"
	_dungeon_root.add_child(_nav_links_root)
	for edge in definition.get("edges", []):
		var kind: String = edge.get("kind", "door")
		if kind not in ["door", "corridor", "shortcut", "secret"]:
			continue
		var from_room := get_room(edge.get("from", ""))
		var to_room := get_room(edge.get("to", ""))
		if from_room == null or to_room == null:
			continue
		var from_socket := from_room.socket_toward(to_room)
		var to_socket := to_room.socket_toward(from_room)
		if from_socket == null or to_socket == null:
			continue
		var link := NavigationLink3D.new()
		link.bidirectional = true
		link.travel_cost = 1.0
		link.navigation_map = _floor_nav_map
		link.start_position = _nav_links_root.to_local(
			from_socket.global_position + from_socket.get_world_facing() * -0.5
		)
		link.end_position = _nav_links_root.to_local(
			to_socket.global_position + to_socket.get_world_facing() * -0.5
		)
		_nav_links_root.add_child(link)


func _wall_direction_to_enum(wall_direction: String) -> CastleRoomConstants.Direction:
	match wall_direction:
		"north":
			return CastleRoomConstants.Direction.NORTH
		"east":
			return CastleRoomConstants.Direction.EAST
		"south":
			return CastleRoomConstants.Direction.SOUTH
		"west":
			return CastleRoomConstants.Direction.WEST
	return CastleRoomConstants.Direction.NORTH


func _sample_placement_offset(room: RoomTemplate, placement: Dictionary) -> Vector3:
	if not placement.get("sampleNavmesh", false):
		return _placement_offset(placement)
	var blockout := room.get_blockout()
	if blockout == null:
		return _placement_offset(placement)
	var nav_point := blockout.sample_random_nav_point(_placement_rng)
	if nav_point == Vector3.ZERO:
		return _placement_offset(placement)
	var hint := _placement_offset(placement)
	return nav_point + Vector3(hint.x * 0.15, 0.0, hint.z * 0.15)


func _build_floor_shell() -> void:
	FloorShellBuilderScript.build(_dungeon_root, _rooms, biome_id)


func _finalize_all_blockouts() -> void:
	for room_id in _rooms:
		var room := get_room(room_id)
		if room == null:
			continue
		var blockout := room.get_blockout()
		if blockout:
			blockout.finalize_geometry()


func _spawn_player() -> void:
	if _player == null:
		return
	var entrance_id: String = definition.get("placements", {}).get("entrance", "entrance")
	var entrance := get_room(entrance_id)
	if entrance:
		_player.global_position = entrance.get_player_spawn_global()
		CharacterFloorSnapScript.snap_feet_to_floor(_player)
	_player.add_to_group("player")


func _placement_inside_room(room: RoomTemplate, local_pos: Vector3, inset: float) -> bool:
	var blockout := room.get_blockout()
	if blockout == null:
		return true
	var half_w := maxf(blockout.room_width * 0.5 - inset, 0.1)
	var half_d := maxf(blockout.room_depth * 0.5 - inset, 0.1)
	return absf(local_pos.x) <= half_w and absf(local_pos.z) <= half_d


func _placement_offset(placement: Dictionary) -> Vector3:
	var pos: Dictionary = placement.get("offset", placement.get("position", {}))
	return Vector3(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0)))


func _place_enemies() -> void:
	var placements: Array = definition.get("placements", {}).get("enemies", [])
	for i in range(placements.size()):
		_spawn_enemy(placements[i], i)


func _spawn_enemy(placement: Dictionary, index: int) -> void:
	var enemy_id: String = placement.get("enemyId", "")
	var scene := _get_enemy_scene(enemy_id)
	if scene == null:
		return
	var room := get_room(placement.get("roomId", ""))
	if room == null:
		return
	var placement_key := _enemy_placement_id(placement, index)
	var enemy: CharacterBody3D = scene.instantiate() as CharacterBody3D
	if enemy == null:
		return
	if enemy.has_method("set_catalog_id"):
		enemy.call("set_catalog_id", enemy_id)
	enemy.position = _sample_placement_offset(room, placement)
	room.add_child(enemy)
	if enemy is CharacterBody3D:
		CharacterFloorSnapScript.snap_feet_to_floor(enemy as CharacterBody3D)
	enemy.set_meta("placement_id", placement_key)
	if enemy.has_method("set_player"):
		enemy.call("set_player", _player)
	if placement.get("isElite", false):
		enemy.set_meta("is_elite", true)
	_apply_floor_scaling(enemy)
	_ensure_enemy_groups(enemy)
	_enemy_by_id[placement_key] = enemy
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_tracked_enemy_died.bind(placement_key))


func _place_loot() -> void:
	var placements: Array = definition.get("placements", {}).get("loot", [])
	for i in range(placements.size()):
		var placement: Dictionary = placements[i]
		var room := get_room(placement.get("roomId", ""))
		if room == null:
			continue
		var chest_key := _loot_placement_id(placement, i)
		var chest: Node3D = CHEST_SCENE.instantiate() as Node3D
		var chest_pos := _sample_placement_offset(room, placement)
		if not _placement_inside_room(room, chest_pos, 1.0):
			push_error(
				"DungeonBuilder: chest '%s' outside room '%s' bounds" % [chest_key, room.room_id]
			)
			chest_pos = _placement_offset(placement)
		chest.position = chest_pos
		chest.set_meta("chest_id", chest_key)
		if chest.has_method("configure"):
			chest.call("configure", placement)
		chest.set_meta("biome_id", biome_id)
		if chest.has_signal("opened"):
			chest.opened.connect(_on_chest_opened)
		room.add_child(chest)
		_chest_by_id[chest_key] = chest


func _trap_scene_for_id(trap_id: String) -> PackedScene:
	var scene_path := TrapCatalog.get_scene_path(trap_id)
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("DungeonBuilder: unknown trap id '%s'" % trap_id)
		return null
	return load(scene_path) as PackedScene


func _place_room_content() -> void:
	RoomContentSpawnerScript.spawn_all(self, definition)
	RoomContentSpawnerScript.spawn_locks(self, definition)
	RoomContentSpawnerScript.spawn_puzzle_gates(self, definition)


func _place_traps() -> void:
	for placement in definition.get("placements", {}).get("traps", []):
		var room := get_room(placement.get("roomId", ""))
		if room == null:
			continue
		var trap_id: String = placement.get("trapId", "")
		var scene: PackedScene = _trap_scene_for_id(trap_id)
		if scene == null:
			continue
		var trap: Node3D = scene.instantiate() as Node3D
		trap.position = _sample_placement_offset(room, placement)
		trap.set_meta("biome_id", biome_id)
		room.add_child(trap)


func _setup_boss() -> void:
	var boss_placement: Variant = definition.get("placements", {}).get("boss")
	if boss_placement == null or not boss_placement is Dictionary:
		return
	var room := get_room(boss_placement.get("roomId", "boss"))
	if room == null:
		return
	var enemy_id: String = boss_placement.get("enemyId", "boss_castle_knight")
	var scene := _get_enemy_scene(enemy_id)
	if scene == null and _is_final_floor:
		scene = FINAL_BOSS_SCENE
	if scene == null:
		return
	_boss = scene.instantiate() as Node
	if _boss.has_method("set_catalog_id"):
		_boss.call("set_catalog_id", enemy_id)
	_boss.set_meta("placement_id", "boss")
	room.add_child(_boss)
	_ensure_enemy_groups(_boss)
	var spawn := room.get_node_or_null("Props/BossSpawn") as Node3D
	if spawn:
		_boss.global_position = spawn.global_position
	else:
		_boss.position = Vector3.ZERO
	if _boss is CharacterBody3D:
		CharacterFloorSnapScript.snap_feet_to_floor(_boss as CharacterBody3D)
	if _boss.has_method("set_player"):
		_boss.call("set_player", _player)
	_apply_floor_scaling(_boss)
	if _boss.has_signal("boss_defeated"):
		_boss.boss_defeated.connect(_on_boss_defeated)
	_enemy_by_id["boss"] = _boss
	if RunFlow:
		RunFlow.begin_boss_fight()


func _setup_exit_portal() -> void:
	var exit_room_id: String = definition.get("placements", {}).get("exit", "boss")
	var room := get_room(exit_room_id)
	if room == null:
		return
	if room.get_node_or_null("Props/ExitPortal"):
		return
	_create_exit_portal(room)


func _create_exit_portal(room: RoomTemplate) -> Area3D:
	var props := room.get_node_or_null("Props")
	if props == null:
		push_error("Exit portal: room %s has no Props node" % room.room_id)
		return null
	if props.get_node_or_null("ExitPortal"):
		return props.get_node_or_null("ExitPortal") as Area3D
	var marker := props.get_node_or_null("ExitPortalMarker") as Node3D
	if marker == null:
		push_error("Exit portal: room %s has no ExitPortalMarker" % room.room_id)
		return null
	var portal := EXIT_PORTAL_SCENE.instantiate() as Area3D
	portal.name = "ExitPortal"
	portal.position = marker.position
	props.add_child(portal)
	if portal.has_method("configure"):
		portal.call("configure", biome_id)
	return portal


func _on_boss_defeated() -> void:
	if _is_final_floor:
		open_exit_portal()
	else:
		_unlock_stair_lever()
	boss_defeated.emit()


func _setup_stair_levers() -> void:
	var stairs_count := 0
	for room_id in _rooms:
		var room := get_room(room_id)
		if room == null:
			continue
		if not RunFloorConfig.is_stairs_room({"templateId": str(room.template_id)}):
			continue
		stairs_count += 1
		if stairs_count > 1:
			push_error(
				"DungeonBuilder: multiple stairs rooms on floor — expected exactly one (found %s)"
				% str(room_id)
			)
		_create_stair_lever(room, str(room_id))


func _create_stair_lever(room: RoomTemplate, room_id: String) -> void:
	if _stair_levers.has(room_id):
		push_error("DungeonBuilder: duplicate stair lever for room %s" % room_id)
		return
	var lever := STAIR_LEVER_SCENE.instantiate() as Node3D
	lever.name = "StairLever"
	var props := room.get_node_or_null("Props")
	if props:
		props.add_child(lever)
	else:
		room.add_child(lever)
	if not _place_stair_lever_on_wall(lever, room):
		lever.queue_free()
		return
	var floor_index := RunFlow.get_current_floor()
	var can_ascend := not RunFlow.is_final_floor() or RunFlow.get_run_mode() == "endless"
	var can_descend := floor_index > 1 and RunFlow.get_run_mode() != "endless"
	var can_retreat := RunFlow.get_run_mode() in ["endless", "castle"]
	lever.call("configure", can_ascend, can_descend, can_retreat, floor_index)
	_stair_levers[room_id] = lever


func get_stair_lever() -> Node3D:
	var stair_id := RunFloorConfig.find_stairs_room_id(definition)
	if stair_id == "":
		return null
	return _stair_levers.get(stair_id, null) as Node3D


func get_stair_levers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for lever in _stair_levers.values():
		if lever is Node3D:
			out.append(lever)
	return out


func _place_stair_lever_on_wall(lever: Node3D, room: RoomTemplate) -> bool:
	var spawn := room.get_node_or_null("SpawnPoints/LeverSpawn") as Node3D
	if spawn == null:
		push_error(
			"DungeonBuilder: missing SpawnPoints/LeverSpawn in %s" % str(room.template_id)
		)
		return false
	lever.position = spawn.position
	lever.rotation = spawn.rotation
	return true


func _unlock_stair_lever() -> void:
	var can_ascend := not RunFlow.is_final_floor() or RunFlow.get_run_mode() == "endless"
	var can_descend := RunFlow.get_current_floor() > 1 and RunFlow.get_run_mode() != "endless"
	var can_retreat := RunFlow.get_run_mode() in ["endless", "castle"]
	var floor_index := RunFlow.get_current_floor()
	for lever in _stair_levers.values():
		if lever and lever.has_method("unlock"):
			lever.call("configure", can_ascend, can_descend, can_retreat, floor_index)
			lever.call("unlock")


func get_floor_nav_map() -> RID:
	return _floor_nav_map


func get_dungeon_root() -> Node3D:
	return _dungeon_root


func get_stair_spawn_global(stair_room_id: String, ascending: bool) -> Dictionary:
	var room := get_room(stair_room_id)
	if room == null:
		return {}
	var spawn := room.get_node_or_null("SpawnPoints/PlayerSpawn") as Node3D
	var pos := spawn.global_position if spawn else room.global_position + Vector3(0, 1.0, -4.0)
	return {
		"position": pos,
		"rotationY": RunFloorConfig.stairs_spawn_facing_y(room),
	}


func _setup_boss_door(castle_run: Node3D) -> void:
	var boss_placement: Variant = definition.get("placements", {}).get("boss")
	if boss_placement == null or not boss_placement is Dictionary:
		return
	var exit_room_id: String = definition.get("placements", {}).get("exit", "boss")
	var room := get_room(exit_room_id)
	if room == null:
		return
	var door := BOSS_ROOM_DOOR_SCENE.instantiate() as Node3D
	door.name = "BossRoomDoor"
	var requirement := DungeonCatalog.get_boss_door_requirement(RunFlow.current_dungeon_id)
	var locks: Array = definition.get("locks", [])
	if door.has_method("configure"):
		door.call(
			"configure",
			biome_id,
			requirement,
			RunFlow.get_current_floor(),
			locks
		)

	var socket := _boss_approach_socket(room)
	if socket:
		var facing := socket.get_world_facing()
		door.position = socket.position + facing * 0.25
	else:
		var blockout := room.get_blockout()
		var depth := blockout.room_depth if blockout else 28.0
		door.position = Vector3(0.0, 0.0, -depth * 0.5 + 0.25)

	room.add_child(door)
	_boss_door = door
	if castle_run.has_method("register_boss_door"):
		castle_run.call("register_boss_door", door)


func get_boss_door() -> Node3D:
	return _boss_door


func _boss_approach_socket(room: RoomTemplate) -> DoorwaySocket:
	var sockets := room.get_sockets()
	if sockets.is_empty():
		return null
	if sockets.size() == 1:
		return sockets[0]
	var best: DoorwaySocket = null
	var best_dot := -2.0
	var approach := -room.global_transform.basis.z
	for socket in sockets:
		var dot := socket.get_world_facing().dot(approach)
		if dot > best_dot:
			best_dot = dot
			best = socket
	return best if best != null else room.find_socket(CastleRoomConstants.Direction.NORTH)


func get_tracked_enemy(placement_id: String) -> Node:
	return _enemy_by_id.get(placement_id)


func get_spawned_enemy_count() -> int:
	return _enemy_by_id.size()


func get_boss_door_outside_spawn() -> Vector3:
	if _boss_door:
		return _boss_door.global_position - _boss_door.global_transform.basis.z * 3.5
	var exit_room_id: String = definition.get("placements", {}).get("exit", "")
	if exit_room_id != "":
		for edge in definition.get("edges", []):
			var from_id := str(edge.get("from", ""))
			var to_id := str(edge.get("to", ""))
			if to_id == exit_room_id:
				var adjacent := get_room(from_id)
				if adjacent:
					return adjacent.get_player_spawn_global()
			if from_id == exit_room_id:
				var adjacent_to := get_room(to_id)
				if adjacent_to:
					return adjacent_to.get_player_spawn_global()
	var entrance := get_room(definition.get("placements", {}).get("entrance", "entrance"))
	if entrance:
		return entrance.get_player_spawn_global()
	if _player:
		return _player.global_position
	return Vector3.ZERO


func capture_enemy_states() -> Dictionary:
	var states := {}
	for placement_id in _enemy_by_id:
		var enemy: Node = _enemy_by_id[placement_id]
		if enemy and is_instance_valid(enemy) and enemy.has_method("capture_state"):
			states[placement_id] = enemy.call("capture_state")
	return states


func respawn_enemies() -> void:
	for placement_id in _enemy_by_id:
		if placement_id == "boss":
			continue
		var enemy: Node = _enemy_by_id[placement_id]
		if enemy and is_instance_valid(enemy) and enemy.has_method("apply_state"):
			enemy.call("apply_state", {"alive": true})
	snapshot_dirty.emit()


func capture_loot_states() -> Dictionary:
	var states := {}
	for chest_id in _chest_by_id:
		var chest: Node = _chest_by_id[chest_id]
		if chest and is_instance_valid(chest) and chest.has_method("is_opened"):
			states[chest_id] = {"opened": chest.call("is_opened")}
	return states


func apply_snapshot(snapshot: Dictionary) -> void:
	var enemies: Dictionary = snapshot.get("enemies", {})
	for placement_id in enemies:
		var enemy: Node = _enemy_by_id.get(placement_id)
		if enemy and is_instance_valid(enemy) and enemy.has_method("apply_state"):
			enemy.call("apply_state", enemies[placement_id])

	var loot_states: Dictionary = snapshot.get("loot", {})
	for chest_id in loot_states:
		var chest: Node = _chest_by_id.get(chest_id)
		if chest and is_instance_valid(chest) and chest.has_method("apply_opened_state"):
			chest.call("apply_opened_state", loot_states[chest_id].get("opened", false))

	if snapshot.get("bossDefeated", false):
		if _is_final_floor:
			open_exit_portal()
		else:
			_unlock_stair_lever()
	for secret in definition.get("placements", {}).get("secrets", []):
		var secret_id := str(secret.get("roomId", ""))
		if secret_id != "" and WorldState.has_flag(WorldFlags.secret_opened(secret_id)):
			reveal_secret(secret_id, false)


func _ensure_enemy_groups(enemy: Node) -> void:
	if enemy == null:
		return
	if not enemy.is_in_group("enemy"):
		enemy.add_to_group("enemy")
	if not enemy.is_in_group("lockable"):
		enemy.add_to_group("lockable")


func _enemy_placement_id(placement: Dictionary, index: int) -> String:
	return "%s:%d" % [placement.get("roomId", ""), index]


func _loot_placement_id(placement: Dictionary, index: int) -> String:
	var chest_id: String = placement.get("chestId", "")
	if chest_id != "":
		return chest_id
	return "%s:%d" % [placement.get("roomId", ""), index]


func _on_tracked_enemy_died(_placement_id: String) -> void:
	snapshot_dirty.emit()


func _on_chest_opened() -> void:
	snapshot_dirty.emit()


func _get_enemy_scene(enemy_id: String) -> PackedScene:
	var scene := EnemyCatalog.get_scene(enemy_id)
	if scene:
		return scene
	if ENEMY_SCENES_FALLBACK.has(enemy_id):
		return ENEMY_SCENES_FALLBACK[enemy_id]
	push_warning("DungeonBuilder: unknown enemy id %s" % enemy_id)
	return null


func unload_from_parent(parent: Node3D) -> void:
	for room_id in _rooms.keys():
		var room: Node = _rooms[room_id]
		if is_instance_valid(room):
			room.queue_free()
	_rooms.clear()
	_enemy_by_id.clear()
	_chest_by_id.clear()
	_boss = null
	_boss_door = null
	_stair_levers.clear()
	_nav_links_root = null
	if _floor_nav_map != RID():
		NavigationServer3D.free_rid(_floor_nav_map)
		_floor_nav_map = RID()
	if _entities and is_instance_valid(_entities):
		_entities.queue_free()
		_entities = null
	if _dungeon_root and is_instance_valid(_dungeon_root):
		_dungeon_root.queue_free()
		_dungeon_root = null
	elif parent:
		var legacy_root := parent.get_node_or_null("DungeonRoot")
		if legacy_root:
			legacy_root.queue_free()
		var rooms_root := parent.get_node_or_null("Rooms")
		if rooms_root:
			rooms_root.queue_free()


func _apply_floor_scaling(enemy: Node) -> void:
	var mode := RunFlow.get_run_mode()
	if mode == "endless":
		var floor_index := RunFlow.get_current_floor()
		var hp_mult := EndlessDifficultyScript.hp_multiplier(floor_index)
		var health := enemy.get_node_or_null("Health") as Health
		if health:
			health.configure(float(health.max_health) * hp_mult)
		if enemy.has_method("set_damage_multiplier"):
			enemy.call(
				"set_damage_multiplier", EndlessDifficultyScript.damage_multiplier(floor_index)
			)
		return
	if mode == "castle":
		var dungeon_id := RunFlow.current_dungeon_id
		var diff_tier := RunFlow.get_difficulty_tier()
		var floor_index := RunFlow.get_current_floor()
		var hp_mult := CastleTierDifficultyScript.combined_hp_multiplier(
			dungeon_id, diff_tier, floor_index
		)
		if enemy.get_meta("is_elite", false):
			hp_mult *= 1.5
		var health := enemy.get_node_or_null("Health") as Health
		if health:
			health.configure(float(health.max_health) * hp_mult)
		if enemy.has_method("set_damage_multiplier"):
			var dmg_mult := CastleTierDifficultyScript.combined_damage_multiplier(
				dungeon_id, diff_tier, floor_index
			)
			if enemy.get_meta("is_elite", false):
				dmg_mult *= 1.25
			enemy.call("set_damage_multiplier", dmg_mult)
		return
	if mode == "waves":
		var wave := WavesRunService.current_wave
		var hp_mult := WavesDifficultyScript.hp_multiplier(wave)
		var health := enemy.get_node_or_null("Health") as Health
		if health:
			health.configure(float(health.max_health) * hp_mult)
		if enemy.has_method("set_damage_multiplier"):
			enemy.call("set_damage_multiplier", WavesDifficultyScript.damage_multiplier(wave))
