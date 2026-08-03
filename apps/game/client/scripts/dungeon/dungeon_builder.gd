extends Node3D
class_name DungeonBuilder

## Loads a DungeonDefinition fixture and instances room templates (BUILDER-2.1).

const FIXTURE_RELATIVE := "content/fixtures/forgotten_castle_slice.json"

const ENEMY_SCENES_FALLBACK := {
	"castle_grunt": preload("res://scenes/enemies/castle_grunt.tscn"),
	"castle_archer": preload("res://scenes/enemies/castle_archer.tscn"),
	"castle_shield": preload("res://scenes/enemies/castle_shield.tscn"),
	"castle_knight": preload("res://scenes/enemies/castle_knight.tscn"),
}

const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")
const SPIKE_TRAP_SCENE := preload("res://scenes/traps/spike_trap.tscn")
const FALLING_TRAP_SCENE := preload("res://scenes/traps/falling_trap.tscn")
const POISON_POOL_SCENE := preload("res://scenes/traps/poison_pool.tscn")
const EXIT_PORTAL_SCRIPT := preload("res://scripts/dungeon/exit_portal.gd")
const BOSS_DOOR_SCRIPT := preload("res://scripts/dungeon/boss_room_door.gd")
const STAIR_LEVER_SCRIPT := preload("res://scripts/dungeon/stair_lever.gd")
const STAIR_COLLISION := preload("res://scripts/dungeon/stair_collision_builder.gd")
const DIORAMA_SKIN := preload("res://scripts/art/diorama_interactable_skin.gd")
const FINAL_BOSS_SCENE := preload("res://scenes/enemies/final_boss_forgotten_castle.tscn")
const EndlessDifficultyScript := preload("res://scripts/dungeon/endless_difficulty.gd")
const CastleTierDifficultyScript := preload("res://scripts/dungeon/castle_tier_difficulty.gd")
const FloorShellBuilderScript := preload("res://scripts/dungeon/floor_shell_builder.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/character_floor_snap.gd")
const RoomContentSpawnerScript := preload("res://scripts/dungeon/room_content/room_content_spawner.gd")

signal build_complete
signal boss_defeated
signal snapshot_dirty

var definition: Dictionary = {}
var biome_id: String = BiomeRegistry.BIOME_CASTLE
var _room_scenes: Dictionary = {}
var _rooms: Dictionary = {}
var _player: CharacterBody3D
var _entities: Node3D
var _boss: Node
var _enemy_by_id: Dictionary = {}
var _chest_by_id: Dictionary = {}
var _boss_door: Node3D
var _stair_lever: Node3D
var _is_final_floor := false


func build(parent: Node3D, player: CharacterBody3D, fixture_path: String = FIXTURE_RELATIVE) -> void:
	build_from_source(parent, player, fixture_path, {})


func build_from_definition(parent: Node3D, player: CharacterBody3D, def: Dictionary) -> void:
	build_from_source(parent, player, "", def)


func build_from_source(parent: Node3D, player: CharacterBody3D, fixture_path: String, def: Dictionary) -> void:
	_player = player
	_entities = Node3D.new()
	_entities.name = "Entities"
	parent.add_child(_entities)
	if not def.is_empty():
		definition = def
	elif fixture_path != "":
		definition = ContentLoader.load_json(fixture_path)
	else:
		definition = {}
	if definition.is_empty():
		push_error("DungeonBuilder: no definition provided")
		return
	biome_id = BiomeRegistry.resolve_biome_id(definition)
	_is_final_floor = bool(definition.get("isFinalFloor", false)) or (
		RunFlow.is_final_floor() and RunFlow.get_run_mode() != "endless"
	)
	_room_scenes = BiomeRegistry.get_room_scenes(biome_id)
	var rooms: Array = definition.get("rooms", [])
	if rooms.is_empty():
		push_error("DungeonBuilder: definition has no rooms")
		return
	_build_rooms(parent)
	_build_shortcut_corridors(parent)
	_build_floor_shell(parent)
	_spawn_player()
	_place_enemies()
	_place_loot()
	_place_traps()
	_place_room_content()
	_setup_boss()
	if _is_final_floor:
		_setup_exit_portal()
	_setup_stair_levers()
	_setup_boss_door(parent)
	build_complete.emit()


