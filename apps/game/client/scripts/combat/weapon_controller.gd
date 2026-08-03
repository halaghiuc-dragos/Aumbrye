extends Node

enum AttackPhase { IDLE, STARTUP, ACTIVE, RECOVERY, DRAWING }

const WEAPON_DATA_RELATIVE := "content/weapons/sword_basic.json"
const DEFAULT_HITBOX_SIZE := Vector3(1.2, 0.8, 1.4)
const DEFAULT_HITBOX_OFFSET := Vector3(0.0, 0.0, 0.55)

const FALLBACK_WEAPON_DATA := {
	"archetype": "sword",
	"damage_type": "physical",
	"buffer_window": 0.2,
	"light_attacks": [
		{
			"damage": 12.0,
			"poise_damage": 10.0,
			"stamina_cost": 12.0,
			"startup": 0.15,
			"active": 0.12,
			"recovery": 0.25,
		}
	],
	"heavy_attack": {
		"damage": 28.0,
		"poise_damage": 35.0,
		"stamina_cost": 32.0,
		"startup": 0.35,
		"active": 0.18,
		"recovery": 0.45,
	},
}

signal attack_started(attack_name: String)
signal attack_ended

@export var hitbox_path: NodePath

var is_attacking := false
var current_phase := AttackPhase.IDLE

var _body: CharacterBody3D
var _stamina: Stamina
var _hitbox: Area3D
var _hitbox_shape: CollisionShape3D
var _combat_reactions: Node
var _weapon_data: Dictionary = {}
var _combo_index := 0
var _phase_timer := 0.0
var _current_attack: Dictionary = {}
var _buffered_attack := ""
var _attack_name := ""
var _damage_multiplier := 1.0
var _draw_charge := 0.0
var _hyperarmor_active := false


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_combat_reactions = _body.get_node_or_null("CombatReactions")
	if hitbox_path:
		_hitbox = get_node_or_null(hitbox_path) as Area3D
		if _hitbox:
			_hitbox_shape = _hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_load_weapon_data()


func get_debug_state() -> String:
	if not is_attacking:
		return "idle"
	var phase_name := "startup"
	match current_phase:
		AttackPhase.ACTIVE:
			phase_name = "active"
		AttackPhase.RECOVERY:
			phase_name = "recovery"
		AttackPhase.DRAWING:
			phase_name = "drawing"
	return phase_name


func _physics_process(delta: float) -> void:
	if _is_action_blocked():
		return
	var archetype: String = _weapon_data.get("archetype", "sword")
	if archetype == "bow":
		_process_bow_input(delta)
		return
	if is_attacking:
		_process_attack_phase(delta)
		return
	if Input.is_action_just_pressed("light_attack"):
		_try_attack("light")
	elif Input.is_action_just_pressed("heavy_attack"):
		_try_attack("heavy")
	if _buffered_attack != "" and not is_attacking:
		_try_attack(_buffered_attack)
		_buffered_attack = ""


func load_weapon_from_path(relative: String) -> void:
	_weapon_data = ContentLoader.load_json(relative)
	if _weapon_data.is_empty():
		push_warning("WeaponController: using fallback weapon data")
		_weapon_data = FALLBACK_WEAPON_DATA.duplicate(true)
	_apply_hitbox_profile()


func set_damage_multiplier(multiplier: float) -> void:
	_damage_multiplier = maxf(0.1, multiplier)


func has_hyperarmor() -> bool:
	return _hyperarmor_active


func _load_weapon_data() -> void:
	load_weapon_from_path(WEAPON_DATA_RELATIVE)


func _try_attack(kind: String) -> void:
	if is_attacking:
		var buffer_window: float = _weapon_data.get("buffer_window", 0.2)
		if _phase_timer <= buffer_window or current_phase == AttackPhase.RECOVERY:
			_buffered_attack = kind
		return
	var attack: Dictionary
	if kind == "heavy":
		attack = _weapon_data.get("heavy_attack", {})
		_attack_name = "heavy"
		_combo_index = 0
	else:
		var lights: Array = _weapon_data.get("light_attacks", [])
		if lights.is_empty():
			return
		_combo_index = _combo_index % lights.size()
		attack = lights[_combo_index]
		_attack_name = "light_%d" % (_combo_index + 1)
	var cost: float = attack.get("stamina_cost", 10.0)
	if _stamina and not _stamina.has(cost):
		return
	if _stamina:
		_stamina.consume(cost)
	_start_attack(attack)


func _start_attack(attack: Dictionary) -> void:
	_current_attack = attack
	is_attacking = true
	current_phase = AttackPhase.STARTUP
	_phase_timer = attack.get("startup", 0.2)
	if _hitbox and _hitbox.has_method("reset_swing"):
		_hitbox.call("reset_swing")
	attack_started.emit(_attack_name)


