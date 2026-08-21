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
const DifficultyProfileScript := preload("res://scripts/dungeon/difficulty_profile.gd")
const FloorShellBuilderScript := preload("res://scripts/dungeon/floor_shell_builder.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")
const RoomContentSpawnerScript := preload(
	"res://scripts/dungeon/room_content/room_content_spawner.gd"
)

signal build_complete
signal boss_defeated
signal snapshot_dirty
## PERF-03: emitted between build steps when building chunked, so a loading-screen host can show
## progress. `ratio` is in [0, 1]; the final emission with ratio 1.0 fires immediately before
## `build_complete`.
signal build_progress(ratio: float)
signal room_cleared(room_id: String)

## Rooms/enemies are instantiated in small batches even within a single "step" so a floor with
## many rooms or a crowded encounter cannot itself blow the per-frame budget below.
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

## Monotonic build id. A chunked build suspends across ~23 `await`s; if the player dies or exits to
## hub in between, the scene swap frees this builder's nodes and the resumed coroutine would run
## against freed instances — the classic intermittent "previously freed instance" crash. Every
## build captures this value on entry and bails the moment it no longer matches.
var _build_generation := 0


func _exit_tree() -> void:
	cancel()
	# C-86: `unload_from_parent()` frees the floor's navigation map correctly — and had no gameplay
	# caller anywhere in the repository. `CastleRun` creates the builder and never unloads it; floor
	# transitions replace the scene, so the builder is freed and only `cancel()` ran. Every floor
	# build therefore created a NavigationServer3D map, set it **active**, and never freed it — so a
	# ten-floor castle run leaked ten and an Umbral Endless run leaked one per floor without bound,
	# each still being stepped every frame alongside the live one.
	unload_from_parent(get_parent() as Node3D)


## Invalidates any build currently suspended mid-await. Safe to call at any time.
func cancel() -> void:
	_build_generation += 1


## Yields between build steps and reports whether the build is still allowed to continue.
##
## Returns false when the build was cancelled, the builder left the tree, or the tree itself is
## gone — every caller must treat that as "stop immediately and touch nothing".
func _yield_step(chunked: bool, my_gen: int) -> bool:
	if chunked:
		var tree := get_tree()
		if tree == null:
			return false
		await tree.process_frame
	return my_gen == _build_generation and is_inside_tree()


## Sole owner of the in-run floor definition cache (REF-11: previously duplicated in
## RunFlow.floor_definitions with a separate, disagreeing eviction policy).
## BUG-30: bounded to MAX_CACHED_FLOORS with distance-from-current eviction — this is a *static*
## cache with no per-run eviction of its own (only clear_floor_cache(), called at run start/end),
## so an endless run used to hold every floor definition it had ever generated in memory for as
## long as the run lasted.
const MAX_CACHED_FLOORS := 8

static var _floor_definition_cache: Dictionary = {}

## Identity of the run the cached floors belong to.
##
## The cache is static, so a run abandoned by a crash used to leave its definitions sitting there
## until clear_floor_cache() happened to be called — and two runs that share floor indices (seeded
## and challenge runs in particular) would then read each other's floors. Stamping the owning run
## makes a stale hit impossible rather than merely unlikely.
static var _cache_run_key := ""

## Floor the player is actually on, for farthest-first eviction. -1 means "not set for this run",
## in which case eviction measures distance from whichever floor is being stored — the right
## default for callers that only ever cache the floor they are on.
static var _cache_reference_floor := -1


## Binds the cache to a run, discarding anything left over from a previous one.
## `run_key` should identify the run uniquely, e.g. "%s:%d:%s" % [run_mode, seed, run_id].
static func begin_run_cache(run_key: String) -> void:
	if run_key != _cache_run_key:
		_floor_definition_cache.clear()
	_cache_run_key = run_key
	_cache_reference_floor = -1


## Tells the cache which floor to measure eviction distance from.
static func set_reference_floor(floor_index: int) -> void:
	_cache_reference_floor = floor_index


static func store_floor_cache(floor_index: int, floor_definition: Dictionary) -> void:
	if floor_definition.is_empty():
		return
	_floor_definition_cache[str(floor_index)] = floor_definition.duplicate(true)
	_trim_floor_cache(_cache_reference_floor if _cache_reference_floor > 0 else floor_index)


static func get_floor_cache(floor_index: int) -> Dictionary:
	var cached: Variant = _floor_definition_cache.get(str(floor_index), {})
	return cached.duplicate(true) if cached is Dictionary else {}


static func erase_floor_cache(floor_index: int) -> void:
	_floor_definition_cache.erase(str(floor_index))


static func clear_floor_cache() -> void:
	_floor_definition_cache.clear()
	_cache_run_key = ""
	_cache_reference_floor = -1


static func _trim_floor_cache(reference_floor: int) -> void:
	if _floor_definition_cache.size() <= MAX_CACHED_FLOORS:
		return
	var keys: Array[int] = []
	for key in _floor_definition_cache:
		keys.append(int(key))
	keys.sort_custom(
		func(a: int, b: int) -> bool: return absi(a - reference_floor) > absi(b - reference_floor)
	)
	while _floor_definition_cache.size() > MAX_CACHED_FLOORS:
		_floor_definition_cache.erase(str(keys.pop_front()))