func get_room(room_id: String) -> RoomTemplate:
	return _rooms.get(room_id) as RoomTemplate


func get_room_ids() -> Array:
	return _rooms.keys()


func open_exit_portal() -> void:
	var exit_room_id: String = definition.get("placements", {}).get("exit", "boss")
	var room := get_room(exit_room_id)
	if room == null:
		return
	var portal := room.get_node_or_null("Props/ExitPortal") as Area3D
	if portal == null:
		portal = _create_exit_portal(room)
	if portal:
		portal.monitoring = true
		portal.visible = true


func _build_rooms(parent: Node3D) -> void:
	var rooms_root := Node3D.new()
	rooms_root.name = "Rooms"
	parent.add_child(rooms_root)
	for room_def in definition.get("rooms", []):
		var template_id: String = room_def.get("templateId", "")
		if not _room_scenes.has(template_id):
			push_warning("DungeonBuilder: unknown template %s" % template_id)
			continue
		var scene: PackedScene = _room_scenes[template_id]
		var instance := scene.instantiate() as RoomTemplate
		var t: Dictionary = room_def.get("transform", {})
		var yaw: float = deg_to_rad(t.get("yaw", 0.0))
		instance.position = Vector3(t.get("x", 0.0), t.get("y", 0.0), t.get("z", 0.0))
		instance.rotation.y = yaw
		instance.name = room_def.get("id", template_id).capitalize()
		instance.room_id = room_def.get("id", "")
		instance.template_id = template_id
		instance.room_type = str(room_def.get("type", instance.room_type))
		var blockout := instance.get_blockout()
		if blockout:
			blockout.skip_floor = false
		rooms_root.add_child(instance)
		_rooms[room_def.get("id", "")] = instance
		if str(room_def.get("templateId", "")).ends_with("_stairs"):
			STAIR_COLLISION.ensure_stair_collision(instance)


func _build_floor_shell(parent: Node3D) -> void:
	FloorShellBuilderScript.build(parent, _rooms, biome_id)


func _build_shortcut_corridors(parent: Node3D) -> void:
	var has_one_way := false
	for edge in definition.get("edges", []):
		if edge.get("kind", "") == "one_way":
			has_one_way = true
			break
	if not has_one_way:
		return
	# L-shaped shortcut mirrors DUNGEON-2.1 hand layout: hall south → corridor → vertical → stairs.
	var floor_mat := BiomeRegistry.get_floor_material(biome_id)
	var wall_mat := BiomeRegistry.get_wall_material(biome_id)
	var vertical := _create_shortcut_blockout(8.0, 18.0, true, true, false, false, floor_mat, wall_mat)
	vertical.name = "ShortcutVertical"
	vertical.position = Vector3(0.0, 0.0, 31.0)
	parent.add_child(vertical)
	var horizontal := _create_shortcut_blockout(18.0, 6.0, true, false, false, true, floor_mat, wall_mat)
	horizontal.name = "ShortcutCorridor"
	horizontal.position = Vector3(9.0, 0.0, 43.0)
	parent.add_child(horizontal)


func _create_shortcut_blockout(
	width: float,
	depth: float,
	door_north: bool,
	door_south: bool,
	door_east: bool,
	door_west: bool,
	floor_mat: Material,
	wall_mat: Material
) -> Node3D:
	var blockout_script := preload("res://scripts/dungeon/castle/castle_blockout.gd")
	var corridor := Node3D.new()
	var blockout := Node3D.new()
	blockout.set_script(blockout_script)
	blockout.set("room_width", width)
	blockout.set("room_depth", depth)
	blockout.set("door_north", door_north)
	blockout.set("door_south", door_south)
	blockout.set("door_east", door_east)
	blockout.set("door_west", door_west)
	blockout.set("floor_material", floor_mat)
	blockout.set("wall_material", wall_mat)
	blockout.set("skip_floor", true)
	corridor.add_child(blockout)
	return corridor


func _spawn_player() -> void:
	if _player == null:
		return
	var entrance_id: String = definition.get("placements", {}).get("entrance", "entrance")
	var entrance := get_room(entrance_id)
	if entrance:
		_player.global_position = entrance.get_player_spawn_global()
	_player.add_to_group("player")


