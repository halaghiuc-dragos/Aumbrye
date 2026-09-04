extends Node

## Checks that a generated floor is a place you can actually walk around.
##
## `definition_health` already answers "did the generator produce something the validator accepts".
## This asks the questions a player would notice and the validator does not: is every doorway backed
## by a room on the other side, does every room connect to every other room, and can you get from
## any dead end to any other dead end without passing through a wall.
##
## It also prints the shape of the floors it saw -- branching, dead ends, loops, how much of the
## floor is optional -- because those numbers are what decide whether exploring one is interesting.

const LocalProcgenScript := preload("res://scripts/dungeon/local_procgen.gd")
const RunFloorConfigScript := preload("res://scripts/dungeon/run_floor_config.gd")
const RoomGraphLayoutScript := preload("res://scripts/dungeon/procgen/room_graph_layout.gd")
const CastleRoomConstantsScript := preload("res://scripts/dungeon/castle/castle_room_constants.gd")
const DungeonBuilderScript := preload("res://scripts/dungeon/dungeon_builder.gd")

const BIOMES: Array[String] = [
	"forgotten_castle", "crystal_caverns", "poison_swamp", "frozen_fortress", "dark_cathedral",
	"iron_vault", "prism_depths", "venom_mire", "glacial_hollow", "umbral_chapel",
]

## Edge kinds you can walk through as the floor is handed to the builder. A secret is a wall until
## the player opens it, and a shortcut whose rooms do not touch is closed by the builder, so neither
## may be relied on to keep the floor connected.
const TRAVERSABLE_KINDS: Array[String] = ["door", "corridor"]

const EPSILON := 0.01

var _failures: Array[String] = []
var _checked := 0
var _metrics: Dictionary = {}
var _holes_by_biome: Dictionary = {}
var _cliffs_by_biome: Dictionary = {}


func _ready() -> void:
	var seeds := 8
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--seeds="):
			seeds = maxi(1, int(str(arg).substr("--seeds=".length())))
	for biome_id in BIOMES:
		for s in seeds:
			var base_seed := 1 + s * 7919 + biome_id.hash()
			for floor_index in range(1, RunFloorConfigScript.MAX_FLOORS + 1):
				var result: Dictionary = LocalProcgenScript.generate(
					biome_id, base_seed, floor_index, "castle", 1, 1, false, false, true
				)
				var label := "%s seed=%d floor=%d" % [biome_id, base_seed, floor_index]
				if not result.get("ok", false):
					_fail("%s: generation failed (%s)" % [label, str(result.get("error", "?"))])
					continue
				await _audit_floor(label, result.get("definition", {}), biome_id)
	_report()


func _audit_floor(label: String, definition: Dictionary, biome_id: String) -> void:
	_checked += 1
	var rooms_by_id := {}
	for room in definition.get("rooms", []):
		var room_id := str(room.get("id", ""))
		if room_id == "":
			_fail("%s: a room has no id" % label)
			continue
		if rooms_by_id.has(room_id):
			_fail("%s: duplicate room id '%s'" % [label, room_id])
			continue
		rooms_by_id[room_id] = room
	if rooms_by_id.is_empty():
		_fail("%s: floor has no rooms" % label)
		return
	var edges: Array = definition.get("edges", [])
	_check_edges_resolve(label, rooms_by_id, edges)
	_check_doorways_are_backed(label, rooms_by_id, edges)
	var secret_ids := _secret_room_ids(rooms_by_id)
	var adjacency := _traversable_adjacency(rooms_by_id, edges)
	_check_all_rooms_connected(label, rooms_by_id, secret_ids, adjacency)
	_check_leaf_to_leaf(label, rooms_by_id, secret_ids, adjacency)
	_check_landmarks(label, definition, adjacency)
	_check_secrets_are_attached(label, rooms_by_id, secret_ids, edges, adjacency)
	_collect_metrics(rooms_by_id, adjacency, edges)
	_collect_lock_metrics(definition, rooms_by_id, adjacency)
	_check_soft_lock(label, definition)
	await _check_geometry(label, definition, biome_id)


