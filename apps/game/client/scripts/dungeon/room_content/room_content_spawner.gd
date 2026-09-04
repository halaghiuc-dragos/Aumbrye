class_name RoomContentSpawner
extends RefCounted


const CONTENT_SCRIPTS := {
	"trap_spike_pack": preload("res://scripts/dungeon/room_content/room_trap_content.gd"),
	"hazard_poison_zone": preload("res://scripts/dungeon/room_content/room_hazard_content.gd"),
	"puzzle_lever_gate": preload("res://scripts/dungeon/room_content/room_puzzle_content.gd"),
	"npc_quest_giver": preload("res://scripts/dungeon/room_content/room_npc_quest_content.gd"),
	"locked_vault_chest":
	preload("res://scripts/dungeon/room_content/room_locked_vault_content.gd"),
	"reward_cache": preload("res://scripts/dungeon/room_content/room_reward_content.gd"),
	"rest_bonfire": preload("res://scripts/dungeon/room_content/room_rest_content.gd"),
	"lore_readable": preload("res://scripts/dungeon/room_content/room_lore_content.gd"),
	"dungeon_merchant": preload("res://scripts/dungeon/room_content/room_merchant_content.gd"),
}


static func spawn_all(builder: DungeonBuilder, definition: Dictionary) -> void:
	for entry in definition.get("roomContent", []):
		if not entry is Dictionary:
			continue
		var room_id: String = entry.get("roomId", "")
		var room := builder.get_room(room_id)
		if room == null:
			continue
		var template_id: String = entry.get("templateId", "")
		if template_id == "":
			continue
		var script: Script = CONTENT_SCRIPTS.get(template_id) as Script
		if script == null:
			push_error("RoomContentSpawner: unknown templateId '%s'" % template_id)
			continue
		var node := Node3D.new()
		node.name = "RoomContent_%s" % template_id
		node.set_script(script)
		node.set_meta("biome_id", builder.biome_id)
		room.add_child(node)
		if node.has_method("configure"):
			node.call("configure", entry, definition)


## The doorway a barrier belongs in, resolved by the builder from the definition edge.
##
## `RoomTemplate.socket_toward` is not usable here: it names the wall from the line between the two
## room centres, and a doorway that has slid along its wall leaves that line pointing at a corner.
static func door_socket(node: Node) -> DoorwaySocket:
	return node.get_meta("door_socket", null) as DoorwaySocket


static func spawn_locks(builder: DungeonBuilder, definition: Dictionary) -> void:
	const LOCK_SCRIPT := preload("res://scripts/dungeon/room_content/room_locked_door_content.gd")
	for lock in definition.get("locks", []):
		if not lock is Dictionary:
			continue
		var from_room := builder.get_room(str(lock.get("from", "")))
		var to_room := builder.get_room(str(lock.get("to", "")))
		if from_room == null or to_room == null:
			continue
		var node := Node3D.new()
		node.name = "LockedDoor_%s" % lock.get("lockId", "gate")
		node.set_script(LOCK_SCRIPT)
		node.set_meta("biome_id", builder.biome_id)
		node.set_meta("door_socket", builder.door_socket_between(from_room, to_room))
		from_room.add_child(node)
		if node.has_method("configure"):
			node.call("configure", lock, from_room, to_room)


static func spawn_shortcut_gates(builder: DungeonBuilder, definition: Dictionary) -> void:
	const GATE_SCRIPT := preload("res://scripts/dungeon/room_content/room_shortcut_gate_content.gd")
	for gate in definition.get("shortcutGates", []):
		if not gate is Dictionary:
			continue
		var room_a := builder.get_room(str(gate.get("roomA", "")))
		var room_b := builder.get_room(str(gate.get("roomB", "")))
		if room_a == null or room_b == null:
			continue
		var node := Node3D.new()
		node.name = "ShortcutGate_%s" % gate.get("gateId", "gate")
		node.set_script(GATE_SCRIPT)
		node.set_meta("biome_id", builder.biome_id)
		node.set_meta("door_socket", builder.door_socket_between(room_a, room_b))
		room_a.add_child(node)
		if node.has_method("configure"):
			node.call("configure", gate, room_a, room_b)


## RM-07: exactly one room per floor -- see `RoomContentAssigner._mark_pre_boss_lock_in()` -- has
## `"lockIn": true` on its `roomContent` entry. One node owns every doorway of that room rather than
## spawning per-doorway like the other gate kinds, since they all have to close and open together.
static func spawn_arena_gates(builder: DungeonBuilder, definition: Dictionary) -> void:
	const ARENA_GATE_SCRIPT := preload("res://scripts/dungeon/room_content/room_arena_gate_content.gd")
	for entry in definition.get("roomContent", []):
		if not entry is Dictionary or not bool((entry as Dictionary).get("lockIn", false)):
			continue
		var room := builder.get_room(str((entry as Dictionary).get("roomId", "")))
		if room == null:
			continue
		var node := Node3D.new()
		node.name = "ArenaGates_%s" % (entry as Dictionary).get("roomId", "")
		node.set_script(ARENA_GATE_SCRIPT)
		node.set_meta("biome_id", builder.biome_id)
		room.add_child(node)
		if node.has_method("configure"):
			node.call("configure", entry, definition)


static func spawn_puzzle_gates(builder: DungeonBuilder, definition: Dictionary) -> void:
	const GATE_SCRIPT := preload("res://scripts/dungeon/room_content/room_puzzle_gate_content.gd")
	for puzzle in definition.get("puzzles", []):
		if not puzzle is Dictionary:
			continue
		var from_room := builder.get_room(str(puzzle.get("roomId", "")))
		var to_room := builder.get_room(str(puzzle.get("gateRoomId", "")))
		if from_room == null or to_room == null:
			continue
		var node := Node3D.new()
		node.name = "PuzzleGate_%s" % puzzle.get("puzzleId", "gate")
		node.set_script(GATE_SCRIPT)
		node.set_meta("biome_id", builder.biome_id)
		node.set_meta("door_socket", builder.door_socket_between(from_room, to_room))
		from_room.add_child(node)
		if node.has_method("configure"):
			node.call("configure", puzzle, from_room, to_room)
