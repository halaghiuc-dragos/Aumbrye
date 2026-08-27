extends RefCounted
class_name EnemyBlackboard


enum Role { ENGAGER, FLANKER, WAITER }

const MAX_ENGAGERS := 2

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