func _placement_offset(placement: Dictionary) -> Vector3:
	var pos: Dictionary = placement.get("offset", placement.get("position", {}))
	return Vector3(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0)))


func _place_enemies() -> void:
	var placements: Array = definition.get("placements", {}).get("enemies", [])
	for i in range(placements.size()):
		_spawn_enemy(placements[i], i)


func _spawn_enemy(placement: Dictionary, index: int) -> void:
	var enemy_id: String = placement.get("enemyId", "")
	var scene := _get_enemy_scene(enemy_id)
	if scene == null:
		return
	var room := get_room(placement.get("roomId", ""))
	if room == null:
		return
	var placement_key := _enemy_placement_id(placement, index)
	var enemy: CharacterBody3D = scene.instantiate() as CharacterBody3D
	if enemy == null:
		return
	enemy.position = _placement_offset(placement)
	CharacterFloorSnapScript.snap_feet_to_floor(enemy)
	enemy.set_meta("placement_id", placement_key)
	if enemy.has_method("set_player"):
		enemy.call("set_player", _player)
	room.add_child(enemy)
	_apply_floor_scaling(enemy)
	_ensure_enemy_groups(enemy)
	_enemy_by_id[placement_key] = enemy
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_tracked_enemy_died.bind(placement_key))


func _place_loot() -> void:
	var placements: Array = definition.get("placements", {}).get("loot", [])
	for i in range(placements.size()):
		var placement: Dictionary = placements[i]
		var room := get_room(placement.get("roomId", ""))
		if room == null:
			continue
		var chest_key := _loot_placement_id(placement, i)
		var chest: Node3D = CHEST_SCENE.instantiate() as Node3D
		chest.position = _placement_offset(placement)
		chest.set_meta("chest_id", chest_key)
		if chest.has_method("configure"):
			chest.call("configure", placement)
		chest.set_meta("biome_id", biome_id)
		if chest.has_signal("opened"):
			chest.opened.connect(_on_chest_opened)
		room.add_child(chest)
		_chest_by_id[chest_key] = chest


func _trap_scene_for_id(trap_id: String) -> PackedScene:
	match trap_id:
		"falling_trap":
			return FALLING_TRAP_SCENE
		"poison_pool", "frost_trap":
			return POISON_POOL_SCENE
		"shadow_trap":
			return SPIKE_TRAP_SCENE
		_:
			return SPIKE_TRAP_SCENE


func _place_room_content() -> void:
	RoomContentSpawnerScript.spawn_all(self, definition)
	RoomContentSpawnerScript.spawn_locks(self, definition)


func _place_traps() -> void:
	for placement in definition.get("placements", {}).get("traps", []):
		var room := get_room(placement.get("roomId", ""))
		if room == null:
			continue
		var trap_id: String = placement.get("trapId", "")
		var scene: PackedScene = _trap_scene_for_id(trap_id)
		var trap: Node3D = scene.instantiate() as Node3D
		trap.position = _placement_offset(placement)
		trap.set_meta("biome_id", biome_id)
		room.add_child(trap)


func _setup_boss() -> void:
	var boss_placement: Variant = definition.get("placements", {}).get("boss")
	if boss_placement == null or not boss_placement is Dictionary:
		return
	var room := get_room(boss_placement.get("roomId", "boss"))
	if room == null:
		return
	var enemy_id: String = boss_placement.get("enemyId", "castle_knight")
	if _is_final_floor and biome_id == BiomeRegistry.BIOME_CASTLE:
		enemy_id = "final_boss_forgotten_castle"
	var scene := _get_enemy_scene(enemy_id)
	if scene == null and _is_final_floor:
		scene = FINAL_BOSS_SCENE
	if scene == null:
		return
	_boss = scene.instantiate() as Node
	_boss.set_meta("placement_id", "boss")
	room.add_child(_boss)
	_ensure_enemy_groups(_boss)
	var spawn := room.get_node_or_null("Props/BossSpawn") as Node3D
	if spawn:
		_boss.global_position = spawn.global_position
	else:
		_boss.position = Vector3.ZERO
	if _boss is CharacterBody3D:
		CharacterFloorSnapScript.snap_feet_to_floor(_boss as CharacterBody3D)
	if _boss.has_method("set_player"):
		_boss.call("set_player", _player)
	_apply_floor_scaling(_boss)
	if _boss.has_signal("boss_defeated"):
		_boss.boss_defeated.connect(_on_boss_defeated)
	_enemy_by_id["boss"] = _boss


