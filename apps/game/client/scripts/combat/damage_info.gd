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

static var _warned_damage_types: Dictionary = {}

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
var attack_class: String = "blockable"
## `PH-01`: how hard this hit shoves the victim, in the same units `Knockback.apply()` takes. Set
## directly by the caller (`Hitbox`/`Projectile`) after `create()`, the same way `crit` is --
## it is a per-attack tuning value, not part of the damage-type/status shape `create()` already
## has too many positional parameters for.
var knockback: float = 0.0
## CB-05: the dagger's identity trait -- 0.0 means "use the global `BACKSTAB_DAMAGE_MULT`".
var backstab_multiplier_override: float = 0.0
## `RG-03`: set by `Hitbox` when the hit came from a `Projectile`'s hitbox rather than a melee
## swing -- lets `Guard` react differently (spark VFX, a parry stamina refund) without a parallel
## interception path.
var is_projectile: bool = false


static func create(
	dmg_amount: float,
	poise_dmg: float,
	dmg_source: Node,
	dmg_type: String = TYPE_PHYSICAL,
	hit_direction: Vector3 = Vector3.ZERO,
	apply_status: String = "",
	status_stack_count: int = 1,
	dmg_attack_class: String = "blockable"
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = dmg_amount
	info.poise_damage = poise_dmg
	info.source = dmg_source
	if dmg_type not in ALL_TYPES:
		if not _warned_damage_types.has(dmg_type):
			_warned_damage_types[dmg_type] = true
			push_warning(
				(
					"DamageInfo: unknown damageType '%s' coerced to physical. Valid types: %s"
				)
				% [dmg_type, ", ".join(ALL_TYPES)]
			)
		dmg_type = TYPE_PHYSICAL
	info.damage_type = dmg_type
	info.direction = hit_direction
	info.status_id = apply_status
	info.status_stacks = maxi(1, status_stack_count)
	info.attack_class = dmg_attack_class
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
