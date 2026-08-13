extends Area3D
class_name Hurtbox

const DEBUG_SCRIPT := preload("res://scripts/combat/combat_collision_debug.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const DamageResolutionScript := preload("res://scripts/combat/damage_resolution.gd")
const HitFeedbackScript := preload("res://scripts/combat/hit_feedback.gd")
const DEFENSE_PER_POINT := 0.02
const DEFENSE_CAP := 0.9
const HYPERARMOR_POISE_MULT := 0.25
const POISE_BROKEN_DAMAGE_MULT := 1.35
const EXHAUSTED_POISE_MULT := 1.5

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
	_cached_character_body = _find_character_body()


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
			hit_resolved.emit(res)
			return

	var owner_body := _cached_character_body
	if owner_body and owner_body.has_method("is_immune") and owner_body.call("is_immune"):
		res.outgoing = 0.0
		res.poise_outgoing = 0.0
		hit_resolved.emit(res)
		return

	var arc := DamageInfo.HitArc.FRONT
	if owner_body and info.source:
		arc = DamageInfo.classify_arc(owner_body, info.source.global_position)

	var guard := _cached_guard if not info.ignore_guard else null
	if guard and guard.has_method("try_parry_attack") and info.source:
		if guard.call("try_parry_attack", info.source):
			res.parried = true
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

	# A successful block absorbs the hit frontally; it cannot also be a backstab.
	final_amount = _apply_arc_multipliers(
		final_amount, final_poise, info, res, DamageInfo.HitArc.FRONT if blocked else arc
	)
	final_poise = res.poise_outgoing
	final_amount *= region_damage_mult
	final_poise *= region_poise_mult
	final_amount = _apply_defense(final_amount)
	final_amount = _apply_resistances(final_amount, info.damage_type)

	if _poise and _poise.is_broken():
		final_amount *= POISE_BROKEN_DAMAGE_MULT

	res.outgoing = final_amount
	res.poise_outgoing = final_poise

	if _health and final_amount > 0.0:
		_health.take_damage(final_amount)
		if team == "player" and RunFlow:
			RunFlow.register_player_boss_damage()

	var hyperarmor := _is_hyperarmor_active()
	if _poise and final_poise > 0.0 and (_health == null or not _health.is_dead()):
		var poise_hit := final_poise
		if hyperarmor:
			poise_hit *= HYPERARMOR_POISE_MULT
			res.absorbed_by_poise = true
		if owner_body and owner_body.is_in_group("player"):
			var stamina := owner_body.get_node_or_null("Stamina") as Stamina
			if stamina and stamina.is_exhausted():
				poise_hit *= EXHAUSTED_POISE_MULT
		# Hyperarmor reduces poise damage rather than negating it — the soulslike convention, and
		# what the HYPERARMOR_POISE_MULT scaling above already implies. Previously the reduced hit
		# was reported in res.poise_outgoing but never actually applied, so telemetry and the HUD
		# showed poise damage that nothing had taken.
		_poise.take_poise_damage(poise_hit)
		res.poise_outgoing = poise_hit

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
	damaged.emit(info)
	if team == "player" and (final_amount > 0.0 or final_poise > 0.0):
		hurt_received.emit(final_amount, final_poise, info.direction)


func try_apply_status(status_id: String, stacks: int = 1, duration: float = -1.0) -> bool:
	if status_id == "":
		return false
	var dodge := _cached_dodge
	if dodge and dodge.get("iframes_active"):
		return false
	var guard := _cached_guard
	if guard and guard.get("is_guard_active"):
		return false
	var ctrl := _resolve_status_controller()
	if ctrl == null:
		return false
	ctrl.apply_status(status_id, stacks, duration)
	return true


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
	var poise_mult := DamageInfo.arc_poise_multiplier(arc)
	res.backstab = arc == DamageInfo.HitArc.BACK
	# poise is returned via caller modifying final_poise separately — store in res stages
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
	var reduction := clampf(defense * DEFENSE_PER_POINT + damage_reduction, 0.0, DEFENSE_CAP)
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
		"on_hit", _cached_character_body, damage, info.direction, info.damage_type, impact
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
	# Status ticks route through receive_hit, so a 10-tick poison stack used to spawn 20 decals
	# plus 10 full-strength flashes and 10 camera shakes. Ticks keep a subdued flash for
	# readability and skip the heavy per-hit VFX entirely.
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
		var tint: Color = MaterialFlashScript.FLASH_TINTS.get(damage_type, Color.WHITE)
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


## Lightweight victim feedback for a damage-over-time tick: a dim material flash only, no decals
## and no camera shake.
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
			"tint": MaterialFlashScript.FLASH_TINTS.get(damage_type, Color.WHITE),
			"blocked": false,
			"crit": false,
			"epicenter": body.global_position + Vector3(0.0, 1.0, 0.0),
		}
	)


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
	var body := _find_character_body()
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
	body.add_child(ctrl)
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


func _find_character_body() -> Node3D:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node as Node3D
		node = node.get_parent()
	return null


func _surface_normal_from_direction(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.01:
		return Vector3.UP
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.04:
		return (-flat).normalized()
	return Vector3.UP
