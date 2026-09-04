extends Node3D


## Fallback only. Enemies resolve through `EnemyCatalog.get_scene()` so the Vigil can field the
## whole bestiary; this dictionary exists purely so a content gap cannot leave a wave empty.
const ENEMY_SCENES_FALLBACK := {
	"castle_grunt": preload("res://scenes/enemies/castle_grunt.tscn"),
	"castle_archer": preload("res://scenes/enemies/castle_archer.tscn"),
	"castle_shield": preload("res://scenes/enemies/castle_shield.tscn"),
	"castle_hound": preload("res://scenes/enemies/castle_hound.tscn"),
}

## Enemies rise at the arena edge, never on top of the player, and never without warning.
const SPAWN_RING_RADIUS := 24.0
const SPAWN_MIN_PLAYER_DISTANCE := 12.0
const SPAWN_TELEGRAPH_SECONDS := 1.1
const SPAWN_TELEGRAPH_STAGGER := 0.12

@export var player_path: NodePath = NodePath("Player")

var _player: CharacterBody3D
var _walls: Array[StaticBody3D] = []
var _chest_nodes: Array[Node3D] = []
var _active_enemies: Array[Node] = []
var _wave_ui: Control
var _hud: Control
var _lobby_active := true
var _torch_holder: Node3D
var _torchlight: Node3D
var _arena_mutator: Node3D
var _spawn_markers: Array[Node3D] = []
var _pending_spawns := 0
var _cash_out_portal: Node3D
const WavesOutdoorsDioramaScript := preload("res://scripts/dungeon/waves_outdoors_diorama.gd")
const ToastScene: PackedScene = preload("res://scenes/ui/achievement_toast.tscn")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")
const WavesTorchHolderScript := preload("res://scripts/dungeon/waves_torch_holder.gd")
const WavesTorchlightScript := preload("res://scripts/dungeon/waves_torchlight.gd")
const WavesArenaMutatorScript := preload("res://scripts/dungeon/waves_arena_mutator.gd")
const WavesSpawnMarkerScript := preload("res://scripts/dungeon/waves_spawn_marker.gd")
const WavesCashOutPortalScript := preload("res://scripts/dungeon/waves_cash_out_portal.gd")
const DifficultyProfileScript := preload("res://scripts/dungeon/difficulty_profile.gd")
const RunModifierServiceScript := preload("res://scripts/dungeon/run_modifier_service.gd")
const RainFieldScript := preload("res://scripts/art/world/rain_field.gd")

const WAVES_FLOOR_HALF := 105.0

const CHEST_RING_RADIUS := 7.5
const LOBBY_SPAWN := Vector3(0.0, 0.0, 4.6)
const ARENA_FLOOR_Y := 0.0
const PIT_RECOVERY_MARGIN := 8.0
const PIT_DAMAGE_FRACTION := 0.1

var _bird_time := 0.0

## MD-01: "a reason to move" -- the cresset's light drains while the player is away from it and
## only refuels near it, so holding one corner of the arena for a whole wave goes dark.
var _cresset_fuel := 1.0
const CRESSET_DRAIN_SECONDS := 28.0
const CRESSET_REFUEL_SECONDS := 6.0
const CRESSET_REFUEL_RADIUS := 13.0


func _ready() -> void:
	add_to_group("waves_run")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as CharacterBody3D
	_build_arena()
	_build_torchlight()
	_attach_weather()
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


func _attach_weather() -> void:
	WeatherService.set_outdoors(true)
	if _player == null or get_node_or_null("RainField") != null:
		return
	var rain := Node3D.new()
	rain.set_script(RainFieldScript)
	add_child(rain)
	rain.call("set_floor_extent", WAVES_FLOOR_HALF, WAVES_FLOOR_HALF)
	rain.call("setup", _player)


