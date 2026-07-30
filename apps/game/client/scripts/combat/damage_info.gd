extends RefCounted
class_name DamageInfo

const TYPE_PHYSICAL := "physical"
const TYPE_FIRE := "fire"
const TYPE_FROST := "frost"
const TYPE_POISON := "poison"
const TYPE_LIGHTNING := "lightning"
const TYPE_ARCANE := "arcane"

const ALL_TYPES: Array[String] = [
	TYPE_PHYSICAL, TYPE_FIRE, TYPE_FROST, TYPE_POISON, TYPE_LIGHTNING, TYPE_ARCANE
]

var amount: float
var damage_type: String = TYPE_PHYSICAL
var poise_damage: float
var source: Node
var direction: Vector3 = Vector3.ZERO
var status_id: String = ""
var status_stacks: int = 1


static func create(
	dmg_amount: float,
	poise_dmg: float,
	dmg_source: Node,
	dmg_type: String = TYPE_PHYSICAL,
	hit_direction: Vector3 = Vector3.ZERO,
	apply_status: String = "",
	status_stack_count: int = 1
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = dmg_amount
	info.poise_damage = poise_dmg
	info.source = dmg_source
	info.damage_type = dmg_type if dmg_type in ALL_TYPES else TYPE_PHYSICAL
	info.direction = hit_direction
	info.status_id = apply_status
	info.status_stacks = maxi(1, status_stack_count)
	return info


static func apply_resistance(base_amount: float, dmg_type: String, resistances: Dictionary) -> float:
	if base_amount <= 0.0 or resistances.is_empty():
		return base_amount
	var resist: float = float(resistances.get(dmg_type, 0.0))
	var multiplier := 1.0 - resist
	return maxf(0.0, base_amount * multiplier)
