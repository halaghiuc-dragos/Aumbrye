extends Node
class_name Guard


const CombatStatModifiersScript := preload("res://scripts/combat/combat_stat_modifiers.gd")

const TUNING_PATH := "content/combat/guard.json"
const FALLBACK_TUNING := {
	"parry_window": 0.18,
	"parry_window_by_class": {"parryable": 1.35, "blockable": 1.0},
	"block_reduction": {"physical": 0.55, "default": 0.35},
	"guard_break_on_unblockable": true,
	"grab_duration": 1.6,
}

const BLOCK_STAMINA_PER_POISE := 0.55
const BLOCK_DAMAGE_REDUCTION := 0.55
const BLOCK_POISE_TRANSFER := 0.35
const GUARD_BREAK_STAGGER := 0.8
const BLOCK_ARC_DEGREES := 120.0
const PARRY_WINDOW := 0.18
const PARRY_STAMINA_COST := 10.0
const PARRY_COOLDOWN := 0.4
const PARRY_STAGGER_ENEMY := 1.2
const RIPOSTE_WINDOW := 1.4
const RIPOSTE_DAMAGE_MULT := 2.0
const DEFAULT_ELEMENTAL_REDUCTION := 0.35
## Poise damage at or above this breaks a shieldless guard, so `castle_enemy_base` derives an
## attack's `unblockable` class from it. Changing this re-colours telegraphs across the bestiary.
const DEFAULT_GUARD_BREAK_POISE := 26.0

enum GuardState { IDLE, GUARDING, GUARD_BROKEN }

signal guard_broken
signal block_state_changed(blocking: bool)
signal parry_success(target: Node)
signal riposte_ready

var is_blocking := false
var guard_broken_state := false
var parry_window_active := false
var is_guard_active := false
var riposte_active := false
var parried_target: Node = null

var _body: CharacterBody3D
var _stamina: Stamina
## A caster raising a shield gets the same slowed-not-stopped regen a melee build gets on
## `_stamina` -- mirrors it exactly rather than leaving mana at full regen while blocking.
var _mana: Mana
var _poise: Poise
var _weapon: WeaponController
var _stagger_timer := 0.0
var _state := GuardState.IDLE
var _parry_timer := 0.0
var _riposte_timer := 0.0
var _block_reduction_bonus := 0.0
var _block_reduction_by_type: Dictionary = {}
var _guard_break_poise := DEFAULT_GUARD_BREAK_POISE
var _block_stability := 1.0
var _last_block_cost := 0.0
var _parry_cooldown_timer := 0.0
var _parry_ready := false

var _parry_window := PARRY_WINDOW
var _parry_window_by_class: Dictionary = {}
var _tuning_block_reduction: Dictionary = {}
var _guard_break_on_unblockable := true
var _grab_duration := 1.6


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_mana = _body.get_node_or_null("Mana") as Mana
	_poise = _body.get_node_or_null("Poise") as Poise
	_weapon = _body.get_node_or_null("WeaponController") as WeaponController
	_load_tuning()


func _load_tuning() -> void:
	var data := ContentLoader.load_json(TUNING_PATH)
	if data.is_empty():
		data = FALLBACK_TUNING.duplicate(true)
	_parry_window = float(data.get("parry_window", PARRY_WINDOW))
	_parry_window_by_class = data.get("parry_window_by_class", {})
	_tuning_block_reduction = data.get("block_reduction", {})
	_guard_break_on_unblockable = bool(data.get("guard_break_on_unblockable", true))
	_grab_duration = float(data.get("grab_duration", 1.6))


func _physics_process(delta: float) -> void:
	if _parry_cooldown_timer > 0.0:
		_parry_cooldown_timer -= delta
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			guard_broken_state = false
			_reset_guard_state()
		else:
			_state = GuardState.GUARD_BROKEN
			is_blocking = false
			parry_window_active = false
			is_guard_active = false
		return

	if _riposte_timer > 0.0:
		_riposte_timer -= delta
		if _riposte_timer <= 0.0:
			riposte_active = false
			parried_target = null
	if parried_target != null and not is_instance_valid(parried_target):
		riposte_active = false
		parried_target = null

	var reactions := _body.get_node_or_null("CombatReactions") as PlayerCombatReactions
	var heal := _body.get_node_or_null("PlayerHeal") as PlayerHeal
	var dodge := _body.get_node_or_null("Dodge") as Dodge
	if (reactions and not reactions.can_act()) or (heal and heal.is_drinking) or (dodge and dodge.is_dodging):
		if _state == GuardState.GUARDING:
			_end_guard()
		return

	match _state:
		GuardState.IDLE:
			is_blocking = false
			parry_window_active = false
			is_guard_active = false
			if (
				PlayerInput.just_pressed(&"block")
				and not guard_broken_state
				and (_weapon == null or _weapon.allows_cancel_into("guard"))
			):
				_enter_guard()
		GuardState.GUARDING:
			_parry_timer -= delta
			parry_window_active = _parry_timer > 0.0
			is_blocking = true
			is_guard_active = true
			if not PlayerInput.pressed(&"block"):
				_end_guard()
		GuardState.GUARD_BROKEN:
			is_blocking = false
			parry_window_active = false
			is_guard_active = false
			if not guard_broken_state:
				_state = GuardState.IDLE