func _exit_tree() -> void:
	WeatherService.set_outdoors(false)
	# MD-01: the "fog" arena state pushes `DayNightService.fog_boost` (a global), which must not
	# leak into whatever scene loads next.
	if _arena_mutator and is_instance_valid(_arena_mutator):
		_arena_mutator.call("clear_state")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_persist_waves_save()


func _build_arena() -> void:
	WavesOutdoorsDioramaScript.apply(self)
	AudioDirector.set_biome(BiomeRegistry.BIOME_UMBRAL)
	AudioDirector.play_dungeon_ambience()
	_build_walls(true)


func _ensure_walls() -> void:
	if not _walls.is_empty():
		return
	_build_walls(true)


func _build_walls(enabled: bool) -> void:
	if enabled and not _walls.is_empty():
		return
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


func _build_torchlight() -> void:
	if _torchlight != null and is_instance_valid(_torchlight):
		return
	var node := Node3D.new()
	node.set_script(WavesTorchlightScript)
	add_child(node)
	node.call("setup", self)
	_torchlight = node
	var mutator := Node3D.new()
	mutator.name = "WavesArenaMutator"
	mutator.set_script(WavesArenaMutatorScript)
	add_child(mutator)
	_arena_mutator = mutator


func _ensure_torch_holder() -> void:
	if _torch_holder != null and is_instance_valid(_torch_holder):
		return
	var holder := Node3D.new()
	holder.set_script(WavesTorchHolderScript)
	add_child(holder)
	holder.position = Vector3.ZERO
	_torch_holder = holder


## The cresset is the "I am ready" switch. On the first lobby it needs the torch buried in one of
## the caches; from the second intermission on it is already burning and the interaction simply
## calls the next wave, so re-kitting is not gated behind a repeated fetch quest.
func light_cresset() -> void:
	if WavesRunService.is_first_lobby():
		if not WavesRunService.place_torch():
			return
	elif not WavesRunService.lobby_ready:
		return
	if _torch_holder and is_instance_valid(_torch_holder):
		_torch_holder.call("set_lit", true)
	if _torchlight and is_instance_valid(_torchlight):
		_torchlight.call("set_lit", true)
	AudioDirector.play_sfx("ui_interact_near", Vector3.ZERO)
	start_waves_from_lobby()
	_persist_waves_save()


func _douse_cresset() -> void:
	if _torch_holder and is_instance_valid(_torch_holder):
		_torch_holder.call("set_lit", false)


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
	_ensure_torch_holder()
	_spawn_chests()
	_douse_cresset()
	if _torchlight and is_instance_valid(_torchlight) and WavesRunService.chest_set > 0:
		_torchlight.call("set_lit", true, true)
	if _player:
		_player.global_position = LOBBY_SPAWN
	_refresh_cash_out_portal()
	if _wave_ui and _wave_ui.has_method("show_lobby"):
		_wave_ui.call("show_lobby")
	if _hud and _hud.has_method("set_objective_text"):
		_hud.call("set_objective_text", "")


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
		chest.position = Vector3(
			cos(angle) * CHEST_RING_RADIUS, 0.0, sin(angle) * CHEST_RING_RADIUS
		)
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


func start_waves_from_lobby() -> void:
	if not WavesRunService.lobby_ready:
		return
	var resuming := WavesRunService.prep_active
	if resuming:
		WavesRunService.leave_prep()
		WavesRunService.advance_wave()
		WavesRunService.auto_equip_best_weapon()
	else:
		WavesRunService.start_waves()
	if _player:
		WavesRunService.apply_equipment_to_player(_player)
	_lobby_active = false
	_ensure_walls()
	_clear_chests()
	_start_wave()
	if _wave_ui and _wave_ui.has_method("show_combat"):
		_wave_ui.call("show_combat", WavesRunService.current_wave)


