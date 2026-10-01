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
signal secret_edge_revealed(from_id: String, to_id: String)

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
var _owns_floor_nav_map := false
var _placement_rng: RandomNumberGenerator
var _boss: Node
## At most one miniboss per floor today (`ProcgenPlacements._place_miniboss`), so a single
## slot -- plus the room it's in, so `castle_run.gd` knows when the player has walked in on it.
var _miniboss: Node
var _miniboss_room_id := ""
var _enemy_by_id: Dictionary = {}
var _cleared_rooms: Dictionary = {}
## Summoned and split enemies alive per room. They are not placements, but a room is only clear
## once they are dead too.
var _room_adds: Dictionary = {}
var _chest_by_id: Dictionary = {}
var _boss_door: Node3D
var _stair_levers: Dictionary = {}
var _is_final_floor := false

var _edge_by_pair: Dictionary = {}

var _build_generation := 0
var _secret_topology_refresh_queued := false
var _secret_refresh_rooms: Dictionary = {}


func _exit_tree() -> void:
	cancel()
	unload_from_parent(get_parent() as Node3D)


func cancel() -> void:
	_build_generation += 1


## A frame has a few milliseconds for the build and no more: a long loop hands the frame back once
## that budget is spent instead of running to its end.
const FRAME_BUDGET_USEC := 4000
var _slice_started_usec := 0


func _yield_step(chunked: bool, my_gen: int) -> bool:
	if chunked:
		var tree := get_tree()
		if tree == null:
			return false
		await tree.process_frame
	_slice_started_usec = Time.get_ticks_usec()
	return my_gen == _build_generation and is_inside_tree()


## Inside a loop: yields only when this frame's budget is gone.
func _yield_if_over_budget(chunked: bool, my_gen: int) -> bool:
	if not chunked or Time.get_ticks_usec() - _slice_started_usec < FRAME_BUDGET_USEC:
		return my_gen == _build_generation
	return await _yield_step(chunked, my_gen)


func build(
	parent: Node3D,
	player: CharacterBody3D,
	fixture_path: String = FIXTURE_RELATIVE,
	chunked: bool = false
) -> bool:
	return await build_from_source(parent, player, fixture_path, {}, chunked)


func build_from_definition(
	parent: Node3D, player: CharacterBody3D, def: Dictionary, chunked: bool = false
) -> bool:
	return await build_from_source(parent, player, "", def, chunked)


func build_from_source(
	parent: Node3D,
	player: CharacterBody3D,
	fixture_path: String,
	def: Dictionary,
	chunked: bool = false
) -> bool:
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
		return false
	biome_id = BiomeRegistry.resolve_biome_id(definition)
	_is_final_floor = (
		bool(definition.get("isFinalFloor", false))
		or (RunFlow.is_final_floor() and RunFlow.get_run_mode() != "endless")
	)
	_room_scenes = BiomeRegistry.get_room_scenes(biome_id)
	var rooms: Array = definition.get("rooms", [])
	if rooms.is_empty():
		push_error("DungeonBuilder: definition has no rooms")
		return false
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
		return false
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_setup_floor_nav_map()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_sync_blockout_doors_from_edges()
	if not await _dress_rooms(chunked, my_gen):
		return false
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	if _verify_doorway_alignment():
		push_error("DungeonBuilder: aborting build, doorway alignment failed")
		_abort_build(parent)
		return false
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_clear_doorway_obstructions()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_build_height_transitions()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_build_floor_shell()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_build_landmarks()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_place_cover()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	if not await _finalize_all_blockouts(chunked, my_gen):
		return false
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_place_secret_mechanisms()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_build_nav_links()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_spawn_player()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	await _place_enemies(chunked, my_gen)
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	await _place_loot(chunked, my_gen)
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_place_traps()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	if not _place_room_content():
		_abort_build(parent)
		return false
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_setup_boss()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	if _is_final_floor:
		_setup_exit_portal()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	_setup_stair_levers()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return false

	if not _setup_boss_door(parent):
		_abort_build(parent)
		return false
	step += 1.0
	build_progress.emit(1.0)
	build_complete.emit()
	return true


func _abort_build(parent: Node3D) -> void:
	unload_from_parent(parent)


func get_room(room_id: String) -> RoomTemplate:
	return _rooms.get(room_id) as RoomTemplate


func get_room_ids() -> Array:
	return _rooms.keys()


func get_boss() -> Node:
	return _boss


func get_miniboss() -> Node:
	return _miniboss if is_instance_valid(_miniboss) else null