## RM-06 item 4: the generator's own gate (`RoomContentValidator`) already rejects a floor that
## fails this before it ships, so a real failure here should never happen -- this exists to prove
## that promise per seed rather than trust it, the same way the rest of this audit re-derives
## things the generator already checked once.
func _check_soft_lock(label: String, definition: Dictionary) -> void:
	var check := RoomContentValidator.validate_definition(definition)
	if not check.get("ok", true):
		_fail("%s: soft-lock -- %s" % [label, str(check.get("reason", "?"))])


## Every edge must name two rooms that exist, and must not loop a room back to itself.
func _check_edges_resolve(label: String, rooms_by_id: Dictionary, edges: Array) -> void:
	for edge in edges:
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if from_id == to_id:
			_fail("%s: edge joins '%s' to itself" % [label, from_id])
			continue
		if not rooms_by_id.has(from_id):
			_fail("%s: edge references missing room '%s'" % [label, from_id])
		if not rooms_by_id.has(to_id):
			_fail("%s: edge references missing room '%s'" % [label, to_id])


## No doorway may open onto nothing.
##
## For every traversable edge the two rooms must share a wall: flush on the axis they meet along,
## overlapping by at least a door's width across it, with the doorway inside both rooms' spans.
## A door that fails any of those is a hole in a wall with rock behind it.
func _check_doorways_are_backed(
	label: String, rooms_by_id: Dictionary, edges: Array
) -> void:
	var door_width: float = CastleRoomConstantsScript.DOOR_WIDTH
	for edge in edges:
		if not TRAVERSABLE_KINDS.has(str(edge.get("kind", ""))):
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if not rooms_by_id.has(from_id) or not rooms_by_id.has(to_id):
			continue
		var a: Dictionary = rooms_by_id[from_id]
		var b: Dictionary = rooms_by_id[to_id]
		var a_rect := _room_rect(a)
		var b_rect := _room_rect(b)
		# The tier-final arena is authored by hand and its edges carry no wall, so work out which
		# side the two rooms meet on. An edge whose rooms touch on no side fails the flush check
		# below, which is the thing actually worth knowing.
		var dir := str(edge.get("dir", ""))
		if dir == "":
			dir = _infer_wall(a_rect, b_rect)
		if dir == "":
			_fail(
				"%s: %s->%s rooms do not touch on any side, so the doorway backs onto nothing"
				% [label, from_id, to_id]
			)
			continue
		var vertical := dir == "north" or dir == "south"
		# Flush check: the rooms must actually touch along the wall the edge names.
		var a_face := a_rect.position.y if dir == "north" else a_rect.end.y
		var b_face := b_rect.end.y if dir == "north" else b_rect.position.y
		if not vertical:
			a_face = a_rect.position.x if dir == "west" else a_rect.end.x
			b_face = b_rect.end.x if dir == "west" else b_rect.position.x
		if absf(a_face - b_face) > EPSILON:
			_fail(
				"%s: %s->%s (%s) rooms are %.2f apart, so the doorway backs onto nothing"
				% [label, from_id, to_id, dir, absf(a_face - b_face)]
			)
			continue
		# Overlap check: a shared face is not enough, they must share enough of it for a door.
		var lo := maxf(a_rect.position.x, b_rect.position.x) if vertical else maxf(
			a_rect.position.y, b_rect.position.y
		)
		var hi := minf(a_rect.end.x, b_rect.end.x) if vertical else minf(
			a_rect.end.y, b_rect.end.y
		)
		if hi - lo < door_width - EPSILON:
			_fail(
				"%s: %s->%s (%s) share only %.2f of wall, less than a %.2f door"
				% [label, from_id, to_id, dir, hi - lo, door_width]
			)
			continue
		# The doorway itself must sit inside the shared stretch, or the opening gets clamped off
		# the end of the wall and the two rooms end up with openings that do not line up.
		var door: Dictionary = edge.get("door", {})
		var along := (lo + hi) * 0.5
		if not door.is_empty():
			along = float(door.get("x", 0.0)) if vertical else float(door.get("z", 0.0))
		if along < lo - EPSILON or along > hi + EPSILON:
			_fail(
				"%s: %s->%s (%s) doorway at %.2f is outside the shared wall %.2f..%.2f"
				% [label, from_id, to_id, dir, along, lo, hi]
			)


