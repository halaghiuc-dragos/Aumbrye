extends Node

enum AttackPhase { IDLE, STARTUP, ACTIVE, RECOVERY, DRAWING }

const CombatStatModifiersScript := preload("res://scripts/combat/combat_stat_modifiers.gd")
const WEAPON_DATA_RELATIVE := "content/weapons/sword_basic.json"
const DEFAULT_HITBOX_SIZE := Vector3(1.2, 0.8, 1.4)
const DEFAULT_HITBOX_OFFSET := Vector3(0.0, 0.0, 0.55)
const COMMIT_SPEED_MULT := 0.2
const RECOVERY_SPEED_MULT := 0.55
const ATTACK_ROT_CAP_MULT := 0.15
const SOFT_LOCK_CONE_DEG := 100.0
const SOFT_LOCK_RANGE := 14.0
const TWO_HAND_DAMAGE_MULT := 1.25
const TWO_HAND_POISE_MULT := 1.35

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
signal weapon_changed(archetype: String)

@export var hitbox_path: NodePath

var is_attacking := false
var current_phase := AttackPhase.IDLE
var is_bow_aiming := false

var _body: CharacterBody3D
var _stamina: Stamina
var _hitbox: Area3D
var _hitbox_shape: CollisionShape3D
var _combat_reactions: Node
var _guard: Node
var _lock_on: LockOn
var _weapon_data: Dictionary = {}
var _combo_index := 0
var _phase_timer := 0.0
var _current_attack: Dictionary = {}
var _buffered_attack := ""
var _attack_name := ""
var _damage_multiplier := 1.0
var _draw_charge := 0.0
var _hyperarmor_active := false
var _two_hand := false
var _combo_idle_timer := 0.0
var _base_damage_multiplier := 1.0
var _weapon_scaling_multiplier := 1.0
var _class_stats: Dictionary = {}
var _talent_stats: Dictionary = {}


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_combat_reactions = _body.get_node_or_null("CombatReactions")
	_guard = _body.get_node_or_null("Guard")
	_lock_on = _body.get_node_or_null("LockOn") as LockOn
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
	if _combo_idle_timer > 0.0:
		_combo_idle_timer -= delta
		if _combo_idle_timer <= 0.0:
			_combo_index = 0
	if _is_action_blocked():
		return
	var archetype: String = _weapon_data.get("archetype", "sword")
	if archetype == "bow":
		_process_bow_input(delta)
		return
	if Input.is_action_just_pressed("two_hand"):
		_toggle_two_hand()
	if Input.is_action_just_pressed("weapon_art"):
		_try_weapon_art()
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
	_weapon_scaling_multiplier = CombatStatModifiersScript.weapon_scaling_multiplier(
		_weapon_data.get("scaling", {}),
		_class_stats
	)
	_refresh_damage_multiplier()
	_apply_hitbox_profile()
	weapon_changed.emit(get_archetype())


func get_archetype() -> String:
	return String(_weapon_data.get("archetype", "sword"))


func get_current_attack_phases() -> Dictionary:
	return {
		"startup": float(_current_attack.get("startup", 0.2)),
		"active": float(_current_attack.get("active", 0.15)),
		"recovery": float(_current_attack.get("recovery", 0.3)),
	}


func set_damage_multiplier(multiplier: float) -> void:
	_base_damage_multiplier = maxf(0.1, multiplier)
	_refresh_damage_multiplier()


func set_combat_stat_modifiers(
	equipment_stats: Dictionary,
	talent_stats: Dictionary,
	class_stats: Dictionary = {}
) -> void:
	_class_stats = class_stats
	_talent_stats = talent_stats
	_weapon_scaling_multiplier = CombatStatModifiersScript.weapon_scaling_multiplier(
		_weapon_data.get("scaling", {}),
		_class_stats
	)
	set_damage_multiplier(CombatStatModifiersScript.damage_multiplier(equipment_stats, talent_stats))


func has_hyperarmor() -> bool:
	return _hyperarmor_active


func locks_movement() -> bool:
	if not is_attacking:
		return false
	if current_phase == AttackPhase.DRAWING:
		return true
	if current_phase == AttackPhase.RECOVERY and _can_dodge_cancel():
		return false
	return current_phase in [AttackPhase.STARTUP, AttackPhase.ACTIVE, AttackPhase.RECOVERY]


func get_move_speed_multiplier() -> float:
	if not is_attacking:
		return 1.0
	if current_phase in [AttackPhase.STARTUP, AttackPhase.ACTIVE, AttackPhase.DRAWING]:
		return COMMIT_SPEED_MULT
	if current_phase == AttackPhase.RECOVERY:
		return RECOVERY_SPEED_MULT
	return 1.0


