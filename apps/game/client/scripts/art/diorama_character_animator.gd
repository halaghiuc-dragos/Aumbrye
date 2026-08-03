extends RefCounted
class_name DioramaCharacterAnimator

## Procedural voxel-body animation for pixel-diorama characters.

enum AnimState {
	IDLE,
	WALK,
	RUN,
	AIR,
	ROLL,
	WINDUP,
	ATTACK,
	BLOCK,
	STAGGER,
	DEAD,
}

const CharacterSkin := preload("res://scripts/art/diorama_character_skin.gd")

var _visual: Node3D
var _parts: Dictionary = {}
var _base_pos: Dictionary = {}
var _base_rot: Dictionary = {}
var _time := 0.0
var _state := AnimState.IDLE
var _profile := "player"
var _hit_flash := 0.0
var _roll_dir := Vector3.FORWARD


func bind(visual: Node3D) -> void:
	_visual = visual
	_parts.clear()
	_base_pos.clear()
	_base_rot.clear()
	if visual == null:
		return
	for child in visual.get_children():
		if child is Node3D:
			var part := child as Node3D
			_parts[part.name] = part
			_base_pos[part.name] = part.position
			_base_rot[part.name] = part.rotation


func set_profile(profile: String) -> void:
	_profile = profile


func set_state(state: AnimState) -> void:
	_state = state


func set_roll_direction(dir: Vector3) -> void:
	if dir.length_squared() > 0.01:
		_roll_dir = dir.normalized()


func trigger_hit() -> void:
	_hit_flash = 0.14


func update(delta: float, params: Dictionary = {}) -> void:
	if _visual == null or _parts.is_empty():
		return
	_time += delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
	_reset_parts()
	match _state:
		AnimState.IDLE:
			_animate_idle()
		AnimState.WALK:
			_animate_locomotion(params.get("speed_ratio", 0.55), false)
		AnimState.RUN:
			_animate_locomotion(params.get("speed_ratio", 1.0), true)
		AnimState.AIR:
			_animate_air(params.get("vertical_speed", 0.0))
		AnimState.ROLL:
			_animate_roll(params.get("roll_progress", 0.0))
		AnimState.WINDUP:
			_animate_windup()
		AnimState.ATTACK:
			_animate_attack()
		AnimState.BLOCK:
			_animate_block()
		AnimState.STAGGER:
			_animate_stagger()
		AnimState.DEAD:
			pass
	_apply_hit_flash()


func _reset_parts() -> void:
	for part_name in _parts:
		var part: Node3D = _parts[part_name]
		part.position = _base_pos[part_name]
		part.rotation = _base_rot[part_name]


func _part(name: String) -> Node3D:
	return _parts.get(name, null) as Node3D


func _move_part(name: String, offset: Vector3) -> void:
	var part := _part(name)
	if part:
		part.position += offset


func _rotate_part(name: String, rot: Vector3) -> void:
	var part := _part(name)
	if part:
		part.rotation += rot


func _animate_idle() -> void:
	var bob := sin(_time * 2.4) * 0.02
	_move_part("Torso", Vector3(0.0, bob, 0.0))
	_move_part("Head", Vector3(0.0, bob * 1.2, 0.0))
	var sway := sin(_time * 1.6) * 0.015
	_move_part("ArmL", Vector3(0.0, sway, 0.0))
	_move_part("ArmR", Vector3(0.0, -sway, 0.0))


func _animate_locomotion(speed_ratio: float, sprinting: bool) -> void:
	var freq := 9.0 if sprinting else 7.0
	var amp := 0.14 if sprinting else 0.1
	var phase := _time * freq * maxf(0.35, speed_ratio)
	var bob := absf(sin(phase)) * 0.05
	_move_part("Torso", Vector3(0.0, bob, 0.0))
	_move_part("Head", Vector3(0.0, bob * 0.6, 0.0))
	var leg_swing := sin(phase) * amp
	var arm_swing := sin(phase + PI) * amp * 0.85
	_move_part("LegL", Vector3(0.0, absf(sin(phase)) * 0.03, leg_swing))
	_move_part("LegR", Vector3(0.0, absf(sin(phase + PI)) * 0.03, -leg_swing))
	_move_part("ArmL", Vector3(0.0, 0.0, -arm_swing))
	_move_part("ArmR", Vector3(0.0, 0.0, arm_swing))
	if _profile == "ranged":
		_rotate_part("Bow", Vector3(sin(phase) * 0.08, 0.0, 0.0))
	elif _profile == "hound":
		_move_part("Torso", Vector3(0.0, bob, sin(phase) * 0.06))
		_rotate_part("Head", Vector3(sin(phase) * 0.12, 0.0, 0.0))