## Every room reachable from every other, walking only through doors that exist.
func _check_all_rooms_connected(
	label: String, rooms_by_id: Dictionary, secret_ids: Dictionary, adjacency: Dictionary
) -> void:
	var start := ""
	for room_id in rooms_by_id:
		if not secret_ids.has(room_id):
			start = str(room_id)
			break
	var seen := _flood(start, adjacency)
	var expected := rooms_by_id.size() - secret_ids.size()
	if seen.size() == expected:
		return
	var stranded: Array[String] = []
	for room_id in rooms_by_id:
		if not seen.has(room_id) and not secret_ids.has(room_id):
			stranded.append(str(room_id))
	if stranded.is_empty():
		return
	stranded.sort()
	_fail(
		"%s: %d of %d rooms are cut off (%s)"
		% [
			label,
			stranded.size(),
			expected,
			", ".join(stranded.slice(0, 4)),
		]
	)


## You can walk from any dead end to any other dead end.
##
## This follows from the floor being one connected component, but it is the property a player
## actually experiences, so it is asserted directly rather than inferred.
func _check_leaf_to_leaf(
	label: String, rooms_by_id: Dictionary, secret_ids: Dictionary, adjacency: Dictionary
) -> void:
	var leaves: Array[String] = []
	for room_id in rooms_by_id:
		if secret_ids.has(room_id):
			continue
		if adjacency.get(room_id, []).size() <= 1:
			leaves.append(str(room_id))
	leaves.sort()
	if leaves.size() < 2:
		return
	var reachable := _flood(leaves[0], adjacency)
	for i in range(1, leaves.size()):
		if not reachable.has(leaves[i]):
			_fail(
				"%s: dead end '%s' cannot be walked to from dead end '%s'"
				% [label, leaves[i], leaves[0]]
			)
			return


## The rooms a floor cannot be played without must exist and be walkable to.
func _check_landmarks(label: String, definition: Dictionary, adjacency: Dictionary) -> void:
	var entrance_id := _room_id_of_type(definition, "entrance")
	if entrance_id == "":
		_fail("%s: no entrance room" % label)
		return
	var reachable := _flood(entrance_id, adjacency)
	var boss_id := _room_id_of_type(definition, "boss")
	if boss_id == "":
		_fail("%s: no boss room" % label)
	elif not reachable.has(boss_id):
		_fail("%s: boss room '%s' cannot be reached from the entrance" % [label, boss_id])
	var stairs_id := ""
	for room in definition.get("rooms", []):
		if RunFloorConfigScript.is_stairs_room(room):
			stairs_id = str(room.get("id", ""))
			break
	# The final floor of a tier is a boss arena and has no stairs by design, so its absence is only
	# a failure when the floor has one and it cannot be walked to.
	if stairs_id != "" and not reachable.has(stairs_id):
		_fail("%s: stairs room '%s' cannot be reached from the entrance" % [label, stairs_id])


## A secret is a wall until it is found, so it is not expected to be walkable to. What it must have
## is a secret edge onto a room that *is* walkable to, or opening it would reveal a sealed pocket.
func _check_secrets_are_attached(
	label: String,
	rooms_by_id: Dictionary,
	secret_ids: Dictionary,
	edges: Array,
	adjacency: Dictionary
) -> void:
	if secret_ids.is_empty():
		return
	var start := ""
	for room_id in rooms_by_id:
		if not secret_ids.has(room_id):
			start = str(room_id)
			break
	var walkable := _flood(start, adjacency)
	var hosts := {}
	for edge in edges:
		if str(edge.get("kind", "")) != "secret":
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		var secret_id := to_id if secret_ids.has(to_id) else from_id
		var host_id := from_id if secret_id == to_id else to_id
		if not hosts.has(secret_id):
			hosts[secret_id] = []
		hosts[secret_id].append(host_id)
	for secret_id in secret_ids:
		var attached: Array = hosts.get(secret_id, [])
		if attached.is_empty():
			_fail("%s: secret room '%s' has no way in at all" % [label, secret_id])
			continue
		var reachable_host := false
		for host_id in attached:
			if walkable.has(host_id):
				reachable_host = true
				break
		if not reachable_host:
			_fail(
				"%s: secret room '%s' opens only onto rooms you cannot reach"
				% [label, secret_id]
			)


static func _secret_room_ids(rooms_by_id: Dictionary) -> Dictionary:
	var out := {}
	for room_id in rooms_by_id:
		var room: Dictionary = rooms_by_id[room_id]
		if str(room.get("type", "")) == "secret":
			out[room_id] = true
	return out


