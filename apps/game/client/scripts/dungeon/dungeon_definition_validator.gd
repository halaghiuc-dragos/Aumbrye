class_name DungeonDefinitionValidator
extends RefCounted

## Structural invariants for generated DungeonDefinition dictionaries (LPG-02).

## Matches `schemaVersion` in content/schemas/dungeon-definition.v2.json.
const SCHEMA_VERSION := 2

const REQUIRED_KEYS: Array[String] = [
	"runId",
	"seed",
	"biomeId",
	"tier",
	"playerLevelSnapshot",
	"rooms",
	"edges",
	"placements",
	"budgets",
]


static func validate(definition: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	# DungeonProcgen stamps 2 and content/schemas/dungeon-definition.v2.json pins `"const": 2`.
	# This check was left on 1 when the v1 schemas were retired, so every generated floor failed
	# validation here — LocalProcgen.generate() burned all three seed salts and returned
	# {"ok": false, "reason": "schema_version"} for every biome.
	if int(definition.get("schemaVersion", 0)) != SCHEMA_VERSION:
		errors.append("schema_version")

	for key in REQUIRED_KEYS:
		if not definition.has(key):
			errors.append("required_keys")
			break

	var rooms: Array = definition.get("rooms", [])
	var room_ids := {}
	for room in rooms:
		if not room is Dictionary:
			errors.append("room_ids_unique")
			break
		var room_id := str(room.get("id", ""))
		if room_id == "" or room_ids.has(room_id):
			errors.append("room_ids_unique")
			break
		room_ids[room_id] = room

	var biome_id := str(definition.get("biomeId", ""))
	for room in rooms:
		if not room is Dictionary:
			break
		var template_id := str(room.get("templateId", ""))
		if template_id == "" or BiomeRegistry.get_room_scene(biome_id, template_id) == null:
			errors.append("room_template_resolves")
			break

	for edge in definition.get("edges", []):
		if not edge is Dictionary:
			errors.append("edge_endpoints_exist")
			break
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if from_id == "" or to_id == "" or not room_ids.has(from_id) or not room_ids.has(to_id):
			errors.append("edge_endpoints_exist")
			break

	# `placements.entrance` and `placements.exit` are **room id strings**; only `placements.boss`
	# is a dictionary, because it carries an enemy id alongside the room.
	#
	# This check used to require a room with `type == "entrance"` and read the placement as
	# `{"roomId": ...}`. Neither has ever been true of what the generator emits — the entrance room
	# is typed `hub`, and the placement is the bare semantic id — so `entrance_present` failed on
	# every floor of every biome. `LocalProcgen.generate()` burned all three seed salts and
	# returned `procgen_failed`, which `RunFlow` turned into a silent return to the hub: **no
	# castle, endless or waves run has ever started through the live path.** Measured at 8 of 8
	# before the fix and 8 of 8 reaching the run scene after it.
	#
	# It went unseen because everything that exercised a built floor bypassed this function —
	# `export_procgen_fixture` calls `DungeonProcgen.generate` directly, and the world-capture tool
	# injects a committed fixture through a root meta. Same shape as the `schema_version` bug
	# noted above, which is the second time this validator has been out of step with its producer.
	var placements: Dictionary = definition.get("placements", {})
	var entrance_id := str(placements.get("entrance", ""))
	if entrance_id == "" or not room_ids.has(entrance_id):
		errors.append("entrance_present")

	var boss_placement: Variant = placements.get("boss")
	if boss_placement != null:
		var boss_count := 0
		for room in rooms:
			if room is Dictionary and str(room.get("type", "")) == "boss":
				boss_count += 1
		if boss_count != 1:
			errors.append("boss_present")

	# Also a room id string. Read as a dictionary this was always null, so `exit_reachable` — the
	# check that the floor can actually be finished — never ran at all.
	var exit_id := str(placements.get("exit", ""))
	if exit_id != "" and entrance_id != "" and not _exit_reachable(definition, entrance_id, exit_id):
		errors.append("exit_reachable")

	var locks_result := RoomContentValidator.validate_definition(definition)
	if not locks_result.get("ok", false):
		errors.append("locks_solvable")

	if _has_room_overlap(rooms):
		errors.append("no_room_overlap")

	if not _placements_in_rooms(placements, room_ids):
		errors.append("placement_in_room")

	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func _exit_reachable(definition: Dictionary, entrance_id: String, exit_id: String) -> bool:
	if entrance_id == "" or exit_id == "":
		return false
	var adjacency := {}
	for edge in definition.get("edges", []):
		if not edge is Dictionary:
			continue
		if str(edge.get("kind", "")) == "secret":
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if from_id == "" or to_id == "":
			continue
		if not adjacency.has(from_id):
			adjacency[from_id] = []
		if not adjacency.has(to_id):
			adjacency[to_id] = []
		adjacency[from_id].append(to_id)
		adjacency[to_id].append(from_id)
	var queue: Array[String] = [entrance_id]
	var visited := {entrance_id: true}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == exit_id:
			return true
		for neighbor in adjacency.get(current, []):
			var next_id := str(neighbor)
			if visited.has(next_id):
				continue
			visited[next_id] = true
			queue.append(next_id)
	return false


static func _has_room_overlap(rooms: Array) -> bool:
	var aabbs: Array[Rect2] = []
	for room in rooms:
		if not room is Dictionary:
			continue
		aabbs.append(_room_aabb(room))
	for i in aabbs.size():
		for j in range(i + 1, aabbs.size()):
			if _rects_overlap(aabbs[i], aabbs[j]):
				return true
	return false


## The room's footprint on the floor plane.
##
## Prefers the `size` the generator already wrote, which `RoomGraphGeometry.build_rooms` computes
## from the same spec and the same yaw it used to *place* the room — so the validator and the
## layout cannot disagree about how big a room is.
##
## The fallback recomputes it, and does so in **radians**. This used to pass `transform.yaw`
## straight to `half_extent_x`, whose parameter is named `yaw_rad`; the transform stores degrees
## (`build_rooms` writes `rad_to_deg`). So a room rotated a quarter turn was measured at
## cos(90 radians), giving footprints that were simply wrong, and `no_room_overlap` reported
## collisions between rooms that do not touch. With `entrance_present` fixed this became the next
## error to fail every floor of every biome.
static func _room_aabb(room: Dictionary) -> Rect2:
	var transform: Dictionary = room.get("transform", {})
	var pos := Vector2(float(transform.get("x", 0.0)), float(transform.get("z", 0.0)))
	var size: Dictionary = room.get("size", {})
	var half_x := 0.0
	var half_z := 0.0
	if size.has("x") and size.has("z"):
		half_x = float(size["x"]) * 0.5
		half_z = float(size["z"]) * 0.5
	else:
		var yaw_rad := deg_to_rad(float(transform.get("yaw", 0.0)))
		var spec := RoomTemplateCatalog.get_spec(str(room.get("templateId", "")))
		half_x = RoomTemplateCatalog.half_extent_x(spec, yaw_rad)
		half_z = RoomTemplateCatalog.half_extent_z(spec, yaw_rad)
	return Rect2(pos.x - half_x, pos.y - half_z, half_x * 2.0, half_z * 2.0)


static func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	return (
		a.position.x < b.position.x + b.size.x
		and a.position.x + a.size.x > b.position.x
		and a.position.y < b.position.y + b.size.y
		and a.position.y + a.size.y > b.position.y
	)


static func _placements_in_rooms(placements: Dictionary, room_ids: Dictionary) -> bool:
	for key in placements:
		var value: Variant = placements[key]
		if value == null:
			continue
		if value is Array:
			for entry in value:
				if entry is Dictionary and not _placement_room_exists(entry, room_ids):
					return false
		elif value is Dictionary:
			if not _placement_room_exists(value, room_ids):
				return false
	return true


static func _placement_room_exists(placement: Dictionary, room_ids: Dictionary) -> bool:
	var room_id := str(placement.get("roomId", ""))
	if room_id == "":
		return true
	return room_ids.has(room_id)