func _setup_exit_portal() -> void:
	var exit_room_id: String = definition.get("placements", {}).get("exit", "boss")
	var room := get_room(exit_room_id)
	if room == null:
		return
	if room.get_node_or_null("Props/ExitPortal"):
		return
	_create_exit_portal(room)


func _create_exit_portal(room: RoomTemplate) -> Area3D:
	var portal := Area3D.new()
	portal.name = "ExitPortal"
	portal.collision_layer = 0
	portal.collision_mask = 2
	portal.monitoring = false
	portal.visible = false
	portal.set_script(EXIT_PORTAL_SCRIPT)
	var marker := room.get_node_or_null("Props/ExitPortalMarker") as Node3D
	if marker:
		portal.position = marker.position
	else:
		portal.position = Vector3(0, 1.5, 12)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 1)
	shape.shape = box
	portal.add_child(shape)
	DIORAMA_SKIN.build_exit_portal(portal, biome_id)
	var props := room.get_node_or_null("Props")
	if props:
		props.add_child(portal)
	return portal


func _on_boss_defeated() -> void:
	if _is_final_floor:
		open_exit_portal()
	else:
		_unlock_stair_lever()
	boss_defeated.emit()


func _setup_stair_levers() -> void:
	for room_id in _rooms:
		var room := get_room(room_id)
		if room == null:
			continue
		if not str(room.template_id).ends_with("_stairs"):
			continue
		_create_stair_lever(room)


func _create_stair_lever(room: RoomTemplate) -> void:
	var lever := Node3D.new()
	lever.name = "StairLever"
	lever.set_script(STAIR_LEVER_SCRIPT)
	var interact := Area3D.new()
	interact.name = "InteractArea"
	interact.collision_layer = 0
	interact.collision_mask = 2
	interact.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 3.0)
	shape.shape = box
	interact.add_child(shape)
	lever.add_child(interact)
	var label := Label3D.new()
	label.name = "Label3D"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 24
	label.position = Vector3(0.0, 2.5, 0.0)
	lever.add_child(label)
	DIORAMA_SKIN.build_lever(lever, biome_id)
	var props := room.get_node_or_null("Props")
	if props:
		props.add_child(lever)
	else:
		room.add_child(lever)
	_place_stair_lever_on_wall(lever, room)
	var can_ascend := not RunFlow.is_final_floor() or RunFlow.get_run_mode() == "endless"
	var can_descend := RunFlow.get_current_floor() > 1 and RunFlow.get_run_mode() != "endless"
	lever.call("configure", can_ascend, can_descend)
	_stair_lever = lever


func _place_stair_lever_on_wall(lever: Node3D, room: RoomTemplate) -> void:
	var spawn := room.get_node_or_null("SpawnPoints/LeverSpawn") as Node3D
	if spawn:
		lever.position = spawn.position
		lever.rotation = spawn.rotation
		return
	var blockout := room.get_blockout()
	var half_w := 4.0
	var half_d := 8.0
	if blockout:
		half_w = blockout.room_width * 0.5
		half_d = blockout.room_depth * 0.5
	# West wall, beside the ramp (not under it), facing into the room.
	lever.position = Vector3(-half_w + 0.55, 0.0, -half_d * 0.25)
	lever.rotation.y = PI * 0.5


func _unlock_stair_lever() -> void:
	if _stair_lever and _stair_lever.has_method("unlock"):
		var can_ascend := not RunFlow.is_final_floor() or RunFlow.get_run_mode() == "endless"
		var can_descend := RunFlow.get_current_floor() > 1 and RunFlow.get_run_mode() != "endless"
		var can_retreat := RunFlow.get_run_mode() in ["endless", "castle"]
		_stair_lever.call("configure", can_ascend, can_descend, can_retreat)
		_stair_lever.call("unlock")


func get_stair_lever() -> Node3D:
	return _stair_lever


