extends RefCounted
class_name TestContext

## Shared state and helpers for validation suites.

const REPORT_PATH := "user://mcp_validation.json"
const SAVE_PATH := "user://aumbrye_save.json"

const SEED_A := 42001
const SEED_B := 99999
const FIXTURE_BOSS := Vector3(38.0, 0.0, 58.0)

const REQUIRED_INPUT_ACTIONS := [
	"interact", "toggle_camera", "lock_on", "sprint", "inventory",
	"pause", "move_forward", "move_back", "move_left", "move_right",
	"debug_toggle", "zoom_in", "zoom_out",
]

const REQUIRED_ENEMIES := [
	"castle_grunt", "castle_archer", "castle_shield", "castle_knight",
]

const REQUIRED_ITEMS := [
	"castle_sword", "health_potion", "iron_scrap", "knight_relic",
]

const KEY_SCENES := [
	"res://scenes/hub/hub.tscn",
	"res://scenes/hub/hub_stub.tscn",
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

const MANUAL_REMAINING := [
	"M7.movement.feel",
	"M7.combat.hp_bar_visual",
	"M7.combat.shield_feel",
	"M7.loot.interact_feel",
	"M7.traps.damage_feel",
	"M7.boss.door_flow",
	"M7.results.escape_flow",
	"M7.camera.toggle_feel",
	"M7.camera.relaunch_persistence",
	"M7.lock_on.fp_readability",
	"M7.hub.interaction_feel",
	"M7.continue.full_playthrough",
	"M7.debug.overlay_runtime",
	"M7.arena.combat_feel",
	"M7.cross_machine.seed",
	"M7.procgen_cli.missing_ux",
	"M7.offline.no_hang",
]

var owner: Node
var tests: Array[Dictionary] = []
var passed: int = 0
var failed: int = 0


func _init(host: Node) -> void:
	owner = host


func record(
	id: String,
	category: String,
	passed_test: bool,
	message: String,
	checklist_ref: String = "",
	duration_ms: int = 0
) -> void:
	if passed_test:
		passed += 1
	else:
		failed += 1
	var entry := {
		"id": id,
		"category": category,
		"pass": passed_test,
		"message": message,
		"duration_ms": duration_ms,
	}
	if checklist_ref != "":
		entry["checklist_ref"] = checklist_ref
	tests.append(entry)


func timed_record(
	id: String,
	category: String,
	passed_test: bool,
	message: String,
	start_ms: int,
	checklist_ref: String = ""
) -> void:
	record(id, category, passed_test, message, checklist_ref, Time.get_ticks_msec() - start_ms)


func file_contains(path: String, needle: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return needle in FileAccess.get_file_as_string(path)


func backup_save_file() -> Dictionary:
	var backup := {"exists": false, "text": ""}
	if FileAccess.file_exists(SAVE_PATH):
		backup["exists"] = true
		backup["text"] = FileAccess.get_file_as_string(SAVE_PATH)
	return backup


func restore_save_file(backup: Dictionary) -> void:
	if backup.get("exists", false):
		var text: String = str(backup.get("text", ""))
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if file:
				file.store_string(text)
		else:
			LocalSave.delete_save()
	else:
		LocalSave.delete_save()
	LocalSave.load_into_services()


func eval_continuable(run: Dictionary) -> bool:
	if run.is_empty():
		return false
	if run.get("playerDead", false):
		return false
	var snapshot: Variant = run.get("snapshot", {})
	if not snapshot is Dictionary or snapshot.is_empty():
		return false
	var player_state: Dictionary = snapshot.get("player", {})
	if player_state.has("health") and float(player_state.get("health", 1.0)) <= 0.0:
		return false
	return true


func player_snapshot_allowed(health: float, is_dead: bool) -> bool:
	if health <= 0.0:
		return false
	if is_dead:
		return false
	return true


func layout_signature(def: Dictionary) -> String:
	var parts: PackedStringArray = []
	for room in def.get("rooms", []):
		if not room is Dictionary:
			continue
		var t: Dictionary = room.get("transform", {})
		parts.append(
			"%s:%s:%.1f,%.1f,%.1f" % [
				room.get("id", ""),
				room.get("templateId", ""),
				float(t.get("x", 0.0)),
				float(t.get("y", 0.0)),
				float(t.get("z", 0.0)),
			]
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


func matches_m2_fixture(def: Dictionary) -> bool:
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


func parse_castle_seed(text: String) -> Variant:
	var trimmed := text.strip_edges()
	if trimmed == "" or not trimmed.is_valid_int():
		return null
	var value := int(trimmed)
	if value < 1:
		return null
	return value


func count_nodes_by_script(node: Node, script_name: String) -> int:
	var count := 0
	var node_script: Script = node.get_script() as Script
	if node_script and str(node_script.resource_path).ends_with(script_name):
		count += 1
	for child in node.get_children():
		count += count_nodes_by_script(child, script_name)
	return count


func count_loot_chests(node: Node) -> int:
	return count_nodes_by_script(node, "loot_chest.gd")


func await_physics(frames: int = 1) -> void:
	for _i in frames:
		await owner.get_tree().physics_frame


func await_frame(frames: int = 1) -> void:
	for _i in frames:
		await owner.get_tree().process_frame