func _enter_guard() -> void:
	_parry_ready = (
		(_stamina == null or _stamina.has(PARRY_STAMINA_COST)) and _parry_cooldown_timer <= 0.0
	)
	_state = GuardState.GUARDING
	_parry_timer = _parry_window if _parry_ready else 0.0
	_parry_cooldown_timer = PARRY_COOLDOWN
	is_guard_active = true
	if _stamina:
		_stamina.set_regen_state(Stamina.RegenState.BLOCKING)
	if _mana:
		_mana.set_regen_state(Mana.RegenState.BLOCKING)
	block_state_changed.emit(true)


func _end_guard() -> void:
	_reset_guard_state()
	block_state_changed.emit(false)


func _reset_guard_state() -> void:
	if _stamina:
		var dodge := _body.get_node_or_null("Dodge") as Dodge
		_stamina.set_regen_state(
			Stamina.RegenState.SUPPRESSED if dodge and dodge.is_dodging else Stamina.RegenState.NORMAL
		)
	if _mana:
		_mana.set_regen_state(Mana.RegenState.NORMAL)
	_state = GuardState.IDLE
	_parry_timer = 0.0
	is_blocking = false
	parry_window_active = false
	is_guard_active = false


func set_combat_stat_modifiers(
	equipment_stats: Dictionary, talent_stats: Dictionary, block_data: Dictionary = {}
) -> void:
	_block_reduction_bonus = CombatStatModifiersScript.block_reduction_bonus(
		equipment_stats, talent_stats
	)
	_block_stability = maxf(
		0.1, float(block_data.get("stability", 1.0)) + ClassPerks.bulwark_stability_bonus(_body)
	)
	_guard_break_poise = maxf(0.0, float(block_data.get("guardBreakPoise", DEFAULT_GUARD_BREAK_POISE)))
	_block_reduction_by_type = _parse_block_reduction(block_data.get("reduction"))


func _parse_block_reduction(value: Variant) -> Dictionary:
	var table: Dictionary = {}
	if value is Dictionary:
		for damage_type in DamageInfo.ALL_TYPES:
			if (value as Dictionary).has(damage_type):
				table[damage_type] = clampf(float((value as Dictionary)[damage_type]), 0.0, 0.95)
	elif value != null:
		var flat := clampf(float(value), 0.0, 0.95)
		for damage_type in DamageInfo.ALL_TYPES:
			table[damage_type] = flat
	return table


func get_grab_duration() -> float:
	return _grab_duration


func _reduction_for(damage_type: String) -> float:
	if _block_reduction_by_type.has(damage_type):
		return float(_block_reduction_by_type[damage_type])
	if damage_type == DamageInfo.TYPE_PHYSICAL:
		return float(_tuning_block_reduction.get("physical", BLOCK_DAMAGE_REDUCTION))
	return float(_tuning_block_reduction.get("default", DEFAULT_ELEMENTAL_REDUCTION))


## An `unblockable` attack skips the block path entirely -- holding shield into a red
## telegraph breaks the guard rather than mitigating the hit, punishing the player for trusting
## colour over the tell. `_guard_break_on_unblockable` only fires the break when the guard was
## actually raised; a hit that arrives while idle is not "holding shield into red".
func modify_incoming_hit(
	info: DamageInfo, arc: DamageInfo.HitArc = DamageInfo.HitArc.FRONT
) -> Dictionary:
	if _stagger_timer > 0.0 or not is_guard_active:
		return {"amount": info.amount, "poise": info.poise_damage}
	if arc != DamageInfo.HitArc.FRONT:
		return {"amount": info.amount, "poise": info.poise_damage}
	if info.attack_class == "unblockable":
		if _guard_break_on_unblockable:
			_trigger_guard_break()
		return {"amount": info.amount, "poise": info.poise_damage, "blocked": false}
	if _guard_break_poise > 0.0 and info.poise_damage >= _guard_break_poise * _block_stability:
		_trigger_guard_break()
		return {"amount": info.amount, "poise": info.poise_damage, "blocked": false}
	var stamina_cost := info.poise_damage * BLOCK_STAMINA_PER_POISE / _block_stability
	_last_block_cost = stamina_cost
	if _stamina == null or not _stamina.consume(stamina_cost):
		_trigger_guard_break()
		return {"amount": info.amount, "poise": info.poise_damage, "blocked": false}
	var reduction := clampf(_reduction_for(info.damage_type) + _block_reduction_bonus, 0.0, 0.95)
	var poise_mult := BLOCK_POISE_TRANSFER / _block_stability
	if _body and CombatEvents:
		CombatEvents.dispatch(
			CombatEvents.ON_BLOCK,
			{
				"actor": _body,
				"target": info.source,
				"amount": info.amount * (1.0 - reduction),
				"damageType": info.damage_type,
			}
		)
	return {
		"amount": info.amount * (1.0 - reduction),
		"poise": info.poise_damage * poise_mult,
		"blocked": true,
	}