func _animate_air(vertical_speed: float) -> void:
	var tuck := clampf(-vertical_speed * 0.04, -0.12, 0.12)
	_move_part("Torso", Vector3(0.0, tuck, 0.0))
	_rotate_part("LegL", Vector3(0.35 + tuck, 0.0, 0.15))
	_rotate_part("LegR", Vector3(0.35 + tuck, 0.0, -0.15))
	_rotate_part("ArmL", Vector3(-0.25, 0.0, -0.2))
	_rotate_part("ArmR", Vector3(-0.25, 0.0, 0.2))
	_move_part("Head", Vector3(0.0, 0.04, 0.0))


func _animate_roll(progress: float) -> void:
	var t := clampf(progress, 0.0, 1.0)
	var curl := sin(t * PI)
	_move_part("Torso", Vector3(0.0, curl * 0.18, 0.0))
	_rotate_part("Torso", Vector3(curl * 0.9, 0.0, curl * 0.35 * sign(_roll_dir.x)))
	_rotate_part("Head", Vector3(curl * 0.4, 0.0, 0.0))
	_rotate_part("LegL", Vector3(curl * 0.8, 0.0, 0.25))
	_rotate_part("LegR", Vector3(curl * 0.8, 0.0, -0.25))
	_rotate_part("ArmL", Vector3(-curl * 0.6, 0.0, -0.15))
	_rotate_part("ArmR", Vector3(-curl * 0.6, 0.0, 0.15))
	if _part("Shield"):
		_move_part("Shield", Vector3(0.0, curl * 0.1, curl * 0.08))


func _animate_windup() -> void:
	var charge := 0.5 + sin(_time * 10.0) * 0.08
	_move_part("Torso", Vector3(0.0, -0.06 * charge, -0.08 * charge))
	_rotate_part("Torso", Vector3(-0.15 * charge, 0.0, 0.0))
	match _profile:
		"ranged":
			_rotate_part("ArmL", Vector3(-0.5 * charge, 0.0, 0.0))
			_rotate_part("ArmR", Vector3(0.35 * charge, 0.0, -0.25 * charge))
			_rotate_part("Bow", Vector3(-0.3 * charge, 0.0, 0.0))
		"shield":
			_move_part("Shield", Vector3(0.0, 0.05, 0.12 * charge))
			_rotate_part("ArmL", Vector3(0.0, 0.0, 0.2 * charge))
			_rotate_part("ArmR", Vector3(-0.35 * charge, 0.0, 0.15 * charge))
		"hound":
			_move_part("Torso", Vector3(0.0, -0.04, -0.14 * charge))
			_rotate_part("Head", Vector3(-0.2 * charge, 0.0, 0.0))
		_:
			_rotate_part("ArmR", Vector3(-0.45 * charge, 0.0, 0.2 * charge))
			_rotate_part("ArmL", Vector3(0.15 * charge, 0.0, -0.1 * charge))


func _animate_attack() -> void:
	var strike := 0.5 + sin(_time * 18.0) * 0.5
	match _profile:
		"ranged":
			_rotate_part("ArmL", Vector3(-0.15, 0.0, 0.0))
			_rotate_part("ArmR", Vector3(0.55 * strike, 0.0, -0.35))
			_rotate_part("Bow", Vector3(0.25 * strike, 0.0, 0.0))
		"shield":
			_rotate_part("ArmR", Vector3(-0.55 * strike, 0.0, 0.35 * strike))
			_move_part("Shield", Vector3(0.0, 0.0, 0.1 * strike))
		"hound":
			_move_part("Torso", Vector3(0.0, 0.0, 0.18 * strike))
			_rotate_part("Head", Vector3(0.35 * strike, 0.0, 0.0))
		_:
			_rotate_part("ArmR", Vector3(-0.75 * strike, 0.0, 0.35 * strike))
			_rotate_part("Torso", Vector3(0.0, 0.0, 0.06 * strike))
	_move_part("Torso", Vector3(0.0, 0.03 * strike, 0.04 * strike))


func _animate_block() -> void:
	var pulse := 0.85 + sin(_time * 6.0) * 0.05
	_move_part("Torso", Vector3(0.0, -0.03, -0.04))
	_rotate_part("ArmL", Vector3(0.0, 0.0, 0.35 * pulse))
	_rotate_part("ArmR", Vector3(0.0, 0.0, -0.2 * pulse))
	if _part("Shield"):
		_move_part("Shield", Vector3(0.0, 0.06, 0.18 * pulse))
		_rotate_part("Shield", Vector3(0.0, 0.0, -0.1))


func _animate_stagger() -> void:
	var wobble := sin(_time * 16.0) * 0.06
	_move_part("Torso", Vector3(wobble, -0.08, 0.0))
	_rotate_part("Torso", Vector3(0.15, 0.0, wobble * 2.0))
	_rotate_part("Head", Vector3(-0.1, 0.0, wobble))


func _apply_hit_flash() -> void:
	if _hit_flash <= 0.0:
		return
	var flash := _hit_flash / 0.14
	for part_name in _parts:
		var part: Node3D = _parts[part_name]
		part.position += Vector3(sin(_time * 40.0) * 0.02 * flash, 0.04 * flash, 0.0)
