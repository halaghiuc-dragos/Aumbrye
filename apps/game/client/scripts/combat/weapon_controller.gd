extends Node

enum AttackPhase { IDLE, STARTUP, ACTIVE, RECOVERY }

const WEAPON_DATA_RELATIVE := "content/weapons/sword_basic.json"
const FALLBACK_WEAPON_DATA := {
	"buffer_window": 0.2,
	"light_attacks": [
		{
			"damage": 12.0,
			"poise_damage": 10.0,
			"stamina_cost": 8.0,
			"startup": 0.15,
			"active": 0.12,
			"recovery": 0.25,
		}
	],
	"heavy_attack": {
		"damage": 28.0,
		"poise_damage": 35.0,
		"stamina_cost": 22.0,
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
var _combat_reactions: Node
var _weapon_data: Dictionary = {}
var _combo_index := 0
var _phase_timer := 0.0
var _current_attack: Dictionary = {}
var _buffered_attack := ""
var _attack_name := ""


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_combat_reactions = _body.get_node_or_null("CombatReactions")
	if hitbox_path:
		_hitbox = get_node_or_null(hitbox_path) as Area3D
		if _hitbox == null:
			push_error("WeaponController: hitbox not found at %s" % hitbox_path)
		elif not _hitbox.has_method("enable"):
			push_error("WeaponController: node at %s is not a Hitbox" % hitbox_path)
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
	var overlap := 0
	if _hitbox and _hitbox.has_method("get_last_overlap_count"):
		overlap = _hitbox.call("get_last_overlap_count")
	return "%s (%s overlaps)" % [phase_name, overlap]


func _physics_process(delta: float) -> void:
	if _is_action_blocked():
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


func _load_weapon_data() -> void:
	_weapon_data = ContentLoader.load_json(WEAPON_DATA_RELATIVE)
	if _weapon_data.is_empty():
		push_warning("WeaponController: using fallback weapon data")
		_weapon_data = FALLBACK_WEAPON_DATA.duplicate(true)


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
			push_warning("WeaponController: no light attacks configured")
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
			if _hitbox and _hitbox.has_method("enable"):
				_hitbox.call("set_attack_values", _current_attack.get("damage", 10.0), _current_attack.get("poise_damage", 10.0))
				_hitbox.call("enable")
		AttackPhase.ACTIVE:
			current_phase = AttackPhase.RECOVERY
			_phase_timer = _current_attack.get("recovery", 0.3)
			if _hitbox and _hitbox.has_method("disable"):
				_hitbox.call("disable")
		AttackPhase.RECOVERY:
			_end_attack()


func _end_attack() -> void:
	is_attacking = false
	current_phase = AttackPhase.IDLE
	if _attack_name.begins_with("light"):
		_combo_index += 1
	attack_ended.emit()


func _is_action_blocked() -> bool:
	if _combat_reactions and _combat_reactions.has_method("can_act"):
		return not _combat_reactions.call("can_act")
	return false