func get_miniboss_room_id() -> String:
	return _miniboss_room_id


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
		instance.position = Vector3(t.get("x", 0.0), 0.0, t.get("z", 0.0))
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
		var tactical_family := str(room_def.get("tacticalFamily", ""))
		if tactical_family != "":
			room_tags.append("family_%s" % tactical_family)
			instance.add_to_group("room_family_%s" % tactical_family)
		instance.room_tags = room_tags
		var blockout := instance.get_blockout()
		if blockout:
			blockout.skip_floor = false
			if blockout.shape == &"split" or str(room_def.get("shape", "")) == "split":
				blockout.shape_override = &"rect"
		rooms_root.add_child(instance)
		_rooms[room_def.get("id", "")] = instance
		if str(room_def.get("templateId", "")).ends_with("_stairs"):
			var decorative_ramp := instance.get_node_or_null("Props/StairRamp") as MeshInstance3D
			if decorative_ramp:
				decorative_ramp.visible = false
		if chunked and (i + 1) % CHUNK_ROOMS_PER_FRAME == 0:
			if not await _yield_step(chunked, my_gen):
				return false
	return true


func _setup_floor_nav_map() -> void:
	if _owns_floor_nav_map and _floor_nav_map != RID():
		NavigationServer3D.free_rid(_floor_nav_map)
	_floor_nav_map = RID()
	_owns_floor_nav_map = false
	var world := get_world_3d()
	if world != null and world.navigation_map != RID():
		# NavigationAgent3D uses World3D.navigation_map unless explicitly overridden. Registering
		# rooms on a private map made the generated floor invisible to live enemy agents.
		_floor_nav_map = world.navigation_map
	else:
		_floor_nav_map = NavigationServer3D.map_create()
		_owns_floor_nav_map = true
		NavigationServer3D.map_set_active(_floor_nav_map, true)
		NavigationServer3D.map_set_use_edge_connections(_floor_nav_map, true)
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


func get_floor_navigation_map() -> RID:
	return _floor_nav_map


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
## panel, the navigation link -- asks through here: the wall comes from the edge itself, because
## doors slide along their walls and the line between two room centres can point at a corner.
func door_socket_between(from_room: RoomTemplate, to_room: RoomTemplate) -> DoorwaySocket:
	if from_room == null or to_room == null:
		return null
	return _socket_for_edge(from_room, to_room, edge_between(from_room.room_id, to_room.room_id))


func _dress_rooms(chunked: bool, my_gen: int) -> bool:
	for room_id in _rooms:
		var room := get_room(str(room_id)) as CastleRoomScene
		if room != null:
			room.dress()
		if not await _yield_if_over_budget(chunked, my_gen):
			return false
	return true


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
## from the rooms: doors slide along their wall, so two neighbours can sit diagonally offset from each
## other and the line between their centres does not name the shared wall.
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
	var raw_lateral := _door_lateral(from_room, socket, edge)
	# `CastleBlockout._build_wall()` clamps its own `door_offset` to the wall's own span before
	# cutting the hole (`limit := (span - DOOR_WIDTH) * 0.5`) -- a lateral computed from the edge's
	# real-world door coordinate can land outside that span (room-size rounding, a door close to a
	# corner, a large multi-cell room), and until now only the *cut* used the clamped value: the
	# frame built below and the socket every neighbour/dressing/nav query reads was placed at the
	# raw, unclamped position. That is the door-to-nowhere bug -- a doorway frame standing somewhere
	# along the wall with the actual passable opening cut at a different point on the same wall, or
	# past the corner into a wall the room doesn't even share with its neighbour. Clamping here once,
	# the same way, keeps the socket and the hole it decorates at the same point on the wall always.
	var half_span := (
		blockout.room_width * 0.5
		if socket.direction in [CastleRoomConstants.Direction.NORTH, CastleRoomConstants.Direction.SOUTH]
		else blockout.room_depth * 0.5
	)
	var lateral_limit := maxf(0.0, half_span - CastleRoomConstants.DOOR_WIDTH * 0.5)
	var lateral := clampf(raw_lateral, -lateral_limit, lateral_limit)
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
	socket.landing_height = blockout.socket_landing_height(socket.direction)
	socket.position.y = socket.landing_height
	# A frame around the hole, not just the hole -- guarded since a floor can resync its
	# door state (`_sync_blockout_doors_from_edges` closes then reopens every door) and this must
	# not stack a second frame on the same socket when that happens.
	if socket.get_node_or_null("DoorwayFrameVisual") == null:
		DIORAMA_SKIN.build_doorway_frame(
			socket, biome_id, CastleRoomConstants.DOOR_WIDTH, CastleRoomConstants.DOOR_HEIGHT
		)


