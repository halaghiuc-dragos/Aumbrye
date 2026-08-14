extends CharacterBody3D

enum State { IDLE, WINDUP, ATTACK, RECOVERY, STAGGER, DEAD }

const ENEMY_ID := "training_grunt"
const HP_BAR_SCRIPT := preload("res://scripts/ui/training_dummy_health_bar.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const AnimControllerScript := preload("res://scripts/art/characters/diorama_anim_controller.gd")
const MaterialDissolveScript := preload("res://scripts/art/characters/material_dissolve.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")

signal attack_telegraph_started
signal attack_active

@export var player_path: NodePath

var _mesh: Node3D
var _animator: DioramaAnimController
@onready var _body_collision: CollisionShape3D = $CollisionShape3D

var _data: Dictionary = {}
var _state := State.IDLE
var _player: Node3D
var _health: Health
var _poise: Poise
var _hitbox: Hitbox
var _hurtbox: Hurtbox
var _hp_bar: EnemyHealthBar
var _state_timer := 0.0
var _cooldown := 0.0
var _stagger_timer := 0.0
var _spawn_origin := Vector3.ZERO
var _windup_duration := 0.0


func _ready() -> void:
	add_to_group("training_dummy")
	_mesh = CharacterSkin.build_training_dummy(self)
	_animator = AnimControllerScript.new()
	_animator.name = "AnimController"
	add_child(_animator)
	# A training dummy is struck but never strikes: it has no hitbox, so its attack clips' frame
	# signals have nothing to drive and their absence is not a wiring fault.
	_animator.expects_hitbox_listeners = false
	_animator.set_profile("melee")
	_animator.set_weapon("sword")
	_animator.bind(_mesh)
	var legacy_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if legacy_mesh:
		legacy_mesh.visible = false
	add_to_group("lockable")
	add_to_group("enemy")
	_data = EnemyCatalog.get_definition(ENEMY_ID)
	_health = get_node_or_null("Health") as Health
	_poise = get_node_or_null("Poise") as Poise
	_hitbox = get_node_or_null("AttackPivot/Hitbox") as Hitbox
	_hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if player_path:
		_player = get_node(player_path) as Node3D
	if _health:
		_health.configure(_data.get("health", 80.0))
		_health.died.connect(_on_died)
		_hp_bar = HP_BAR_SCRIPT.new() as EnemyHealthBar
		_hp_bar.name = "HealthBar"
		add_child(_hp_bar)
		_hp_bar.setup(_health)
	if _poise:
		_poise.configure(_data.get("poise", 40.0))
		_poise.poise_broken.connect(_on_poise_broken)
	var hurtbox := get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox:
		hurtbox.damaged.connect(_on_hurt)
	_spawn_origin = global_position


func _physics_process(delta: float) -> void:
	if _health and _health.is_dead():
		if not is_dead():
			_on_died()
		return
	if is_dead():
		return
	if _cooldown > 0.0:
		_cooldown -= delta
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			if _health and _health.is_dead():
				_on_died()
				return
			_state = State.IDLE
		return
	_process_state(delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	_update_diorama_animation(delta)


func is_dead() -> bool:
	return _state == State.DEAD


func get_diorama_visual() -> Node3D:
	return _mesh


func begin_attack_windup_bar(duration: float) -> void:
	_windup_duration = maxf(0.05, duration)
	if _hp_bar:
		_hp_bar.begin_attack_telegraph(_windup_duration)


func hide_attack_windup_bar() -> void:
	_windup_duration = 0.0
	if _hp_bar:
		_hp_bar.hide_attack_telegraph()


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


func _update_diorama_animation(_delta: float) -> void:
	if _animator == null or not _animator.is_bound() or is_dead():
		return
	var speed := velocity.length()
	if speed > 0.2:
		_animator.request_locomotion(&"walk", {"speed": speed})
	else:
		_animator.request_locomotion(&"idle")


func _process_state(delta: float) -> void:
	match _state:
		State.IDLE:
			_face_player()
			if _can_attack():
				_start_windup()
		State.WINDUP:
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
			_state_timer -= delta
			if _state_timer <= 0.0:
				_end_attack()
		State.RECOVERY:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_state = State.IDLE
				_cooldown = _data.get("attack_cooldown", 1.5)


func _can_attack() -> bool:
	if _cooldown > 0.0 or not _player:
		return false
	var attack_range: float = _data.get("attack_range", 2.2)
	return global_position.distance_to(_player.global_position) <= attack_range


func _start_windup() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.WINDUP
	var windup: float = float(_data.get("windup_duration", 0.7))
	_state_timer = windup
	if _animator and _animator.is_bound():
		_animator.play_attack(
			windup,
			float(_data.get("active_duration", 0.15)),
			float(_data.get("recovery_duration", 0.9))
		)
	begin_attack_windup_bar(windup)
	var forward := -global_transform.basis.z
	VfxService.play_telegraph(
		global_position,
		float(_data.get("telegraph_radius", 1.6)),
		windup,
		Color(0.95, 0.34, 0.28),
		String(_data.get("telegraph_shape", "circle")),
		forward
	)
	attack_telegraph_started.emit()


func _start_attack() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.ATTACK
	_state_timer = _data.get("active_duration", 0.15)
	hide_attack_windup_bar()
	if _hitbox:
		_hitbox.set_attack_values(
			_data.get("attack_damage", 14.0), _data.get("attack_poise_damage", 12.0)
		)
		_hitbox.enable()
	attack_active.emit()


func _end_attack() -> void:
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	if _mesh:
		_mesh.scale = Vector3.ONE
	_state = State.RECOVERY
	_state_timer = _data.get("recovery_duration", 0.9)


func _face_player() -> void:
	if not _player:
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return
	var angle := atan2(to_player.x, to_player.z)
	rotation.y = lerp_angle(rotation.y, angle, 8.0 * get_physics_process_delta_time())


func _on_died() -> void:
	_state = State.DEAD
	velocity = Vector3.ZERO
	hide_attack_windup_bar()
	if _hitbox:
		_hitbox.disable()
	if _hurtbox:
		_hurtbox.monitorable = false
	if _animator and _animator.is_bound():
		_animator.play_death()
	if _mesh:
		var opts := MaterialDissolveScript.death_opts_for_profile("dummy")
		opts["duration"] = 0.4
		opts["vfx_position"] = global_position
		opts["has_animator"] = _animator != null and _animator.is_bound()
		MaterialDissolveScript.play_death_visual(_mesh, opts)


func _on_poise_broken() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	apply_stagger(_data.get("stagger_duration", 1.0))


func _on_hurt(_info: DamageInfo) -> void:
	if is_dead():
		return
	if _animator and _animator.is_bound():
		_animator.play_flinch()


func reset_enemy() -> void:
	_state = State.IDLE
	_state_timer = 0.0
	_cooldown = 0.0
	_stagger_timer = 0.0
	velocity = Vector3.ZERO
	global_position = _spawn_origin
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	hide_attack_windup_bar()
	if _hurtbox:
		_hurtbox.monitorable = true
		_hurtbox.monitoring = true
	if _body_collision:
		_body_collision.disabled = false
	if _mesh:
		_mesh.scale = Vector3.ONE
		_mesh.position = Vector3.ZERO
		MaterialDissolveScript.reset_death_visual(_mesh)
	if _animator:
		_animator.revive()
		_animator.reset_combo()
	if _health:
		_health.configure(_data.get("health", 80.0))
	if _poise:
		_poise.reset_poise()
		_poise.configure(_data.get("poise", 40.0))
	if _mesh:
		MaterialFlashScript.restore_all(_mesh)
