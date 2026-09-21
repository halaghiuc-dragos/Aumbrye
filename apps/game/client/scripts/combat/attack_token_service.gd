extends Node


const DEFAULT_MAX_TOKENS := 2

var _leases_by_encounter: Dictionary = {}
var _owner_connections: Dictionary = {}


func request_token(
	encounter_id: String, lease_owner: Node, lease_kind: String = "attack", max_tokens: int = DEFAULT_MAX_TOKENS
) -> bool:
	if lease_owner == null or not is_instance_valid(lease_owner):
		return false
	var owner_key := "%d:%s" % [lease_owner.get_instance_id(), lease_kind]
	var leases: Dictionary = _leases_by_encounter.get(encounter_id, {})
	if leases.has(owner_key):
		return true
	if leases.size() >= max_tokens:
		return false
	leases[owner_key] = weakref(lease_owner)
	_leases_by_encounter[encounter_id] = leases
	if not _owner_connections.has(lease_owner.get_instance_id()):
		lease_owner.tree_exiting.connect(release_owner.bind(lease_owner.get_instance_id()), CONNECT_ONE_SHOT)
		_owner_connections[lease_owner.get_instance_id()] = true
	return true


func release_token(encounter_id: String, lease_owner: Node, lease_kind: String = "attack") -> void:
	if lease_owner == null:
		return
	_release_owner_key(encounter_id, "%d:%s" % [lease_owner.get_instance_id(), lease_kind])


func release_owner(owner_id: int) -> void:
	for encounter_id in _leases_by_encounter.keys():
		var leases: Dictionary = _leases_by_encounter[encounter_id]
		for owner_key in leases.keys():
			if str(owner_key).begins_with("%d:" % owner_id):
				leases.erase(owner_key)
		if leases.is_empty():
			_leases_by_encounter.erase(encounter_id)
		else:
			_leases_by_encounter[encounter_id] = leases
	_owner_connections.erase(owner_id)


func _release_owner_key(encounter_id: String, owner_key: String) -> void:
	var leases: Dictionary = _leases_by_encounter.get(encounter_id, {})
	leases.erase(owner_key)
	if leases.is_empty():
		_leases_by_encounter.erase(encounter_id)
	else:
		_leases_by_encounter[encounter_id] = leases


func reset_all() -> void:
	_leases_by_encounter.clear()
	_owner_connections.clear()
