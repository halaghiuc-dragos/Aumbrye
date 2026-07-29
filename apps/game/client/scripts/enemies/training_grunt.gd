extends CharacterBody3D

enum State { IDLE, WINDUP, ATTACK, RECOVERY, STAGGER, DEAD }

const DATA_RELATIVE := "content/enemies/training_grunt.json"

signal attack_telegraph_started
signal attack_active

@export var player_path: NodePath

@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _data: Dictionary = {}
var _state := State.IDLE
var _player: Node3D
var _health: Health
var _poise: Poise
var _hitbox: Hitbox
var _state_timer := 0.0
var _cooldown := 0.0
var _stagger_timer := 0.0


func _ready() -> void:
	add_to_group("lockable")
	add_to_group("enemy")
	_data = ContentLoader.load_json(DATA_RELATIVE)
	_health = get_node_or_null("Health") as Health
	_poise = get_node_or_null("Poise") as Poise
	_hitbox = get_node_or_null("Hitbox") as Hitbox
	if player_path:
		_player = get_node(player_path) as Node3D
	if _health:
		_health.configure(_data.get("health", 80.0))
		_health.died.connect(_on_died)
	if _poise:
		_poise.configure(_data.get("poise", 40.0))
		_poise.poise_broken.connect(_on_poise_broken)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if _cooldown > 0.0:
		_cooldown -= delta
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			_state = State.IDLE
		return
	_process_state(delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()


func is_dead() -> bool:
	return _state == State.DEAD


func apply_stagger(duration: float) -> void:
	_state = State.STAGGER
	_stagger_timer = duration
	if _hitbox:
		_hitbox.disable()


func _process_state(delta: float) -> void:
	match _state:
		State.IDLE:
			_face_player()
			if _can_attack():
				_start_windup()
		State.WINDUP:
			_state_timer -= delta
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
	var range: float = _data.get("attack_range", 2.2)
	return global_position.distance_to(_player.global_position) <= range


func _start_windup() -> void:
	_state = State.WINDUP
	_state_timer = _data.get("windup_duration", 0.7)
	if _mesh:
		_mesh.scale = Vector3(1.08, 1.08, 1.08)
	attack_telegraph_started.emit()


func _start_attack() -> void:
	_state = State.ATTACK
	_state_timer = _data.get("active_duration", 0.15)
	if _hitbox:
		_hitbox.set_attack_values(
			_data.get("attack_damage", 14.0),
			_data.get("attack_poise_damage", 12.0)
		)
		_hitbox.enable()
	attack_active.emit()
	_try_parry_check()


func _end_attack() -> void:
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	if _mesh:
		_mesh.scale = Vector3.ONE
	_state = State.RECOVERY
	_state_timer = _data.get("recovery_duration", 0.9)


func _try_parry_check() -> void:
	if not _player:
		return
	var parry := _player.get_node_or_null("Parry")
	if parry and parry.has_method("try_parry_attack"):
		if parry.call("try_parry_attack", self):
			var stagger: float = parry.call("get_parry_stagger_duration")
			apply_stagger(stagger)


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
	if _hitbox:
		_hitbox.disable()


func _on_poise_broken() -> void:
	apply_stagger(_data.get("stagger_duration", 1.0))


func reset_enemy() -> void:
	_state = State.IDLE
	_state_timer = 0.0
	_cooldown = 0.0
	_stagger_timer = 0.0
	if _hitbox:
		_hitbox.disable()
		_hitbox.reset_swing()
	if _health:
		_health.configure(_data.get("health", 80.0))
	if _poise:
		_poise.reset_poise()
		_poise.configure(_data.get("poise", 40.0))
