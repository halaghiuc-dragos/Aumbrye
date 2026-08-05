extends Node3D

## Castle run scene controller — uses DungeonBuilder as authoritative path.

const BUILDER_SCRIPT := preload("res://scripts/dungeon/dungeon_builder.gd")
const BOSS_ROOM_ID := "boss"
const BOSS_GATE_DEPTH_THRESHOLD := 4.0
const BossIntroScript := preload("res://scripts/ui/boss_intro_ui.gd")
const EpilogueCardScript := preload("res://scripts/ui/epilogue_card.gd")
const StairMenuScript := preload("res://scripts/ui/stair_menu.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")
const XpShardPickupScript := preload("res://scripts/progression/xp_shard_pickup.gd")

@export var player_path: NodePath = NodePath("Player")
@export var hud_path: NodePath = NodePath("CombatHUD")
@export var inventory_ui_path: NodePath = NodePath("InventoryUI")

var player_room_id := ""
var _player: CharacterBody3D
var _builder: DungeonBuilder
var _boss_door: Node
var _boss_defeated := false
var _hud: Control
var _boss_intro: Control
var _epilogue_card: Control
var _stair_menu: Control
var _boss_intro_shown := false
var _dungeon_def: Dictionary = {}


func _ready() -> void:
	add_to_group("castle_run")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as CharacterBody3D
	_builder = BUILDER_SCRIPT.new()
	add_child(_builder)
	_builder.boss_defeated.connect(_on_boss_defeated)
	_builder.snapshot_dirty.connect(_persist_snapshot)
	var def := _resolve_dungeon_definition()
	if def.is_empty():
		push_error("CastleRun: missing procgen dungeon definition")
		RunFlow.return_to_hub("Dungeon data missing — could not load generated layout.")
		return
	_builder.build_from_definition(self, _player, def)
	_apply_biome_presentation(def)
	_wire_run_ui(def)
	_restore_saved_snapshot()
	_apply_floor_transition_spawn()
	player_room_id = _find_room_id_at(_player.global_position)
	call_deferred("_ensure_safe_player_spawn")
	_wire_player_death()
	_wire_player_health_autosave()
	_wire_weapon_from_inventory()
	_wire_inventory_autosave()
	_spawn_recoverable_xp_shard()
	InventoryService.apply_equipment_to_player_node(_player)
	AudioDirector.play_dungeon_ambience()
	set_physics_process(true)
	RunFlow.clear_continue_restore()
	call_deferred("_persist_snapshot")
	call_deferred("_apply_pixel_diorama_scene")



func _apply_biome_presentation(def: Dictionary) -> void:
	var biome_id := BiomeRegistry.resolve_biome_id(def)
	BiomeRegistry.apply_run_presentation(self, biome_id, RunFlow.get_run_mode())


