extends Node3D

## Aumbrye Outskirts (Umbral Waves) — open meadow, lobby chests, wave combat.

const ENEMY_SCENES := {
	"castle_grunt": preload("res://scenes/enemies/castle_grunt.tscn"),
	"castle_archer": preload("res://scenes/enemies/castle_archer.tscn"),
	"castle_shield": preload("res://scenes/enemies/castle_shield.tscn"),
	"castle_knight": preload("res://scenes/enemies/castle_knight.tscn"),
	"castle_hound": preload("res://scenes/enemies/castle_hound.tscn"),
	"boss_castle_knight": preload("res://scenes/enemies/castle_knight.tscn"),
}

@export var player_path: NodePath = NodePath("Player")

var _player: CharacterBody3D
var _walls: Array[StaticBody3D] = []
var _chest_nodes: Array[Node3D] = []
var _active_enemies: Array[Node] = []
var _wave_ui: Control
var _lobby_active := true
var _prep_countdown := 0.0
const WavesOutdoorsDioramaScript := preload("res://scripts/dungeon/waves_outdoors_diorama.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")

var _bird_time := 0.0


func _ready() -> void:
	add_to_group("waves_run")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as CharacterBody3D
	_build_arena()
	_build_ui()
	_build_combat_hud()
	if WavesRunService.lobby_ready and WavesRunService.current_wave > 0:
		_start_combat_from_continue()
	else:
		_show_lobby()
	_restore_waves_snapshot()
	_persist_waves_save()
	if _player:
		WavesRunService.apply_equipment_to_player(_player)
		_wire_player_death()
	call_deferred("_apply_pixel_diorama_scene")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_persist_waves_save()


func _build_arena() -> void:
	WavesOutdoorsDioramaScript.apply(self)
	AudioDirector.set_biome(BiomeRegistry.BIOME_UMBRAL)
	_build_walls(true)


func _build_walls(enabled: bool) -> void:
	for wall in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()
	if not enabled:
		return
	var half := WavesOutdoorsDioramaScript.ARENA_HALF
	var span := half * 2.0
	var wall_h := CastleRoomConstants.WALL_HEIGHT
	var specs := [
		{"pos": Vector3(0.0, wall_h * 0.5, -half), "size": Vector3(span, wall_h, 1.0)},
		{"pos": Vector3(0.0, wall_h * 0.5, half), "size": Vector3(span, wall_h, 1.0)},
		{"pos": Vector3(-half, wall_h * 0.5, 0.0), "size": Vector3(1.0, wall_h, span)},
		{"pos": Vector3(half, wall_h * 0.5, 0.0), "size": Vector3(1.0, wall_h, span)},
	]
	for spec in specs:
		var wall := StaticBody3D.new()
		wall.name = "WaveWall"
		var shape := CollisionShape3D.new()
		var col := BoxShape3D.new()
		col.size = spec["size"]
		shape.shape = col
		wall.add_child(shape)
		wall.position = spec["pos"]
		wall.collision_layer = 1
		wall.collision_mask = 0
		add_child(wall)
		_walls.append(wall)


func _build_ui() -> void:
	_wave_ui = Control.new()
	_wave_ui.name = "WavesUI"
	_wave_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	var script := load("res://scripts/ui/waves_run_ui.gd")
	if script:
		_wave_ui.set_script(script)
	add_child(_wave_ui)


func _show_lobby() -> void:
	_lobby_active = true
	_build_walls(true)
	_spawn_chests()
	if _player:
		_player.global_position = Vector3(0, 0, 0)
	if _wave_ui and _wave_ui.has_method("show_lobby"):
		_wave_ui.call("show_lobby")


func _spawn_chests() -> void:
	for chest in _chest_nodes:
		if is_instance_valid(chest):
			chest.queue_free()
	_chest_nodes.clear()
	var chest_script := load("res://scripts/dungeon/waves_chest.gd")
	for i in WavesRunService.get_chest_count():
		var chest := Node3D.new()
		chest.name = "WavesChest_%d" % i
		chest.set_script(chest_script)
		var angle := float(i) / float(WavesRunService.get_chest_count()) * TAU
		chest.position = Vector3(cos(angle) * 14.0, 0.0, sin(angle) * 14.0)
		add_child(chest)
		chest.call("configure", i)
		if WavesRunService.chests_opened.get(str(i), false):
			chest.call("apply_opened_state", true)
		_chest_nodes.append(chest)


