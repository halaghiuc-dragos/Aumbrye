extends RefCounted
class_name EnemyBlackboard

## Per-room shared awareness: who is awake, where the player was last seen, and which
## members are pressing versus circling. Roles cooperate with AttackTokenService — the
## board decides who is *allowed* to ask for a token, the service still decides how many
## swings land at once.

enum Role { ENGAGER, FLANKER, WAITER }

const MAX_ENGAGERS := 2
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


static func role_for(room_id: int, member: Node) -> int:
	if not _rooms.has(room_id):
		return Role.ENGAGER
	var roles: Dictionary = (_rooms[room_id] as Dictionary)["roles"]
	return int(roles.get(member.get_instance_id(), Role.ENGAGER))


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
