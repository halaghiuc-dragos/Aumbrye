extends Node3D

## Umbral Waves arena — lobby chests, wave milestones, isolated inventory.

const ENEMY_SCENES := {
	"castle_grunt": preload("res://scenes/enemies/castle_grunt.tscn"),
	"castle_archer": preload("res://scenes/enemies/castle_archer.tscn"),
	"castle_shield": preload("res://scenes/enemies/castle_shield.tscn"),
	"castle_knight": preload("res://scenes/enemies/castle_knight.tscn"),
	"castle_hound": preload("res://scenes/enemies/castle_hound.tscn"),
	"boss_castle_knight": preload("res://scenes/enemies/boss_castle_knight.tscn"),
}

@export var player_path: NodePath = NodePath("Player")

var _player: CharacterBody3D
var _walls: Array[StaticBody3D] = []
var _chest_nodes: Array[Node3D] = []
var _active_enemies: Array[Node] = []
var _wave_ui: Control
var _lobby_active := true
var _prep_countdown := 0.0


func _ready() -> void:
	add_to_group("waves_run")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as CharacterBody3D
	_build_arena()
	_build_ui()
	if WavesRunService.lobby_ready and WavesRunService.current_wave > 0:
		_start_combat_from_continue()
	else:
		_show_lobby()
	_persist_waves_save()
	if _player:
		WavesRunService.apply_equipment_to_player(_player)
		_wire_player_death()


func _build_arena() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(40, 0.5, 40)
	floor_mesh.mesh = floor_box
	floor_mesh.material_override = load("res://assets/cathedral/mat_floor.tres")
	floor_body.add_child(floor_mesh)
	var floor_shape := CollisionShape3D.new()
	var floor_col := BoxShape3D.new()
	floor_col.size = Vector3(40, 0.5, 40)
	floor_shape.shape = floor_col
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	_build_walls(true)


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
	var mat := load("res://assets/cathedral/mat_wall.tres")
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
	for i in WavesRunService.CHEST_RARITIES.size():
		var chest := Node3D.new()
		chest.name = "WavesChest_%d" % i
		chest.set_script(chest_script)
		var angle := float(i) / float(WavesRunService.CHEST_RARITIES.size()) * TAU
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


func _persist_waves_save() -> void:
	var payload := WavesRunService.to_save_dict()
	payload["snapshot"] = {
		"player": {
			"x": _player.global_position.x if _player else 0.0,
			"y": _player.global_position.y if _player else 0.0,
			"z": _player.global_position.z if _player else 0.0,
			"health": (_player.get_node("Health") as Health).current if _player and _player.get_node_or_null("Health") else 100.0,
		},
	}
	LocalSave.set_waves_active_run(payload)


func _wire_player_death() -> void:
	var reactions := _player.get_node_or_null("CombatReactions")
	if reactions and reactions.has_signal("player_died"):
		if not reactions.player_died.is_connected(_on_player_died):
			reactions.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	await get_tree().create_timer(1.5).timeout
	RunFlow.on_waves_failed()