func open_waves_chest(index: int) -> void:
	if not _lobby_active:
		return
	var result := WavesRunService.open_chest(index)
	if result.is_empty():
		return
	if index < _chest_nodes.size():
		var chest: Node = _chest_nodes[index]
		if chest.has_method("apply_opened_state"):
			chest.call("apply_opened_state", true)
	if _wave_ui and _wave_ui.has_method("refresh_lobby"):
		_wave_ui.call("refresh_lobby")
	_persist_waves_save()


func try_ready() -> void:
	if not WavesRunService.all_chests_opened():
		return
	WavesRunService.mark_ready()
	if _wave_ui and _wave_ui.has_method("refresh_lobby"):
		_wave_ui.call("refresh_lobby")


func start_waves_from_lobby() -> void:
	if not WavesRunService.lobby_ready:
		return
	WavesRunService.start_waves()
	_lobby_active = false
	_build_walls(false)
	_clear_chests()
	_start_wave()
	if _wave_ui and _wave_ui.has_method("show_combat"):
		_wave_ui.call("show_combat", WavesRunService.current_wave)


func _start_combat_from_continue() -> void:
	_lobby_active = false
	_build_walls(not WavesRunService.prep_active)
	if WavesRunService.prep_active:
		_prep_countdown = 5.0
		if _wave_ui and _wave_ui.has_method("show_prep"):
			_wave_ui.call("show_prep", WavesRunService.current_wave, _prep_countdown)
	else:
		_start_wave()
		if _wave_ui and _wave_ui.has_method("show_combat"):
			_wave_ui.call("show_combat", WavesRunService.current_wave)


func _start_wave() -> void:
	_clear_enemies()
	var wave := WavesRunService.current_wave
	for enemy_id in WavesRunService.get_enemies_for_wave(wave):
		_spawn_enemy(enemy_id)
	_persist_waves_save()


func _spawn_enemy(enemy_id: String) -> void:
	var scene: PackedScene = ENEMY_SCENES.get(enemy_id)
	if scene == null:
		return
	var enemy: CharacterBody3D = scene.instantiate() as CharacterBody3D
	if enemy == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = WavesRunService.to_save_dict().get("seed", 1) + WavesRunService.current_wave * 17 + _active_enemies.size()
	enemy.position = Vector3(rng.randf_range(-28, 28), 0.0, rng.randf_range(-28, 28))
	CharacterFloorSnapScript.snap_feet_to_floor(enemy)
	if enemy.has_method("set_player"):
		enemy.call("set_player", _player)
	add_child(enemy)
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died)
	elif enemy.has_signal("boss_defeated"):
		enemy.boss_defeated.connect(_on_enemy_died)
	_active_enemies.append(enemy)


func _on_enemy_died() -> void:
	WavesRunService.register_kill()
	_active_enemies = _active_enemies.filter(func(e: Node) -> bool:
		return is_instance_valid(e) and not (e.has_method("is_dead") and e.call("is_dead"))
	)
	if _active_enemies.is_empty():
		_on_wave_cleared()


func _on_wave_cleared() -> void:
	if WavesRunService.is_final_milestone() and WavesRunService.current_wave >= 50:
		_show_reward_pick()
		return
	if WavesRunService.is_milestone(WavesRunService.current_wave):
		WavesRunService.enter_prep()
		_build_walls(true)
		_prep_countdown = 5.0
		if _wave_ui and _wave_ui.has_method("show_prep"):
			_wave_ui.call("show_prep", WavesRunService.current_wave, _prep_countdown)
	else:
		WavesRunService.advance_wave()
		_start_wave()
		if _wave_ui and _wave_ui.has_method("show_combat"):
			_wave_ui.call("show_combat", WavesRunService.current_wave)
	_persist_waves_save()


func _process(delta: float) -> void:
	_bird_time += delta
	_animate_birds()
	if _prep_countdown > 0.0:
		_prep_countdown -= delta
		if _prep_countdown <= 0.0:
			WavesRunService.leave_prep()
			_build_walls(false)
			WavesRunService.advance_wave()
			_start_wave()
			if _wave_ui and _wave_ui.has_method("show_combat"):
				_wave_ui.call("show_combat", WavesRunService.current_wave)


func _show_reward_pick() -> void:
	if _wave_ui and _wave_ui.has_method("show_reward_pick"):
		_wave_ui.call("show_reward_pick")


func complete_waves_with_rewards(item_ids: Array) -> void:
	RunFlow.complete_waves_run(item_ids)


func _clear_enemies() -> void:
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active_enemies.clear()


func _clear_chests() -> void:
	for chest in _chest_nodes:
		if is_instance_valid(chest):
			chest.queue_free()
	_chest_nodes.clear()


