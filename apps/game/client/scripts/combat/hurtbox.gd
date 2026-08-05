extends Area3D
class_name Hurtbox

const DEBUG_SCRIPT := preload("res://scripts/combat/combat_collision_debug.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const BACKSTAB_ARC_DEGREES := 70.0
const BACKSTAB_DAMAGE_MULT := 1.5
const DEFENSE_PER_POINT := 0.02

signal damaged(info: DamageInfo)

@export var team: String = "enemy"
@export var health_path: NodePath
@export var poise_path: NodePath

var _health: Health
var _poise: Poise


func _ready() -> void:
	add_to_group("combat_hurtbox")
	monitorable = true
	if health_path:
		_health = get_node(health_path) as Health
	if poise_path:
		_poise = get_node(poise_path) as Poise
	DEBUG_SCRIPT.set_debug_draw(self, false, DEBUG_SCRIPT.HURTBOX_COLOR)


func set_debug_draw(enabled: bool) -> void:
	DEBUG_SCRIPT.set_debug_draw(self, enabled, DEBUG_SCRIPT.HURTBOX_COLOR)


func receive_hit(info: DamageInfo) -> void:
	if _health and _health.is_dead():
		return
	var dodge := _find_dodge()
	if dodge and dodge.get("iframes_active"):
		return
	var guard := _find_guard()
	if guard and guard.has_method("try_parry_attack") and info.source:
		if guard.call("try_parry_attack", info.source):
			return
	var final_amount := info.amount
	var final_poise := info.poise_damage
	if guard and guard.has_method("modify_incoming_hit"):
		var modified: Dictionary = guard.call("modify_incoming_hit", info)
		final_amount = modified.get("amount", final_amount)
		final_poise = modified.get("poise", final_poise)
		if modified.get("blocked", false):
			_emit_block_feedback(final_amount)
	final_amount = _apply_backstab(final_amount, info)
	final_amount = _apply_defense(final_amount)
	final_amount = _apply_resistances(final_amount, info.damage_type)
	if _health and final_amount > 0.0:
		_health.take_damage(final_amount)
	if _poise and final_poise > 0.0 and (_health == null or not _health.is_dead()):
		_poise.take_poise_damage(final_poise)
	_apply_status_from_hit(info)
	_emit_victim_feedback(final_amount, info.direction)
	damaged.emit(info)


func _apply_backstab(amount: float, info: DamageInfo) -> float:
	if amount <= 0.0 or info.source == null:
		return amount
	var body := _find_character_body()
	if body == null:
		return amount
	var victim_facing := body.global_transform.basis.z
	victim_facing.y = 0.0
	if victim_facing.length_squared() < 0.01:
		return amount
	var to_attacker: Vector3 = info.source.global_position - body.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.01:
		return amount
	var angle := rad_to_deg(victim_facing.angle_to(to_attacker.normalized()))
	if angle <= BACKSTAB_ARC_DEGREES:
		return amount * BACKSTAB_DAMAGE_MULT
	return amount


func _apply_defense(amount: float) -> float:
	if amount <= 0.0:
		return amount
	var body := _find_character_body()
	if body == null:
		return amount
	var defense := float(body.get_meta("combat_defense", 0.0))
	var damage_reduction := float(body.get_meta("combat_damage_reduction", 0.0))
	if defense <= 0.0 and damage_reduction <= 0.0:
		return amount
	var reduction := clampf(defense * DEFENSE_PER_POINT + damage_reduction, 0.0, 0.9)
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


func _emit_block_feedback(chip_damage: float) -> void:
	var body := _find_character_body()
	if body == null:
		return
	var anchor: Array = VfxService.resolve_combat_anchor(body)
	VfxService.play_block(anchor[0], anchor[1])
	VfxService.play_impact_decal(anchor[0], anchor[1])
	var feedback := body.get_node_or_null("HitFeedback")
	if feedback and feedback.has_method("on_hit_blocked"):
		feedback.call("on_hit_blocked", body, chip_damage)


func _emit_victim_feedback(damage: float, direction: Vector3 = Vector3.ZERO) -> void:
	if damage <= 0.0:
		return
	var body := _find_character_body()
	if body == null:
		return
	MaterialFlashScript.flash(body)
	var hit_pos := body.global_position + Vector3(0.0, 1.0, 0.0)
	VfxService.play_blood_decal(hit_pos, direction)
	VfxService.play_impact_decal(hit_pos, direction)
	var feedback := body.get_node_or_null("HitFeedback")
	if feedback and feedback.has_method("on_hit_received"):
		feedback.call("on_hit_received", damage, direction)


func _apply_resistances(amount: float, damage_type: String) -> float:
	var resistances := _get_resistances()
	return DamageInfo.apply_resistance(amount, damage_type, resistances)


func _get_resistances() -> Dictionary:
	var body := _find_character_body()
	if body and body.has_method("get_enemy_id"):
		var enemy_id: String = body.call("get_enemy_id")
		if enemy_id != "":
			return EnemyCatalog.get_definition(enemy_id).get("resistances", {})
	return {}


func _apply_status_from_hit(info: DamageInfo) -> void:
	if info.status_id == "":
		return
	var body := _find_character_body()
	if body == null:
		return
	var status_ctrl := body.get_node_or_null("StatusController") as StatusController
	if status_ctrl:
		status_ctrl.apply_status(info.status_id, info.status_stacks)


func _find_character_body() -> Node3D:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node as Node3D
		node = node.get_parent()
	return null