func get_rotation_cap_multiplier() -> float:
	if is_attacking and current_phase in [AttackPhase.STARTUP, AttackPhase.ACTIVE, AttackPhase.DRAWING]:
		return ATTACK_ROT_CAP_MULT
	return 1.0


func get_attack_lunge_velocity() -> Vector3:
	# Attack displacement is handled by the diorama animation rig only.
	return Vector3.ZERO


func enable_hitbox_from_anim() -> void:
	if is_attacking and current_phase == AttackPhase.ACTIVE:
		_enable_hitbox_for_attack()


func disable_hitbox_from_anim() -> void:
	_disable_hitbox()


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
	var cost: float = _scaled_stamina_cost(float(attack.get("stamina_cost", 10.0)))
	if _stamina and not _stamina.has(cost):
		return
	if _stamina:
		_stamina.consume(cost)
	_snap_soft_lock_facing()
	_start_attack(attack)


func _try_weapon_art() -> void:
	if is_attacking:
		return
	var art: Dictionary = _weapon_data.get("art", {})
	if art.is_empty():
		return
	var cost: float = _scaled_stamina_cost(float(art.get("stamina_cost", 24.0)))
	if _stamina and not _stamina.has(cost):
		return
	if _stamina:
		_stamina.consume(cost)
	var attack := {
		"damage": float(art.get("damage", 20.0)),
		"poise_damage": float(art.get("poise_damage", 18.0)),
		"startup": float(art.get("startup", 0.25)),
		"active": float(art.get("active", 0.18)),
		"recovery": float(art.get("recovery", 0.4)),
		"hyperarmor": true,
	}
	_attack_name = "weapon_art"
	_snap_soft_lock_facing()
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
			_snap_soft_lock_facing()
			_enable_hitbox_for_attack()
		AttackPhase.ACTIVE:
			current_phase = AttackPhase.RECOVERY
			_phase_timer = _current_attack.get("recovery", 0.3)
			_disable_hitbox()
		AttackPhase.RECOVERY:
			_end_attack()
		AttackPhase.DRAWING:
			pass


func _enable_hitbox_for_attack() -> void:
	if _hitbox == null or not _hitbox.has_method("enable"):
		return
	var dmg: float = float(_current_attack.get("damage", 10.0)) * _damage_multiplier
	var poise: float = float(_current_attack.get("poise_damage", 10.0)) * _damage_multiplier
	if _guard and _guard.has_method("get_riposte_damage_multiplier"):
		var riposte_mult: float = _guard.call("get_riposte_damage_multiplier")
		if riposte_mult > 1.0:
			dmg *= riposte_mult
			poise *= riposte_mult
			_guard.call("consume_riposte")
	var dmg_type: String = _current_attack.get("damage_type", _weapon_data.get("damage_type", "physical"))
	var status_id: String = _current_attack.get("status", _weapon_data.get("status_on_hit", ""))
	var status_stacks: int = int(_current_attack.get("status_stacks", 1))
	_hitbox.call("set_attack_values", dmg, poise, dmg_type, status_id, status_stacks)
	_hitbox.call("enable")
	_hyperarmor_active = bool(_current_attack.get("hyperarmor", false))
	if not _hyperarmor_active:
		_hyperarmor_active = float(_current_attack.get("poise_threshold", 0.0)) > 0.0
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
	var buffer_window: float = _weapon_data.get("buffer_window", 0.2)
	var recovery: float = float(_current_attack.get("recovery", 0.3))
	_combo_idle_timer = buffer_window + recovery
	if _attack_name.begins_with("light"):
		_combo_index += 1
	attack_ended.emit()


func _process_bow_input(delta: float) -> void:
	is_bow_aiming = Input.is_action_pressed("block") or Input.is_action_pressed("light_attack")
	if is_attacking and current_phase == AttackPhase.DRAWING:
		if Input.is_action_pressed("heavy_attack"):
			_draw_charge = minf(1.0, _draw_charge + delta / float(_weapon_data.get("draw_time", 0.8)))
		elif _draw_charge > 0.05:
			_fire_bow_shot()
		else:
			_reset_bow()
		return
	if is_attacking:
		_process_attack_phase(delta)
		return
	if Input.is_action_pressed("heavy_attack"):
		current_phase = AttackPhase.DRAWING
		is_attacking = true
		_draw_charge = minf(1.0, _draw_charge + delta / float(_weapon_data.get("draw_time", 0.8)))
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
	_snap_soft_lock_facing()
	attack_started.emit(_attack_name)


func _reset_bow() -> void:
	_draw_charge = 0.0
	is_attacking = false
	current_phase = AttackPhase.IDLE
	is_bow_aiming = false