## The socket on the wall the edge names, or null when the edge names none: the callers report it,
## because guessing the wall from the room centres picks the wrong one on offset neighbours.
##
## `edge.dir` is authored once, facing outward from `edge.from` toward `edge.to` -- so a caller
## asking for the socket on the far side of the same edge needs the opposite of that facing, or it
## picks the far room's opposite wall instead of the one the two rooms actually share.
func _socket_for_edge(
	from_room: RoomTemplate, _to_room: RoomTemplate, edge: Dictionary
) -> DoorwaySocket:
	var dir_name := str(edge.get("dir", ""))
	if dir_name == "":
		return null
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
	return best


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
## The two rooms are seated flush on the lattice and the opening is cut from the edge's own world
## position, so the two sockets should coincide exactly; a nonzero span means a room's footprint
## and its reserved cells have drifted apart, which is the one failure that silently produces doors
## opening onto solid rock. Returns true if a mismatch was found, so `_build_debug_build()` can
## abort the build rather than let it limp -- a mismatch here is exactly the failure
## bedrock plane exists to catch, and it should never ship undetected during development.
func _verify_doorway_alignment() -> bool:
	var mismatch := false
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
			mismatch = true
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
			mismatch = true
	return mismatch


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
## A round or octagon room's opening sits on the circle, not on the wall-centre rectangle the
## plain-rect version below assumes -- using the radius in place of `half_w`/`half_d` keeps the zone
## anchored to where the wall segments were actually skipped
## (`CastleBlockout._build_curved_perimeter()`), not to a wall that does not exist there.
func _doorway_zones(blockout: CastleBlockout) -> Array:
	if blockout.shape == &"round" or blockout.shape == &"octagon":
		var radius: float = minf(blockout.room_width, blockout.room_depth) * 0.5
		var curved_zones: Array = []
		if blockout.door_north:
			curved_zones.append(_zone(true, blockout.door_north_offset, -radius, -radius + DOORWAY_CLEARANCE))
		if blockout.door_south:
			curved_zones.append(_zone(true, blockout.door_south_offset, radius - DOORWAY_CLEARANCE, radius))
		if blockout.door_east:
			curved_zones.append(_zone(false, blockout.door_east_offset, radius - DOORWAY_CLEARANCE, radius))
		if blockout.door_west:
			curved_zones.append(_zone(false, blockout.door_west_offset, -radius, -radius + DOORWAY_CLEARANCE))
		return curved_zones
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
	for edge in definition.get("edges", []):
		var kind := str(edge.get("kind", "door"))
		if kind == "secret":
			continue
		var from_room := get_room(str(edge.get("from", "")))
		var to_room := get_room(str(edge.get("to", "")))
		if from_room == null or to_room == null:
			continue
		# A logical room transform is not enough here: a split room has a raised north
		# landing while its origin remains at the floor's base elevation. Compare the
		# doorway landings themselves so every physical rise gets a valid transition.
		var from_socket := _socket_for_edge(from_room, to_room, edge)
		var to_socket := _socket_for_edge(to_room, from_room, edge)
		if from_socket == null or to_socket == null:
			push_error(
				"DungeonBuilder: missing socket for height transition %s->%s"
				% [edge.get("from", ""), edge.get("to", "")]
			)
			continue
		var from_y := from_socket.global_position.y
		var to_y := to_socket.global_position.y
		if absf(from_y - to_y) < 0.001:
			continue
		var lower_room := from_room if from_y < to_y else to_room
		var higher_room := to_room if from_y < to_y else from_room
		var blockout := lower_room.get_blockout()
		if blockout == null:
			continue
		var socket := from_socket if lower_room == from_room else to_socket
		if socket == null:
			push_error(
				(
					"DungeonBuilder: no height-transition socket from %s toward %s"
					% [lower_room.room_id, higher_room.room_id]
				)
			)
			continue
		# A "down" one-way edge omits the ramp entirely -- the doorway is still cut normally,
		# but with nothing to climb, `HEIGHT_STEP`'s 3-unit rise is tall enough on its own that a
		# player can drop from the higher room into the lower one yet cannot get back up without a
		# ramp. No separate collision trick needed, unlike `RoomShortcutGateContent`'s barrier.
		if str(edge.get("oneWay", "")) == "down":
			continue
		var direction := _direction_to_vector(socket.direction)
		var lateral := _door_lateral(lower_room, socket, edge)
		var step_count := ceili(absf(from_y - to_y) / STEP_HEIGHT)
		blockout.add_height_stairs(step_count, direction, STEP_HEIGHT, lateral)


func _direction_to_vector(direction: CastleRoomConstants.Direction) -> Vector2i:
	match direction:
		CastleRoomConstants.Direction.NORTH:
			return Vector2i(0, -1)
		CastleRoomConstants.Direction.EAST:
			return Vector2i(1, 0)
		CastleRoomConstants.Direction.SOUTH:
			return Vector2i(0, 1)
		_:
			return Vector2i(-1, 0)


