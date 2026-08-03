extends CharacterBody3D
class_name CastleEnemyBase

## Shared patrol/chase/deaggro AI for castle enemies (ENEMY-2.1 base).

enum State { PATROL, CHASE, WINDUP, ATTACK, RECOVERY, STAGGER, DEAD }

signal enemy_died
signal attack_telegraph_started
signal attack_active

const DATA_PATH := ""

const ENEMY_TURN_SPEED := 22.0
const HP_BAR_SCRIPT := preload("res://scripts/ui/enemy_health_bar.gd")
const GlobalDropServiceScript := preload("res://scripts/loot/global_drop_service.gd")
const CharacterSkin := preload("res://scripts/art/diorama_character_skin.gd")
const CharacterAnimator := preload("res://scripts/art/diorama_character_animator.gd")

@export var player_path: NodePath

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _telegraph: MeshInstance3D = $TelegraphMesh
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
var _animator
var _anim_profile := "melee"


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
		_attach_health_bar()
	if _poise:
		_poise.configure(_data.get("poise", 40.0))
		_poise.poise_broken.connect(_on_poise_broken)
	if _hurtbox:
		_hurtbox.damaged.connect(_on_hurt)
		_apply_hurtbox_data()
	_setup_diorama_visual()
	_pick_patrol_target()


func set_player(player: Node3D) -> void:
	_player = player


func get_enemy_id() -> String:
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
	_diorama_visual = CharacterSkin.build_enemy_body(self, _anim_profile, theme)
	if _mesh:
		_mesh.visible = false
	_animator = CharacterAnimator.new()
	_animator.bind(_diorama_visual)
	_animator.set_profile(_anim_profile)


func get_diorama_visual() -> Node3D:
	return _diorama_visual


func get_hp_bar_height() -> float:
	return 2.2


func _attach_health_bar() -> void:
	_hp_bar = HP_BAR_SCRIPT.new() as EnemyHealthBar
	_hp_bar.name = "HealthBar"
	add_child(_hp_bar)
	_hp_bar.setup(_health, get_hp_bar_height())


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
	if mat == null:
		mat = StandardMaterial3D.new()
	else:
		mat = mat.duplicate()
	(mat as StandardMaterial3D).albedo_color = color
	_mesh.set_surface_override_material(0, mat)


func is_dead() -> bool:
	return _state == State.DEAD


func capture_state() -> Dictionary:
	var defeated := is_dead() or (_health != null and _health.is_dead())
	var state := { "alive": not defeated }
	if _health and not defeated:
		state["health"] = _health.current
	return state


func apply_state(state: Dictionary) -> void:
	if not state.get("alive", true):
		_finalize_death(true)
		return
	if is_dead():
		return
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
	if _telegraph:
		_telegraph.visible = false
	if _hp_bar:
		_hp_bar.visible = false
	if _hurtbox:
		_hurtbox.monitorable = false
		_hurtbox.monitoring = false
	if _body_collision:
		_body_collision.disabled = true
	_play_death_visual()


func _play_death_visual() -> void:
	VfxService.play_death(global_position, Color(0.55, 0.22, 0.18))
	var visual := _diorama_visual if _diorama_visual else _mesh as Node3D
	if visual == null:
		return
	var death_scale := Vector3(0.2, 0.05, 0.2)
	var tween := create_tween()
	tween.tween_property(visual, "scale", death_scale, 0.35)
	if _diorama_visual:
		tween.parallel().tween_property(_diorama_visual, "position:y", -0.8, 0.35)


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
	var tier := RunFlow.get_dungeon_tier() if RunFlow.get_run_mode() == "castle" else 1
	var drop_id := GlobalDropServiceScript.roll_enemy_drop(get_instance_id(), floor_index, tier)
	if drop_id != "":
		InventoryService.add_item(drop_id, 1)


func _force_dead_silent() -> void:
	_finalize_death(true)


func apply_stagger(duration: float) -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.STAGGER
	_stagger_timer = duration
	if _hitbox:
		_hitbox.disable()
	if _telegraph:
		_telegraph.visible = false
	if _diorama_visual:
		_diorama_visual.scale = Vector3.ONE
	elif _mesh:
		_mesh.scale = Vector3.ONE


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


func _update_diorama_animation(delta: float) -> void:
	if _animator == null or is_dead():
		return
	var anim_state := CharacterAnimator.AnimState.IDLE
	var params: Dictionary = {}
	match _state:
		State.PATROL, State.CHASE, State.RECOVERY:
			if velocity.length() > 0.35:
				anim_state = CharacterAnimator.AnimState.WALK
				params["speed_ratio"] = clampf(velocity.length() / maxf(_data.get("move_speed", 3.5), 0.01), 0.25, 1.1)
		State.WINDUP:
			anim_state = CharacterAnimator.AnimState.WINDUP
		State.ATTACK:
			anim_state = CharacterAnimator.AnimState.ATTACK
		State.STAGGER:
			anim_state = CharacterAnimator.AnimState.STAGGER
		State.DEAD:
			anim_state = CharacterAnimator.AnimState.DEAD
	if _anim_profile == "shield" and _state in [State.CHASE, State.WINDUP] and velocity.length() < 0.2:
		anim_state = CharacterAnimator.AnimState.BLOCK
	_animator.set_state(anim_state)
	_animator.update(delta, params)


func _update_ai(delta: float) -> void:
	match _state:
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.WINDUP:
			_apply_chase_velocity(delta, 0.9)
			_state_timer -= delta
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
		_state = State.PATROL
		_pick_patrol_target()
		return
	if _can_attack():
		_start_windup()
		return
	_apply_chase_velocity(delta)


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
	if _aggro_locked:
		return true
	var aggro: float = _data.get("aggro_range", 10.0)
	if global_position.distance_to(_player.global_position) > aggro:
		return false
	if _has_line_of_sight_to_player():
		_aggro_locked = true
		return true
	return false


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
	_state = State.WINDUP
	_state_timer = _data.get("windup_duration", 0.7)
	if _diorama_visual:
		_diorama_visual.scale = Vector3(1.04, 1.04, 1.04)
	elif _mesh:
		_mesh.scale = Vector3(1.08, 1.08, 1.08)
	if _telegraph:
		_telegraph.visible = true
	attack_telegraph_started.emit()


func _start_attack() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.ATTACK
	_state_timer = _data.get("active_duration", 0.15)
	if _telegraph:
		_telegraph.visible = false
	if _hitbox:
		_hitbox.set_attack_values(
			_data.get("attack_damage", 14.0),
			_data.get("attack_poise_damage", 12.0),
			_data.get("damage_type", DamageInfo.TYPE_PHYSICAL),
			_data.get("status_on_hit", ""),
			int(_data.get("status_stacks_on_hit", 1))
		)
		_hitbox.enable()
	attack_active.emit()
	_try_parry_check()


func _end_attack() -> void:
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	if _diorama_visual:
		_diorama_visual.scale = Vector3.ONE
	elif _mesh:
		_mesh.scale = Vector3.ONE
	_state = State.RECOVERY
	_state_timer = _data.get("recovery_duration", 0.9)


func _try_parry_check() -> void:
	if not _player:
		return
	var guard: Node = _player.get_node_or_null("Guard")
	if guard and guard.has_method("try_parry_attack"):
		if guard.call("try_parry_attack", self):
			var stagger: float = guard.call("get_parry_stagger_duration")
			apply_stagger(stagger)


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


func _on_hurt(_info: DamageInfo) -> void:
	if is_dead():
		return
	if _animator:
		_animator.trigger_hit()
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
