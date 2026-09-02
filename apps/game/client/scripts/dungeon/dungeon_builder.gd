extends Node3D
class_name DungeonBuilder

const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")


const FIXTURE_RELATIVE := "content/fixtures/forgotten_castle_slice.json"

const ENEMY_SCENES_FALLBACK := {
	"castle_grunt": preload("res://scenes/enemies/castle_grunt.tscn"),
	"castle_archer": preload("res://scenes/enemies/castle_archer.tscn"),
	"castle_shield": preload("res://scenes/enemies/castle_shield.tscn"),
	"castle_knight": preload("res://scenes/enemies/castle_knight.tscn"),
}

const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")
const EXIT_PORTAL_SCENE := preload("res://scenes/dungeon/exit_portal.tscn")
const BOSS_ROOM_DOOR_SCENE := preload("res://scenes/dungeon/boss_room_door.tscn")
const STAIR_LEVER_SCENE := preload("res://scenes/dungeon/stair_lever.tscn")
const STAIR_COLLISION := preload("res://scripts/dungeon/stair_collision_builder.gd")
const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const FINAL_BOSS_SCENE := preload("res://scenes/enemies/final_boss_forgotten_castle.tscn")
const ILLUSORY_WALL_SCENE := preload("res://scenes/dungeon/illusory_wall.tscn")
const HIDDEN_LEVER_SCENE := preload("res://scenes/dungeon/hidden_lever.tscn")
const DifficultyProfileScript := preload("res://scripts/dungeon/difficulty_profile.gd")
const FloorShellBuilderScript := preload("res://scripts/dungeon/floor_shell_builder.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")
const RoomContentSpawnerScript := preload(
	"res://scripts/dungeon/room_content/room_content_spawner.gd"
)

signal build_complete
signal boss_defeated
signal snapshot_dirty
signal build_progress(ratio: float)
signal room_cleared(room_id: String)

const CHUNK_ROOMS_PER_FRAME := 3
const CHUNK_ENEMIES_PER_FRAME := 4
const CHUNK_LOOT_PER_FRAME := 6

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
var _cleared_rooms: Dictionary = {}
var _chest_by_id: Dictionary = {}
var _boss_door: Node3D
var _stair_levers: Dictionary = {}
var _is_final_floor := false

var _edge_by_pair: Dictionary = {}

var _build_generation := 0


func _exit_tree() -> void:
	cancel()
	unload_from_parent(get_parent() as Node3D)


func cancel() -> void:
	_build_generation += 1


func _yield_step(chunked: bool, my_gen: int) -> bool:
	if chunked:
		var tree := get_tree()
		if tree == null:
			return false
		await tree.process_frame
	return my_gen == _build_generation and is_inside_tree()


func build(
	parent: Node3D,
	player: CharacterBody3D,
	fixture_path: String = FIXTURE_RELATIVE,
	chunked: bool = false
) -> void:
	await build_from_source(parent, player, fixture_path, {}, chunked)


func build_from_definition(
	parent: Node3D, player: CharacterBody3D, def: Dictionary, chunked: bool = false
) -> void:
	await build_from_source(parent, player, "", def, chunked)


func build_from_source(
	parent: Node3D,
	player: CharacterBody3D,
	fixture_path: String,
	def: Dictionary,
	chunked: bool = false
) -> void:
	cancel()
	var my_gen := _build_generation
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
	const TOTAL_STEPS := 21.0
	var step := 0.0

	if not await _build_rooms(chunked, my_gen):
		_abort_build(parent)
		return
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_setup_floor_nav_map()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_sync_blockout_doors_from_edges()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_verify_doorway_alignment()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_clear_doorway_obstructions()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_build_height_transitions()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_build_floor_shell()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_build_landmarks()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_place_cover()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_finalize_all_blockouts()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_place_secret_mechanisms()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_build_nav_links()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_spawn_player()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	await _place_enemies(chunked, my_gen)
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	await _place_loot(chunked, my_gen)
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_place_traps()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_place_room_content()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_setup_boss()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	if _is_final_floor:
		_setup_exit_portal()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_setup_stair_levers()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_setup_boss_door(parent)
	step += 1.0
	build_progress.emit(1.0)
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