## `attack_class` widens (or shuts) the parry window: `unblockable` and `grab` can
## never be parried, and `parryable` gets the generous multiplier from `guard.json` -- the blue
## telegraph is the one the game wants read and answered, so it forgives a later reaction than an
## amber one would.
func try_parry_attack(
	attacker: Node,
	arc: DamageInfo.HitArc = DamageInfo.HitArc.FRONT,
	attack_class: String = "blockable",
	is_projectile: bool = false,
	impact_direction: Vector3 = Vector3.ZERO
) -> bool:
	if _state != GuardState.GUARDING or not _parry_ready:
		return false
	if attack_class == "unblockable" or attack_class == "grab":
		return false
	if arc != DamageInfo.HitArc.FRONT:
		return false
	if not _is_within_block_arc(impact_direction):
		return false
	var multiplier := float(_parry_window_by_class.get(attack_class, 1.0))
	var elapsed := _parry_window - _parry_timer
	if elapsed < 0.0 or elapsed > _parry_window * multiplier:
		return false
	if _stamina and _stamina.is_exhausted():
		return false
	if _stamina and not _stamina.consume(PARRY_STAMINA_COST):
		return false
	_stagger_attacker(attacker)
	if attacker and attacker.has_method("get_enemy_id"):
		BestiaryService.record_counter(str(attacker.call("get_enemy_id")), "parry")
	if RunBuffs:
		RunBuffs.note_combat_moment("parry")
	parry_success.emit(attacker)
	riposte_active = true
	parried_target = attacker
	_riposte_timer = RIPOSTE_WINDOW
	riposte_ready.emit()
	if _body and CombatEvents:
		CombatEvents.dispatch(CombatEvents.ON_PARRY, {"actor": _body, "target": attacker})
	if _body:
		var anchor: Array = VfxService.resolve_combat_anchor(_body)
		VfxService.play_parry(anchor[0], anchor[1])
		# Timing a shield perfectly against an arrow should feel like a clean win, not a
		# break-even trade -- refund what the parry itself cost, on top of the deflected shot never
		# spending anything else.
		if is_projectile:
			VfxService.play_parry_spark(anchor[0], anchor[1])
			if _stamina:
				_stamina.restore(PARRY_STAMINA_COST)
	_end_guard()
	block_state_changed.emit(false)
	return true


func _stagger_attacker(attacker: Node) -> void:
	var target: Node = attacker
	if target and not target.has_method("apply_stagger"):
		if target.get_parent() and target.get_parent().has_method("apply_stagger"):
			target = target.get_parent()
	if target and target.has_method("apply_stagger"):
		target.call("apply_stagger", PARRY_STAGGER_ENEMY)
	if target and target.has_method("cancel_attack"):
		target.call("cancel_attack")
	elif attacker and attacker.has_method("disable"):
		attacker.call("disable")


func consume_riposte() -> void:
	riposte_active = false
	parried_target = null
	_riposte_timer = 0.0


func locks_movement() -> bool:
	return _stagger_timer > 0.0


func reset_after_revive() -> void:
	guard_broken_state = false
	_stagger_timer = 0.0
	_state = GuardState.IDLE
	riposte_active = false
	parried_target = null
	_riposte_timer = 0.0
	_reset_guard_state()


## The one definition of "frontal" for this body, against `BLOCK_ARC_DEGREES` -- the same arc
## `modify_incoming_hit()` and `try_parry_attack()` use via `DamageInfo.classify_arc()`. Public so
## the animation layer (`PlayerAnimDirector`) can ask it directly instead of keeping its own copy
## that disagreed with the mechanics about what counts as a blocked hit.
func is_frontal_hit(direction: Vector3) -> bool:
	if direction.length_squared() < 0.01:
		return true
	var facing := CombatFacing.aim_forward_of(_body)
	var angle := rad_to_deg(facing.angle_to(-direction.normalized()))
	return angle <= BLOCK_ARC_DEGREES * 0.5


func _is_within_block_arc(impact_direction: Vector3) -> bool:
	if _body == null:
		return true
	if impact_direction.length_squared() < 0.01:
		return true
	var to_attacker := -impact_direction
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.01:
		return true
	var facing := CombatFacing.aim_forward_of(_body)
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		return true
	var angle := rad_to_deg(facing.normalized().angle_to(to_attacker.normalized()))
	return angle <= BLOCK_ARC_DEGREES * 0.5


func _trigger_guard_break() -> void:
	guard_broken_state = true
	_state = GuardState.GUARD_BROKEN
	_parry_timer = 0.0
	is_blocking = false
	parry_window_active = false
	is_guard_active = false
	_stagger_timer = maxf(GUARD_BREAK_STAGGER, _poise_break_duration())
	if _poise:
		_poise.take_poise_damage(_poise.max_poise)
	guard_broken.emit()
	block_state_changed.emit(false)
	if _body and CombatEvents:
		CombatEvents.dispatch(CombatEvents.ON_GUARD_BREAK, {"actor": _body})


func _poise_break_duration() -> float:
	if _poise and "break_duration" in _poise:
		return maxf(0.0, float(_poise.break_duration))
	return 0.0
