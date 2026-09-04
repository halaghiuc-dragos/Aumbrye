class_name WorldFlags
extends RefCounted


const NS_LOCK := "lock"
const NS_LEVER := "lever"
const NS_DOOR := "door"
const NS_ROOM := "room"
const NS_SECRET := "secret"
const NS_CHEST := "chest"
const NS_TRAP := "trap"
const NS_KEY := "key"

const NAMESPACES: Array[String] = [
	NS_LOCK,
	NS_LEVER,
	NS_DOOR,
	NS_ROOM,
	NS_SECRET,
	NS_CHEST,
	NS_TRAP,
	NS_KEY,
]


## A key the player is carrying on the current floor.
##
## Keys live here rather than in the inventory on purpose: they are a Doom keycard, not loot. They
## take up no bag space, cannot be dropped or sold, and are wiped when the player takes the stairs.
static func key_held(key_id: String) -> String:
	return "%s.%s.held" % [NS_KEY, key_id]


static func lock_opened(lock_id: String) -> String:
	return "%s.%s.opened" % [NS_LOCK, lock_id]


## A one-way shortcut gate pulled open from its far side -- stays open for the rest of the floor,
## the same as any other lock.
static func door_opened(door_id: String) -> String:
	return "%s.%s.opened" % [NS_DOOR, door_id]


static func lever_pulled(lever_id: String) -> String:
	return "%s.%s.pulled" % [NS_LEVER, lever_id]


static func room_cleared(room_id: String) -> String:
	return "%s.%s.cleared" % [NS_ROOM, room_id]


static func secret_opened(secret_id: String) -> String:
	return "%s.%s.opened" % [NS_SECRET, secret_id]


## RM-09: a run-level counter of secrets found on the current floor, shown on the results screen.
## Reset by `DungeonBuilder.build_from_definition()` on every new floor (see there).
static func secrets_found_this_floor() -> String:
	return "%s.floor.count" % NS_SECRET


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