func _build_rooms(chunked: bool, my_gen: int) -> bool:
	DioramaRoomDressing.begin_floor_lighting_pass(biome_id)
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
	var room_defs: Array = definition.get("rooms", [])
	for i in range(room_defs.size()):
		var room_def: Dictionary = room_defs[i]
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
		instance.room_kind = str(room_def.get("kind", ""))
		var room_tags := PackedStringArray()
		for tag in room_def.get("tags", []):
			var tag_name := str(tag)
			if tag_name == "":
				continue
			room_tags.append(tag_name)
			instance.add_to_group("room_tag_%s" % tag_name)
		instance.room_tags = room_tags
		var blockout := instance.get_blockout()
		if blockout:
			blockout.skip_floor = false
		rooms_root.add_child(instance)
		_rooms[room_def.get("id", "")] = instance
		if str(room_def.get("templateId", "")).ends_with("_stairs"):
			STAIR_COLLISION.ensure_stair_collision(instance)
		if chunked and (i + 1) % CHUNK_ROOMS_PER_FRAME == 0:
			if not await _yield_step(chunked, my_gen):
				return false
	return true


func _setup_floor_nav_map() -> void:
	if _floor_nav_map != RID():
		NavigationServer3D.free_rid(_floor_nav_map)
		_floor_nav_map = RID()
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


## Opens exactly the doorways the floor's edges call for, and no others.
##
## Every room starts with the doors its *template* declares -- `_apply_kind_spec` sets all four from
## the kind spec, and most kinds declare all four -- so without closing them first a room ends up
## with holes in walls that back onto solid rock or onto a neighbour that has no matching opening.
## Only edges know which walls are really shared, so they are the authority. Secret doors stay shut
## on purpose: a secret is revealed by finding its lever or wall, not by the floor being built.
## The definition edge joining two rooms, in either order, or `{}` when they are not neighbours.
func edge_between(from_id: String, to_id: String) -> Dictionary:
	if _edge_by_pair.is_empty():
		for edge in definition.get("edges", []):
			var a := str(edge.get("from", ""))
			var b := str(edge.get("to", ""))
			_edge_by_pair["%s>%s" % [a, b]] = edge
			_edge_by_pair["%s>%s" % [b, a]] = edge
	return _edge_by_pair.get("%s>%s" % [from_id, to_id], {})


## The socket on `from_room` that faces the doorway it shares with `to_room`.
##
## Everything that wants to sit in a doorway -- the locked door, the puzzle gate, the illusory
## panel, the navigation link -- has to ask through here rather than through
## `RoomTemplate.socket_toward`. That guesses the wall from the line between the two room centres,
## which was correct only while every door was pinned to the middle of its wall. Doors slide now,
## so two neighbours routinely sit diagonally offset and the centre line points at a corner: the
## guess picks whichever of the two walls is nearer, and half the time that is the wall the rooms
## do not share at all.
func door_socket_between(from_room: RoomTemplate, to_room: RoomTemplate) -> DoorwaySocket:
	if from_room == null or to_room == null:
		return null
	return _socket_for_edge(from_room, to_room, edge_between(from_room.room_id, to_room.room_id))


func _sync_blockout_doors_from_edges() -> void:
	_close_all_blockout_doors()
	for edge in definition.get("edges", []):
		var kind := str(edge.get("kind", "door"))
		if kind in ["secret", "shortcut"]:
			continue
		var from_room := get_room(str(edge.get("from", "")))
		var to_room := get_room(str(edge.get("to", "")))
		if from_room == null or to_room == null:
			continue
		_open_blockout_door_toward(from_room, to_room, edge)
		_open_blockout_door_toward(to_room, from_room, edge)


func _close_all_blockout_doors() -> void:
	for room_id in _rooms:
		var room := get_room(room_id)
		if room == null:
			continue
		var blockout := room.get_blockout()
		if blockout == null:
			continue
		blockout.door_north = false
		blockout.door_south = false
		blockout.door_east = false
		blockout.door_west = false


