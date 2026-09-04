extends Area3D
class_name Hurtbox

const DEBUG_SCRIPT := preload("res://scripts/combat/combat_collision_debug.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const DamageResolutionScript := preload("res://scripts/combat/damage_resolution.gd")
const HitFeedbackScript := preload("res://scripts/combat/hit_feedback.gd")
## Armour follows a diminishing-returns curve rather than a straight line.
##
## The old rule was `points * 0.02`, capped at 90%. Defence and armour sum across all nine
## equipment slots, and the gear in the content tree carries enough of both that the player crossed
## the cap in the *second* biome of ten -- from there on they took a flat tenth of every hit, for
## the rest of the game, no matter what hit them. That is why a training dummy could swing at the
## player all day and why every telegraph in the game was safe to ignore.
##
## `points / (points + DEFENSE_SOFTENING)` never reaches immunity, so another point of armour is
## always worth something and never trivialises the fight. At the softening constant below a
## starting loadout removes about a fifth of incoming damage and a fully geared one about a half.
## The remaining cap is there so flat damageReduction cannot stack past it either.
const DEFENSE_SOFTENING := 340.0
const DEFENSE_CAP := 0.75
const HYPERARMOR_POISE_MULT := 0.25
const POISE_BROKEN_DAMAGE_MULT := 1.35
const EXHAUSTED_POISE_MULT := 1.5
## `PH-01`: a hit that breaks poise this frame shoves harder -- the number that finally makes a
## poise break *look* like the swing that caused it rather than a stat crossing a threshold.
const POISE_BREAK_KNOCKBACK_MULT := 2.0
const KNOCKBACK_MASS_MIN := 0.5
const KNOCKBACK_MASS_MAX := 3.0

signal damaged(info: DamageInfo)
signal hurt_received(amount: float, poise_damage: float, direction: Vector3)
signal hit_resolved(resolution: RefCounted)

@export var team: String = "enemy"
@export var health_path: NodePath
@export var poise_path: NodePath
@export var region: String = "body"
@export var region_damage_mult := 1.0
@export var region_poise_mult := 1.0

var _health: Health
var _poise: Poise
var _status_controller: StatusController
var _cached_dodge: Node
var _cached_guard: Node
var _cached_character_body: Node3D


func _ready() -> void:
	add_to_group("combat_hurtbox")
	monitorable = true
	if health_path:
		_health = get_node(health_path) as Health
	if poise_path:
		_poise = get_node(poise_path) as Poise
	_status_controller = _resolve_status_controller()
	DEBUG_SCRIPT.set_debug_draw(self, false, DEBUG_SCRIPT.HURTBOX_COLOR)
	tree_entered.connect(_refresh_sibling_cache)
	_refresh_sibling_cache()


func _refresh_sibling_cache() -> void:
	_cached_dodge = _find_dodge()
	_cached_guard = _find_guard()
	_cached_character_body = CombatGroups.owning_body(self)


func set_debug_draw(enabled: bool) -> void:
	DEBUG_SCRIPT.set_debug_draw(self, enabled, DEBUG_SCRIPT.HURTBOX_COLOR)


func receive_hit(info: DamageInfo) -> void:
	var res: RefCounted = DamageResolutionScript.new()
	res.incoming = info.amount
	res.outgoing = info.amount
	res.poise_incoming = info.poise_damage
	res.poise_outgoing = info.poise_damage
	res.damage_type = info.damage_type
	res.crit = info.crit
	res.region = region

	if _health and _health.is_dead():
		hit_resolved.emit(res)
		return

	if not info.ignore_iframes:
		var dodge := _cached_dodge
		if dodge and dodge.get("iframes_active"):
			res.dodged = true
			res.outgoing = 0.0
			res.poise_outgoing = 0.0
			var iframe_body := _cached_character_body
			if iframe_body:
				var iframe_feedback := iframe_body.get_node_or_null("HitFeedback")
				if iframe_feedback and iframe_feedback.has_method("on_dodge_iframe"):
					iframe_feedback.call("on_dodge_iframe")
				# CB-06: "a dodge that actually avoided a hit" -- the timed i-frame dodge, not the
				# passive evasion-stat roll below (that is a miss chance, not a player action).
				if CombatEvents:
					CombatEvents.dispatch(
						CombatEvents.ON_PERFECT_DODGE, {"actor": iframe_body, "target": info.source}
					)
			hit_resolved.emit(res)
			return

	var owner_body := _cached_character_body
	# Evasion is rolled before guard, arc and armour so a slipped hit is a clean miss rather than a
	# hit that happens to arrive at zero: the difference is visible, since a miss plays no impact,
	# costs no poise and cannot apply a status.
	if not info.periodic and _roll_evasion(owner_body):
		res.dodged = true
		res.outgoing = 0.0
		res.poise_outgoing = 0.0
		var evade_feedback := owner_body.get_node_or_null("HitFeedback") if owner_body else null
		if evade_feedback and evade_feedback.has_method("on_dodge_iframe"):
			evade_feedback.call("on_dodge_iframe")
		hit_resolved.emit(res)
		return
	if owner_body and owner_body.has_method("is_immune") and owner_body.call("is_immune"):
		res.outgoing = 0.0
		res.poise_outgoing = 0.0
		hit_resolved.emit(res)
		return

	if info.attack_class == "grab" and not info.periodic and _try_apply_grab(info, owner_body, res):
		hit_resolved.emit(res)
		return

	var arc := DamageInfo.HitArc.FRONT
	if owner_body and info.source:
		arc = DamageInfo.classify_arc(owner_body, info.source.global_position)

	var guard := _cached_guard if not info.ignore_guard else null
	if guard and guard.has_method("try_parry_attack") and info.source:
		if guard.call("try_parry_attack", info.source, arc, info.attack_class):
			res.parried = true
			res.outgoing = 0.0
			res.poise_outgoing = 0.0
			hit_resolved.emit(res)
			return
	# CB-03: attempted only once the parry itself was unavailable (unaffordable or on cooldown) --
	# `try_just_guard()` checks its own tighter timing window independently.
	if guard and guard.has_method("try_just_guard") and info.source:
		if guard.call("try_just_guard", info.source, arc, info.attack_class):
			res.blocked = true
			res.outgoing = 0.0
			res.poise_outgoing = 0.0
			hit_resolved.emit(res)
			return

	var final_amount := info.amount
	var final_poise := info.poise_damage
	var blocked := false
	if guard and guard.has_method("modify_incoming_hit"):
		var modified: Dictionary = guard.call("modify_incoming_hit", info, arc)
		final_amount = modified.get("amount", final_amount)
		final_poise = modified.get("poise", final_poise)
		if modified.get("blocked", false):
			blocked = true
			res.blocked = true
			_emit_block_feedback(final_amount)

	final_amount = _apply_arc_multipliers(
		final_amount, final_poise, info, res, DamageInfo.HitArc.FRONT if blocked else arc
	)
	final_poise = res.poise_outgoing
	final_amount *= region_damage_mult
	final_poise *= region_poise_mult
	final_amount = _apply_defense(final_amount)
	final_amount = _apply_resistances(final_amount, info.damage_type)
	final_amount = _apply_status_damage_taken(final_amount)

	if _poise and _poise.is_broken():
		final_amount *= POISE_BROKEN_DAMAGE_MULT

	if team == "player":
		final_amount = AccessibilitySettings.scale_incoming_player_damage(final_amount)

	res.outgoing = final_amount
	res.poise_outgoing = final_poise

	if _health and final_amount > 0.0:
		_health.take_damage(final_amount)
		if team == "player" and RunFlow:
			RunFlow.register_player_boss_damage()

	var hyperarmor := _is_hyperarmor_active()
	var poise_broke_this_hit := false
	if _poise and final_poise > 0.0 and (_health == null or not _health.is_dead()):
		var was_broken := _poise.is_broken()
		var poise_hit := final_poise
		if hyperarmor:
			poise_hit *= HYPERARMOR_POISE_MULT
			res.absorbed_by_poise = true
		if owner_body and owner_body.is_in_group("player"):
			var stamina := owner_body.get_node_or_null("Stamina") as Stamina
			if stamina and stamina.is_exhausted():
				poise_hit *= EXHAUSTED_POISE_MULT
		_poise.take_poise_damage(poise_hit)
		res.poise_outgoing = poise_hit
		poise_broke_this_hit = not was_broken and _poise.is_broken()

	_apply_knockback(info, res, owner_body, hyperarmor, poise_broke_this_hit)
	_apply_status_from_hit(info)
	var impact := _impact_class_for(res, info.execution)
	_emit_victim_feedback(
		final_amount,
		info.direction,
		info.damage_type,
		res.blocked,
		res.backstab,
		impact,
		info.periodic
	)
	_emit_attacker_feedback(info, final_amount, impact, res.blocked)
	_dispatch_combat_events(info, res)
	hit_resolved.emit(res)
	if team != "player" and RunBuffs and res.outgoing > 0.0:
		RunBuffs.note_player_hit(res)
	damaged.emit(info)
	if team == "player" and (final_amount > 0.0 or final_poise > 0.0):
		hurt_received.emit(final_amount, final_poise, info.direction)


## `EN-02`: a grab bypasses poise, guard and parry entirely -- it is answered by not being caught.
## Returns true only when a `PlayerCombatReactions` on the victim actually accepted the grab; a
## victim with none (an enemy, say) falls through to the normal damage pipeline instead.
func _try_apply_grab(info: DamageInfo, owner_body: Node, res: RefCounted) -> bool:
	if owner_body == null:
		return false
	var reactions := owner_body.get_node_or_null("CombatReactions")
	if reactions == null or not reactions.has_method("apply_grab"):
		return false
	var guard := _cached_guard
	var duration := 1.6
	if guard and guard.has_method("get_grab_duration"):
		duration = float(guard.call("get_grab_duration"))
	var final_amount := _apply_defense(info.amount)
	final_amount = _apply_resistances(final_amount, info.damage_type)
	if team == "player":
		final_amount = AccessibilitySettings.scale_incoming_player_damage(final_amount)
	res.outgoing = final_amount
	res.poise_outgoing = 0.0
	reactions.call("apply_grab", final_amount, info.source, duration)
	return true


## `PH-01`: only a hit that actually landed pushes the victim -- a blocked, parried or dodged hit
## must not, or a raised shield would still get shoved around by the swing it just stopped.
## Horizontal-only and mass-scaled (Trap 1): `Knockback.apply()` already flattens the direction, so
## the only work here is picking the strength and finding the victim's `Knockback` node.
func _apply_knockback(
	info: DamageInfo, res: RefCounted, owner_body: Node, hyperarmor: bool, poise_broke: bool
) -> void:
	if info.knockback <= 0.0 or res.outgoing <= 0.0:
		return
	if res.blocked or res.parried or res.dodged:
		return
	if owner_body == null:
		return
	var knockback_node := owner_body.get_node_or_null("Knockback") as Knockback
	if knockback_node == null:
		return
	var strength := info.knockback
	if poise_broke:
		strength *= POISE_BREAK_KNOCKBACK_MULT
	if hyperarmor:
		strength *= HYPERARMOR_POISE_MULT
	strength /= clampf(_target_mass(owner_body), KNOCKBACK_MASS_MIN, KNOCKBACK_MASS_MAX)
	knockback_node.apply(info.direction, strength)


func _target_mass(body: Node) -> float:
	if body.has_method("get_enemy_id"):
		var enemy_id: String = body.call("get_enemy_id")
		if enemy_id != "":
			return float(EnemyCatalog.get_definition(enemy_id).get("mass", 1.0))
	return 1.0


func receive_periodic_damage(amount: float, dmg_type: String = DamageInfo.TYPE_PHYSICAL) -> void:
	var info := DamageInfo.create(amount, 0.0, null, dmg_type)
	info.ignore_iframes = true
	info.ignore_guard = true
	info.periodic = true
	receive_hit(info)


func _apply_arc_multipliers(
	amount: float, poise: float, info: DamageInfo, res: RefCounted, arc: DamageInfo.HitArc
) -> float:
	if amount <= 0.0 or info.source == null:
		return amount
	var dmg_mult := DamageInfo.arc_damage_multiplier(arc)
	# CB-05: the dagger's backstab is the best in the game -- a per-weapon override on the arc
	# multiplier every other weapon still gets from the shared default.
	if arc == DamageInfo.HitArc.BACK and info.backstab_multiplier_override > 0.0:
		dmg_mult = info.backstab_multiplier_override
	var poise_mult := DamageInfo.arc_poise_multiplier(arc)
	res.backstab = arc == DamageInfo.HitArc.BACK
	res.stages.append(
		{
			"stage": "arc",
			"arc": arc,
			"damage_before": amount,
			"damage_after": amount * dmg_mult,
		}
	)
	res.poise_outgoing = poise * poise_mult
	return amount * dmg_mult


func _roll_evasion(body: Node) -> bool:
	if body == null:
		return false
	var chance := float(body.get_meta("combat_evasion", 0.0))
	if chance <= 0.0:
		return false
	return randf() < chance


func _apply_defense(amount: float) -> float:
	if amount <= 0.0:
		return amount
	var body := _cached_character_body
	if body == null:
		return amount
	var defense := float(body.get_meta("combat_defense", 0.0))
	var damage_reduction := float(body.get_meta("combat_damage_reduction", 0.0))
	if defense <= 0.0 and damage_reduction <= 0.0:
		return amount
	var from_armour := maxf(0.0, defense) / (maxf(0.0, defense) + DEFENSE_SOFTENING)
	var reduction := clampf(from_armour + damage_reduction, 0.0, DEFENSE_CAP)
	return amount * (1.0 - reduction)


func _find_guard() -> Node:
	var node: Node = self
	while node:
		var guard := node.get_node_or_null("Guard")
		if guard:
			return guard
		node = node.get_parent()
	return null


func _find_dodge() -> Node:
	var node: Node = self
	while node:
		var dodge := node.get_node_or_null("Dodge")
		if dodge:
			return dodge
		node = node.get_parent()
	return null


func _is_hyperarmor_active() -> bool:
	var body := _cached_character_body
	if body == null:
		return false
	var weapon := body.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("has_hyperarmor") and weapon.call("has_hyperarmor"):
		return true
	if body.has_method("is_hyperarmor_active") and body.call("is_hyperarmor_active"):
		return true
	return false


func _emit_block_feedback(chip_damage: float) -> void:
	var body := _cached_character_body
	if body == null:
		return
	var feedback := body.get_node_or_null("HitFeedback")
	if feedback and feedback.has_method("on_hit_blocked"):
		feedback.call("on_hit_blocked", body, chip_damage)


func _impact_class_for(res: RefCounted, execution: String) -> int:
	if res.crit or res.backstab or execution != "":
		return HitFeedbackScript.ImpactClass.CRITICAL
	if res.blocked or res.absorbed_by_poise or res.outgoing < HitFeedbackScript.GLANCING_DAMAGE:
		return HitFeedbackScript.ImpactClass.GLANCING
	return HitFeedbackScript.ImpactClass.SOLID


func _emit_attacker_feedback(
	info: DamageInfo, damage: float, impact: int, blocked: bool
) -> void:
	if damage <= 0.0 and not blocked:
		return
	if info.source == null or not is_instance_valid(info.source):
		return
	var feedback := info.source.get_node_or_null("HitFeedback")
	if feedback == null or not feedback.has_method("on_hit"):
		return
	feedback.call(
		"on_hit",
		_cached_character_body,
		damage,
		info.direction,
		info.damage_type,
		impact,
		bool(info.crit)
	)


func _dispatch_combat_events(info: DamageInfo, res: RefCounted) -> void:
	if not CombatEvents:
		return
	var victim := _cached_character_body
	var attacker := info.source
	if attacker and is_instance_valid(attacker) and attacker.is_in_group("player") and res.outgoing > 0.0:
		var ctx := {
			"actor": attacker,
			"target": victim,
			"amount": res.outgoing,
			"damageType": res.damage_type,
		}
		CombatEvents.dispatch(CombatEvents.ON_HIT, ctx)
		if res.crit:
			CombatEvents.dispatch(CombatEvents.ON_CRIT, ctx)
		if res.backstab or info.execution == "backstab":
			CombatEvents.dispatch(CombatEvents.ON_BACKSTAB, ctx)
		if info.execution == "riposte":
			CombatEvents.dispatch(CombatEvents.ON_RIPOSTE, ctx)
	if victim and victim.is_in_group("player") and res.outgoing > 0.0:
		CombatEvents.dispatch(
			CombatEvents.ON_HIT_TAKEN,
			{
				"actor": victim,
				"target": attacker,
				"amount": res.outgoing,
				"damageType": res.damage_type,
			}
		)


func _emit_victim_feedback(
	damage: float,
	direction: Vector3 = Vector3.ZERO,
	damage_type: String = "physical",
	blocked: bool = false,
	crit: bool = false,
	impact: int = HitFeedbackScript.ImpactClass.SOLID,
	periodic: bool = false,
) -> void:
	if damage <= 0.0:
		return
	var body := _cached_character_body
	if body == null:
		return
	if periodic:
		_emit_periodic_feedback(body, damage_type)
		return
	var visual: Node3D = null
	if body.has_method("get_diorama_visual"):
		visual = body.call("get_diorama_visual") as Node3D
	if visual == null:
		visual = body.get_node_or_null("Facing/DioramaVisual") as Node3D
	if visual:
		var max_hp := 1.0
		if _health:
			max_hp = maxf(1.0, _health.max_health)
		var proportion := clampf(damage / maxf(1.0, max_hp * 0.25), 0.15, 1.0)
		var strength := lerpf(0.35, 1.0, proportion)
		var duration := lerpf(0.14, 0.30, proportion)
		var tint: Color = MaterialFlashScript.tint_for_damage_type(damage_type)
		var anchor: Array = VfxService.resolve_combat_anchor(body)
		var params := {
			"strength": strength,
			"duration": duration,
			"tint": tint,
			"blocked": blocked,
			"crit": crit,
			"epicenter": anchor[0],
		}
		MaterialFlashScript.flash(visual, params)
		if body.is_in_group("player"):
			var director := body.get_node_or_null("AnimDirector")
			if director and director.has_method("flash_viewmodel"):
				var vm_params := params.duplicate()
				vm_params["strength"] = strength * 0.35
				director.call("flash_viewmodel", vm_params)
	VfxService.play_blood_decal(
		body.global_position + Vector3(0.0, 1.0, 0.0), direction, _surface_normal_from_direction(direction)
	)
	VfxService.play_impact_decal(
		body.global_position + Vector3(0.0, 1.0, 0.0), direction, _surface_normal_from_direction(direction)
	)
	var feedback := body.get_node_or_null("HitFeedback")
	if feedback and feedback.has_method("on_hit_received"):
		feedback.call("on_hit_received", damage, direction, damage_type, impact)


func _emit_periodic_feedback(body: Node3D, damage_type: String) -> void:
	var visual: Node3D = null
	if body.has_method("get_diorama_visual"):
		visual = body.call("get_diorama_visual") as Node3D
	if visual == null:
		visual = body.get_node_or_null("Facing/DioramaVisual") as Node3D
	if visual == null:
		return
	MaterialFlashScript.flash(
		visual,
		{
			"strength": 0.3,
			"duration": 0.12,
			"tint": MaterialFlashScript.tint_for_damage_type(damage_type),
			"blocked": false,
			"crit": false,
			"epicenter": body.global_position + Vector3(0.0, 1.0, 0.0),
		}
	)


func _apply_status_damage_taken(amount: float) -> float:
	if amount <= 0.0:
		return amount
	var ctrl := _resolve_status_controller()
	if ctrl == null or not ctrl.has_method("get_damage_taken_multiplier"):
		return amount
	return amount * maxf(0.0, float(ctrl.call("get_damage_taken_multiplier")))


func _apply_resistances(amount: float, damage_type: String) -> float:
	var resistances := _get_resistances()
	return DamageInfo.apply_resistance(amount, damage_type, resistances)


func _get_resistances() -> Dictionary:
	var body := _cached_character_body
	if body == null:
		return {}
	if body.is_in_group("player") and body.has_meta("combat_resistances"):
		return body.get_meta("combat_resistances")
	if body.has_method("get_enemy_id"):
		var enemy_id: String = body.call("get_enemy_id")
		if enemy_id != "":
			return EnemyCatalog.get_definition(enemy_id).get("resistances", {})
	return {}


func _resolve_status_controller() -> StatusController:
	if _status_controller and is_instance_valid(_status_controller):
		return _status_controller
	var body := CombatGroups.owning_body(self)
	if body == null:
		return null
	var ctrl := body.get_node_or_null("StatusController") as StatusController
	if ctrl:
		_status_controller = ctrl
		return ctrl
	if _health == null:
		return null
	ctrl = StatusController.new()
	ctrl.name = "StatusController"
	ctrl.team = team
	body.add_child.call_deferred(ctrl)
	ctrl.set_health(_health)
	_status_controller = ctrl
	return ctrl


func _apply_status_from_hit(info: DamageInfo) -> void:
	if info.status_id == "":
		return
	var status_ctrl := _resolve_status_controller()
	if status_ctrl == null:
		return
	var gain := _build_up_gain(info.status_id, maxi(1, info.status_stacks))
	if info.periodic or gain <= 0.0 or not status_ctrl.has_method("add_build_up"):
		status_ctrl.apply_status(info.status_id, info.status_stacks)
		_notify_player_status_applied(info, _cached_character_body)
		return
	if bool(status_ctrl.call("add_build_up", info.status_id, gain)):
		_notify_player_status_applied(info, _cached_character_body)


func _build_up_gain(status_id: String, stacks: int) -> float:
	var definition := StatusCatalog.get_definition(status_id)
	var threshold := float(definition.get("buildUpThreshold", 0.0))
	if threshold <= 0.0:
		return 0.0
	return float(definition.get("buildUpPerHit", threshold * 0.25)) * float(stacks)


func _notify_player_status_applied(info: DamageInfo, victim_body: Node3D) -> void:
	if info.source == null or not info.source.is_in_group("player"):
		return
	if victim_body == null or not victim_body.has_method("get_enemy_id"):
		return
	if str(victim_body.call("get_enemy_id")) == "":
		return
	if AchievementService:
		AchievementService.notify(
			"status_applied", {"status_id": info.status_id}
		)

func _surface_normal_from_direction(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.01:
		return Vector3.UP
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.04:
		return (-flat).normalized()
	return Vector3.UP