func _start_combat_from_continue() -> void:
	_ensure_walls()
	if WavesRunService.prep_active:
		_show_lobby()
		return
	_lobby_active = false
	_ensure_torch_holder()
	if _torch_holder and is_instance_valid(_torch_holder):
		_torch_holder.call("set_lit", true)
	if _torchlight and is_instance_valid(_torchlight):
		_torchlight.call("set_lit", true, true)
	_start_wave()
	if _wave_ui and _wave_ui.has_method("show_combat"):
		_wave_ui.call("show_combat", WavesRunService.current_wave)


func _start_wave() -> void:
	_clear_enemies()
	_clear_spawn_markers()
	_cresset_fuel = 1.0
	var wave := WavesRunService.current_wave
	# MD-01: one arena mutation per five-wave block -- wave 45 should not be wave 5 with more
	# enemies. `chest_set` already counts intermission blocks, so it doubles as the block index.
	if _arena_mutator:
		_arena_mutator.call(
			"apply_block", WavesRunService.chest_set, _torchlight, WavesRunService.get_arena_states()
		)
	# MD-01: one modifier from wave 10 on, so wave 45 fights differently than wave 5 fought.
	RunModifierServiceScript.apply_waves_wave_modifier(wave, WavesRunService.get_seed())
	var subtitle := tr("WAVES_TITLE_SUBTITLE") % wave
	var active_modifier := RunModifierServiceScript.active_modifiers()
	if not active_modifier.is_empty():
		subtitle += "  —  %s" % RunModifierServiceScript.describe(active_modifier[0])
	# HD-01
	if _hud and _hud.has_method("show_region_title"):
		_hud.call("show_region_title", "The Vigil", subtitle)
	var enemy_ids := WavesRunService.get_enemies_for_wave(wave)
	_pending_spawns = enemy_ids.size()
	_refresh_remaining()
	for index in enemy_ids.size():
		_spawn_enemy_telegraphed(str(enemy_ids[index]), index, enemy_ids.size())
	_persist_waves_save()


## MD-01: which side wave `wave` opens from -- "ring" is the original even spread, "converge"
## forces the player to turn and hold one direction, "scatter" breaks the even spacing so the ring
## itself stops being a readable pattern. Kept to a minority of waves so the ring stays the norm.
func _spawn_pattern_for_wave(wave: int) -> String:
	if wave < 3:
		return "ring"
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(WavesRunService.get_seed(), wave * 811 + 5)
	var roll := rng.randf()
	if roll < 0.55:
		return "ring"
	elif roll < 0.78:
		return "converge"
	return "scatter"


