extends RefCounted
class_name EnemyBlackboard

## Per-room shared awareness: who is awake, where the player was last seen, and which
## members are pressing versus circling. Roles cooperate with AttackTokenService — the
## board decides who is *allowed* to ask for a token, the service still decides how many
## swings land at once.

enum Role { ENGAGER, FLANKER, WAITER }

const MAX_ENGAGERS := 2

## C-29: how many physics frames a cached room centre may be reused for.
const BOUNDS_MAX_STALE_FRAMES := 6
const MAX_FLANKERS := 2

static var _rooms: Dictionary = {}


static func room_key(node: Node) -> int:
	var parent := node.get_parent()
	if parent == null:
		return 0
	return int(parent.get_instance_id())


static func register(room_id: int, member: Node) -> void:
	var record := _record(room_id)
	var members: Array = record["members"]
	if not members.has(member):
		members.append(member)


static func unregister(room_id: int, member: Node) -> void:
	if not _rooms.has(room_id):
		return
	var record: Dictionary = _rooms[room_id]
	(record["members"] as Array).erase(member)
	var engaged: Array = record["engaged"]
	var was_engaged := engaged.has(member)
	engaged.erase(member)
	(record["roles"] as Dictionary).erase(member.get_instance_id())
	if (record["members"] as Array).is_empty():
		_rooms.erase(room_id)
		return
	if was_engaged:
		_assign_roles(record)


static func members(room_id: int) -> Array:
	if not _rooms.has(room_id):
		return []
	var record: Dictionary = _rooms[room_id]
	_prune(record)
	return record["members"]


## Registered members within `radius` of `origin`, across every room.
##
## Walks only the per-room rosters rather than the whole `enemy` scene group, and skips a room
## outright once its cached centre is further away than the radius plus the room's own extent —
## so a crowded endless floor costs a few room checks instead of an O(N) scan inside one frame.
##
## Note this sees only members that registered with the board. Bosses deliberately do not (see
## CastleEnemyBase._join_room_board), so this is the right query for ally-alert propagation but NOT
## for player-facing target selection, which must still be able to find a boss.
static func nearby(origin: Vector3, radius: float) -> Array:
	var found: Array = []
	if radius <= 0.0:
		return found
	var radius_sq := radius * radius

	for room_id in _rooms.keys():
		var record: Dictionary = _rooms[room_id]
		_prune(record)
		var members_list: Array = record["members"]
		if members_list.is_empty():
			continue

		var bounds := _room_bounds(record, members_list)
		var reach := radius + float(bounds["extent"])
		if (bounds["center"] as Vector3).distance_squared_to(origin) > reach * reach:
			continue

		for member in members_list:
			if not is_instance_valid(member) or not (member is Node3D):
				continue
			if (member as Node3D).global_position.distance_squared_to(origin) <= radius_sq:
				found.append(member)

	return found


## Cached centre/extent for a room's roster, refreshed when the membership changes so the common
## case is a single Vector3 comparison instead of re-measuring every member.
static func _room_bounds(record: Dictionary, members_list: Array) -> Dictionary:
	# C-29: the cache was keyed on member *count* alone — the comment said "refreshed when the
	# membership changes", but enemies move every frame while the count stays constant, so
	# `nearby()` culled whole rooms against a stale centre and ally-alert propagation could miss
	# enemies that had walked toward the player. Count still invalidates immediately; a frame
	# stamp bounds how stale the centre can get.
	var frame := Engine.get_physics_frames()
	var cached: Variant = record.get("bounds")
	if (
		cached is Dictionary
		and int((cached as Dictionary).get("count", -1)) == members_list.size()
		and frame - int((cached as Dictionary).get("frame", -BOUNDS_MAX_STALE_FRAMES)) < BOUNDS_MAX_STALE_FRAMES
	):
		return cached

	var center := Vector3.ZERO
	var counted := 0
	for member in members_list:
		if is_instance_valid(member) and member is Node3D:
			center += (member as Node3D).global_position
			counted += 1
	if counted > 0:
		center /= float(counted)

	var extent := 0.0
	for member in members_list:
		if is_instance_valid(member) and member is Node3D:
			extent = maxf(extent, center.distance_to((member as Node3D).global_position))

	var bounds := {
		"center": center, "extent": extent, "count": members_list.size(), "frame": frame
	}
	record["bounds"] = bounds
	return bounds