func get_stair_spawn_global(stair_room_id: String, ascending: bool) -> Dictionary:
	var room := get_room(stair_room_id)
	if room == null:
		return {}
	var spawn := room.get_node_or_null("SpawnPoints/PlayerSpawn") as Node3D
	var pos := spawn.global_position if spawn else room.global_position + Vector3(0, 1.0, -4.0)
	return {
		"position": pos,
		"rotationY": RunFloorConfig.stairs_spawn_facing_y(room, ascending),
	}


func _setup_boss_door(castle_run: Node3D) -> void:
	var room := get_room("boss")
	if room == null:
		return
	var door := Node3D.new()
	door.name = "BossRoomDoor"
	var barrier := StaticBody3D.new()
	barrier.name = "Barrier"
	barrier.collision_layer = 1
	barrier.collision_mask = 0
	var barrier_shape := CollisionShape3D.new()
	var barrier_box := BoxShape3D.new()
	barrier_box.size = Vector3(
		CastleRoomConstants.DOOR_WIDTH,
		CastleRoomConstants.DOOR_HEIGHT,
		CastleRoomConstants.WALL_THICKNESS
	)
	barrier_shape.name = "BarrierShape"
	barrier_shape.shape = barrier_box
	barrier_shape.position = Vector3(0.0, CastleRoomConstants.DOOR_HEIGHT * 0.5, 0.0)
	barrier.add_child(barrier_shape)
	var barrier_mesh := MeshInstance3D.new()
	barrier_mesh.name = "MeshInstance3D"
	var mesh := BoxMesh.new()
	mesh.size = barrier_box.size
	barrier_mesh.mesh = mesh
	barrier_mesh.position = barrier_shape.position
	barrier_mesh.material_override = BiomeRegistry.get_wall_material(biome_id)
	barrier.add_child(barrier_mesh)
	door.add_child(barrier)

	var interact := Area3D.new()
	interact.name = "InteractArea"
	interact.collision_layer = 0
	interact.collision_mask = 2
	interact.monitoring = true
	var interact_shape := CollisionShape3D.new()
	var interact_box := BoxShape3D.new()
	interact_box.size = Vector3(5.0, 4.0, 3.0)
	interact_shape.shape = interact_box
	# North (-Z) of the barrier — arena side, where the player stops before opening.
	interact_shape.position = Vector3(0.0, 2.0, -2.0)
	interact.add_child(interact_shape)
	door.add_child(interact)

	var label := Label3D.new()
	label.name = "Label3D"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.position = Vector3(0.0, 4.0, -2.0)
	label.visible = false
	door.add_child(label)

	door.set_script(BOSS_DOOR_SCRIPT)
	DIORAMA_SKIN.build_boss_door_frame(door, biome_id)

	var socket := room.find_socket(CastleRoomConstants.Direction.NORTH)
	if socket:
		door.position = socket.position + Vector3(0.0, 0.0, -0.25)
	else:
		var blockout := room.get_blockout()
		var depth := blockout.room_depth if blockout else 28.0
		door.position = Vector3(0.0, 0.0, -depth * 0.5 + 0.25)

	room.add_child(door)
	_boss_door = door
	if castle_run.has_method("register_boss_door"):
		castle_run.call("register_boss_door", door)


func get_boss_door() -> Node3D:
	return _boss_door


func get_tracked_enemy(placement_id: String) -> Node:
	return _enemy_by_id.get(placement_id)


func get_spawned_enemy_count() -> int:
	return _enemy_by_id.size()


func get_boss_door_outside_spawn() -> Vector3:
	if _boss_door:
		# Arena side is local -Z (interact area faces the approach corridor).
		return _boss_door.global_position - _boss_door.global_transform.basis.z * 3.5
	var arena := get_room("arena")
	if arena:
		return arena.get_player_spawn_global()
	var entrance := get_room(definition.get("placements", {}).get("entrance", "entrance"))
	if entrance:
		return entrance.get_player_spawn_global()
	if _player:
		return _player.global_position
	return Vector3.ZERO


func capture_enemy_states() -> Dictionary:
	var states := {}
	for placement_id in _enemy_by_id:
		var enemy: Node = _enemy_by_id[placement_id]
		if enemy and is_instance_valid(enemy) and enemy.has_method("capture_state"):
			states[placement_id] = enemy.call("capture_state")
	return states


