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

enum HitArc { FRONT, SIDE, BACK }

const BACK_ARC_HALF_DEGREES := 55.0
const BACKSTAB_DAMAGE_MULT := 1.6
const BACKSTAB_POISE_MULT := 2.0
const SIDE_DAMAGE_MULT := 1.15
const SIDE_POISE_MULT := 1.2
const RESISTANCE_MULT_MIN := 0.0
const RESISTANCE_MULT_MAX := 2.0

var amount: float
var damage_type: String = TYPE_PHYSICAL
var poise_damage: float
var source: Node
var direction: Vector3 = Vector3.ZERO
var status_id: String = ""
var status_stacks: int = 1
var crit: bool = false
var ignore_iframes: bool = false
var ignore_guard: bool = false
var periodic: bool = false
var execution: String = ""


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


static func apply_resistance(
	base_amount: float, dmg_type: String, resistances: Dictionary
) -> float:
	if base_amount <= 0.0 or resistances.is_empty():
		return base_amount
	var resist: float = float(resistances.get(dmg_type, 0.0))
	var multiplier := clampf(1.0 - resist, RESISTANCE_MULT_MIN, RESISTANCE_MULT_MAX)
	return maxf(0.0, base_amount * multiplier)


static func classify_arc(victim: Node3D, attacker_position: Vector3) -> HitArc:
	if victim == null:
		return HitArc.FRONT
	var facing := Vector3.ZERO
	var facing_node := victim.get_node_or_null("Facing") as Node3D
	if facing_node:
		facing = facing_node.global_transform.basis.z
	else:
		facing = victim.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		return HitArc.FRONT
	var to_attacker := attacker_position - victim.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.01:
		return HitArc.FRONT
	var angle_deg := rad_to_deg(facing.angle_to(to_attacker.normalized()))
	if angle_deg <= 60.0:
		return HitArc.FRONT
	if angle_deg >= 180.0 - BACK_ARC_HALF_DEGREES:
		return HitArc.BACK
	return HitArc.SIDE


static func arc_damage_multiplier(arc: HitArc) -> float:
	match arc:
		HitArc.BACK:
			return BACKSTAB_DAMAGE_MULT
		HitArc.SIDE:
			return SIDE_DAMAGE_MULT
		_:
			return 1.0


static func arc_poise_multiplier(arc: HitArc) -> float:
	match arc:
		HitArc.BACK:
			return BACKSTAB_POISE_MULT
		HitArc.SIDE:
			return SIDE_POISE_MULT
		_:
			return 1.0
