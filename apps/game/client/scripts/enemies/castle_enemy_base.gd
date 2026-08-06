extends CharacterBody3D
class_name CastleEnemyBase

## Shared patrol/chase/deaggro AI for castle enemies (ENEMY-2.1 base).

enum State { PATROL, CHASE, INVESTIGATE, RETREAT, WINDUP, ATTACK, RECOVERY, STAGGER, DEAD }

signal enemy_died
signal attack_telegraph_started
signal attack_active

const DATA_PATH := ""

const ENEMY_TURN_SPEED := 22.0
const HP_BAR_SCRIPT := preload("res://scripts/ui/enemy_health_bar.gd")
const MaterialDissolveScript := preload("res://scripts/art/characters/material_dissolve.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const GlobalDropServiceScript := preload("res://scripts/loot/global_drop_service.gd")
const CharacterFloorSnapScript := preload("res://scripts/art/characters/character_floor_snap.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const CharacterRigCatalogScript := preload("res://scripts/art/characters/character_rig_catalog.gd")
const AnimControllerScript := preload("res://scripts/art/characters/diorama_anim_controller.gd")

@export var player_path: NodePath

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _body_collision: CollisionShape3D = $CollisionShape3D

var _data: Dictionary = {}
var _hp_bar: EnemyHealthBar
var _state := State.PATROL
var _player: Node3D
var _health: Health
var _poise: Poise
var _hitbox: Hitbox
var _hurtbox: Hurtbox
var _state_timer := 0.0
var _cooldown := 0.0
var _stagger_timer := 0.0
var _spawn_origin := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _patrol_wait := 0.0
var _aggro_locked := false
var _diorama_visual: Node3D
var _animator: DioramaAnimController
var _anim_profile := "melee"
var _last_known_player_pos := Vector3.ZERO
var _attack_token_group := ""
var _attack_token_held := false
var _current_attack_data: Dictionary = {}
var _combo_step := 0
var _combat_registered := false
var _deaggro_los_timer := 0.0
var _windup_duration := 0.0
var _last_hit_direction := Vector3.ZERO
var _catalog_id_override := ""
var _damage_multiplier := 1.0
var _sync_hitbox_from_anim := false
const DEAGGRO_LOS_TIMEOUT := 3.0


func set_damage_multiplier(mult: float) -> void:
	_damage_multiplier = maxf(0.1, mult)


func get_lock_threat() -> float:
	if _state in [State.WINDUP, State.ATTACK]:
		return 0.6
	if _aggro_locked:
		return 0.3
	return 0.0


func get_lock_priority() -> float:
	return 0.0


func get_lock_orbit_radius() -> float:
	var collision_radius := _get_collision_radius()
	if _is_boss_enemy():
		return maxf(LockOnMovement.ORBIT_RADIUS_BOSS_MIN, collision_radius + LockOnMovement.ORBIT_RADIUS_BOSS_PAD)
	if collision_radius <= 0.38:
		return LockOnMovement.ORBIT_RADIUS_SMALL
	if _anim_profile == "brute" or collision_radius >= 0.55:
		return LockOnMovement.ORBIT_RADIUS_LARGE
	return LockOnMovement.ORBIT_RADIUS_STANDARD


func _get_collision_radius() -> float:
	if _body_collision and _body_collision.shape is CapsuleShape3D:
		return (_body_collision.shape as CapsuleShape3D).radius
	return 0.45


func _is_boss_enemy() -> bool:
	var enemy_id := get_enemy_id()
	return enemy_id.contains("boss") or enemy_id.contains("miniboss")


func _ready() -> void:
	add_to_group("lockable")
	add_to_group("enemy")
	_spawn_origin = global_position
	var enemy_id := get_enemy_id()
	if enemy_id.is_empty():
		_data = ContentLoader.load_json(get_data_path())
	else:
		_data = EnemyCatalog.get_definition(enemy_id)
	_health = get_node_or_null("Health") as Health
	_poise = get_node_or_null("Poise") as Poise
	_hitbox = get_node_or_null("AttackPivot/Hitbox") as Hitbox
	_hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if player_path and not player_path.is_empty():
		_player = get_node_or_null(player_path) as Node3D
	if _health:
		_health.configure(_data.get("health", 80.0))
		_health.died.connect(_on_died)
	if _poise:
		_poise.configure(_data.get("poise", 40.0), float(_data.get("stagger_duration", 1.0)))
		_poise.poise_broken.connect(_on_poise_broken)
	if _hurtbox:
		_hurtbox.damaged.connect(_on_hurt)
		if _hurtbox.has_signal("hit_resolved"):
			_hurtbox.hit_resolved.connect(_on_hit_resolved)
		_apply_hurtbox_data()
	_setup_diorama_visual()
	if _health:
		_attach_health_bar()
	_pick_patrol_target()


func set_player(player: Node3D) -> void:
	_player = player


func set_catalog_id(id: String) -> void:
	_catalog_id_override = id
	if not _data.is_empty() or id.is_empty():
		return
	_data = EnemyCatalog.get_definition(id)
	if _health and not _data.is_empty():
		_health.configure(_data.get("health", 80.0))
	if _poise and not _data.is_empty():
		_poise.configure(_data.get("poise", 40.0))


func get_enemy_id() -> String:
	if not _catalog_id_override.is_empty():
		return _catalog_id_override
	return _resolve_enemy_id()


func _resolve_enemy_id() -> String:
	return ""


func get_data_path() -> String:
	var enemy_id := get_enemy_id()
	if enemy_id.is_empty():
		return DATA_PATH
	return EnemyCatalog.get_content_path(enemy_id)


func _setup_diorama_visual() -> void:
	var enemy_id := get_enemy_id()
	if enemy_id.is_empty():
		enemy_id = str(_data.get("id", ""))
	_anim_profile = CharacterSkin.profile_for_enemy_data(_data)
	var theme := CharacterSkin.theme_for_enemy_id(enemy_id)
	_diorama_visual = CharacterSkin.build_enemy_body(self, _anim_profile, theme, enemy_id, _data)
	if _mesh:
		_mesh.visible = false
	CharacterFloorSnapScript.snap_character(self, _diorama_visual)
	_animator = AnimControllerScript.new()
	_animator.name = "AnimController"
	add_child(_animator)
	_animator.set_profile(_anim_profile)
	_animator.set_theme(theme)
	_animator.set_weapon(String(_data.get("weapon_kit", _default_weapon_for_profile())))
	_animator.bind(_diorama_visual)
	_animator.swing_frame.connect(_on_anim_swing_frame)
	_animator.hitbox_open_frame.connect(_on_anim_hitbox_open)
	_animator.hitbox_close_frame.connect(_on_anim_hitbox_close)


func _on_anim_hitbox_open() -> void:
	if _state == State.ATTACK and _hitbox:
		_hitbox.enable()


func _on_anim_hitbox_close() -> void:
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()


func _default_weapon_for_profile() -> String:
	match _anim_profile:
		"ranged":
			return "bow"
		"brute":
			return "greatsword"
		"caster", "beast", "hound":
			return ""
	return "sword"


func _on_anim_swing_frame() -> void:
	var anchor: Array = VfxService.resolve_combat_anchor(self)
	VfxService.play_weapon_trail(anchor[0], anchor[1], Color(0.95, 0.62, 0.42))


func get_diorama_visual() -> Node3D:
	return _diorama_visual


func get_hp_bar_height() -> float:
	return _estimate_body_top_y() + 0.22


func get_lock_aim_point() -> Vector3:
	var chest_y := maxf(1.0, _estimate_body_top_y() * 0.55)
	return global_position + Vector3(0.0, chest_y, 0.0)


func _estimate_body_top_y() -> float:
	if _diorama_visual:
		return _node_max_y(_diorama_visual)
	if _body_collision and _body_collision.shape is CapsuleShape3D:
		var cap := _body_collision.shape as CapsuleShape3D
		return _body_collision.position.y + cap.height * 0.5
	return 1.55


func _node_max_y(node: Node3D) -> float:
	var max_y := 0.0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh is BoxMesh:
				var box := mesh_instance.mesh as BoxMesh
				max_y = maxf(max_y, mesh_instance.position.y + box.size.y * 0.5)
		elif child is Node3D:
			max_y = maxf(max_y, child.position.y + _node_max_y(child as Node3D))
	return max_y


func _attach_health_bar() -> void:
	_hp_bar = HP_BAR_SCRIPT.new() as EnemyHealthBar
	_hp_bar.name = "HealthBar"
	add_child(_hp_bar)
	_hp_bar.setup(_health, get_hp_bar_height())


func begin_attack_windup_bar(duration: float) -> void:
	_windup_duration = maxf(0.05, duration)
	if _hp_bar:
		_hp_bar.begin_attack_telegraph(_windup_duration)


func hide_attack_windup_bar() -> void:
	_windup_duration = 0.0
	if _hp_bar:
		_hp_bar.hide_attack_telegraph()


func _show_attack_telegraph(duration: float) -> void:
	var radius := float(
		_current_attack_data.get("telegraph_radius", _data.get("telegraph_radius", 1.6))
	)
	var shape := String(
		_current_attack_data.get("telegraph_shape", _data.get("telegraph_shape", "circle"))
	)
	var tint := Color(0.95, 0.34, 0.28)
	if _data.has("telegraph_tint"):
		tint = Color(_data["telegraph_tint"])
	var forward := -global_transform.basis.z
	VfxService.play_telegraph(global_position, radius, duration, tint, shape, forward)


func _apply_hurtbox_data() -> void:
	if _hurtbox == null:
		return
	if _data.has("block_mitigation"):
		_hurtbox.set("block_mitigation", _data.get("block_mitigation"))
	if _data.has("block_angle_deg"):
		_hurtbox.set("block_angle_deg", _data.get("block_angle_deg"))


func _apply_mesh_tint(color: Color) -> void:
	if _mesh == null:
		return
	var mat: Material = _mesh.get_surface_override_material(0)
	if mat is ShaderMaterial:
		var shader_mat := (mat as ShaderMaterial).duplicate() as ShaderMaterial
		shader_mat.set_shader_parameter("color_base", color)
		shader_mat.set_shader_parameter("color_shadow", color.darkened(0.3))
		_mesh.set_surface_override_material(0, shader_mat)
		return
	var standard := (
		(mat.duplicate() as StandardMaterial3D)
		if mat is StandardMaterial3D
		else StandardMaterial3D.new()
	)
	standard.albedo_color = color
	_mesh.set_surface_override_material(0, standard)


func respawn_at_rest() -> void:
	if not is_dead():
		return
	_state = State.PATROL
	_stagger_timer = 0.0
	_cooldown = 0.0
	_aggro_locked = false
	_unregister_combat_engagement()
	global_position = _spawn_origin
	velocity = Vector3.ZERO
	if _health:
		_health.configure(_data.get("health", 80.0))
	if _poise:
		_poise.configure(_data.get("poise", 40.0), float(_data.get("stagger_duration", 1.0)))
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	hide_attack_windup_bar()
	if _hurtbox:
		_hurtbox.monitorable = true
		_hurtbox.monitoring = true
	if _hp_bar:
		_hp_bar.visible = true
	if _animator and _animator.is_bound():
		_animator.revive()
	if _diorama_visual:
		MaterialDissolveScript.reset_death_visual(_diorama_visual)
		MaterialFlashScript.restore_all(_diorama_visual)
	_pick_patrol_target()


func is_dead() -> bool:
	return _state == State.DEAD


func capture_state() -> Dictionary:
	var defeated := is_dead() or (_health != null and _health.is_dead())
	var state := {"alive": not defeated}
	if _health and not defeated:
		state["health"] = _health.current
	return state


func apply_state(state: Dictionary) -> void:
	if not state.get("alive", true):
		_finalize_death(true)
		return
	if is_dead():
		respawn_at_rest()
	if _health and state.has("health"):
		var hp := float(state.get("health", _health.max_health))
		if hp <= 0.0:
			_finalize_death(true)
			return
		_health.restore_current(hp)


func _finalize_death(silent: bool) -> void:
	if is_dead():
		return
	_clear_combat_debug_draw()
	_state = State.DEAD
	velocity = Vector3.ZERO
	_stagger_timer = 0.0
	_cooldown = 0.0
	_aggro_locked = false
	_unregister_combat_engagement()
	if _health:
		_health.force_dead()
	if not silent:
		RunFlow.register_kill(get_enemy_id())
		_award_kill_coins()
		_try_roll_global_drop()
		enemy_died.emit()
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	hide_attack_windup_bar()
	if _hp_bar:
		_hp_bar.visible = false
	if _animator and _animator.is_bound():
		_animator.play_death()
	if _hurtbox:
		_hurtbox.monitorable = false
		_hurtbox.monitoring = false
	if _body_collision:
		_body_collision.disabled = true
	_play_death_visual()


func _play_death_visual() -> void:
	AudioDirector.play_sfx("death", global_position)
	var visual := _diorama_visual if _diorama_visual else _mesh as Node3D
	if visual == null:
		return
	var archetype := CharacterRigCatalogScript.archetype_for_enemy(get_enemy_id(), _data)
	var opts := MaterialDissolveScript.death_opts_for_enemy(
		_anim_profile, _is_boss_enemy(), _data, archetype
	)
	opts["vfx_position"] = global_position
	opts["vfx_tint"] = Color(0.55, 0.22, 0.18)
	opts["has_animator"] = _animator != null and _animator.is_bound()
	if _last_hit_direction.length_squared() > 0.01:
		opts["sweep_dir"] = _last_hit_direction
	MaterialDissolveScript.play_death_visual(visual, opts)


func _award_kill_coins() -> void:
	var reward := int(_data.get("coinReward", _data.get("goldReward", 5)))
	if reward > 0 and CharacterService:
		CharacterService.add_coins(reward)


func _try_roll_global_drop() -> void:
	if not RunFlow.is_run_active():
		return
	if RunFlow.get_run_mode() == "waves":
		return
	var floor_index := RunFlow.get_current_floor()
	var tier := RunFlow.get_difficulty_tier() if RunFlow.get_run_mode() == "castle" else 1
	var dungeon_id := RunFlow.current_dungeon_id if RunFlow.get_run_mode() == "castle" else ""
	var drop_id := GlobalDropServiceScript.roll_enemy_drop(
		get_instance_id(), floor_index, tier, dungeon_id
	)
	if drop_id != "":
		InventoryService.add_loot(drop_id)


func _force_dead_silent() -> void:
	_finalize_death(true)


func apply_stagger(duration: float) -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.STAGGER
	_stagger_timer = duration
	if _hitbox:
		_hitbox.disable()
	hide_attack_windup_bar()
	if _animator and _animator.is_bound():
		_animator.play_stagger(duration)
	elif _mesh:
		_mesh.scale = Vector3.ONE


func cancel_attack() -> void:
	if _state in [State.WINDUP, State.ATTACK]:
		_end_attack()


func _physics_process(delta: float) -> void:
	if _health and _health.is_dead():
		if not is_dead():
			_finalize_death(true)
		return
	if is_dead():
		return
	if _cooldown > 0.0:
		_cooldown -= delta
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			if _health and _health.is_dead():
				_finalize_death(true)
				return
			_state = State.PATROL
		return
	_update_ai(delta)
	if _should_track_player():
		_track_player_facing(delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	_update_diorama_animation(delta)


## Only locomotion is pushed per frame. Attacks, staggers and death are one-shot
## clips owned by the controller's priority stack, so they are started from the
## state transitions instead of being re-asserted every tick.
func _update_diorama_animation(_delta: float) -> void:
	if _animator == null or not _animator.is_bound() or is_dead():
		return
	var speed := velocity.length()
	var shield_up := _anim_profile == "shield" and _state == State.CHASE and speed < 0.2
	_animator.set_blocking(shield_up)
	if speed > 0.35:
		var move_speed: float = maxf(float(_data.get("move_speed", 3.5)), 0.01)
		var clip := &"run" if speed > move_speed * 0.85 and _animator.has_clip(&"run") else &"walk"
		_animator.request_locomotion(clip, {"speed": speed})
	else:
		_animator.request_locomotion(&"idle")


func _update_ai(delta: float) -> void:
	match _state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.INVESTIGATE:
			_process_investigate(delta)
		State.RETREAT:
			_process_retreat(delta)
		State.WINDUP:
			_apply_chase_velocity(delta, 0.9)
			_state_timer -= delta
			if _windup_duration > 0.0:
				var elapsed := _windup_duration - _state_timer
				if _hp_bar:
					_hp_bar.set_attack_telegraph_progress(
						clampf(elapsed / _windup_duration, 0.0, 1.0)
					)
			if _state_timer <= 0.0:
				_start_attack()
		State.ATTACK:
			_apply_chase_velocity(delta, 0.7)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_end_attack()
		State.RECOVERY:
			_apply_chase_velocity(delta, 0.85)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.CHASE if _has_aggro() else State.PATROL
				_cooldown = _data.get("attack_cooldown", 1.5)


func _process_patrol(delta: float) -> void:
	if _has_aggro():
		_state = State.CHASE
		return
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		velocity = Vector3.ZERO
		return
	var to_target := _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.5:
		_patrol_wait = randf_range(1.0, 2.5)
		_pick_patrol_target()
		return
	velocity = to_target.normalized() * _data.get("move_speed", 3.0)
	_face_direction(to_target, delta)


func _process_chase(delta: float) -> void:
	if not _has_aggro():
		_state = State.INVESTIGATE
		_state_timer = 2.5
		return
	_last_known_player_pos = _player.global_position
	if _should_retreat():
		_state = State.RETREAT
		_state_timer = 1.8
		return
	if _can_attack():
		_start_windup()
		return
	_apply_chase_velocity(delta)


func _process_investigate(delta: float) -> void:
	if _has_aggro():
		_state = State.CHASE
		return
	_state_timer -= delta
	var to_last := _last_known_player_pos - global_position
	to_last.y = 0.0
	if to_last.length() > 0.75:
		velocity = to_last.normalized() * _data.get("move_speed", 3.0) * 0.75
		_face_direction(to_last, delta)
	else:
		velocity = Vector3.ZERO
	if _state_timer <= 0.0:
		_state = State.PATROL
		_pick_patrol_target()


func _process_retreat(delta: float) -> void:
	_state_timer -= delta
	if _player == null:
		_state = State.PATROL
		return
	var away := global_position - _player.global_position
	away.y = 0.0
	if away.length_squared() > 0.01:
		velocity = away.normalized() * _data.get("move_speed", 3.0)
		_face_direction(-away, delta)
	if _state_timer <= 0.0:
		_state = State.CHASE if _has_aggro() else State.PATROL


func _should_retreat() -> bool:
	if _health == null:
		return false
	var threshold: float = float(_data.get("retreat_threshold", 0.0))
	if threshold <= 0.0:
		return false
	return _health.current / _health.max_health <= threshold


func _apply_chase_velocity(_delta: float, speed_mult: float = 1.0) -> void:
	if _player == null:
		velocity = Vector3.ZERO
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var stop_range: float = _data.get("attack_range", 2.2) * 0.85
	if dist > stop_range:
		velocity = to_player.normalized() * _data.get("move_speed", 3.5) * speed_mult
	else:
		velocity = Vector3.ZERO


func _has_aggro() -> bool:
	if _player == null:
		return false
	var aggro: float = _data.get("aggro_range", 10.0)
	if _aggro_locked:
		var deaggro: float = _data.get("deaggro_range", aggro * 1.6)
		if global_position.distance_to(_player.global_position) > deaggro:
			_drop_aggro()
			return false
		if _has_line_of_sight_to_player():
			_deaggro_los_timer = 0.0
		else:
			_deaggro_los_timer += get_physics_process_delta_time()
			if _deaggro_los_timer >= DEAGGRO_LOS_TIMEOUT:
				_drop_aggro()
				return false
		return true
	if global_position.distance_to(_player.global_position) > aggro:
		return false
	if _has_line_of_sight_to_player():
		_register_combat_engagement()
		_aggro_locked = true
		_deaggro_los_timer = 0.0
		return true
	return false


func _drop_aggro() -> void:
	_aggro_locked = false
	_deaggro_los_timer = 0.0
	_unregister_combat_engagement()


func _can_attack() -> bool:
	if _cooldown > 0.0 or _player == null:
		return false
	if _is_cross_boss_boundary_with_player():
		return false
	var attack_range: float = _data.get("attack_range", 2.2)
	if global_position.distance_to(_player.global_position) > attack_range:
		return false
	return _has_line_of_sight_to_player()


func _has_line_of_sight_to_player() -> bool:
	if _player == null:
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var from := global_position + Vector3(0, 1.2, 0)
	var to := _player.global_position + Vector3(0, 1.0, 0)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 1
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.exclude = [get_rid()]
	if _player is CollisionObject3D:
		params.exclude.append((_player as CollisionObject3D).get_rid())
	return space.intersect_ray(params).is_empty()


func _is_cross_boss_boundary_with_player() -> bool:
	if _player == null:
		return false
	var castle_run: Node = get_tree().get_first_node_in_group("castle_run")
	if castle_run and castle_run.has_method("is_cross_boss_boundary"):
		return castle_run.call("is_cross_boss_boundary", self, _player)
	return false


func _start_windup() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_select_attack_data()
	_attack_token_group = str(_data.get("attack_token_group", "room_default"))
	if AttackTokenService and not AttackTokenService.request_token(_attack_token_group):
		return
	_attack_token_held = true
	_state = State.WINDUP
	var windup: float = float(
		_current_attack_data.get("windup_duration", _data.get("windup_duration", 0.7))
	)
	var windup_variance: float = float(
		_current_attack_data.get("windup_variance", _data.get("windup_variance", 0.0))
	)
	if windup_variance > 0.0:
		windup += randf_range(-windup_variance, windup_variance)
	_state_timer = maxf(0.05, windup)
	_sync_hitbox_from_anim = (
		_animator != null and _animator.is_bound() and not _animator._events_path.is_empty()
	)
	if _animator and _animator.is_bound():
		_animator.play_attack(
			_state_timer,
			float(_current_attack_data.get("active_duration", _data.get("active_duration", 0.15))),
			float(
				_current_attack_data.get("recovery_duration", _data.get("recovery_duration", 0.9))
			)
		)
	elif _mesh:
		_mesh.scale = Vector3(1.08, 1.08, 1.08)
	_show_attack_telegraph(_state_timer)
	begin_attack_windup_bar(_state_timer)
	AudioDirector.play_sfx("windup", global_position + Vector3(0.0, 1.0, 0.0))
	attack_telegraph_started.emit()


func _start_attack() -> void:
	if is_dead() or (_health and _health.is_dead()):
		_release_attack_token()
		return
	_state = State.ATTACK
	_state_timer = float(
		_current_attack_data.get("active_duration", _data.get("active_duration", 0.15))
	)
	hide_attack_windup_bar()
	if _hitbox:
		_hitbox.set_attack_values(
			float(_current_attack_data.get("attack_damage", _data.get("attack_damage", 14.0)))
			* _damage_multiplier,
			float(
				_current_attack_data.get(
					"attack_poise_damage", _data.get("attack_poise_damage", 12.0)
				)
			)
			* _damage_multiplier,
			_current_attack_data.get(
				"damage_type", _data.get("damage_type", DamageInfo.TYPE_PHYSICAL)
			),
			_current_attack_data.get("status_on_hit", _data.get("status_on_hit", "")),
			int(
				_current_attack_data.get(
					"status_stacks_on_hit", _data.get("status_stacks_on_hit", 1)
				)
			)
		)
		if not _sync_hitbox_from_anim:
			_hitbox.enable()
	attack_active.emit()


func _end_attack() -> void:
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	if _diorama_visual:
		_diorama_visual.scale = Vector3.ONE
	elif _mesh:
		_mesh.scale = Vector3.ONE
	_state = State.RECOVERY
	_state_timer = float(
		_current_attack_data.get("recovery_duration", _data.get("recovery_duration", 0.9))
	)
	_release_attack_token()
	var combo: Array = _current_attack_data.get("combo_followups", [])
	if combo.size() > 0 and _combo_step < combo.size() and _has_aggro():
		_combo_step += 1
		_current_attack_data = combo[_combo_step - 1]
		_state = State.WINDUP
		_state_timer = float(_current_attack_data.get("windup_duration", 0.35))
		begin_attack_windup_bar(_state_timer)
	else:
		_combo_step = 0


func _select_attack_data() -> void:
	var attacks: Array = _data.get("attacks", [])
	if attacks.is_empty():
		_current_attack_data = _data
		_combo_step = 0
		return
	if _combo_step > 0:
		return
	_current_attack_data = attacks[randi() % attacks.size()]
	_combo_step = 0


func _release_attack_token() -> void:
	if _attack_token_held and AttackTokenService:
		AttackTokenService.release_token(_attack_token_group)
	_attack_token_held = false


func _register_combat_engagement() -> void:
	if _combat_registered or AudioDirector == null:
		return
	_combat_registered = true
	AudioDirector.register_combat_engagement()


func _unregister_combat_engagement() -> void:
	if not _combat_registered or AudioDirector == null:
		return
	_combat_registered = false
	AudioDirector.unregister_combat_engagement()


func _try_parry_check() -> void:
	# Parry resolution lives in Hurtbox.receive_hit during active hit frames.
	pass


func _face_direction(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.01:
		return
	var angle := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, angle, ENEMY_TURN_SPEED * delta)


func _should_track_player() -> bool:
	return _player != null and (_aggro_locked or _state != State.PATROL)


func _track_player_facing(delta: float) -> void:
	if _player == null:
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	_face_direction(to_player, delta)


func _pick_patrol_target() -> void:
	var radius: float = _data.get("patrol_radius", 4.0)
	var offset := Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius, radius))
	_patrol_target = _spawn_origin + offset


func _on_died() -> void:
	_finalize_death(false)


func _on_poise_broken() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	apply_stagger(_data.get("stagger_duration", 1.0))


func _on_hit_resolved(res) -> void:
	if res.outgoing <= 0.0:
		return
	_on_hurt(DamageInfo.new())


func _on_hurt(info: DamageInfo) -> void:
	if info.direction.length_squared() > 0.01:
		_last_hit_direction = info.direction
	if is_dead():
		return
	if _animator and _animator.is_bound():
		_animator.play_flinch()
		return
	if not _mesh:
		return
	var tween := create_tween()
	_mesh.scale = Vector3(1.12, 1.12, 1.12)
	tween.tween_property(_mesh, "scale", Vector3.ONE, 0.1)


func _clear_combat_debug_draw() -> void:
	if _hitbox and _hitbox.has_method("set_debug_draw"):
		_hitbox.call("set_debug_draw", false)
	if _hurtbox and _hurtbox.has_method("set_debug_draw"):
		_hurtbox.call("set_debug_draw", false)