## `chunked=false` (the default) builds synchronously in one call, exactly as before — every
## validation-suite fixture and any other caller that does not pass `chunked=true` sees no
## behavioural change at all, since none of the `await`s below are ever reached.
## `chunked=true` (used by the real gameplay path, see RunFlow._transition_floor /
## CastleRun._ready) yields to the scheduler between build steps — and, within the two heaviest
## steps, every few rooms/enemies — so a floor build never blocks a single frame for its full
## duration. Callers must `await` this when passing `chunked=true`.
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
	# Supersede any build already in flight, and remember our own id so every resumption below can
	# tell whether it is still the current one.
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
	# 21 progress-reporting steps; kept as a flat list (rather than dividing by an exact count)
	# so adding/removing a step later cannot desync the ratio math.
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

	_wire_shortcut_edges()
	step += 1.0
	build_progress.emit(step / TOTAL_STEPS)
	if not await _yield_step(chunked, my_gen):
		return

	_build_doorway_bridges()
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
	# C-176: the shadow-casting omni budget is a floor budget, and was being reset per room — so a
	# 28-room floor spent `max_shadow_omnis` (default 2) twenty-eight times over.
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
		# C-151: the authored tags, onto the node and into groups.
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
		# Template, not kind: this is about geometry. Any room built from the stairs scene has steps
		# in it and needs stair collision, whatever role the generator gave the room.
		if str(room_def.get("templateId", "")).ends_with("_stairs"):
			STAIR_COLLISION.ensure_stair_collision(instance)
		if chunked and (i + 1) % CHUNK_ROOMS_PER_FRAME == 0:
			if not await _yield_step(chunked, my_gen):
				return false
	return true


func _setup_floor_nav_map() -> void:
	# C-86: `build_from_source()` can run more than once on the same builder, and each call used to
	# assign a fresh RID over the old one without freeing it.
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


## Inverse of `_open_blockout_door_toward`, for a shortcut whose two rooms did not end up flush.
func _close_blockout_door_toward(from_room: RoomTemplate, to_room: RoomTemplate) -> void:
	var blockout := from_room.get_blockout()
	if blockout == null:
		return
	var socket := from_room.socket_toward(to_room)
	if socket == null:
		return
	match socket.direction:
		CastleRoomConstants.Direction.NORTH:
			blockout.door_north = false
		CastleRoomConstants.Direction.EAST:
			blockout.door_east = false
		CastleRoomConstants.Direction.SOUTH:
			blockout.door_south = false
		CastleRoomConstants.Direction.WEST:
			blockout.door_west = false


func _build_doorway_bridges() -> void:
	var closed_shortcuts: PackedStringArray = []
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
			# C-210: a doorway carved between two rooms whose sockets do not meet opens into a
			# hole. Close it rather than build it.
			#
			# For a `shortcut` this is expected, not a fault. Rooms are positioned by a
			# breadth-first walk out from the entrance, so only the edges that walk *used* are
			# guaranteed to touch; a shortcut joins two grid-adjacent cells reached along different
			# branches, and once room sizes vary their world positions have no reason to line up.
			# Measured on the committed fixture: every `door`, `corridor` and `secret` edge touches
			# exactly, and every `shortcut` misses — by 8.0, 17.2 and 19.8 units, which are not
			# footprint mismatches but rooms that are simply nowhere near each other.
			#
			# Closing them is correct under this layout. Opening them needs the constraint-solving
			# positioning rewrite tracked as C-157, and until that lands a per-edge warning reports
			# expected behaviour as a defect on every floor. One summary line at the end instead.
			if kind == "shortcut":
				_close_blockout_door_toward(from_room, to_room)
				_close_blockout_door_toward(to_room, from_room)
				closed_shortcuts.append(
					"%s->%s (%.1f)" % [edge.get("from", ""), edge.get("to", ""), span]
				)
			else:
				# A tree edge that does not meet *is* a fault: those are load-bearing for
				# connectivity and cannot simply be closed.
				push_error(
					(
						"DungeonBuilder: doorway span %.2f on %s->%s indicates a footprint mismatch"
						% [span, edge.get("from", ""), edge.get("to", "")]
					)
				)

	if not closed_shortcuts.is_empty():
		print_verbose(
			(
				"DungeonBuilder: %d optional shortcut(s) closed because their rooms do not touch "
				+ "— expected under the current tree-walk layout (C-157): %s"
			)
			% [closed_shortcuts.size(), ", ".join(closed_shortcuts)]
		)


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
		# Method, not property — see castle_blockout.set_navigation_map.
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


func get_floor_nav_map() -> RID:
	return _floor_nav_map


func get_dungeon_root() -> Node3D:
	return _dungeon_root


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
	# C-116: this negated the basis z, so a room with more than one candidate socket picked the one
	# on the **opposite** wall — the boss door bridged across the room instead of out of it. The
	# project's forward for a placed node is +basis.z (`CombatFacing`), the same convention the
	# C-41 sweep applied everywhere else; this site is a *room*, not a camera, and was missed by
	# that sweep because it reads `room.` rather than a facing or camera node.
	var approach := CombatFacing.forward_of(room)
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