static func report_engaged(room_id: int, member: Node, engaged: bool) -> void:
	var record := _record(room_id)
	_prune(record)
	var list: Array = record["engaged"]
	if engaged:
		if list.has(member):
			return
		list.append(member)
	else:
		if not list.has(member):
			return
		list.erase(member)
		(record["roles"] as Dictionary).erase(member.get_instance_id())
	_assign_roles(record)


## Hands the pressing slot to the next member in line after a swing resolves or a hit
## staggers the current engager, so a group takes turns instead of one enemy monopolising.
static func yield_engager(room_id: int, member: Node) -> void:
	if not _rooms.has(room_id):
		return
	var record: Dictionary = _rooms[room_id]
	_prune(record)
	var list: Array = record["engaged"]
	if list.size() <= MAX_ENGAGERS or not list.has(member):
		return
	list.erase(member)
	list.append(member)
	_assign_roles(record)


## C-28: both defaults used to be `Role.ENGAGER`, but `_assign_roles` only writes entries for
## members in the `engaged` list — so every enemy that had *not* engaged reported the pressing role
## instead of the waiting one, which is exactly backwards from this file's own stated purpose ("the
## board decides who is *allowed* to ask for a token"). An unknown member waits.
static func role_for(room_id: int, member: Node) -> int:
	if not _rooms.has(room_id):
		return Role.WAITER
	var roles: Dictionary = (_rooms[room_id] as Dictionary)["roles"]
	return int(roles.get(member.get_instance_id(), Role.WAITER))


static func report_player_position(room_id: int, position: Vector3) -> void:
	var record := _record(room_id)
	record["alert_position"] = position
	record["alerted"] = true


static func has_alert(room_id: int) -> bool:
	if not _rooms.has(room_id):
		return false
	return bool((_rooms[room_id] as Dictionary)["alerted"])


static func alert_position(room_id: int) -> Vector3:
	if not _rooms.has(room_id):
		return Vector3.ZERO
	return (_rooms[room_id] as Dictionary)["alert_position"]


static func clear_room(room_id: int) -> void:
	_rooms.erase(room_id)


static func clear_all() -> void:
	_rooms.clear()


static func engaged_count(room_id: int) -> int:
	if not _rooms.has(room_id):
		return 0
	var record: Dictionary = _rooms[room_id]
	_prune(record)
	return (record["engaged"] as Array).size()


static func _record(room_id: int) -> Dictionary:
	if not _rooms.has(room_id):
		_rooms[room_id] = {
			"members": [],
			"engaged": [],
			"roles": {},
			"alert_position": Vector3.ZERO,
			"alerted": false,
		}
	return _rooms[room_id]


static func _prune(record: Dictionary) -> void:
	var members_list: Array = record["members"]
	for i in range(members_list.size() - 1, -1, -1):
		if not is_instance_valid(members_list[i]):
			members_list.remove_at(i)
	var engaged: Array = record["engaged"]
	for i in range(engaged.size() - 1, -1, -1):
		if not is_instance_valid(engaged[i]):
			engaged.remove_at(i)


static func _assign_roles(record: Dictionary) -> void:
	var roles: Dictionary = record["roles"]
	var engaged: Array = record["engaged"]
	for i in engaged.size():
		var member: Node = engaged[i]
		var role := Role.WAITER
		if i < MAX_ENGAGERS:
			role = Role.ENGAGER
		elif i < MAX_ENGAGERS + MAX_FLANKERS:
			role = Role.FLANKER
		var key := member.get_instance_id()
		if int(roles.get(key, -1)) == int(role):
			continue
		roles[key] = int(role)
		var enemy := member as CastleEnemyBase
		if enemy != null:
			enemy.set_ai_role(int(role))