func _build_landmarks() -> void:
	var landmarks: Array = definition.get("landmarks", [])
	if landmarks.is_empty():
		return
	var root := Node3D.new()
	root.name = "Landmarks"
	_dungeon_root.add_child(root)
	for hint in landmarks:
		var pos: Dictionary = hint.get("position", {})
		var scale_hint: Dictionary = hint.get("scale", {})
		var height := float(scale_hint.get("y", 16.0))
		var half_width := maxf(0.5, float(scale_hint.get("x", 2.0)) * 0.5)
		var kind := str(hint.get("kind", "landmark"))
		var landmark: Node3D
		match kind:
			"boss_spire":
				landmark = DioramaPropFactory.build_boss_spire(biome_id, height, half_width)
			"boss_silhouette":
				landmark = DioramaPropFactory.build_boss_silhouette(biome_id, height, half_width)
			"orientation_spire":
				landmark = DioramaPropFactory.build_orientation_spire(biome_id, height, half_width)
			_:
				landmark = DioramaPropFactory.build_orientation_spire(biome_id, height, half_width)
		landmark.position = Vector3(
			float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0))
		)
		var room_id := str(hint.get("revealRoomId", hint.get("roomId", "")))
		if room_id != "" and kind in ["junction_beacon", "orientation_spire"]:
			landmark.set_meta("map_landmark_room_id", room_id)
			landmark.set_meta("map_landmark_reveal_distance", 24.0 if kind == "orientation_spire" else 8.0)
			landmark.add_to_group("map_landmark_revealer")
		root.add_child(landmark)


func _place_cover() -> void:
	# Generated cover used full-height wall blocks at tactical anchors. Those blocks could
	# obstruct stair rooms and visually read as stray walls. Keep traversal clear.
	pass


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
		# A lever hides best in a place the room's own lighting already draws the eye to,
		# not tucked in a socket like the illusory wall (which has to sit in an actual doorway gap
		# to disguise as one). Falls back to the socket when the room has no fixture to anchor on.
		var fixture_pos: Variant = (
			_brightest_fixture_position(props) if mechanism == "hidden_lever" else null
		)
		if fixture_pos != null:
			mechanism_node.position = fixture_pos
		elif socket:
			mechanism_node.position = socket.position
			mechanism_node.rotation = socket.rotation
		if mechanism_node.has_method("configure"):
			mechanism_node.call("configure", secret_room_id, self)
		mechanism_node.set_meta("secret_room_id", secret_room_id)
		props.add_child(mechanism_node)
		var flag_id := WorldFlags.secret_opened(secret_room_id)
		if WorldState.has_flag(flag_id):
			reveal_secret(secret_room_id, false)


## The room's brightest light fixture, in the parent room's local frame -- a `Brazier` first (the
## biggest light `DioramaRoomDressing` builds), falling back to any wall/ceiling torch. `null` when
## the room's dressing has nothing of the kind, so the caller falls back to the doorway socket.
func _brightest_fixture_position(props: Node3D) -> Variant:
	var dressing := props.get_node_or_null("DioramaDressing")
	if dressing == null:
		return null
	var torch: Node3D = null
	for child in dressing.get_children():
		var node := child as Node3D
		if node == null:
			continue
		if node.name.contains("Brazier"):
			return node.position
		if torch == null and node.name.contains("Torch"):
			torch = node
	if torch != null:
		return torch.position
	return null


func reveal_secret(secret_room_id: String, set_flag: bool = true) -> void:
	var secret_room := get_room(secret_room_id)
	if secret_room == null:
		return
	if set_flag:
		WorldState.set_flag(WorldFlags.secret_opened(secret_room_id), true)
		# A run-level counter for the results screen. Only on a genuine new reveal -- not
		# when a floor reload replays an already-opened secret from its persisted flag (that call
		# passes `set_flag = false`), which would otherwise recount the same secret every load.
		var found := int(WorldState.get_flag(WorldFlags.secrets_found_this_floor(), 0))
		WorldState.set_flag(WorldFlags.secrets_found_this_floor(), found + 1)
		# The reveal framing -- same gate as the counter above, a genuine new find only.
		if _player:
			var camera := _player.get_node_or_null("CameraPivot/SpringArm3D")
			if camera and camera.has_method("play_reveal_framing"):
				camera.call("play_reveal_framing", secret_room.global_position)
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
				_secret_refresh_rooms[from_id] = true
				_secret_refresh_rooms[to_id] = true
				secret_edge_revealed.emit(from_id, to_id)
	_queue_secret_topology_refresh()
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


func _queue_secret_topology_refresh() -> void:
	if _secret_topology_refresh_queued:
		return
	_secret_topology_refresh_queued = true
	call_deferred("_refresh_secret_topology")


