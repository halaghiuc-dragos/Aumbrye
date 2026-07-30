extends Node3D

## Hand-authored Forgotten Castle vertical slice layout (DUNGEON-2.1).

const ROOM_SCENES := {
	"castle_entrance": preload("res://scenes/rooms/castle/castle_entrance.tscn"),
	"castle_stairs": preload("res://scenes/rooms/castle/castle_stairs.tscn"),
	"castle_courtyard": preload("res://scenes/rooms/castle/castle_courtyard.tscn"),
	"castle_hall": preload("res://scenes/rooms/castle/castle_hall.tscn"),
	"castle_treasure": preload("res://scenes/rooms/castle/castle_treasure.tscn"),
	"castle_secret": preload("res://scenes/rooms/castle/castle_secret.tscn"),
	"castle_arena": preload("res://scenes/rooms/castle/castle_arena.tscn"),
	"castle_boss": preload("res://scenes/rooms/castle/castle_boss.tscn"),
}

@export var player_path: NodePath = NodePath("Player")
@export var hud_path: NodePath = NodePath("CombatHUD")

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
	var portal := get_node_or_null("Rooms/CastleBoss/Props/ExitPortal") as Area3D
	if portal:
		portal.monitoring = true
		portal.visible = true
