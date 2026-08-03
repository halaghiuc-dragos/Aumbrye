extends Node3D

## Umbral Waves arena — lobby chests, wave milestones, isolated inventory.

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
var _settings_ui: Control


func _ready() -> void:
	add_to_group("waves_run")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as CharacterBody3D
	_apply_biome_presentation()
	_build_arena()
	_build_ui()
	_attach_settings_ui()
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


func _apply_biome_presentation() -> void:
	BiomeRegistry.apply_run_presentation(self, BiomeRegistry.BIOME_UMBRAL, RunModeConfig.MODE_WAVES)


func _build_arena() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(40, 0.5, 40)
	floor_mesh.mesh = floor_box
	var waves_biome := BiomeRegistry.BIOME_UMBRAL
	floor_mesh.material_override = BiomeRegistry.get_floor_material(waves_biome)
	floor_body.add_child(floor_mesh)
	var floor_shape := CollisionShape3D.new()
	var floor_col := BoxShape3D.new()
	floor_col.size = Vector3(40, 0.5, 40)
	floor_shape.shape = floor_col
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	_build_walls(true)
	DioramaRoomDressing.apply_to_waves_arena(self, waves_biome)


func _build_walls(enabled: bool) -> void:
	for wall in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()
	if not enabled:
		return
	var specs := [
		{"pos": Vector3(0, 2.5, -20), "size": Vector3(40, 5, 1)},
		{"pos": Vector3(0, 2.5, 20), "size": Vector3(40, 5, 1)},
		{"pos": Vector3(-20, 2.5, 0), "size": Vector3(1, 5, 40)},
		{"pos": Vector3(20, 2.5, 0), "size": Vector3(1, 5, 40)},
	]
	var mat := BiomeRegistry.get_wall_material(BiomeRegistry.BIOME_UMBRAL)
	for spec in specs:
		var wall := StaticBody3D.new()
		wall.name = "WaveWall"
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec["size"]
		mesh.mesh = box
		mesh.material_override = mat
		wall.add_child(mesh)
		var shape := CollisionShape3D.new()
		var col := BoxShape3D.new()
		col.size = spec["size"]
		shape.shape = col
		wall.add_child(shape)
		wall.position = spec["pos"]
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
	var inv_ui := Control.new()
	inv_ui.name = "WavesInventoryUI"
	inv_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inv_script := load("res://scripts/ui/waves_inventory_ui.gd")
	if inv_script:
		inv_ui.set_script(inv_script)
	add_child(inv_ui)


func _attach_settings_ui() -> void:
	var settings_script := load("res://scripts/ui/settings_ui.gd")
	if settings_script == null:
		return
	_settings_ui = Control.new()
	_settings_ui.name = "SettingsUI"
	_settings_ui.set_script(settings_script)
	_settings_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_settings_ui)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _any_blocking_ui_open():
		return
	if _settings_ui and _settings_ui.has_method("open_settings"):
		_settings_ui.call("open_settings")
		get_viewport().set_input_as_handled()


func _any_blocking_ui_open() -> bool:
	var inv := get_node_or_null("WavesInventoryUI")
	if inv and inv.has_method("is_open") and inv.call("is_open"):
		return true
	if _settings_ui and _settings_ui.has_method("is_open") and _settings_ui.call("is_open"):
		return true
	return false


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
		chest.position = Vector3(cos(angle) * 8.0, 0.0, sin(angle) * 8.0)
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
	var enemy: Node3D = scene.instantiate() as Node3D
	var rng := RandomNumberGenerator.new()
	rng.seed = WavesRunService.to_save_dict().get("seed", 1) + WavesRunService.current_wave * 17 + _active_enemies.size()
	enemy.position = Vector3(rng.randf_range(-12, 12), 0.0, rng.randf_range(-12, 12))
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
	margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	margin.offset_left = 24.0
	margin.offset_top = -120.0
	margin.offset_right = 324.0
	margin.offset_bottom = -24.0
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


func _apply_pixel_diorama_scene() -> void:
	PixelDioramaSettings.apply_to_scene(self)
