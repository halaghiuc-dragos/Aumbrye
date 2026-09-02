extends Node3D

const BossRewardHallScript := preload("res://scripts/dungeon/boss_reward_hall.gd")


const BUILDER_SCRIPT := preload("res://scripts/dungeon/dungeon_builder.gd")
const BOSS_ROOM_ID := "boss"
const BOSS_GATE_DEPTH_THRESHOLD := 4.0
const BossIntroScript := preload("res://scripts/ui/boss_intro_ui.gd")
const EpilogueCardScript := preload("res://scripts/ui/epilogue_card.gd")
const RelicOfferUIScript := preload("res://scripts/ui/relic_offer_ui.gd")
const StairMenuScript := preload("res://scripts/ui/stair_menu.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")
const XpShardPickupScript := preload("res://scripts/progression/xp_shard_pickup.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

@export var player_path: NodePath = NodePath("Player")
@export var hud_path: NodePath = NodePath("CombatHUD")

var player_room_id := ""
var _player: CharacterBody3D
var _builder: DungeonBuilder
var _boss_door: Node
var _boss_defeated := false
var _hud: Control
var _boss_intro: Control
var _epilogue_card: Control
var _relic_offer: Control
var _stair_menu: Control
var _boss_intro_shown := false
var _dungeon_def: Dictionary = {}
const SNAPSHOT_DEBOUNCE_SEC := 2.0
var _snapshot_dirty := false
var _snapshot_timer := 0.0


func _ready() -> void:
	add_to_group("castle_run")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as CharacterBody3D
	_builder = BUILDER_SCRIPT.new()
	add_child(_builder)
	_builder.boss_defeated.connect(_on_boss_defeated)
	_builder.snapshot_dirty.connect(_persist_snapshot)
	_builder.room_cleared.connect(_on_room_cleared)
	var def := _resolve_dungeon_definition()
	if def.is_empty():
		push_error("CastleRun: missing procgen dungeon definition")
		RunFlow.return_to_hub("Dungeon data missing — could not load generated layout.")
		return
	var player_process_mode := Node.PROCESS_MODE_INHERIT
	if _player:
		player_process_mode = _player.process_mode
		_player.process_mode = Node.PROCESS_MODE_DISABLED
	SceneTransition.claim(get_tree(), "Building the floor...")
	var report_build := func(ratio: float) -> void:
		SceneTransition.report_progress(get_tree(), ratio)
	if not _builder.build_progress.is_connected(report_build):
		_builder.build_progress.connect(report_build)
	await _builder.build_from_definition(self, _player, def, true)
	if _builder.build_progress.is_connected(report_build):
		_builder.build_progress.disconnect(report_build)
	SceneTransition.finish(get_tree())
	if _player:
		_player.process_mode = player_process_mode
	_apply_biome_presentation(def)
	_wire_run_ui(def)
	var snapshot := _take_run_snapshot_meta()
	_restore_saved_snapshot(snapshot)
	_apply_floor_transition_spawn(snapshot)
	player_room_id = _find_room_id_at(_player.global_position)
	_notify_room(player_room_id)
	call_deferred("_ensure_safe_player_spawn")
	_wire_player_death()
	_wire_player_health_autosave()
	_wire_weapon_from_inventory()
	_wire_inventory_autosave()
	_spawn_recoverable_xp_shard()
	_show_respawn_outcome_if_needed()
	InventoryService.apply_equipment_to_player_node(_player)
	_announce_floor_entry(def)
	AudioDirector.play_dungeon_ambience()
	set_physics_process(true)
	# One relic choice per ten-floor block, offered at the block's first floor rather than its
	# boss -- consistent with why the very first one moved off the first boss to begin with (see
	# `_offer_opening_umbral`), and the only way to keep the count exactly one per block: the old
	# scheme also handed one out at every floor's boss, which is one a floor rather than one a
	# block.
	var offer_umbral := (
		not RunFlow.is_continue_restore()
		and RunFloorConfig.floor_within_block(RunFlow.get_current_floor()) == 1
		and not RunFlow.has_floor_transition()
	)
	RunFlow.clear_continue_restore()
	call_deferred("_persist_snapshot")
	call_deferred("_apply_pixel_diorama_scene")
	if offer_umbral:
		call_deferred("_offer_opening_umbral")


func _apply_biome_presentation(def: Dictionary) -> void:
	var biome_id := BiomeRegistry.resolve_biome_id(def)
	BiomeRegistry.apply_run_presentation(self, biome_id, RunFlow.get_run_mode())
	_apply_player_viewmodel_theme(PixelStyle.theme_from_biome(biome_id))


func _apply_player_viewmodel_theme(theme: int) -> void:
	if _player == null:
		return
	var director := _player.get_node_or_null("AnimDirector")
	if director and director.has_method("set_viewmodel_theme"):
		director.call("set_viewmodel_theme", theme)


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
	if _snapshot_dirty:
		_snapshot_timer += _delta
		if _snapshot_timer >= SNAPSHOT_DEBOUNCE_SEC:
			_snapshot_timer = 0.0
			_snapshot_dirty = false
			_persist_snapshot()
	var room_id := _find_room_id_at(_player.global_position)
	if room_id != "" and room_id != player_room_id:
		player_room_id = room_id
		_notify_room(room_id)
		_persist_snapshot()
	if (
		_boss_door
		and not _boss_defeated
		and _boss_door.call("is_opened")
		and _is_player_deep_in_boss_room()
	):
		if not _boss_door.call("is_sealed"):
			_boss_door.call("seal_door")
			_persist_snapshot()


func _wire_run_ui(def: Dictionary) -> void:
	_dungeon_def = def
	_hud = get_node_or_null(hud_path) as Control
	if _hud and _hud.has_method("configure_minimap"):
		_hud.call("configure_minimap", def)
	_boss_intro = BossIntroScript.new()
	add_child(_boss_intro)
	_epilogue_card = EpilogueCardScript.new()
	add_child(_epilogue_card)
	_relic_offer = RelicOfferUIScript.new()
	_relic_offer.name = "RelicOfferUI"
	add_child(_relic_offer)
	_stair_menu = StairMenuScript.new()
	add_child(_stair_menu)


func _show_respawn_outcome_if_needed() -> void:
	var root := get_tree().root
	if not root.has_meta("run_respawn_results"):
		return
	var results: Variant = root.get_meta("run_respawn_results")
	root.remove_meta("run_respawn_results")
	if results is Dictionary and _hud and _hud.has_method("show_respawn_outcome"):
		_hud.call("show_respawn_outcome", results)


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
		AudioDirector.play_stinger("boss_reveal")
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


func _on_room_cleared(room_id: String) -> void:
	if _hud and _hud.has_method("mark_room_cleared"):
		_hud.call("mark_room_cleared", room_id)


func _announce_floor_entry(def: Dictionary) -> void:
	if _hud and _hud.has_method("set_minimap_fog_of_war"):
		(
			_hud
			. call(
				"set_minimap_fog_of_war",
				RunModifierService.has_modifier(RunModifierService.MODIFIER_FOG_OF_WAR)
			)
		)
	if CombatEvents and _player:
		CombatEvents.dispatch(CombatEvents.ON_FLOOR_ENTER, {"actor": _player})
	if _hud == null or not _hud.has_method("show_region_title"):
		return
	var biome_id := BiomeRegistry.resolve_biome_id(def)
	if RunFlow.get_run_mode() != "endless":
		var theme_label := str(def.get("floorThemeLabel", ""))
		if theme_label != "":
			_hud.call("show_region_title", "Floor %d" % RunFlow.get_current_floor(), theme_label)
		return
	if not RunFlow.consume_pending_region_card():
		return
	var region_name := BiomeRegistry.get_display_name(biome_id)
	if region_name == "":
		return
	_hud.call(
		"show_region_title", region_name, "Floor %d" % RunFlow.get_current_floor()
	)


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
		Vector3(float(shard.get("x", 0.0)), float(shard.get("y", 0.0)), float(shard.get("z", 0.0))),
		int(shard.get("xp", 0)),
		int(shard.get("gold", 0))
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


func _get_boss_room_id() -> String:
	var boss_placement: Variant = _dungeon_def.get("placements", {}).get("boss", {})
	if boss_placement is Dictionary:
		return str(boss_placement.get("roomId", BOSS_ROOM_ID))
	return BOSS_ROOM_ID


func _is_player_deep_in_boss_room() -> bool:
	var room := _builder.get_room(_get_boss_room_id())
	if room == null or _player == null:
		return false
	var local := room.to_local(_player.global_position)
	var blockout := room.get_blockout()
	var half_d := (blockout.room_depth if blockout else 28.0) * 0.5
	return local.z > -half_d + BOSS_GATE_DEPTH_THRESHOLD


func _is_in_boss_fight() -> bool:
	if _boss_defeated or _player == null:
		return false
	return _find_room_id_at(_player.global_position) == _get_boss_room_id()


func is_cross_boss_boundary(attacker: Node, target: Node) -> bool:
	var attacker_room := _get_entity_room_id(attacker)
	var target_room := _get_entity_room_id(target)
	if attacker_room == _get_boss_room_id() or target_room == _get_boss_room_id():
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
	if AudioDirector:
		AudioDirector.notify_player_vitality(_current / maxf(_max_value, 0.001))
	_snapshot_dirty = true


func _wire_weapon_from_inventory() -> void:
	var weapon := _player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("load_weapon_from_path"):
		weapon.load_weapon_from_path(InventoryService.inventory.get_equipped_weapon_data_path())


func _wire_inventory_autosave() -> void:
	if not InventoryService.inventory_changed.is_connected(_on_inventory_changed):
		InventoryService.inventory_changed.connect(_on_inventory_changed)


func _on_inventory_changed() -> void:
	_persist_snapshot()


func _take_run_snapshot_meta() -> Dictionary:
	var root := get_tree().root
	if not root.has_meta("run_snapshot"):
		return {}
	var snapshot: Variant = root.get_meta("run_snapshot")
	root.remove_meta("run_snapshot")
	if snapshot is Dictionary:
		return snapshot
	return {}


func _apply_floor_transition_spawn(snapshot: Dictionary = {}) -> void:
	if snapshot.is_empty():
		return
	if bool(snapshot.get("restartFloor", false)):
		_teleport_to_safe_spawn({})
		return
	if bool(snapshot.get("floorTransition", false)):
		_place_at_stair_from_snapshot(snapshot)


func _place_at_stair_from_snapshot(snapshot: Dictionary) -> void:
	var ascending := bool(snapshot.get("ascending", true))
	var stair_id := RunFloorConfig.find_stairs_room_id(_dungeon_def)
	var spawn_info := _builder.get_stair_spawn_global(stair_id, ascending)
	if spawn_info.is_empty():
		return
	_player.global_position = spawn_info.get("position", _player.global_position)
	_player.rotation.y = float(spawn_info.get("rotationY", _player.rotation.y))
	player_room_id = stair_id


func _restore_saved_snapshot(snapshot: Dictionary = {}) -> void:
	if snapshot.is_empty():
		return
	_apply_snapshot(snapshot)


func _apply_snapshot(snapshot: Dictionary) -> void:
	var rejected := WorldState.restore_flags(snapshot.get("worldFlags", {}))
	if rejected > 0:
		push_warning("CastleRun: dropped %d invalid world flag(s) from snapshot" % rejected)
	_builder.apply_snapshot(snapshot)
	_boss_defeated = snapshot.get("bossDefeated", false)
	var door_state := str(snapshot.get("bossDoorState", ""))
	if door_state == "":
		door_state = "RELEASED" if _boss_defeated else "CLOSED"
	if _boss_door and _boss_door.has_method("apply_state"):
		_boss_door.call("apply_state", door_state)
	elif _boss_defeated and _boss_door:
		_boss_door.call("release_door")
	if _boss_defeated:
		_open_boss_reward_hall()

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
		CharacterFloorSnapScript.snap_feet_to_world_y(_player, floor_y)
	elif _find_room_id_at(_player.global_position) == "":
		_teleport_to_safe_spawn(snapshot)


func _ensure_safe_player_spawn() -> void:
	if _player == null:
		return
	await get_tree().physics_frame
	CharacterFloorSnapScript.snap_to_floor_below(_player)
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
			CharacterFloorSnapScript.snap_to_floor_below(_player)
			player_room_id = room_id
			return
	var entrance_id := str(_dungeon_def.get("placements", {}).get("entrance", "entrance"))
	var entrance := _builder.get_room(entrance_id)
	if entrance != null:
		_player.global_position = entrance.get_player_spawn_global()
		CharacterFloorSnapScript.snap_to_floor_below(_player)
		player_room_id = entrance_id


func _apply_boss_fight_continue() -> void:
	if _boss_door and _boss_door.has_method("reset_door"):
		_boss_door.call("reset_door")
	var boss: Node = _builder.get_tracked_enemy("boss")
	if boss and is_instance_valid(boss) and boss.has_method("apply_state"):
		boss.call("apply_state", {"alive": true})
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
		"player":
		{
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
		"bossDoorState": (
			_boss_door.call("get_state_name")
			if _boss_door and _boss_door.has_method("get_state_name")
			else ""
		),
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
	active["schemaVersion"] = SaveMigrator.CURRENT_VERSION
	active["lastCheckpoint"] = snapshot.duplicate(true)
	active["snapshot"] = snapshot.duplicate(true)
	LocalSave.set_active_run(active)
	LocalSave.autosave_checkpoint()


func _persist_snapshot() -> void:
	if not _should_persist_snapshot():
		return
	var snapshot := _capture_run_snapshot()
	if snapshot.is_empty():
		return
	var active := LocalSave.get_active_run()
	if active.is_empty():
		return
	active["schemaVersion"] = SaveMigrator.CURRENT_VERSION
	active["snapshot"] = snapshot
	LocalSave.set_active_run(active)


## The umbral the shard carries. A separate offer key from the opening umbral so listening to a
## dead warden cannot re-roll the choice the run opened with.
func offer_umbral_relic() -> void:
	if _relic_offer == null or not is_instance_valid(_relic_offer):
		return
	if not _relic_offer.has_method("open_offer"):
		return
	_relic_offer.call("open_offer", "shard:%d:%d" % [RunFlow.current_seed, RunFlow.current_floor])


## The opening umbral. A relic choice before the first room, so the player knows what this run is
## about inside the first minute instead of finding out at the first boss. Seeded on the run and
## the block, so the same seed always opens the same three at a given block, and each ten-floor
## block rolls its own set rather than repeating the first one.
func _offer_opening_umbral() -> void:
	if _relic_offer == null or not is_instance_valid(_relic_offer):
		return
	if not _relic_offer.has_method("open_offer"):
		return
	var block := RunFloorConfig.block_index(RunFlow.get_current_floor())
	_relic_offer.call("open_offer", "umbral:%d:%d" % [RunFlow.current_seed, block])


func _on_boss_defeated() -> void:
	_boss_defeated = true
	if _hud and _hud.has_method("unbind_boss"):
		_hud.call("unbind_boss")
	RunFlow.register_boss_defeated()
	if _boss_door:
		_boss_door.call("release_door")
	AudioDirector.play_stinger("floor_clear")
	# Restocked here and not in `_open_boss_reward_hall`, which also runs on restore: refilling the
	# shelves on every reload would turn a three-potion stock into an unlimited one.
	BossRewardHallScript.restock_for_floor()
	_open_boss_reward_hall()


## Puts the merchant and the way home into the boss room once the boss is down.
##
## Also runs when a saved run is restored onto a floor that was already cleared, so a player who
## quits in the boss room and comes back still finds them there.
func _open_boss_reward_hall() -> void:
	if not _boss_defeated:
		return
	var room := _builder.get_room(_get_boss_room_id())
	if room == null:
		return
	if BossRewardHallScript.is_open_in(room):
		return
	var hall := BossRewardHallScript.new()
	hall.name = BossRewardHallScript.HALL_NAME
	room.add_child(hall)
	hall.setup(RunFlow.current_biome_id)
	AudioDirector.play_dungeon_ambience()
	_persist_snapshot()
	if RunFlow.is_final_floor() and RunFlow.get_run_mode() == "castle":
		CharacterService.set_flag("story_completed", true)
		if _epilogue_card and _epilogue_card.has_method("show_epilogue"):
			await (
				_epilogue_card
				. call(
					"show_epilogue",
					(
						"The Forgotten Sovereign falls. The tower's reset slows — for one breath the oath is fulfilled. "
						+ "Your umbral endures in Aumbrye Tower until the next summons."
					)
				)
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
	var reactions := _player.get_node_or_null("CombatReactions")
	var reactions_dead := reactions != null and bool(reactions.get("is_dead"))
	var health_value := health.current if health else 0.0
	var is_dead := health.is_dead() if health else false
	return should_persist_player_state(health_value, is_dead, reactions_dead)


static func should_persist_player_state(
	health: float, is_dead: bool, reactions_dead: bool = false
) -> bool:
	if is_dead or reactions_dead:
		return false
	if health <= 0.0:
		return false
	return true


func _apply_pixel_diorama_scene() -> void:
	PixelDioramaBootstrap.attach(self)