## Picks a point the player can see coming and is not standing on -- on the arena edge for "ring"
## and "scatter", within a forced sector for "converge".
func _spawn_point_for(index: int, total: int, wave: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(WavesRunService.get_seed(), wave * 17 + index)
	var angle: float
	var spread := TAU / float(maxi(1, total))
	match _spawn_pattern_for_wave(wave):
		"converge":
			var sector_rng := RandomNumberGenerator.new()
			sector_rng.seed = FloorSeedMix.mix(WavesRunService.get_seed(), wave * 991 + 7)
			var sector_center := sector_rng.randf_range(0.0, TAU)
			var sector_width := deg_to_rad(70.0)
			angle = sector_center + rng.randf_range(-sector_width * 0.5, sector_width * 0.5)
		"scatter":
			angle = rng.randf_range(0.0, TAU)
		_:
			var base_angle := rng.randf_range(0.0, TAU) if index == 0 else 0.0
			angle = base_angle + spread * float(index) + rng.randf_range(-spread * 0.3, spread * 0.3)
	var radius := SPAWN_RING_RADIUS * rng.randf_range(0.82, 1.0)
	var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	if _player == null:
		return point
	# Never open a wave inside the player's guard — push the point around the ring until it is far
	# enough away that they get to react to it.
	var player_flat := Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	for _attempt in 8:
		if point.distance_to(player_flat) >= SPAWN_MIN_PLAYER_DISTANCE:
			break
		angle += spread if spread > 0.4 else 0.7
		point = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	return point


func _spawn_enemy_telegraphed(enemy_id: String, index: int, total: int) -> void:
	var wave := WavesRunService.current_wave
	var point := _spawn_point_for(index, total, wave)
	var marker := Node3D.new()
	marker.name = "SpawnMarker"
	marker.set_script(WavesSpawnMarkerScript)
	add_child(marker)
	marker.position = point
	marker.call("setup")
	_spawn_markers.append(marker)
	_refresh_radar_spawn_markers()
	AudioDirector.play_sfx("windup", point)
	await get_tree().create_timer(
		SPAWN_TELEGRAPH_SECONDS + SPAWN_TELEGRAPH_STAGGER * float(index)
	).timeout
	if not is_inside_tree() or _lobby_active:
		return
	if wave != WavesRunService.current_wave:
		return
	if marker != null and is_instance_valid(marker):
		_spawn_markers.erase(marker)
		marker.queue_free()
		_refresh_radar_spawn_markers()
	_pending_spawns = maxi(0, _pending_spawns - 1)
	_spawn_enemy(enemy_id, point)


func _spawn_enemy(enemy_id: String, spawn_point: Vector3) -> void:
	var scene := _resolve_enemy_scene(enemy_id)
	if scene == null:
		push_warning("WavesRun: no scene for enemy '%s'" % enemy_id)
		_refresh_remaining()
		return
	var enemy: CharacterBody3D = scene.instantiate() as CharacterBody3D
	if enemy == null:
		_refresh_remaining()
		return
	if enemy.has_method("set_catalog_id"):
		enemy.call("set_catalog_id", EnemyCatalog.resolve_id(enemy_id))
	enemy.position = spawn_point
	add_child(enemy)
	_apply_wave_scaling(enemy)
	CharacterFloorSnapScript.snap_to_floor_below(enemy)
	if enemy.has_method("set_player"):
		enemy.call("set_player", _player)
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died.bind(enemy))
	elif enemy.has_signal("boss_defeated"):
		enemy.boss_defeated.connect(_on_enemy_died.bind(enemy))
	# HD-01: no boss bar showed in the Vigil even on a boss wave (`WavesRunService.is_boss_wave()`)
	# before this -- the HUD only ever got wired up for castle mode's boss room.
	if enemy.has_signal("boss_defeated") and _hud and _hud.has_method("bind_boss"):
		_hud.call("bind_boss", enemy)
	_active_enemies.append(enemy)
	if VfxService:
		VfxService.play_portal_activate(spawn_point)
	_refresh_remaining()


## MD-01: mirrors `DungeonBuilder._apply_floor_scaling()` -- the Vigil spawns enemies directly
## rather than through `DungeonBuilder`, so it never picked up the wave's HP/damage curve or the
## per-wave modifier's effects (`WavesDifficultyProfile` already existed but nothing called it).
func _apply_wave_scaling(enemy: Node) -> void:
	var wave := WavesRunService.current_wave
	var profile := DifficultyProfileScript.for_run("waves")
	var health := enemy.get_node_or_null("Health") as Health
	if health:
		health.configure(float(health.max_health) * profile.hp_multiplier(wave))
	if enemy.has_method("set_damage_multiplier"):
		enemy.call("set_damage_multiplier", profile.damage_multiplier(wave))
	if enemy.has_method("apply_phase_modifiers"):
		enemy.call("apply_phase_modifiers", profile.behaviour_modifiers(wave))


func _resolve_enemy_scene(enemy_id: String) -> PackedScene:
	var scene := EnemyCatalog.get_scene(enemy_id)
	if scene != null:
		return scene
	if ENEMY_SCENES_FALLBACK.has(enemy_id):
		return ENEMY_SCENES_FALLBACK[enemy_id]
	return null