func capture_loot_states() -> Dictionary:
	var states := {}
	for chest_id in _chest_by_id:
		var chest: Node = _chest_by_id[chest_id]
		if chest and is_instance_valid(chest) and chest.has_method("is_opened"):
			states[chest_id] = { "opened": chest.call("is_opened") }
	return states


func apply_snapshot(snapshot: Dictionary) -> void:
	var enemies: Dictionary = snapshot.get("enemies", {})
	for placement_id in enemies:
		var enemy: Node = _enemy_by_id.get(placement_id)
		if enemy and is_instance_valid(enemy) and enemy.has_method("apply_state"):
			enemy.call("apply_state", enemies[placement_id])

	var loot_states: Dictionary = snapshot.get("loot", {})
	for chest_id in loot_states:
		var chest: Node = _chest_by_id.get(chest_id)
		if chest and is_instance_valid(chest) and chest.has_method("apply_opened_state"):
			chest.call("apply_opened_state", loot_states[chest_id].get("opened", false))

	if snapshot.get("bossDefeated", false):
		if _is_final_floor:
			open_exit_portal()
		else:
			_unlock_stair_lever()


func _ensure_enemy_groups(enemy: Node) -> void:
	if enemy == null:
		return
	if not enemy.is_in_group("enemy"):
		enemy.add_to_group("enemy")
	if not enemy.is_in_group("lockable"):
		enemy.add_to_group("lockable")


func _enemy_placement_id(placement: Dictionary, index: int) -> String:
	return "%s:%d" % [placement.get("roomId", ""), index]


func _loot_placement_id(placement: Dictionary, index: int) -> String:
	var chest_id: String = placement.get("chestId", "")
	if chest_id != "":
		return chest_id
	return "%s:%d" % [placement.get("roomId", ""), index]


func _on_tracked_enemy_died(_placement_id: String) -> void:
	snapshot_dirty.emit()


func _on_chest_opened() -> void:
	snapshot_dirty.emit()


func _get_enemy_scene(enemy_id: String) -> PackedScene:
	var scene := EnemyCatalog.get_scene(enemy_id)
	if scene:
		return scene
	if ENEMY_SCENES_FALLBACK.has(enemy_id):
		return ENEMY_SCENES_FALLBACK[enemy_id]
	push_warning("DungeonBuilder: unknown enemy id %s" % enemy_id)
	return null


func unload_from_parent(parent: Node3D) -> void:
	for room_id in _rooms.keys():
		var room: Node = _rooms[room_id]
		if is_instance_valid(room):
			room.queue_free()
	_rooms.clear()
	_enemy_by_id.clear()
	_chest_by_id.clear()
	_boss = null
	_boss_door = null
	_stair_lever = null
	if _entities and is_instance_valid(_entities):
		_entities.queue_free()
		_entities = null
	if parent:
		var rooms_root := parent.get_node_or_null("Rooms")
		if rooms_root:
			rooms_root.queue_free()
		for shortcut_name in ["ShortcutVertical", "ShortcutCorridor"]:
			var shortcut := parent.get_node_or_null(shortcut_name)
			if shortcut:
				shortcut.queue_free()


func _apply_floor_scaling(enemy: Node) -> void:
	var mode := RunFlow.get_run_mode()
	if mode == "endless":
		var floor_index := RunFlow.get_current_floor()
		var hp_mult := EndlessDifficultyScript.hp_multiplier(floor_index)
		var health := enemy.get_node_or_null("Health") as Health
		if health:
			health.configure(float(health.max_health) * hp_mult)
		if enemy.has_method("set_damage_multiplier"):
			enemy.call("set_damage_multiplier", EndlessDifficultyScript.damage_multiplier(floor_index))
		return
	if mode == "castle":
		var tier := RunFlow.get_dungeon_tier()
		var hp_mult := CastleTierDifficultyScript.hp_multiplier(tier)
		var health := enemy.get_node_or_null("Health") as Health
		if health:
			health.configure(float(health.max_health) * hp_mult)
		if enemy.has_method("set_damage_multiplier"):
			enemy.call("set_damage_multiplier", CastleTierDifficultyScript.damage_multiplier(tier))