## Opens the door on `from_room` that leads to `to_room`, at the point the two rooms share.
##
## `edge` carries the wall and the world position of the doorway, because neither can be recovered
## from the rooms any more: doors slide along their wall now, so two neighbours can sit diagonally
## offset from each other and the line between their centres no longer names the shared wall.
func _open_blockout_door_toward(
	from_room: RoomTemplate, to_room: RoomTemplate, edge: Dictionary = {}
) -> void:
	var blockout := from_room.get_blockout()
	if blockout == null:
		return
	var socket := _socket_for_edge(from_room, to_room, edge)
	if socket == null:
		push_error(
			"DungeonBuilder: no socket from %s toward %s" % [from_room.room_id, to_room.room_id]
		)
		return
	var lateral := _door_lateral(from_room, socket, edge)
	match socket.direction:
		CastleRoomConstants.Direction.NORTH:
			blockout.door_north = true
			blockout.door_north_offset = lateral
		CastleRoomConstants.Direction.EAST:
			blockout.door_east = true
			blockout.door_east_offset = lateral
		CastleRoomConstants.Direction.SOUTH:
			blockout.door_south = true
			blockout.door_south_offset = lateral
		CastleRoomConstants.Direction.WEST:
			blockout.door_west = true
			blockout.door_west_offset = lateral
	socket.position = RoomTemplateCatalogScript.socket_wall_position(
		socket.direction, blockout.room_width * 0.5, blockout.room_depth * 0.5, lateral
	)


## The socket on the wall the edge names, falling back to the old centre-delta guess.
##
## `edge.dir` is authored once, facing outward from `edge.from` toward `edge.to` -- so a caller
## asking for the socket on the far side of the same edge needs the opposite of that facing, or it
## picks the far room's opposite wall instead of the one the two rooms actually share.
func _socket_for_edge(
	from_room: RoomTemplate, to_room: RoomTemplate, edge: Dictionary
) -> DoorwaySocket:
	var dir_name := str(edge.get("dir", ""))
	if dir_name == "":
		return from_room.socket_toward(to_room)
	var world_dir := Vector3.ZERO
	match dir_name:
		"north":
			world_dir = Vector3(0.0, 0.0, -1.0)
		"south":
			world_dir = Vector3(0.0, 0.0, 1.0)
		"east":
			world_dir = Vector3(1.0, 0.0, 0.0)
		_:
			world_dir = Vector3(-1.0, 0.0, 0.0)
	if str(edge.get("from", "")) != from_room.room_id:
		world_dir = -world_dir
	var best: DoorwaySocket = null
	var best_dot := 0.5
	for socket in from_room.get_sockets():
		var dot := socket.get_world_facing().dot(world_dir)
		if dot > best_dot:
			best_dot = dot
			best = socket
	return best if best != null else from_room.socket_toward(to_room)


## How far along its wall the doorway sits, in the room's own frame.
func _door_lateral(from_room: RoomTemplate, socket: DoorwaySocket, edge: Dictionary) -> float:
	var door: Dictionary = edge.get("door", {})
	if door.is_empty():
		return 0.0
	var local := from_room.to_local(
		Vector3(float(door.get("x", 0.0)), 0.0, float(door.get("z", 0.0)))
	)
	# North and south walls run along the room's local x; east and west along its local z.
	match socket.direction:
		CastleRoomConstants.Direction.NORTH, CastleRoomConstants.Direction.SOUTH:
			return local.x
		_:
			return local.z