## Only the two rooms a revealed secret joins changed shape, so only they are rebuilt.
func _refresh_secret_topology() -> void:
	_secret_topology_refresh_queued = false
	for room_id in _secret_refresh_rooms:
		var room := get_room(str(room_id))
		if room == null:
			continue
		var blockout := room.get_blockout()
		if blockout:
			blockout.finalize_geometry()
		if room is CastleRoomScene:
			(room as CastleRoomScene).carve_navigation()
	_secret_refresh_rooms.clear()
	if _nav_links_root:
		_nav_links_root.queue_free()
		_nav_links_root = null
	if _dungeon_root:
		_build_nav_links()


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
		# A secret has no opening either until it is found; `reveal_secret` links it then.
		if kind not in ["door", "corridor", "secret"]:
			continue
		if kind == "secret" and not _is_secret_edge_open(edge):
			continue
		_add_nav_link(edge)


func _is_secret_edge_open(edge: Dictionary) -> bool:
	for room_key in ["from", "to"]:
		if WorldState.has_flag(WorldFlags.secret_opened(str(edge.get(room_key, "")))):
			return true
	return false


func _add_nav_link(edge: Dictionary) -> void:
	var from_room := get_room(str(edge.get("from", "")))
	var to_room := get_room(str(edge.get("to", "")))
	if from_room == null or to_room == null:
		return
	var from_socket := _socket_for_edge(from_room, to_room, edge)
	var to_socket := _socket_for_edge(to_room, from_room, edge)
	if from_socket == null or to_socket == null:
		return
	var link := NavigationLink3D.new()
	link.enabled = true
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
	var nav_result: Dictionary = blockout.sample_random_nav_point(_placement_rng)
	if not bool(nav_result.get("ok", false)):
		return _placement_offset(placement)
	var nav_point: Vector3 = nav_result.get("position", Vector3.ZERO)
	var hint := _placement_offset(placement)
	return nav_point + Vector3(hint.x * 0.15, 0.0, hint.z * 0.15)


func _build_floor_shell() -> void:
	FloorShellBuilderScript.build(_dungeon_root, _rooms, biome_id)


func _finalize_all_blockouts(chunked: bool, my_gen: int) -> bool:
	for room_id in _rooms:
		var room := get_room(room_id)
		if room == null:
			continue
		var blockout := room.get_blockout()
		if blockout:
			blockout.finalize_geometry()
		# The props are all placed by now, so the room's navigation can be cut around them.
		if room is CastleRoomScene:
			(room as CastleRoomScene).carve_navigation()
		if not await _yield_if_over_budget(chunked, my_gen):
			return false
	return true


func _spawn_player() -> void:
	if _player == null:
		return
	var entrance_id: String = definition.get("placements", {}).get("entrance", "entrance")
	var entrance := get_room(entrance_id)
	if entrance:
		Teleport.to(_player, entrance.get_player_spawn_global())
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


## A first build of an enemy model costs 30-50 ms (files read, meshes built); every later one is
## almost free. Paying it here, once per distinct enemy and while the loading screen is up, keeps
## it out of the fight.
func _prewarm_enemy_models(chunked: bool, my_gen: int, placements: Array) -> bool:
	var seen := {}
	var ids: Array[String] = []
	for placement in placements:
		ids.append(str((placement as Dictionary).get("enemyId", "")))
	var boss: Variant = definition.get("placements", {}).get("boss")
	if boss is Dictionary:
		ids.append(str((boss as Dictionary).get("enemyId", "")))
	for enemy_id in ids:
		if enemy_id == "" or seen.has(enemy_id):
			continue
		seen[enemy_id] = true
		var data := EnemyCatalog.get_definition(enemy_id)
		if data.is_empty():
			continue
		var host := Node3D.new()
		add_child(host)
		DioramaCharacterSkin.build_enemy_body(
			host,
			DioramaCharacterSkin.profile_for_enemy_data(data),
			DioramaCharacterSkin.theme_for_enemy_id(enemy_id),
			enemy_id,
			data
		)
		remove_child(host)
		host.free()
		if not await _yield_step(chunked, my_gen):
			return false
	return true