func _resolve_dungeon_definition() -> Dictionary:
	var def: Dictionary = RunFlow.current_dungeon_definition
	if def.is_empty() and get_tree().root.has_meta("dungeon_definition"):
		var meta_def: Variant = get_tree().root.get_meta("dungeon_definition")
		if meta_def is Dictionary:
			def = meta_def
	if def.is_empty():
		return {}
	return def.duplicate(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_persist_snapshot()


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	var room_id := _find_room_id_at(_player.global_position)
	if room_id != "" and room_id != player_room_id:
		player_room_id = room_id
		_notify_room(room_id)
		_persist_snapshot()
	if _boss_door and not _boss_defeated and _boss_door.call("is_opened") and _is_player_deep_in_boss_room():
		if not _boss_door.call("is_sealed"):
			_boss_door.call("seal_door")
			_persist_snapshot()


func respawn_enemies() -> void:
	_builder.respawn_enemies()


func _wire_run_ui(def: Dictionary) -> void:
	_dungeon_def = def
	_hud = get_node_or_null(hud_path) as Control
	if _hud and _hud.has_method("configure_minimap"):
		_hud.call("configure_minimap", def)
	_boss_intro = BossIntroScript.new()
	add_child(_boss_intro)
	_epilogue_card = EpilogueCardScript.new()
	add_child(_epilogue_card)
	_stair_menu = StairMenuScript.new()
	add_child(_stair_menu)
	_notify_room(player_room_id)


func _notify_room(room_id: String) -> void:
	if room_id == "":
		return
	if _hud:
		if _hud.has_method("mark_room_visited"):
			_hud.call("mark_room_visited", room_id)
		if _hud.has_method("set_current_room"):
			_hud.call("set_current_room", room_id)
	_update_branch_previews(room_id)
	_update_objective_for_room(room_id)
	if room_id == BOSS_ROOM_ID and not _boss_intro_shown:
		_boss_intro_shown = true
		var boss_placement: Variant = _dungeon_def.get("placements", {}).get("boss", {})
		var boss_id := "boss_castle_knight"
		if boss_placement is Dictionary:
			boss_id = str(boss_placement.get("enemyId", boss_id))
		if _boss_intro and _boss_intro.has_method("show_intro"):
			_boss_intro.call("show_intro", boss_id)
		if _hud and _hud.has_method("bind_boss") and _builder and _builder.has_method("get_boss"):
			var boss: Node = _builder.get_boss()
			if boss:
				_hud.call("bind_boss", boss)


func _update_branch_previews(room_id: String) -> void:
	if _hud == null or not _hud.has_method("set_branch_previews"):
		return
	var hints: Array = []
	for preview in _dungeon_def.get("branchPreviews", []):
		if preview is Dictionary and str(preview.get("fromRoomId", "")) == room_id:
			hints.append(preview)
	_hud.call("set_branch_previews", hints)


func _spawn_recoverable_xp_shard() -> void:
	var shard: Dictionary = RunFlow.get_recoverable_xp_shard()
	if shard.is_empty():
		return
	if int(shard.get("floor", 0)) != RunFlow.get_current_floor():
		return
	if str(shard.get("dungeonId", "")) != RunFlow.current_dungeon_id:
		return
	var pickup: Area3D = XpShardPickupScript.new()
	pickup.name = "XpShardPickup"
	add_child(pickup)
	pickup.configure(
		Vector3(
			float(shard.get("x", 0.0)),
			float(shard.get("y", 0.0)),
			float(shard.get("z", 0.0))
		),
		int(shard.get("xp", 0))
	)


func _update_objective_for_room(room_id: String) -> void:
	if _hud == null or not _hud.has_method("set_objective_world_position"):
		return
	var stair_id := RunFloorConfig.find_stairs_room_id(_dungeon_def)
	if room_id == stair_id or stair_id == "":
		var boss_placement: Variant = _dungeon_def.get("placements", {}).get("boss", {})
		var boss_room_id := BOSS_ROOM_ID
		if boss_placement is Dictionary:
			boss_room_id = str(boss_placement.get("roomId", BOSS_ROOM_ID))
		var boss_room := _builder.get_room(boss_room_id)
		if boss_room:
			_hud.call("set_objective_world_position", boss_room.global_position)
	else:
		var stairs := _builder.get_room(stair_id)
		if stairs:
			_hud.call("set_objective_world_position", stairs.global_position)


func register_boss_door(door: Node) -> void:
	_boss_door = door
	if door.has_signal("door_opened") and not door.door_opened.is_connected(_on_boss_door_opened):
		door.door_opened.connect(_on_boss_door_opened)
	if door.has_signal("door_sealed") and not door.door_sealed.is_connected(_persist_snapshot):
		door.door_sealed.connect(_persist_snapshot)


func _on_boss_door_opened() -> void:
	_persist_snapshot()


func _is_player_deep_in_boss_room() -> bool:
	var room := _builder.get_room(BOSS_ROOM_ID)
	if room == null or _player == null:
		return false
	var local := room.to_local(_player.global_position)
	var blockout := room.get_blockout()
	var half_d := (blockout.room_depth if blockout else 28.0) * 0.5
	return local.z > -half_d + BOSS_GATE_DEPTH_THRESHOLD


func _is_in_boss_fight() -> bool:
	if _boss_defeated or _player == null:
		return false
	return _find_room_id_at(_player.global_position) == BOSS_ROOM_ID


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


func _wire_player_health_autosave() -> void:
	if _player == null:
		return
	var health := _player.get_node_or_null("Health") as Health
	if health and not health.health_changed.is_connected(_on_player_health_changed):
		health.health_changed.connect(_on_player_health_changed)


func _on_player_health_changed(_current: float, _max_value: float) -> void:
	_persist_snapshot()


func _wire_weapon_from_inventory() -> void:
	var weapon := _player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("load_weapon_from_path"):
		weapon.load_weapon_from_path(InventoryService.inventory.get_equipped_weapon_data_path())


func _wire_inventory_autosave() -> void:
	if not InventoryService.inventory_changed.is_connected(_on_inventory_changed):
		InventoryService.inventory_changed.connect(_on_inventory_changed)


func _on_inventory_changed() -> void:
	_persist_snapshot()


func _apply_floor_transition_spawn() -> void:
	var root := get_tree().root
	if not root.has_meta("run_snapshot"):
		return
	var snapshot: Variant = root.get_meta("run_snapshot")
	if not snapshot is Dictionary:
		return
	if not snapshot.get("floorTransition", false):
		return
	var ascending := bool(snapshot.get("ascending", true))
	var stair_id := RunFloorConfig.find_stairs_room_id(_resolve_dungeon_definition())
	var spawn_info := _builder.get_stair_spawn_global(stair_id, ascending)
	if spawn_info.is_empty():
		return
	_player.global_position = spawn_info.get("position", _player.global_position)
	_player.rotation.y = float(spawn_info.get("rotationY", _player.rotation.y))
	player_room_id = stair_id


func _restore_saved_snapshot() -> void:
	var root := get_tree().root
	if not root.has_meta("run_snapshot"):
		return
	var snapshot: Variant = root.get_meta("run_snapshot")
	if not snapshot is Dictionary or snapshot.is_empty():
		return
	_apply_snapshot(snapshot)
	root.remove_meta("run_snapshot")


func _apply_snapshot(snapshot: Dictionary) -> void:
	WorldState.restore_flags(snapshot.get("worldFlags", {}))
	_builder.apply_snapshot(snapshot)
	_boss_defeated = snapshot.get("bossDefeated", false)
	if _boss_defeated and _boss_door:
		_boss_door.call("release_door")

	if snapshot.get("inBossFight", false):
		_apply_boss_fight_continue()
		_restore_player_health(snapshot.get("player", {}))
	elif snapshot.has("player"):
		var player_state: Dictionary = snapshot.get("player", {})
		_player.global_position = Vector3(
			float(player_state.get("x", _player.global_position.x)),
			float(player_state.get("y", _player.global_position.y)),
			float(player_state.get("z", _player.global_position.z))
		)
		_player.rotation.y = float(player_state.get("rotationY", _player.rotation.y))
		_restore_player_health(player_state)

	if snapshot.has("playerRoomId"):
		player_room_id = str(snapshot.get("playerRoomId", player_room_id))
	call_deferred("_finalize_player_restore", snapshot)


func _finalize_player_restore(snapshot: Dictionary) -> void:
	if _player == null:
		return
	await get_tree().physics_frame
	var floor_y := _raycast_floor_y(_player.global_position)
	if not is_nan(floor_y):
		CharacterFloorSnapScript.snap_feet_to_floor(_player, floor_y)
	elif _find_room_id_at(_player.global_position) == "":
		_teleport_to_safe_spawn(snapshot)


func _ensure_safe_player_spawn() -> void:
	if _player == null:
		return
	await get_tree().physics_frame
	CharacterFloorSnapScript.snap_feet_to_floor(_player)
	if _find_room_id_at(_player.global_position) == "":
		_teleport_to_safe_spawn({})


func _raycast_floor_y(world_pos: Vector3) -> float:
	var space := _player.get_world_3d().direct_space_state
	if space == null:
		return NAN
	var from := world_pos + Vector3(0.0, 3.0, 0.0)
	var to := world_pos + Vector3(0.0, -24.0, 0.0)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 1
	params.collide_with_areas = false
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return NAN
	var hit_pos: Vector3 = hit.get("position", world_pos)
	return hit_pos.y


func _teleport_to_safe_spawn(snapshot: Dictionary) -> void:
	var room_id := str(snapshot.get("playerRoomId", player_room_id))
	if room_id != "":
		var room := _builder.get_room(room_id)
		if room != null:
			_player.global_position = room.get_player_spawn_global()
			CharacterFloorSnapScript.snap_feet_to_floor(_player)
			player_room_id = room_id
			return
	var entrance_id := str(_resolve_dungeon_definition().get("placements", {}).get("entrance", "entrance"))
	var entrance := _builder.get_room(entrance_id)
	if entrance != null:
		_player.global_position = entrance.get_player_spawn_global()
		CharacterFloorSnapScript.snap_feet_to_floor(_player)
		player_room_id = entrance_id


func _apply_boss_fight_continue() -> void:
	if _boss_door and _boss_door.has_method("reset_door"):
		_boss_door.call("reset_door")
	var boss: Node = _builder.get_tracked_enemy("boss")
	if boss and is_instance_valid(boss) and boss.has_method("apply_state"):
		boss.call("apply_state", { "alive": true })
	_player.global_position = _builder.get_boss_door_outside_spawn()
	player_room_id = _find_room_id_at(_player.global_position)


func _restore_player_health(player_state: Dictionary) -> void:
	if player_state.is_empty() or _player == null:
		return
	var health := _player.get_node_or_null("Health") as Health
	if health == null or not player_state.has("health"):
		return
	health.restore_current(float(player_state.get("health", health.current)))


func _capture_run_snapshot() -> Dictionary:
	if _player == null:
		return {}
	var player_health := 0.0
	var health := _player.get_node_or_null("Health") as Health
	if health:
		player_health = health.current
	return {
		"player": {
			"x": _player.global_position.x,
			"y": _player.global_position.y,
			"z": _player.global_position.z,
			"rotationY": _player.rotation.y,
			"health": player_health,
		},
		"playerRoomId": player_room_id,
		"currentFloor": RunFlow.get_current_floor(),
		"enemies": _builder.capture_enemy_states(),
		"loot": _builder.capture_loot_states(),
		"bossDefeated": _boss_defeated,
		"inBossFight": _is_in_boss_fight(),
		"killCount": RunFlow.get_kill_count(),
		"lootCollected": RunFlow.get_loot_collected(),
		"lootClaimedInstanceIds": RunFlow.get_loot_claimed_instance_ids(),
		"worldFlags": WorldState.all_flags(),
	}


func persist_bonfire_checkpoint() -> void:
	_builder.respawn_enemies()
	var snapshot := _capture_run_snapshot()
	if snapshot.is_empty():
		return
	var active := LocalSave.get_active_run()
	if active.is_empty():
		return
	active["schemaVersion"] = 4
	active["lastCheckpoint"] = snapshot.duplicate(true)
	active["snapshot"] = snapshot.duplicate(true)
	LocalSave.set_active_run(active)
	LocalSave.autosave()


func _persist_snapshot() -> void:
	if not _should_persist_snapshot():
		return
	var snapshot := _capture_run_snapshot()
	if snapshot.is_empty():
		return
	var active := LocalSave.get_active_run()
	if active.is_empty():
		return
	active["schemaVersion"] = 4
	active["snapshot"] = snapshot
	LocalSave.set_active_run(active)


func _on_boss_defeated() -> void:
	_boss_defeated = true
	if _hud and _hud.has_method("unbind_boss"):
		_hud.call("unbind_boss")
	RunFlow.register_boss_defeated()
	if _boss_door:
		_boss_door.call("release_door")
	AudioDirector.play_dungeon_ambience()
	_persist_snapshot()
	if RunFlow.is_final_floor() and RunFlow.get_run_mode() == "castle":
		CharacterService.set_flag("story_completed", true)
		if _epilogue_card and _epilogue_card.has_method("show_epilogue"):
			await _epilogue_card.call(
				"show_epilogue",
				"The Forgotten Sovereign falls. The tower's reset slows — for one breath the oath is fulfilled. "
				+ "Your echo endures in Aumbrye Tower until the next summons."
			)


func _on_player_died() -> void:
	if _boss_door:
		_boss_door.call("release_door")
	await get_tree().create_timer(1.5).timeout
	RunFlow.on_player_died()


func _should_persist_snapshot() -> bool:
	if not RunFlow.is_run_active() or _player == null:
		return false
	var health := _player.get_node_or_null("Health") as Health
	if health and health.is_dead():
		return false
	var reactions := _player.get_node_or_null("CombatReactions")
	if reactions and reactions.get("is_dead"):
		return false
	return true


func _apply_pixel_diorama_scene() -> void:
	PixelDioramaBootstrap.attach(self)
