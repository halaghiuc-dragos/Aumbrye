extends RefCounted
class_name ValidationFixtures

## Shared constants and procgen fixture helpers for validation suites.

const SAVE_PATH := "user://aumbrye_save.json"

const SEED_A := 42001
const SEED_B := 99999
const FIXTURE_BOSS := Vector3(38.0, 0.0, 58.0)

const REQUIRED_INPUT_ACTIONS := [
	"interact",
	"toggle_camera",
	"lock_on",
	"sprint",
	"inventory",
	"pause",
	"move_forward",
	"move_back",
	"move_left",
	"move_right",
	"debug_toggle",
	"zoom_in",
	"zoom_out",
]

const REQUIRED_ENEMIES := [
	"castle_grunt",
	"castle_archer",
	"castle_shield",
	"castle_knight",
]

const REQUIRED_ITEMS := [
	"castle_sword",
	"health_potion",
	"iron_scrap",
	"knight_relic",
]

const KEY_SCENES := [
	"res://scenes/hub/hub.tscn",
	"res://scenes/dungeon/castle_run.tscn",
	"res://scenes/debug/combat_arena.tscn",
	"res://scenes/player/player.tscn",
	"res://scenes/ui/castle_entry_menu.tscn",
]

const ROOM_TEMPLATE_SCENES := {
	"castle_entrance": "res://scenes/rooms/castle/castle_entrance.tscn",
	"castle_stairs": "res://scenes/rooms/castle/castle_stairs.tscn",
	"castle_courtyard": "res://scenes/rooms/castle/castle_courtyard.tscn",
	"castle_hall": "res://scenes/rooms/castle/castle_hall.tscn",
	"castle_treasure": "res://scenes/rooms/castle/castle_treasure.tscn",
	"castle_secret": "res://scenes/rooms/castle/castle_secret.tscn",
	"castle_arena": "res://scenes/rooms/castle/castle_arena.tscn",
	"castle_boss": "res://scenes/rooms/castle/castle_boss.tscn",
}


static func layout_signature(def: Dictionary) -> String:
	var parts: PackedStringArray = []
	for room in def.get("rooms", []):
		if not room is Dictionary:
			continue
		var t: Dictionary = room.get("transform", {})
		(
			parts
			. append(
				(
					"%s:%s:%.1f,%.1f,%.1f"
					% [
						room.get("id", ""),
						room.get("templateId", ""),
						float(t.get("x", 0.0)),
						float(t.get("y", 0.0)),
						float(t.get("z", 0.0)),
					]
				)
			)
		)
	parts.sort()
	var edge_parts: PackedStringArray = []
	for edge in def.get("edges", []):
		if edge is Dictionary:
			edge_parts.append(
				"%s>%s:%s" % [edge.get("from", ""), edge.get("to", ""), edge.get("kind", "")]
			)
	edge_parts.sort()
	return "%s||%s" % ["|".join(parts), "|".join(edge_parts)]


static func matches_m2_fixture(def: Dictionary) -> bool:
	if def.get("rooms", []).size() != 8:
		return false
	for room in def.get("rooms", []):
		if room.get("id", "") == "boss":
			var t: Dictionary = room.get("transform", {})
			var pos := Vector3(float(t.get("x", 0)), 0.0, float(t.get("z", 0)))
			if pos.distance_to(FIXTURE_BOSS) < 0.01:
				for edge in def.get("edges", []):
					if edge.get("kind", "") == "one_way":
						return true
	return false