func _place_enemies(chunked: bool, my_gen: int) -> void:
	var placements: Array = definition.get("placements", {}).get("enemies", [])
	if not await _prewarm_enemy_models(chunked, my_gen, placements):
		return
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
	# Set before `add_child()` so `_ready()` (which reads it) sees the trigger already
	# configured, instead of enemy briefly existing idle-and-visible for a frame.
	var trigger := str(placement.get("trigger", "idle"))
	if trigger != "idle" and enemy.has_method("set_spawn_trigger"):
		enemy.call("set_spawn_trigger", trigger, float(placement.get("triggerDelay", 2.0)))
	# Set before `add_child()`, same reason as `trigger` above -- `_ready()` reads this
	# meta to apply the elite's poise, scale, rim and name plate, and add_child() runs `_ready()`
	# synchronously before this function's own statements after it would otherwise get the chance.
	if placement.get("isElite", false):
		enemy.set_meta("is_elite", true)
		enemy.set_meta("elite_affix", str(placement.get("affixId", "")))
	# Encounter ownership is data-derived rather than an incidental RoomTemplate parent instance.
	# The floor seed keeps an otherwise repeated room ID from sharing pressure permits with a
	# different reconstructed floor, while spawned/summoned actors can inherit this exact key.
	var encounter_room_id := str(placement.get("roomId", ""))
	enemy.set_meta(
		"encounter_key", hash("floor:%d:%s" % [int(definition.get("seed", 0)), encounter_room_id])
	)
	enemy.position = _sample_placement_offset(room, placement)
	room.add_child(enemy)
	if enemy is CharacterBody3D:
		CharacterFloorSnapScript.snap_to_floor_below(enemy as CharacterBody3D)
	enemy.set_meta("placement_id", placement_key)
	enemy.set_meta("catalog_id", enemy_id)
	if enemy.has_method("set_player"):
		enemy.call("set_player", _player)
	if placement.get("isMiniboss", false):
		enemy.set_meta("is_miniboss", true)
		_miniboss = enemy
		_miniboss_room_id = str(placement.get("roomId", ""))
	_apply_floor_scaling(enemy)
	if enemy.has_method("capture_spawn_state"):
		enemy.call("capture_spawn_state")
	_ensure_enemy_groups(enemy)
	_enemy_by_id[placement_key] = enemy
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_tracked_enemy_died.bind(placement_key))
	if enemy.has_signal("adds_spawned"):
		enemy.adds_spawned.connect(_on_adds_spawned)


## Called by `castle_run.gd:_notify_room()` on room entry. Enemies not marked `ambush` (or
## already woken) are unaffected -- `wake_ambush()` on an idle enemy does nothing since `_ambush_hidden`
## was never set.
func wake_ambushers(room_id: String) -> void:
	if room_id == "":
		return
	var prefix := "%s:" % room_id
	for placement_key in _enemy_by_id:
		if not str(placement_key).begins_with(prefix):
			continue
		var enemy: Node = _enemy_by_id[placement_key]
		if enemy != null and is_instance_valid(enemy) and enemy.has_method("wake_ambush"):
			enemy.call("wake_ambush")


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
		room.add_child(chest)
		register_chest(chest_key, chest)
		if chunked and (i + 1) % CHUNK_LOOT_PER_FRAME == 0:
			if not await _yield_step(chunked, my_gen):
				return


## Every chest on the floor goes through here, whoever spawned it, so floor snapshots capture and
## restore all of them and none refills after Continue.
func register_chest(chest_id: String, chest: Node) -> void:
	chest.set_meta("chest_id", chest_id)
	if chest.has_signal("opened") and not chest.opened.is_connected(_on_chest_opened):
		chest.opened.connect(_on_chest_opened)
	if chest.has_signal("contents_changed") and not chest.contents_changed.is_connected(_on_chest_opened):
		chest.contents_changed.connect(_on_chest_opened)
	_chest_by_id[chest_id] = chest


func _trap_scene_for_id(trap_id: String) -> PackedScene:
	var scene_path := TrapCatalog.get_scene_path(trap_id)
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("DungeonBuilder: unknown trap id '%s'" % trap_id)
		return null
	return load(scene_path) as PackedScene


func _place_room_content() -> bool:
	var gate_failure := RoomContentSpawnerScript.validate_required_gates(self, definition)
	if not gate_failure.is_empty():
		push_error("DungeonBuilder: required gate placement failed %s" % JSON.stringify(gate_failure))
		return false
	var content_failure := RoomContentSpawnerScript.spawn_all(self, definition)
	if not content_failure.is_empty():
		push_error("DungeonBuilder: required room content placement failed %s" % JSON.stringify(content_failure))
		return false
	RoomContentSpawnerScript.spawn_locks(self, definition)
	RoomContentSpawnerScript.spawn_puzzle_gates(self, definition)
	RoomContentSpawnerScript.spawn_shortcut_gates(self, definition)
	RoomContentSpawnerScript.spawn_arena_gates(self, definition)
	return true


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
		trap.set_meta("trap_damage_mult", _trap_damage_multiplier())
		room.add_child(trap)