func _process_attack_phase(delta: float) -> void:
	_phase_timer -= delta
	if _phase_timer > 0.0:
		return
	match current_phase:
		AttackPhase.STARTUP:
			current_phase = AttackPhase.ACTIVE
			_phase_timer = _current_attack.get("active", 0.15)
			_enable_hitbox_for_attack()
		AttackPhase.ACTIVE:
			current_phase = AttackPhase.RECOVERY
			_phase_timer = _current_attack.get("recovery", 0.3)
			_disable_hitbox()
		AttackPhase.RECOVERY:
			_end_attack()


func _enable_hitbox_for_attack() -> void:
	if _hitbox == null or not _hitbox.has_method("enable"):
		return
	var dmg: float = float(_current_attack.get("damage", 10.0)) * _damage_multiplier
	var poise: float = float(_current_attack.get("poise_damage", 10.0)) * _damage_multiplier
	var dmg_type: String = _current_attack.get("damage_type", _weapon_data.get("damage_type", "physical"))
	var status_id: String = _current_attack.get("status", _weapon_data.get("status_on_hit", ""))
	var status_stacks: int = int(_current_attack.get("status_stacks", 1))
	_hitbox.call("set_attack_values", dmg, poise, dmg_type, status_id, status_stacks)
	_hitbox.call("enable")
	_hyperarmor_active = _weapon_data.get("archetype", "") == "greatsword"
	if _body:
		var anchor: Array = VfxService.resolve_combat_anchor(_body)
		VfxService.play_attack_swing(anchor[0], anchor[1])


func _disable_hitbox() -> void:
	_hyperarmor_active = false
	if _hitbox and _hitbox.has_method("disable"):
		_hitbox.call("disable")


func _end_attack() -> void:
	is_attacking = false
	current_phase = AttackPhase.IDLE
	_hyperarmor_active = false
	if _attack_name.begins_with("light"):
		_combo_index += 1
	attack_ended.emit()


func _process_bow_input(delta: float) -> void:
	if is_attacking:
		_process_attack_phase(delta)
		return
	if Input.is_action_pressed("heavy_attack"):
		current_phase = AttackPhase.DRAWING
		is_attacking = true
		_draw_charge = minf(1.0, _draw_charge + delta / float(_weapon_data.get("draw_time", 0.8)))
		return
	if current_phase == AttackPhase.DRAWING and _draw_charge > 0.05:
		_fire_bow_shot()
		return
	if Input.is_action_just_pressed("light_attack"):
		_try_attack("light")


func _fire_bow_shot() -> void:
	var heavy: Dictionary = _weapon_data.get("heavy_attack", {})
	var cost: float = heavy.get("stamina_cost", 18.0)
	if _stamina and not _stamina.has(cost):
		_reset_bow()
		return
	if _stamina:
		_stamina.consume(cost)
	var scaled := heavy.duplicate()
	scaled["damage"] = float(heavy.get("damage", 20.0)) * lerpf(0.5, 1.5, _draw_charge)
	_draw_charge = 0.0
	_current_attack = scaled
	is_attacking = true
	current_phase = AttackPhase.STARTUP
	_phase_timer = 0.08
	_attack_name = "bow_shot"
	_apply_hitbox_profile(true)
	attack_started.emit(_attack_name)


func _reset_bow() -> void:
	_draw_charge = 0.0
	is_attacking = false
	current_phase = AttackPhase.IDLE


func _apply_hitbox_profile(for_bow_shot: bool = false) -> void:
	if _hitbox_shape == null or _hitbox_shape.shape == null:
		return
	var archetype: String = _weapon_data.get("archetype", "sword")
	var size := DEFAULT_HITBOX_SIZE
	var offset := DEFAULT_HITBOX_OFFSET
	match archetype:
		"spear":
			size = Vector3(0.9, 0.7, 2.4)
			offset = Vector3(0.0, 0.0, 1.35)
		"dagger":
			size = Vector3(0.8, 0.6, 0.9)
			offset = Vector3(0.0, 0.0, 0.4)
		"greatsword":
			size = Vector3(1.6, 1.0, 1.8)
			offset = Vector3(0.0, 0.0, 0.85)
		"bow":
			size = Vector3(0.6, 0.6, 8.0 if for_bow_shot else 1.0)
			offset = Vector3(0.0, 0.0, 4.0 if for_bow_shot else 0.5)
	if _hitbox_shape.shape is BoxShape3D:
		(_hitbox_shape.shape as BoxShape3D).size = size
	_hitbox_shape.position = offset


func _is_action_blocked() -> bool:
	if _combat_reactions and _combat_reactions.has_method("can_act"):
		if not _combat_reactions.call("can_act") and not _hyperarmor_active:
			return true
	var status_ctrl := _body.get_node_or_null("StatusController") as StatusController
	if status_ctrl and status_ctrl.is_stunned():
		return true
	return false
