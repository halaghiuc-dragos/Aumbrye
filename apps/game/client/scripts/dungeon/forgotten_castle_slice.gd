extends Node3D

## Editor/validation fixture only — hand-authored Forgotten Castle layout (DUNGEON-2.1).
## Not wired to RunFlow; production runs use `castle_run.tscn` + procgen definitions.
## Fixture JSON: `content/fixtures/forgotten_castle_slice.json` for `DungeonBuilder.build()`.

@export var player_path: NodePath = NodePath("Player")
@export var hud_path: NodePath = NodePath("CombatHUD")

const EXIT_ROOM_ID := "boss"

var _player: CharacterBody3D
var _boss_door_open := false


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	if _player:
		_player.add_to_group("player")
	_spawn_player_at_entrance()


func _spawn_player_at_entrance() -> void:
	if _player == null:
		return
	var entrance := get_node_or_null("Rooms/CastleEntrance") as RoomTemplate
	if entrance:
		var spawn := entrance.get_player_spawn_global()
		_player.global_position = spawn


func open_boss_door() -> void:
	_boss_door_open = true
	var marker := get_node_or_null("Rooms/CastleArena/Props/BossDoorMarker") as Node3D
	if marker:
		marker.visible = true


func open_exit_portal() -> void:
	var portal := _find_exit_portal()
	if portal and portal.has_method("activate"):
		portal.call("activate")


func _find_exit_portal() -> Area3D:
	var rooms := get_node_or_null("Rooms")
	if rooms == null:
		return null
	for child in rooms.get_children():
		if child is RoomTemplate and (child as RoomTemplate).room_id == EXIT_ROOM_ID:
			return child.get_node_or_null("Props/ExitPortal") as Area3D
	return null