func _trap_damage_multiplier() -> float:
	var mode := RunFlow.get_run_mode()
	if mode != "endless" and mode != "castle":
		return 1.0
	var profile := DifficultyProfileScript.for_run(
		mode, RunFlow.current_dungeon_id, RunFlow.get_difficulty_tier()
	)
	return profile.damage_multiplier(RunFlow.get_current_floor())


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
	var boss_variant: Dictionary = boss_placement.get("variant", {}) as Dictionary
	if not boss_variant.is_empty():
		_boss.set_meta("boss_variant_id", str(boss_variant.get("id", "")))
		_boss.set_meta("boss_variant_label", str(boss_variant.get("label", "")))
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
	if _boss.has_signal("adds_spawned"):
		_boss.adds_spawned.connect(_on_adds_spawned)
	_apply_floor_scaling(_boss, true)
	if not boss_variant.is_empty() and _boss.has_method("apply_arena_modifier"):
		var modifier: Variant = boss_variant.get("modifier", {})
		if modifier is Dictionary:
			_boss.call("apply_arena_modifier", modifier as Dictionary)
	if _is_final_floor:
		_apply_final_floor_arena_flavor()
	if _boss.has_signal("boss_defeated"):
		_boss.boss_defeated.connect(_on_boss_defeated)
	elif _boss.has_signal("enemy_died"):
		_boss.enemy_died.connect(_on_boss_defeated)
	if _boss.has_method("capture_spawn_state"):
		_boss.call("capture_spawn_state")
	_enemy_by_id["boss"] = _boss


## Every biome's final floor uses the same entrance -> arena -> boss line and, absent a
## bespoke set piece (`final_boss_forgotten_castle.gd` is still the only one), the same reused
## floor-boss fight -- so the boss *pattern* is not what makes a tier's ending distinct. The biome's
## `finalFloor.arenaHazards`/`arenaAdds`/`arenaModifier` are the per-biome twist instead, applied
## once here rather than through the boss's own `phases` (which are per-boss, not per-biome).
func _apply_final_floor_arena_flavor() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var biome := BiomeRegistry.get_biome(biome_id)
	var final_floor: Dictionary = biome.get("finalFloor", {}) as Dictionary
	if final_floor.is_empty():
		return
	for spec in final_floor.get("arenaHazards", []):
		if spec is Dictionary and _boss.has_method("spawn_hazard_ring"):
			_boss.call("spawn_hazard_ring", spec as Dictionary)
	for spec in final_floor.get("arenaAdds", []):
		if spec is Dictionary and _boss.has_method("spawn_adds"):
			_boss.call("spawn_adds", spec as Dictionary)
	var modifier: Variant = final_floor.get("arenaModifier", null)
	if modifier is Dictionary and not (modifier as Dictionary).is_empty():
		if _boss.has_method("apply_arena_modifier"):
			_boss.call("apply_arena_modifier", modifier as Dictionary)


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
		"rotationY": RunFloorConfig.stairs_spawn_facing_y(room, _entry_socket(room)),
	}


## False when the boss room cannot be given its gate, which makes the whole floor unwinnable.
func _setup_boss_door(castle_run: Node3D) -> bool:
	var boss_placement: Variant = definition.get("placements", {}).get("boss")
	if boss_placement == null or not boss_placement is Dictionary:
		return true
	var exit_room_id: String = definition.get("placements", {}).get("exit", "boss")
	var room := get_room(exit_room_id)
	if room == null:
		return false
	var door := BOSS_ROOM_DOOR_SCENE.instantiate() as Node3D
	door.name = "BossRoomDoor"
	var requirement := DungeonCatalog.get_boss_door_requirement(RunFlow.current_dungeon_id)
	var locks: Array = definition.get("locks", [])
	if door.has_method("configure"):
		door.call("configure", biome_id, requirement, RunFlow.get_current_floor(), locks)

	var socket := _entry_socket(room)
	if socket == null:
		door.free()
		return false
	door.position = socket.position + socket.get_world_facing() * 0.25
	door.rotation.y = socket.rotation.y

	room.add_child(door)
	_boss_door = door
	if castle_run.has_method("register_boss_door"):
		castle_run.call("register_boss_door", door)
	return true


## The boss and stairs rooms each have exactly one non-secret edge; its socket is the real entrance.
func _entry_edge(room: RoomTemplate) -> Dictionary:
	for edge in definition.get("edges", []):
		if str(edge.get("kind", "door")) in ["secret", "shortcut"]:
			continue
		if str(edge.get("from", "")) == room.room_id or str(edge.get("to", "")) == room.room_id:
			return edge
	return {}


func _entry_socket(room: RoomTemplate) -> DoorwaySocket:
	var edge := _entry_edge(room)
	if edge.is_empty():
		push_error("Boss room %s has no entry edge" % room.room_id)
		return null
	var other_id := str(edge.get("to", "")) if str(edge.get("from", "")) == room.room_id else str(edge.get("from", ""))
	var neighbour := get_room(other_id)
	if neighbour == null:
		push_error("Boss room %s entry edge names missing room %s" % [room.room_id, other_id])
		return null
	return _socket_for_edge(room, neighbour, edge)


