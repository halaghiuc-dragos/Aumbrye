extends Node3D

## Castle run scene controller — uses DungeonBuilder as authoritative path.

const BUILDER_SCRIPT := preload("res://scripts/dungeon/dungeon_builder.gd")
const BOSS_ROOM_ID := "boss"
const BOSS_GATE_DEPTH_THRESHOLD := 4.0

@export var player_path: NodePath = NodePath("Player")
@export var hud_path: NodePath = NodePath("CombatHUD")
@export var inventory_ui_path: NodePath = NodePath("InventoryUI")

var player_room_id := ""
var _player: CharacterBody3D
var _builder: DungeonBuilder
var _boss_door: Node
var _boss_defeated := false


func _ready() -> void:
	add_to_group("castle_run")
	_player = get_node_or_null(player_path) as CharacterBody3D
	_builder = BUILDER_SCRIPT.new()
	add_child(_builder)
	_builder.boss_defeated.connect(_on_boss_defeated)
	_builder.build(self, _player)
	player_room_id = _find_room_id_at(_player.global_position)
	_wire_player_death()
	_wire_weapon_from_inventory()
	AudioDirector.play_dungeon_ambience()
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	var room_id := _find_room_id_at(_player.global_position)
	if room_id != "" and room_id != player_room_id:
		player_room_id = room_id
	if _boss_door and not _boss_defeated and _boss_door.call("is_opened") and _is_player_deep_in_boss_room():
		if not _boss_door.call("is_sealed"):
			_boss_door.call("seal_door")


func register_boss_door(door: Node) -> void:
	_boss_door = door


func _is_player_deep_in_boss_room() -> bool:
	var room := _builder.get_room(BOSS_ROOM_ID)
	if room == null or _player == null:
		return false
	var local := room.to_local(_player.global_position)
	var blockout := room.get_blockout()
	var half_d := (blockout.room_depth if blockout else 28.0) * 0.5
	return local.z > -half_d + BOSS_GATE_DEPTH_THRESHOLD


func is_cross_boss_boundary(attacker: Node, target: Node) -> bool:
	var attacker_room := _get_entity_room_id(attacker)
	var target_room := _get_entity_room_id(target)
	if attacker_room == BOSS_ROOM_ID or target_room == BOSS_ROOM_ID:
		return attacker_room != target_room
	return false


func _get_entity_room_id(entity: Node) -> String:
	if entity == null:
		return ""
	if entity.is_in_group("player"):
		return player_room_id
	var node: Node = entity
	while node:
		if node is RoomTemplate:
			return (node as RoomTemplate).room_id
		node = node.get_parent()
	return ""


func _find_room_id_at(world_pos: Vector3) -> String:
	for room_id in _builder.get_room_ids():
		var room := _builder.get_room(room_id)
		if room and room.contains_world_point(world_pos):
			return room_id
	return ""


func _wire_player_death() -> void:
	if _player == null:
		return
	var reactions := _player.get_node_or_null("CombatReactions")
	if reactions and reactions.has_signal("player_died"):
		if not reactions.player_died.is_connected(_on_player_died):
			reactions.player_died.connect(_on_player_died)


func _wire_weapon_from_inventory() -> void:
	var weapon := _player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("load_weapon_from_path"):
		weapon.load_weapon_from_path(InventoryService.inventory.get_equipped_weapon_data_path())


func _on_boss_defeated() -> void:
	_boss_defeated = true
	if _boss_door:
		_boss_door.call("release_door")
	AudioDirector.play_dungeon_ambience()


func _on_player_died() -> void:
	if _boss_door:
		_boss_door.call("release_door")
	await get_tree().create_timer(1.5).timeout
	RunFlow.on_player_died()