func _collect_metrics(
	rooms_by_id: Dictionary, adjacency: Dictionary, edges: Array
) -> void:
	var degree_total := 0
	var dead_ends := 0
	var junctions := 0
	for room_id in rooms_by_id:
		var degree: int = adjacency.get(room_id, []).size()
		degree_total += degree
		if degree <= 1:
			dead_ends += 1
		if degree >= 3:
			junctions += 1
	var traversable := 0
	var shortcuts := 0
	var secrets := 0
	for edge in edges:
		var kind := str(edge.get("kind", ""))
		if TRAVERSABLE_KINDS.has(kind):
			traversable += 1
		elif kind == "shortcut":
			shortcuts += 1
		elif kind == "secret":
			secrets += 1
	# Edges beyond a spanning tree are the loops -- the routes that let a floor fold back on itself.
	var loops := traversable - (rooms_by_id.size() - 1)
	_bump("rooms", rooms_by_id.size())
	_bump("dead_ends", dead_ends)
	_bump("junctions", junctions)
	_bump("loops", maxi(0, loops))
	_bump("shortcuts", shortcuts)
	_bump("secrets", secrets)
	_bump("degree_total", degree_total)


## How much of the floor sits behind a locked door.
##
## This is the pacing number: with no locks on the way to the boss a player can walk the critical
## path start to finish, so a floor is only as long as the route. Every lock on that route is a
## detour to find its key first.
func _collect_lock_metrics(
	definition: Dictionary, rooms_by_id: Dictionary, adjacency: Dictionary
) -> void:
	var locks: Array = definition.get("locks", [])
	_bump("locks", locks.size())
	if locks.is_empty():
		_bump("floors_without_locks", 1)
	var boss_id := _room_id_of_type(definition, "boss")
	var entrance_id := _room_id_of_type(definition, "entrance")
	if boss_id == "" or entrance_id == "":
		return
	# Walk from the entrance refusing to pass any locked door. Anything still reachable is what a
	# player could rush to without finding a single key.
	var blocked := {}
	for lock in locks:
		blocked[str(lock.get("to", ""))] = true
	var seen := {entrance_id: true}
	var queue: Array[String] = [entrance_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_id in adjacency.get(current, []):
			if seen.has(next_id) or blocked.has(next_id):
				continue
			seen[next_id] = true
			queue.append(next_id)
	if seen.has(boss_id):
		_bump("floors_boss_unlocked", 1)
	_bump("rooms_before_any_key", seen.size())
	_bump("rooms_total_for_gate", rooms_by_id.size())


func _bump(key: String, amount: int) -> void:
	_metrics[key] = int(_metrics.get(key, 0)) + amount


func _traversable_adjacency(rooms_by_id: Dictionary, edges: Array) -> Dictionary:
	var adjacency := {}
	for room_id in rooms_by_id:
		adjacency[room_id] = []
	for edge in edges:
		if not TRAVERSABLE_KINDS.has(str(edge.get("kind", ""))):
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if not adjacency.has(from_id) or not adjacency.has(to_id):
			continue
		adjacency[from_id].append(to_id)
		adjacency[to_id].append(from_id)
	return adjacency


func _flood(start: String, adjacency: Dictionary) -> Dictionary:
	var seen := {}
	if start == "" or not adjacency.has(start):
		return seen
	seen[start] = true
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_id in adjacency.get(current, []):
			if seen.has(next_id):
				continue
			seen[next_id] = true
			queue.append(next_id)
	return seen


func _room_id_of_type(definition: Dictionary, room_type: String) -> String:
	for room in definition.get("rooms", []):
		if str(room.get("type", "")) == room_type or str(room.get("id", "")) == room_type:
			return str(room.get("id", ""))
	return ""


## Which side of `a` the rectangle `b` sits flush against, or "" if they do not touch.
static func _infer_wall(a: Rect2, b: Rect2) -> String:
	var x_overlap := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var z_overlap := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	if x_overlap > EPSILON:
		if absf(a.position.y - b.end.y) <= EPSILON:
			return "north"
		if absf(a.end.y - b.position.y) <= EPSILON:
			return "south"
	if z_overlap > EPSILON:
		if absf(a.position.x - b.end.x) <= EPSILON:
			return "west"
		if absf(a.end.x - b.position.x) <= EPSILON:
			return "east"
	return ""


## A room's footprint in world space, as a Rect2 on the xz plane.
func _room_rect(room: Dictionary) -> Rect2:
	var transform: Dictionary = room.get("transform", {})
	var size: Dictionary = room.get("size", {})
	var w := float(size.get("x", 0.0))
	var d := float(size.get("z", 0.0))
	var cx := float(transform.get("x", 0.0))
	var cz := float(transform.get("z", 0.0))
	return Rect2(cx - w * 0.5, cz - d * 0.5, w, d)


## Builds the floor for real and casts rays into it -- the check that would have caught the
## reported fall-through bug before it was reported. `_check_doorways_are_backed()` above reasons
## about the room definitions; a hole from a height change, a pruned room or a mis-seated secret
## only exists in the geometry the builder actually produces.
func _check_geometry(label: String, definition: Dictionary, biome_id: String) -> void:
	var parent := Node3D.new()
	add_child(parent)
	var builder := DungeonBuilderScript.new()
	parent.add_child(builder)
	await builder.build_from_definition(parent, null, definition, false)
	# The physics server registers newly created collision shapes asynchronously -- a ray cast
	# fired the instant the build finishes can miss rooms built late in the instancing loop, which
	# reads exactly like a missing floor. One synced physics frame is enough for every shape built
	# this frame to be queryable.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var holes := 0
	for room_id in builder.get_room_ids():
		var room := builder.get_room(room_id)
		if room == null:
			continue
		if is_nan(_probe_floor_y(space, room.global_position + Vector3(0.0, 2.0, 0.0))):
			_fail("%s: room '%s' centre has no floor beneath it" % [label, room_id])
			holes += 1
		for socket in room.get_sockets():
			var inward := -socket.get_world_facing()
			var probe_pos := socket.global_position + inward * 1.0 + Vector3(0.0, 2.0, 0.0)
			if is_nan(_probe_floor_y(space, probe_pos)):
				_fail(
					"%s: room '%s' doorway %s has no floor 1m inside it"
					% [label, room_id, socket.get_socket_name()]
				)
				holes += 1
	var cliffs := _check_doorway_continuity(label, builder, definition, space)
	_holes_by_biome[biome_id] = int(_holes_by_biome.get(biome_id, 0)) + holes
	_cliffs_by_biome[biome_id] = int(_cliffs_by_biome.get(biome_id, 0)) + cliffs
	parent.queue_free()


## For every non-secret edge, several points across the threshold must each find floor close to
## the height a monotonic staircase would put it at. A height change must read as a climb, not a
## drop -- sampled from the *lower* room's own socket, facing toward the higher one, because that
## is the room `_build_height_transitions()` actually builds the flight in; querying the higher
## room's socket instead samples across an unrelated stretch of wall and reads as nonsense.
func _check_doorway_continuity(
	label: String, builder: DungeonBuilder, definition: Dictionary, space: PhysicsDirectSpaceState3D
) -> int:
	var cliffs := 0
	for edge in definition.get("edges", []):
		var kind := str(edge.get("kind", "door"))
		if kind in ["secret", "shortcut"]:
			continue
		# RM-04: a "down" one-way edge omits its ramp on purpose (see
		# `dungeon_builder.gd:_build_height_transitions()`) -- the doorway is meant to drop, so the
		# jump-detection below would flag exactly the geometry the feature is supposed to build.
		if str(edge.get("oneWay", "")) == "down":
			continue
		var from_room := builder.get_room(str(edge.get("from", "")))
		var to_room := builder.get_room(str(edge.get("to", "")))
		if from_room == null or to_room == null:
			continue
		var from_y := from_room.position.y
		var to_y := to_room.position.y
		var lower_room := from_room if from_y <= to_y else to_room
		var higher_room := to_room if from_y <= to_y else from_room
		var socket := builder.door_socket_between(lower_room, higher_room)
		if socket == null:
			continue
		var facing := socket.get_world_facing()
		var origin := socket.global_position
		var is_height_change := absf(from_y - to_y) > 0.01
		var expected_lo := minf(from_y, to_y) - 0.5
		var expected_hi := maxf(from_y, to_y) + CastleRoomConstantsScript.WALL_HEIGHT + 0.5
		var samples := 9
		var prev_y := NAN
		for i in range(samples):
			# The +0.13 keeps every sample off a tread seam: treads tile on a 0.8m pitch from the
			# wall, and a ray fired exactly at a shared edge between two boxes can miss both and
			# fall through to whatever is underneath, which reads as a hole that is not there.
			var t := (float(i) - float(samples - 1) * 0.5) * 0.5 + 0.13
			var probe_pos := origin + facing * t + Vector3(0.0, 3.0, 0.0)
			var hit_y := _probe_floor_y(space, probe_pos, 8.0)
			if is_nan(hit_y):
				_fail(
					"%s: doorway %s->%s has a gap %.1fm from the threshold"
					% [label, lower_room.room_id, higher_room.room_id, t]
				)
				cliffs += 1
				continue
			if hit_y < expected_lo or hit_y > expected_hi:
				_fail(
					"%s: doorway %s->%s floor at %.2f is outside expected range %.2f..%.2f"
					% [label, lower_room.room_id, higher_room.room_id, hit_y, expected_lo, expected_hi]
				)
				cliffs += 1
			# Only a genuine height-transition doorway is expected to climb monotonically -- a
			# flat doorway can legitimately have a raised prop or cover obstacle near it (a crate,
			# a torch stand) without that being a floor defect, so the jump test would just be
			# flagging level-design content, not a hole.
			elif is_height_change and not is_nan(prev_y) and absf(hit_y - prev_y) > 1.5:
				_fail(
					(
						"%s: doorway %s->%s floor jumps %.2f between samples 0.5m apart --"
						+ " a cliff, not a staircase"
					)
					% [label, lower_room.room_id, higher_room.room_id, absf(hit_y - prev_y)]
				)
				cliffs += 1
			prev_y = hit_y
	return cliffs


func _probe_floor_y(
	space: PhysicsDirectSpaceState3D, from: Vector3, max_drop: float = 6.0
) -> float:
	if space == null:
		return NAN
	var params := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -max_drop, 0.0))
	params.collision_mask = 1
	params.collide_with_areas = false
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return NAN
	var hit_pos: Vector3 = hit.get("position", from)
	return hit_pos.y


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _checked > 0:
		var floors := float(_checked)
		print(
			(
				"FLOOR SHAPE  rooms %.1f  dead ends %.1f  junctions %.1f  loops %.1f  "
				+ "shortcuts %.1f  secrets %.1f  mean exits/room %.2f"
			)
			% [
				_metrics.get("rooms", 0) / floors,
				_metrics.get("dead_ends", 0) / floors,
				_metrics.get("junctions", 0) / floors,
				_metrics.get("loops", 0) / floors,
				_metrics.get("shortcuts", 0) / floors,
				_metrics.get("secrets", 0) / floors,
				float(_metrics.get("degree_total", 0)) / maxf(1.0, _metrics.get("rooms", 1)),
			]
		)
	if _checked > 0:
		var floors2 := float(_checked)
		print(
			(
				"FLOOR GATING  locks %.2f/floor  floors with no lock %.1f%%  "
				+ "boss reachable with no key %.1f%%  reachable before any key %.0f%% of rooms"
			)
			% [
				_metrics.get("locks", 0) / floors2,
				100.0 * _metrics.get("floors_without_locks", 0) / floors2,
				100.0 * _metrics.get("floors_boss_unlocked", 0) / floors2,
				(
					100.0
					* float(_metrics.get("rooms_before_any_key", 0))
					/ maxf(1.0, float(_metrics.get("rooms_total_for_gate", 1)))
				),
			]
		)
	var total_holes := 0
	var total_cliffs := 0
	for biome_id in BIOMES:
		var holes := int(_holes_by_biome.get(biome_id, 0))
		var cliffs := int(_cliffs_by_biome.get(biome_id, 0))
		total_holes += holes
		total_cliffs += cliffs
		print("GEOMETRY %s: %d holes, %d cliffs" % [biome_id, holes, cliffs])
	print("GEOMETRY TOTAL: %d holes, %d cliffs" % [total_holes, total_cliffs])
	var shown := 0
	for failure in _failures:
		print("  " + failure)
		shown += 1
		if shown >= 30:
			print("  ... and %d more" % (_failures.size() - shown))
			break
	print("CONNECTIVITY RESULT %d failures across %d floors" % [_failures.size(), _checked])
	get_tree().quit(0 if _failures.is_empty() else 1)