func _build_combat_hud() -> void:
	if get_node_or_null("CombatHUD"):
		return
	var hud := Control.new()
	hud.name = "CombatHUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_script := load("res://scripts/ui/combat_hud.gd")
	if hud_script:
		hud.set_script(hud_script)
		hud.set("player_path", NodePath("../Player"))
		hud.set("lock_on_path", NodePath("../Player/LockOn"))
	add_child(hud)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 20.0
	margin.offset_top = 20.0
	margin.offset_right = 300.0
	margin.offset_bottom = 84.0
	hud.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)
	var health := ProgressBar.new()
	health.name = "HealthBar"
	health.custom_minimum_size = Vector2(280, 24)
	health.max_value = 100.0
	health.value = 100.0
	health.show_percentage = false
	vbox.add_child(health)
	var stamina := ProgressBar.new()
	stamina.name = "StaminaBar"
	stamina.custom_minimum_size = Vector2(280, 18)
	stamina.max_value = 100.0
	stamina.value = 100.0
	stamina.show_percentage = false
	vbox.add_child(stamina)


func _restore_waves_snapshot() -> void:
	if not RunFlow.is_continue_restore():
		return
	var root := get_tree().root
	if not root.has_meta("run_snapshot"):
		return
	var snapshot: Variant = root.get_meta("run_snapshot")
	if not snapshot is Dictionary or snapshot.is_empty():
		return
	var player_state: Dictionary = snapshot.get("player", {})
	if _player and not player_state.is_empty():
		_player.global_position = Vector3(
			float(player_state.get("x", _player.global_position.x)),
			float(player_state.get("y", _player.global_position.y)),
			float(player_state.get("z", _player.global_position.z))
		)
		_player.rotation.y = float(player_state.get("rotationY", _player.rotation.y))
		var health := _player.get_node_or_null("Health") as Health
		if health and player_state.has("health"):
			health.restore_current(float(player_state.get("health", health.current)))
		var camera_state: Dictionary = player_state.get("camera", {})
		if not camera_state.is_empty():
			var spring := _player.get_node_or_null("CameraPivot/SpringArm3D")
			if spring and spring.has_method("apply_state"):
				spring.call("apply_state", camera_state)
	root.remove_meta("run_snapshot")
	RunFlow.clear_continue_restore()


func _persist_waves_save() -> void:
	var payload := WavesRunService.to_save_dict()
	var player_state := {
		"x": _player.global_position.x if _player else 0.0,
		"y": _player.global_position.y if _player else 0.0,
		"z": _player.global_position.z if _player else 0.0,
		"rotationY": _player.rotation.y if _player else 0.0,
		"health": (_player.get_node("Health") as Health).current if _player and _player.get_node_or_null("Health") else 100.0,
	}
	var spring := _player.get_node_or_null("CameraPivot/SpringArm3D") if _player else null
	if spring and spring.has_method("capture_state"):
		player_state["camera"] = spring.call("capture_state")
	payload["snapshot"] = {"player": player_state}
	LocalSave.set_waves_active_run(payload)


func _wire_player_death() -> void:
	var reactions := _player.get_node_or_null("CombatReactions")
	if reactions and reactions.has_signal("player_died"):
		if not reactions.player_died.is_connected(_on_player_died):
			reactions.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	await get_tree().create_timer(1.5).timeout
	RunFlow.on_waves_failed()


func _animate_birds() -> void:
	for bird in get_tree().get_nodes_in_group("waves_bird"):
		if not bird is Node3D:
			continue
		var node := bird as Node3D
		var radius: float = float(node.get_meta("orbit_radius", 6.0))
		var speed: float = float(node.get_meta("orbit_speed", 0.5))
		var phase: float = float(node.get_meta("orbit_phase", 0.0))
		var wing_phase: float = float(node.get_meta("wing_phase", 0.0))
		var home_x: float = float(node.get_meta("home_x", 0.0))
		var home_y: float = float(node.get_meta("home_y", 10.0))
		var home_z: float = float(node.get_meta("home_z", 0.0))
		var angle := _bird_time * speed + phase
		node.position = Vector3(
			home_x + cos(angle) * radius,
			home_y + sin(_bird_time * 1.6 + phase) * 0.35,
			home_z + sin(angle) * radius
		)
		node.rotation.y = angle + PI * 0.5
		var wing_l := node.get_node_or_null("WingL") as Node3D
		var wing_r := node.get_node_or_null("WingR") as Node3D
		var flap := sin(_bird_time * 8.0 + wing_phase) * 0.35
		if wing_l:
			wing_l.rotation.z = flap
		if wing_r:
			wing_r.rotation.z = -flap


func _apply_pixel_diorama_scene() -> void:
	PixelDioramaBootstrap.attach(self)