## HD-01: enemy-count status is HUD territory now -- routed through set_objective_text rather
## than waves_run_ui.gd's own panel.
func _refresh_remaining() -> void:
	if _hud and _hud.has_method("set_objective_text"):
		var remaining := _active_enemies.size() + _pending_spawns
		_hud.call(
			"set_objective_text",
			"%s  —  %d left" % [tr("WAVES_WAVE_ACTIVE").format({"wave": WavesRunService.current_wave}), remaining]
		)


func _clear_spawn_markers() -> void:
	for marker in _spawn_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_spawn_markers.clear()
	_pending_spawns = 0
	_refresh_radar_spawn_markers()


## HD-05: keeps the arena radar's pending-spawn dots in sync with `_spawn_markers`.
func _refresh_radar_spawn_markers() -> void:
	if _hud and _hud.has_method("set_radar_spawn_markers"):
		_hud.call("set_radar_spawn_markers", _spawn_markers)


func _on_enemy_died(enemy: Node) -> void:
	WavesRunService.register_kill()
	var enemy_id := ""
	if enemy and enemy.has_method("get_enemy_id"):
		enemy_id = str(enemy.call("get_enemy_id"))
	QuestService.register_kill(enemy_id)
	_active_enemies = _active_enemies.filter(
		func(e: Node) -> bool:
			return is_instance_valid(e) and not (e.has_method("is_dead") and e.call("is_dead"))
	)
	_refresh_remaining()
	if _active_enemies.is_empty() and _pending_spawns <= 0:
		_on_wave_cleared()


func _on_wave_cleared() -> void:
	var wave := WavesRunService.current_wave
	if wave >= WavesRunService.final_wave():
		_douse_cresset()
		_show_reward_pick()
		return
	if WavesRunService.is_intermission_wave(wave):
		_enter_intermission()
	else:
		WavesRunService.advance_wave()
		_start_wave()
		if _wave_ui and _wave_ui.has_method("show_combat"):
			_wave_ui.call("show_combat", WavesRunService.current_wave)
	_persist_waves_save()


func _enter_intermission() -> void:
	WavesRunService.enter_prep()
	WavesRunService.begin_chest_set()
	_ensure_walls()
	_clear_enemies()
	_clear_spawn_markers()
	_show_lobby()


## The wizard's way out. From `cashOutFromWave` on, every intermission opens a portal beside the
## cresset; speaking to him banks exactly one carried item and ends the Vigil there.
func _refresh_cash_out_portal() -> void:
	var offered := WavesRunService.is_cash_out_wave(WavesRunService.current_wave)
	if not offered:
		if _cash_out_portal != null and is_instance_valid(_cash_out_portal):
			_cash_out_portal.queue_free()
		_cash_out_portal = null
		return
	if _cash_out_portal != null and is_instance_valid(_cash_out_portal):
		return
	var portal := Node3D.new()
	portal.name = "WavesCashOutPortal"
	portal.set_script(WavesCashOutPortalScript)
	add_child(portal)
	portal.call("setup", self)
	_cash_out_portal = portal
	if VfxService:
		VfxService.play_portal_activate(portal.global_position)


## Called by the wizard once the player has chosen what to walk away with.
func cash_out_with_item(item_ids: Array) -> void:
	RunFlow.cash_out_waves_run(item_ids)


func open_cash_out_picker() -> void:
	if _wave_ui and _wave_ui.has_method("show_cash_out_pick"):
		_wave_ui.call("show_cash_out_pick")


func _process(delta: float) -> void:
	_bird_time += delta
	_animate_birds()
	_check_arena_fall()
	_update_cresset_fuel(delta)


