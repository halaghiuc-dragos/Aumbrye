extends RefCounted
class_name DamageInfo

var amount: float
var damage_type: String = "physical"
var poise_damage: float
var source: Node
var direction: Vector3 = Vector3.ZERO


static func create(
	dmg_amount: float,
	poise_dmg: float,
	dmg_source: Node,
	dmg_type: String = "physical",
	hit_direction: Vector3 = Vector3.ZERO
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = dmg_amount
	info.poise_damage = poise_dmg
	info.source = dmg_source
	info.damage_type = dmg_type
	info.direction = hit_direction
	return info
