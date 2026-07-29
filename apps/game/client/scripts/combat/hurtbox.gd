extends Area3D
class_name Hurtbox

signal damaged(info: DamageInfo)

@export var team: String = "enemy"
@export var health_path: NodePath
@export var poise_path: NodePath

var _health: Health
var _poise: Poise


func _ready() -> void:
	if health_path:
		_health = get_node(health_path) as Health
	if poise_path:
		_poise = get_node(poise_path) as Poise


func receive_hit(info: DamageInfo) -> void:
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
	if _health and final_amount > 0.0:
		_health.take_damage(final_amount)
	if _poise and final_poise > 0.0:
		_poise.take_poise_damage(final_poise)
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