## MD-01: only active during combat -- the lobby/intermission cresset is a separate always-lit prop
## (`WavesTorchHolder`), and the ring lighting (`WavesTorchlight`) is held fully lit there too.
func _update_cresset_fuel(delta: float) -> void:
	if _lobby_active or _torchlight == null or not is_instance_valid(_torchlight):
		return
	if _player == null or not is_instance_valid(_player):
		return
	var near_cresset := _player.global_position.length() <= CRESSET_REFUEL_RADIUS
	if near_cresset:
		_cresset_fuel = minf(1.0, _cresset_fuel + delta / CRESSET_REFUEL_SECONDS)
	else:
		_cresset_fuel = maxf(0.0, _cresset_fuel - delta / CRESSET_DRAIN_SECONDS)
	_torchlight.call("set_fuel_level", _cresset_fuel)


## Same positional (not timer- or velocity-gated) recovery as `CastleRun._recover_fallen_player()`,
## against the arena's single floor plane instead of a per-room test. Never lethal.
func _check_arena_fall() -> void:
	if _player == null:
		return
	if _player.global_position.y >= ARENA_FLOOR_Y - PIT_RECOVERY_MARGIN:
		return
	_player.global_position = LOBBY_SPAWN
	CharacterFloorSnapScript.snap_to_floor_below(_player)
	var health := _player.get_node_or_null("Health") as Health
	if health:
		var pit_damage := health.max_health * PIT_DAMAGE_FRACTION
		health.take_damage(minf(pit_damage, maxf(health.current - 1.0, 0.0)))
	RunFlow.emit_run_warning(tr("WARN_FELL"))


func _show_reward_pick() -> void:
	if _wave_ui and _wave_ui.has_method("show_reward_pick"):
		_wave_ui.call("show_reward_pick")
	if _hud and _hud.has_method("set_objective_text"):
		_hud.call("set_objective_text", "")


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
	var hud_scene := load("res://scenes/ui/combat_hud.tscn") as PackedScene
	if hud_scene == null:
		return
	var hud := hud_scene.instantiate() as Control
	hud.name = "CombatHUD"
	hud.set("player_path", NodePath("../Player"))
	hud.set("lock_on_path", NodePath("../Player/LockOn"))
	add_child(hud)
	_hud = hud
	# HD-01: the HUD contract every run scene owes a call to -- see combat_hud.gd's header comment.
	if hud.has_method("configure_for_mode"):
		hud.call("configure_for_mode", "waves")
	# HD-05: the arena has no room graph -- radar mode replaces the dungeon minimap instead of
	# leaving it hidden.
	if hud.has_method("enable_arena_radar"):
		hud.call("enable_arena_radar", SPAWN_RING_RADIUS * 1.1)
	# AD-04: same immediate bounty-complete banner castle_run.gd gets -- waves is a valid bounty
	# mode too, and used to only learn about it at the results screen.
	if QuestService and not QuestService.quest_updated.is_connected(_on_quest_updated):
		QuestService.quest_updated.connect(_on_quest_updated)
	# SY-02: a quest's counter moving used to produce no feedback at all mid-run.
	if QuestService and not QuestService.quest_progress_advanced.is_connected(_on_quest_progress_advanced):
		QuestService.quest_progress_advanced.connect(_on_quest_progress_advanced)


func _on_quest_updated(quest_id: String, _state: String) -> void:
	if not BountyService.is_bounty(quest_id):
		return
	var def := QuestCatalog.get_definition(quest_id)
	if _hud and _hud.has_method("show_run_warning"):
		_hud.call("show_run_warning", tr("HUD_BOUNTY_COMPLETE").format({"name": str(def.get("title", quest_id))}))


func _on_quest_progress_advanced(quest_id: String, count: int, required: int) -> void:
	var def := QuestCatalog.get_definition(quest_id)
	var toast := ToastScene.instantiate()
	if toast.has_method("show_quest_progress"):
		get_tree().root.add_child(toast)
		toast.show_quest_progress(str(def.get("title", quest_id)), count, required)


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
		"health":
		(
			(_player.get_node("Health") as Health).current
			if _player and _player.get_node_or_null("Health")
			else 100.0
		),
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
