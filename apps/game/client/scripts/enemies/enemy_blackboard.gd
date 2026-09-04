extends RefCounted
class_name EnemyBlackboard


enum Role { ENGAGER, FLANKER, WAITER }

const MAX_ENGAGERS := 2

const BOUNDS_MAX_STALE_FRAMES := 6
const MAX_FLANKERS := 2

## `EN-08`: a flanker's target bearing, in degrees either side of the player's own facing.
const FLANK_ANGLE_DEG := 100.0
## Roles are re-run on a timer, not only on membership change, so they follow the player turning.
const REASSIGN_INTERVAL_MSEC := 1500

static var _rooms: Dictionary = {}


static func room_key(node: Node) -> int:
	var parent := node.get_parent()
	if parent == null:
		return 0
	return int(parent.get_instance_id())


static func register(room_id: int, member: Node) -> void:
	var record := _record(room_id)
	var members_list: Array = record["members"]
	if not members_list.has(member):
		members_list.append(member)
		_assign_roles(record)


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


static func _room_bounds(record: Dictionary, members_list: Array) -> Dictionary:
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


static func report_player_position(room_id: int, position: Vector3) -> void:
	var record := _record(room_id)
	record["alert_position"] = position
	record["alerted"] = true


static func alert_position(room_id: int) -> Vector3:
	if not _rooms.has(room_id):
		return Vector3.ZERO
	return (_rooms[room_id] as Dictionary)["alert_position"]


static func clear_all() -> void:
	_rooms.clear()


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


## Re-runs role assignment for `room_id` if `REASSIGN_INTERVAL_MSEC` has passed since the last run.
## Cheap to call every tick from every engaged enemy's own AI update -- it is a dictionary lookup
## and a time comparison in the common case, and only the *first* caller in a given window actually
## re-sorts. This is what keeps a flanker's role (and target bearing) following the player as they
## turn, instead of only updating when an enemy joins or leaves the fight.
static func maybe_reassign(room_id: int) -> void:
	if not _rooms.has(room_id):
		return
	var record: Dictionary = _rooms[room_id]
	var now := Time.get_ticks_msec()
	if now - int(record.get("last_assign_msec", 0)) < REASSIGN_INTERVAL_MSEC:
		return
	record["last_assign_msec"] = now
	_assign_roles(record)


## `EN-08`: roles are sorted by bearing from the player's own facing, not by insertion order --
## `ENGAGER` goes to whoever is nearest the front arc, `FLANKER` to whoever is nearest the ±90°
## arcs *among those left over*, so a flanker actually flanks instead of just being third in line.
static func _assign_roles(record: Dictionary) -> void:
	var roles: Dictionary = record["roles"]
	var engaged: Array = record["engaged"]
	if engaged.is_empty():
		return
	var player := _infer_player(engaged)
	var angle_by_id: Dictionary = {}
	var player_pos := Vector3.ZERO
	var facing := Vector3.ZERO
	if player != null:
		facing = CombatFacing.aim_forward_of(player)
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			facing = facing.normalized()
			player_pos = player.global_position
			for member in engaged:
				if member is Node3D:
					angle_by_id[member.get_instance_id()] = _signed_angle_deg(
						player_pos, facing, (member as Node3D).global_position
					)
		else:
			player = null

	var pool: Array = engaged.duplicate()
	var engagers := _take_nearest_front(pool, angle_by_id, MAX_ENGAGERS)
	var flankers := _take_nearest_flank(pool, angle_by_id, MAX_FLANKERS)

	for i in engaged.size():
		var member: Node = engaged[i]
		var role := Role.WAITER
		if engagers.has(member):
			role = Role.ENGAGER
		elif flankers.has(member):
			role = Role.FLANKER
		var key := member.get_instance_id()
		var role_changed := int(roles.get(key, -1)) != int(role)
		roles[key] = int(role)
		var enemy := member as CastleEnemyBase
		if enemy == null:
			continue
		if role_changed:
			enemy.set_ai_role(int(role))

	if player != null:
		_assign_flank_bearings(flankers, angle_by_id)


static func _infer_player(engaged: Array) -> Node3D:
	for member in engaged:
		if member is CastleEnemyBase:
			var candidate := (member as CastleEnemyBase).get_player() as Node3D
			if candidate != null and is_instance_valid(candidate):
				return candidate
	return null


static func _signed_angle_deg(origin: Vector3, facing: Vector3, target_pos: Vector3) -> float:
	var to_target := target_pos - origin
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(facing.signed_angle_to(to_target.normalized(), Vector3.UP))


static func _take_nearest_front(pool: Array, angle_by_id: Dictionary, count: int) -> Array:
	pool.sort_custom(
		func(a, b):
			return (
				absf(float(angle_by_id.get(a.get_instance_id(), 0.0)))
				< absf(float(angle_by_id.get(b.get_instance_id(), 0.0)))
			)
	)
	var picked: Array = pool.slice(0, count)
	for member in picked:
		pool.erase(member)
	return picked


static func _take_nearest_flank(pool: Array, angle_by_id: Dictionary, count: int) -> Array:
	pool.sort_custom(
		func(a, b):
			var da := absf(absf(float(angle_by_id.get(a.get_instance_id(), 0.0))) - 90.0)
			var db := absf(absf(float(angle_by_id.get(b.get_instance_id(), 0.0))) - 90.0)
			return da < db
	)
	var picked: Array = pool.slice(0, count)
	for member in picked:
		pool.erase(member)
	return picked


## Each flanker gets a target *angle*, not a radius multiplier -- one to either side of the
## player's facing, biased toward whichever side the flanker is already nearer so it does not have
## to travel all the way around. With two flankers the second always takes the opposite side, so
## the pair actually splits rather than both drifting to the same shoulder.
static func _assign_flank_bearings(flankers: Array, angle_by_id: Dictionary) -> void:
	var used_positive := false
	var used_negative := false
	for member in flankers:
		var enemy := member as CastleEnemyBase
		if enemy == null:
			continue
		var current: float = float(angle_by_id.get(member.get_instance_id(), 0.0))
		var positive := current >= 0.0
		if positive and used_positive and not used_negative:
			positive = false
		elif not positive and used_negative and not used_positive:
			positive = true
		if positive:
			used_positive = true
		else:
			used_negative = true
		var target_deg := FLANK_ANGLE_DEG if positive else -FLANK_ANGLE_DEG
		enemy.set_desired_flank_angle_deg(target_deg)
