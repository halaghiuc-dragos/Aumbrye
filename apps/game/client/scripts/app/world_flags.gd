class_name WorldFlags
extends RefCounted

## Canonical run-flag id builders. Every WorldState key must come from here.

const NS_LOCK := "lock"
const NS_LEVER := "lever"
const NS_DOOR := "door"
const NS_ROOM := "room"
const NS_SECRET := "secret"
const NS_CHEST := "chest"
const NS_TRAP := "trap"

const NAMESPACES: Array[String] = [
	NS_LOCK,
	NS_LEVER,
	NS_DOOR,
	NS_ROOM,
	NS_SECRET,
	NS_CHEST,
	NS_TRAP,
]


static func lock_opened(lock_id: String) -> String:
	return "%s.%s.opened" % [NS_LOCK, lock_id]


static func lever_pulled(lever_id: String) -> String:
	return "%s.%s.pulled" % [NS_LEVER, lever_id]


static func room_cleared(room_id: String) -> String:
	return "%s.%s.cleared" % [NS_ROOM, room_id]


static func chest_opened(instance_id: String) -> String:
	return "%s.%s.opened" % [NS_CHEST, instance_id]


static func secret_opened(secret_id: String) -> String:
	return "%s.%s.opened" % [NS_SECRET, secret_id]


static func trap_disarmed(trap_id: String) -> String:
	return "%s.%s.disarmed" % [NS_TRAP, trap_id]


static func is_valid_id(flag_id: String) -> bool:
	var parts := flag_id.split(".")
	return parts.size() == 3 and parts[0] in NAMESPACES and parts[1] != ""


static func migrate_legacy_id(legacy_id: String) -> String:
	if legacy_id.begins_with("key_"):
		return lock_opened("lock_%s" % legacy_id.substr(4))
	if legacy_id.begins_with("quest_") and legacy_id.ends_with("_active"):
		var quest_id := legacy_id.trim_prefix("quest_").trim_suffix("_active")
		return secret_opened(quest_id)
	return ""
