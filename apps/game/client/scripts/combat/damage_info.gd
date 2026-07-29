extends RefCounted
class_name DamageInfo

var amount: float
var damage_type: String = "physical"
var poise_damage: float
var source: Node
var direction: Vector3 = Vector3.ZERO


static func create(
	amount: float,
	poise_damage: float,
	source: Node,
	damage_type: String = "physical",
	direction: Vector3 = Vector3.ZERO
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	info.poise_damage = poise_damage
	info.source = source
	info.damage_type = damage_type
	info.direction = direction
	return info