func get_boss_door() -> Node3D:
	return _boss_door


func get_tracked_enemy(placement_id: String) -> Node:
	return _enemy_by_id.get(placement_id)


func get_boss_door_outside_spawn() -> Vector3:
	var exit_room := get_room(str(definition.get("placements", {}).get("exit", "boss")))
	if exit_room != null:
		var edge := _entry_edge(exit_room)
		var other_id := str(edge.get("to", "")) if str(edge.get("from", "")) == exit_room.room_id else str(edge.get("from", ""))
		var neighbour := get_room(other_id)
		if neighbour != null:
			var outer_socket := _socket_for_edge(neighbour, exit_room, edge)
			if outer_socket != null:
				return outer_socket.global_position - outer_socket.get_world_facing() * 3.5
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
		if enemy and enemy.has_meta("is_miniboss"):
			continue
		if enemy and is_instance_valid(enemy) and enemy.has_method("apply_state"):
			enemy.call("apply_state", {"alive": true})
	snapshot_dirty.emit()


func capture_loot_states() -> Dictionary:
	var states := {}
	for chest_id in _chest_by_id:
		var chest: Node = _chest_by_id[chest_id]
		if chest and is_instance_valid(chest):
			if chest.has_method("capture_state"):
				states[chest_id] = chest.call("capture_state")
			elif chest.has_method("is_opened"):
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
		if chest and is_instance_valid(chest):
			if chest.has_method("apply_state"):
				chest.call("apply_state", loot_states[chest_id])
			elif chest.has_method("apply_opened_state"):
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


## Scales every batch of adds like the enemies placed on the floor, and counts them toward the
## room's clear.
func _on_adds_spawned(nodes: Array) -> void:
	for node in nodes:
		if not is_instance_valid(node):
			continue
		_apply_floor_scaling(node)
		if node.has_signal("adds_spawned"):
			node.adds_spawned.connect(_on_adds_spawned)
		var room := node.get_parent() as RoomTemplate
		if room == null or not node.has_signal("enemy_died"):
			continue
		var room_id := room.room_id
		if not _room_has_placements(room_id):
			continue
		if not _room_adds.has(room_id):
			_room_adds[room_id] = []
		(_room_adds[room_id] as Array).append(node)
		node.enemy_died.connect(_on_tracked_enemy_died.bind("%s:add" % room_id))


func _room_has_placements(room_id: String) -> bool:
	var prefix := "%s:" % room_id
	for key in _enemy_by_id:
		if str(key).begins_with(prefix):
			return true
	return false


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
	for add in _room_adds.get(room_id, []):
		if not is_instance_valid(add):
			continue
		if add.has_method("is_dead") and bool(add.call("is_dead")):
			continue
		return
	_cleared_rooms[room_id] = true
	# Persisted, not just the signal -- an arena lock-in gate reopens by listening for this
	# flag (see `room_arena_gate_content.gd`), and a save resumed inside an already-cleared arena
	# has to come back open rather than sealed, which a signal alone cannot survive a reload for.
	WorldState.set_flag(WorldFlags.room_cleared(room_id), true)
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
	_room_adds.clear()
	_chest_by_id.clear()
	_boss = null
	_boss_door = null
	_stair_levers.clear()
	_nav_links_root = null
	if _owns_floor_nav_map and _floor_nav_map != RID():
		NavigationServer3D.free_rid(_floor_nav_map)
	_floor_nav_map = RID()
	_owns_floor_nav_map = false
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
	var affix_id := str(enemy.get_meta("elite_affix", "")) if is_elite else ""
	if is_elite and mode == "castle":
		hp_mult *= 1.5 * float(EliteAffixes.definition(affix_id).get("hpMult", 1.0))
	var health := enemy.get_node_or_null("Health") as Health
	if health:
		health.configure(float(health.max_health) * hp_mult)
	if enemy.has_method("set_damage_multiplier"):
		var dmg_mult := profile.damage_multiplier(progress)
		if is_elite and mode == "castle":
			dmg_mult *= 1.25 * float(EliteAffixes.definition(affix_id).get("damageMult", 1.0))
		enemy.call("set_damage_multiplier", dmg_mult)
	if is_boss:
		return
	if enemy.has_method("apply_phase_modifiers"):
		var behaviour := profile.behaviour_modifiers(progress)
		for key in EliteAffixes.behaviour_modifiers(affix_id):
			behaviour[key] = float(behaviour.get(key, 1.0)) * float(EliteAffixes.behaviour_modifiers(affix_id)[key])
		enemy.call("apply_phase_modifiers", behaviour)