func _toggle_two_hand() -> void:
	if get_archetype() in ["bow", "dagger"]:
		return
	_two_hand = not _two_hand
	_refresh_damage_multiplier()


func _refresh_damage_multiplier() -> void:
	var stance_mult := TWO_HAND_DAMAGE_MULT if _two_hand else 1.0
	_damage_multiplier = _base_damage_multiplier * _weapon_scaling_multiplier * stance_mult


func _can_dodge_cancel() -> bool:
	if current_phase != AttackPhase.RECOVERY:
		return false
	var recovery: float = float(_current_attack.get("recovery", 0.3))
	return _phase_timer <= recovery * 0.35


func _scaled_stamina_cost(base_cost: float) -> float:
	return base_cost * CombatStatModifiersScript.stamina_cost_multiplier(_talent_stats)


func _snap_soft_lock_facing() -> void:
	if _lock_on and _lock_on.is_locked and _lock_on.current_target:
		_face_target(_lock_on.current_target)
		return
	var target := _find_soft_lock_target()
	if target:
		_face_target(target)


func _get_soft_lock_aim_direction() -> Vector3:
	if _body == null:
		return Vector3.FORWARD
	var camera_pivot := _body.get_node_or_null("CameraPivot") as Node3D
	if camera_pivot:
		var dir := -camera_pivot.global_transform.basis.z
		dir.y = 0.0
		if dir.length_squared() > 0.01:
			return dir.normalized()
	if _body.has_method("get_facing_direction"):
		var facing: Vector3 = _body.call("get_facing_direction")
		facing.y = 0.0
		if facing.length_squared() > 0.01:
			return facing.normalized()
	return Vector3.FORWARD


func _face_target(target: Node3D) -> void:
	if _body == null or target == null:
		return
	var facing := _body.get_node_or_null("Facing") as Node3D
	if facing == null:
		return
	var to_target := target.global_position - _body.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return
	facing.rotation.y = atan2(to_target.x, to_target.z)


func _find_soft_lock_target() -> Node3D:
	if _body == null:
		return null
	var best: Node3D
	var best_score := -INF
	var facing := _get_soft_lock_aim_direction()
	for node in get_tree().get_nodes_in_group("lockable"):
		if not node is Node3D or not is_instance_valid(node):
			continue
		if node.has_method("is_dead") and node.call("is_dead"):
			continue
		var offset := (node as Node3D).global_position - _body.global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist > SOFT_LOCK_RANGE or dist < 0.01:
			continue
		var dir := offset / dist
		var angle := rad_to_deg(facing.angle_to(dir))
		if angle > SOFT_LOCK_CONE_DEG:
			continue
		var score := (SOFT_LOCK_CONE_DEG - angle) / dist
		if score > best_score:
			best_score = score
			best = node as Node3D
	return best


func _apply_hitbox_profile(for_bow_shot: bool = false) -> void:
	if _hitbox_shape == null or _hitbox_shape.shape == null:
		return
	var archetype: String = _weapon_data.get("archetype", "sword")
	var size := DEFAULT_HITBOX_SIZE
	var offset := DEFAULT_HITBOX_OFFSET
	match archetype:
		"spear":
			size = Vector3(1.0, 0.75, 1.65)
			offset = Vector3(0.0, 0.0, 0.72)
		"dagger":
			size = Vector3(0.8, 0.6, 0.9)
			offset = Vector3(0.0, 0.0, 0.4)
		"greatsword":
			size = Vector3(1.6, 1.0, 1.8)
			offset = Vector3(0.0, 0.0, 0.85)
		"axe":
			size = Vector3(1.4, 0.9, 1.5)
			offset = Vector3(0.0, 0.0, 0.75)
		"staff":
			size = Vector3(0.8, 0.7, 2.0)
			offset = Vector3(0.0, 0.0, 1.1)
		"bow":
			size = Vector3(0.6, 0.6, 8.0 if for_bow_shot else 1.0)
			offset = Vector3(0.0, 0.0, 4.0 if for_bow_shot else 0.5)
	if _two_hand and archetype != "bow":
		size *= 1.1
		offset.z *= 1.08
	if _hitbox_shape.shape is BoxShape3D:
		(_hitbox_shape.shape as BoxShape3D).size = size
	_hitbox_shape.position = offset


func _is_action_blocked() -> bool:
	var dodge := _body.get_node_or_null("Dodge")
	if dodge and dodge.get("is_dodging"):
		return true
	if _guard and _guard.get("is_guard_active"):
		return true
	if _combat_reactions and _combat_reactions.has_method("can_act"):
		if not _combat_reactions.call("can_act") and not _hyperarmor_active:
			return true
	var status_ctrl := _body.get_node_or_null("StatusController") as StatusController
	if status_ctrl and status_ctrl.is_stunned():
		return true
	return false