## Checks that both sides of every doorway agree on where it is.
##
## Purely a tripwire -- it builds nothing. The two rooms are seated flush on the lattice and the
## opening is cut from the edge's own world position, so the two sockets should coincide exactly;
## a nonzero span means a room's footprint and its reserved cells have drifted apart, which is the
## one failure that silently produces doors opening onto solid rock.
func _verify_doorway_alignment() -> void:
	for edge in definition.get("edges", []):
		var kind := str(edge.get("kind", "door"))
		# Shortcuts are the graph links the lattice could not close: the two rooms do not touch, so
		# there is no wall to cut. They stay in the definition for the minimap and nothing else.
		if kind in ["secret", "shortcut"]:
			continue
		var from_room := get_room(str(edge.get("from", "")))
		var to_room := get_room(str(edge.get("to", "")))
		if from_room == null or to_room == null:
			continue
		var from_socket := _socket_for_edge(from_room, to_room, edge)
		var to_socket := _socket_for_edge(to_room, from_room, edge)
		if from_socket == null or to_socket == null:
			push_error(
				(
					"DungeonBuilder: missing socket on edge %s->%s"
					% [edge.get("from", ""), edge.get("to", "")]
				)
			)
			continue
		var offset := to_socket.global_position - from_socket.global_position
		offset.y = 0.0
		if offset.length() >= 0.5:
			push_error(
				(
					"DungeonBuilder: doorway span %.2f on %s->%s indicates a footprint mismatch"
					% [offset.length(), edge.get("from", ""), edge.get("to", "")]
				)
			)


## Frees dressing that the doorway sweep found standing in an opening.
##
## Room dressing is authored against a room's own frame, from back when every door sat in the
## middle of its wall -- so a banner hung at the centre of the north wall, and pillars and braziers
## were tucked into corners well clear of it. Doors slide along their wall now, and the dressing
## has no idea where this floor put them, so the banner ends up bricking a doorway and a brazier
## ends up standing in one. Neither the dressing nor the blockout can see the other, so the check
## has to happen here, once the doors for this floor are final.
const DOORWAY_CLEARANCE := 1.6

## Half the width kept clear either side of the opening, a little wider than the door itself so a
## prop cannot clip its jamb.
const DOORWAY_HALF_SPAN := CastleRoomConstants.DOOR_WIDTH * 0.5 + 0.4

const DRESSING_ROOTS := ["DioramaDressing", "CeilingLighting"]


func _clear_doorway_obstructions() -> void:
	for room_id in _rooms:
		var room := get_room(room_id)
		if room == null:
			continue
		var blockout := room.get_blockout()
		if blockout == null:
			continue
		var props := room.get_node_or_null("Props") as Node3D
		if props == null:
			continue
		var zones := _doorway_zones(blockout)
		if zones.is_empty():
			continue
		for root in _prop_roots(props):
			for child in root.get_children():
				var prop := child as Node3D
				if prop == null:
					continue
				# Markers are not geometry. They are where enemies, chests and levers get put, and
				# freeing one costs the room its spawn rather than clearing anything.
				if prop is Marker3D:
					continue
				# Anything mounted above the lintel clears the opening on its own -- the ceiling
				# torches are the whole reason this is checked rather than assumed.
				if prop.position.y >= CastleRoomConstants.DOOR_HEIGHT:
					continue
				if _in_any_doorway(zones, prop.position):
					root.remove_child(prop)
					prop.queue_free()


## `Props` itself plus the two roots the dressing pass fills, which is every place a room's
## scenery ends up: authored props sit directly under `Props`, generated ones one level down.
func _prop_roots(props: Node3D) -> Array[Node3D]:
	var roots: Array[Node3D] = [props]
	for root_name in DRESSING_ROOTS:
		var root := props.get_node_or_null(root_name) as Node3D
		if root != null:
			roots.append(root)
	return roots


## Each open doorway as `{axis_pos, along, lo, hi}` in the room's own frame: the strip of floor in
## front of the opening that has to stay walkable.
func _doorway_zones(blockout: CastleBlockout) -> Array:
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	var zones: Array = []
	if blockout.door_north:
		zones.append(_zone(true, blockout.door_north_offset, -half_d, -half_d + DOORWAY_CLEARANCE))
	if blockout.door_south:
		zones.append(_zone(true, blockout.door_south_offset, half_d - DOORWAY_CLEARANCE, half_d))
	if blockout.door_east:
		zones.append(_zone(false, blockout.door_east_offset, half_w - DOORWAY_CLEARANCE, half_w))
	if blockout.door_west:
		zones.append(_zone(false, blockout.door_west_offset, -half_w, -half_w + DOORWAY_CLEARANCE))
	return zones


