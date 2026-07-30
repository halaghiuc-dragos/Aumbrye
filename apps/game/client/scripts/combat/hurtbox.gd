extends Area3D
class_name Hurtbox

const DEBUG_SCRIPT := preload("res://scripts/combat/combat_collision_debug.gd")

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
	var final_amount := info.amount
	var final_poise := info.poise_damage
	var guard := _find_guard()
	if guard and guard.has_method("modify_incoming_hit"):
		var modified: Dictionary = guard.call("modify_incoming_hit", info)
		final_amount = modified.get("amount", final_amount)
		final_poise = modified.get("poise", final_poise)
		if modified.get("blocked", false):
			_emit_block_feedback(final_amount)
	final_amount = _apply_resistances(final_amount, info.damage_type)
	if _health and final_amount > 0.0:
		_health.take_damage(final_amount)
	if _poise and final_poise > 0.0 and (_health == null or not _health.is_dead()):
		_poise.take_poise_damage(final_poise)
	_apply_status_from_hit(info)
	damaged.emit(info)


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
	var feedback := body.get_node_or_null("HitFeedback")
	if feedback and feedback.has_method("on_hit_blocked"):
		feedback.call("on_hit_blocked", body, chip_damage)


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
