extends Area3D
class_name Hitbox

@export var damage_amount := 10.0
@export var poise_damage := 15.0
@export var team: String = "player"

var _owner_node: Node
var _hit_targets: Array[int] = []
var _active := false


func _ready() -> void:
	add_to_group("combat_hitbox")
	area_entered.connect(_on_area_entered)
	monitoring = false
	monitorable = false
	_owner_node = _find_combat_owner()


func enable() -> void:
	_active = true
	monitoring = true


func disable() -> void:
	_active = false
	monitoring = false


func reset_swing() -> void:
	_hit_targets.clear()


func set_attack_values(damage: float, poise: float) -> void:
	damage_amount = damage
	poise_damage = poise


func _on_area_entered(area: Area3D) -> void:
	if not _active or not area is Hurtbox:
		return
	var hurtbox := area as Hurtbox
	if hurtbox.team == team:
		return
	var target_id := hurtbox.get_instance_id()
	if target_id in _hit_targets:
		return
	_hit_targets.append(target_id)
	var direction := Vector3.ZERO
	if _owner_node:
		direction = (hurtbox.global_position - _owner_node.global_position).normalized()
	var info := DamageInfo.create(damage_amount, poise_damage, _owner_node, "physical", direction)
	hurtbox.receive_hit(info)
	var feedback := _owner_node.get_node_or_null("HitFeedback")
	if feedback and feedback.has_method("on_hit"):
		feedback.on_hit(hurtbox.get_parent(), damage_amount)


func _find_combat_owner() -> Node:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return get_parent()