func _zone(along_x: bool, offset: float, lo: float, hi: float) -> Dictionary:
	return {"along_x": along_x, "offset": offset, "lo": lo, "hi": hi}


## `radius` widens the opening by the half-footprint of whatever is being tested, so a wide pillar
## whose centre clears the doorway but whose corner does not is still caught.
func _in_any_doorway(zones: Array, local_pos: Vector3, radius: float = 0.0) -> bool:
	for zone in zones:
		var along: float = local_pos.x if zone["along_x"] else local_pos.z
		var across: float = local_pos.z if zone["along_x"] else local_pos.x
		if absf(along - float(zone["offset"])) > DOORWAY_HALF_SPAN + radius:
			continue
		if across >= float(zone["lo"]) - radius and across <= float(zone["hi"]) + radius:
			return true
	return false


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
	var zones_by_room := {}
	for placement in cover_placements:
		var room := get_room(placement.get("roomId", ""))
		if room == null:
			continue
		var blockout := room.get_blockout()
		if blockout == null:
			continue
		if not zones_by_room.has(room):
			zones_by_room[room] = _doorway_zones(blockout)
		var offset: Dictionary = placement.get("offset", {})
		var size: Dictionary = placement.get("size", {})
		var size_vec := Vector3(
			float(size.get("x", 1.2)), float(size.get("y", 2.4)), float(size.get("z", 1.2))
		)
		var local_pos := Vector3(
			float(offset.get("x", 0.0)), float(offset.get("y", 0.0)), float(offset.get("z", 0.0))
		)
		# Cover anchors are authored per room kind, so they know nothing about where this floor slid
		# the doors. A pillar is solid collision -- one standing in an opening does not just look
		# wrong, it seals the room. Dropped rather than nudged: the anchor list is generous and the
		# room reads fine one pillar short.
		var half_footprint := maxf(size_vec.x, size_vec.z) * 0.5
		if _in_any_doorway(zones_by_room.get(room, []), local_pos, half_footprint):
			continue
		blockout.add_cover_obstacle(local_pos, size_vec, wall_mat)


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
			socket = door_socket_between(parent_room, secret_room)
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
				_open_blockout_door_toward(from_room, to_room, edge)
				_open_blockout_door_toward(to_room, from_room, edge)
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
		# Shortcuts are deliberately absent: they are the links the lattice could not close, so
		# there is no opening to walk through and a link across one routes enemies into rock.
		if kind not in ["door", "corridor", "secret"]:
			continue
		var from_room := get_room(edge.get("from", ""))
		var to_room := get_room(edge.get("to", ""))
		if from_room == null or to_room == null:
			continue
		var from_socket := _socket_for_edge(from_room, to_room, edge)
		var to_socket := _socket_for_edge(to_room, from_room, edge)
		if from_socket == null or to_socket == null:
			continue
		var link := NavigationLink3D.new()
		link.bidirectional = true
		link.travel_cost = 1.0
		link.set_navigation_map(_floor_nav_map)
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
		CharacterFloorSnapScript.snap_to_floor_below(_player)
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


func _place_enemies(chunked: bool, my_gen: int) -> void:
	var placements: Array = definition.get("placements", {}).get("enemies", [])
	for i in range(placements.size()):
		_spawn_enemy(placements[i], i)
		if chunked and (i + 1) % CHUNK_ENEMIES_PER_FRAME == 0:
			if not await _yield_step(chunked, my_gen):
				return


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
		CharacterFloorSnapScript.snap_to_floor_below(enemy as CharacterBody3D)
	enemy.set_meta("placement_id", placement_key)
	enemy.set_meta("catalog_id", enemy_id)
	if enemy.has_method("set_player"):
		enemy.call("set_player", _player)
	if placement.get("isElite", false):
		enemy.set_meta("is_elite", true)
	_apply_floor_scaling(enemy)
	_ensure_enemy_groups(enemy)
	_enemy_by_id[placement_key] = enemy
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_tracked_enemy_died.bind(placement_key))


func _place_loot(chunked: bool, my_gen: int) -> void:
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
		if chunked and (i + 1) % CHUNK_LOOT_PER_FRAME == 0:
			if not await _yield_step(chunked, my_gen):
				return


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
	RoomContentSpawnerScript.spawn_shortcut_gates(self, definition)


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
		CharacterFloorSnapScript.snap_to_floor_below(_boss as CharacterBody3D)
	if _boss.has_method("set_player"):
		_boss.call("set_player", _player)
	_boss.set_meta("catalog_id", enemy_id)
	_apply_floor_scaling(_boss, true)
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
		if not RunFloorConfig.is_stairs_room({"kind": room.room_kind}):
			continue
		stairs_count += 1
		if stairs_count > 1:
			push_error(
				(
					"DungeonBuilder: multiple stairs rooms on floor — expected exactly one (found %s)"
					% str(room_id)
				)
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


func _place_stair_lever_on_wall(lever: Node3D, room: RoomTemplate) -> bool:
	var spawn := room.get_node_or_null("SpawnPoints/LeverSpawn") as Node3D
	if spawn == null:
		push_error("DungeonBuilder: missing SpawnPoints/LeverSpawn in %s" % str(room.template_id))
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


func get_stair_spawn_global(stair_room_id: String, _ascending: bool) -> Dictionary:
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
		door.call("configure", biome_id, requirement, RunFlow.get_current_floor(), locks)

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


func _boss_approach_socket(room: RoomTemplate) -> DoorwaySocket:
	var sockets := room.get_sockets()
	if sockets.is_empty():
		return null
	if sockets.size() == 1:
		return sockets[0]
	var best: DoorwaySocket = null
	var best_dot := -2.0
	var approach := CombatFacing.forward_of(room)
	for socket in sockets:
		var dot := socket.get_world_facing().dot(approach)
		if dot > best_dot:
			best_dot = dot
			best = socket
	return best if best != null else room.find_socket(CastleRoomConstants.Direction.NORTH)


func get_tracked_enemy(placement_id: String) -> Node:
	return _enemy_by_id.get(placement_id)


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


func _on_tracked_enemy_died(placement_id: String) -> void:
	snapshot_dirty.emit()
	_dispatch_room_clear(placement_id)


func _dispatch_room_clear(placement_id: String) -> void:
	var separator := placement_id.rfind(":")
	if separator <= 0:
		return
	var room_id := placement_id.substr(0, separator)
	if room_id == "" or _cleared_rooms.has(room_id):
		return
	var prefix := "%s:" % room_id
	for other_id in _enemy_by_id:
		var other := str(other_id)
		if other == placement_id or not other.begins_with(prefix):
			continue
		var enemy: Node = _enemy_by_id[other_id]
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and bool(enemy.call("is_dead")):
			continue
		return
	_cleared_rooms[room_id] = true
	room_cleared.emit(room_id)
	if CombatEvents and _player:
		CombatEvents.dispatch(CombatEvents.ON_ROOM_CLEAR, {"actor": _player})


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
	_cleared_rooms.clear()
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


func _apply_floor_scaling(enemy: Node, is_boss: bool = false) -> void:
	var mode := RunFlow.get_run_mode()
	var progress: int
	match mode:
		"endless", "castle":
			progress = RunFlow.get_current_floor()
		"waves":
			progress = WavesRunService.current_wave
		_:
			return
	var profile := DifficultyProfileScript.for_run(
		mode, RunFlow.current_dungeon_id, RunFlow.get_difficulty_tier()
	)
	var is_elite: bool = enemy.get_meta("is_elite", false)
	var hp_mult := profile.hp_multiplier(progress)
	if is_elite and mode == "castle":
		hp_mult *= 1.5
	var health := enemy.get_node_or_null("Health") as Health
	if health:
		health.configure(float(health.max_health) * hp_mult)
	if enemy.has_method("set_damage_multiplier"):
		var dmg_mult := profile.damage_multiplier(progress)
		if is_elite and mode == "castle":
			dmg_mult *= 1.25
		enemy.call("set_damage_multiplier", dmg_mult)
	if is_boss:
		return
	if enemy.has_method("apply_phase_modifiers"):
		enemy.call("apply_phase_modifiers", profile.behaviour_modifiers(progress))
