extends Hurtbox


@export var block_mitigation := 0.75
@export var block_angle_deg := 100.0

var _owner_body: Node3D
var _reduction_by_type: Dictionary = {}


func _ready() -> void:
	super._ready()
	_owner_body = CombatGroups.owning_body(self)


## Same shape `Guard._parse_block_reduction()` accepts: a per-type dictionary, or a flat number
## applied to every type. Without this, every damage type fell back to the flat `block_mitigation`,
## so a fire hit mitigated exactly as well as a physical one.
func set_block_reduction(value: Variant) -> void:
	_reduction_by_type = _parse_block_reduction(value)


func _parse_block_reduction(value: Variant) -> Dictionary:
	var table: Dictionary = {}
	if value is Dictionary:
		for damage_type in DamageInfo.ALL_TYPES:
			if (value as Dictionary).has(damage_type):
				table[damage_type] = clampf(float((value as Dictionary)[damage_type]), 0.0, 0.95)
	elif value != null:
		var flat := clampf(float(value), 0.0, 0.95)
		for damage_type in DamageInfo.ALL_TYPES:
			table[damage_type] = flat
	return table


func _reduction_for(damage_type: String) -> float:
	if _reduction_by_type.has(damage_type):
		return float(_reduction_by_type[damage_type])
	return block_mitigation


## An `unblockable` attack skips the shield's mitigation the same way it skips the
## player's `Guard` in `modify_incoming_hit()` -- otherwise a shield enemy would absorb a red
## telegraph just as well as any other hit, which is the exact lie the attack class exists to fix.
##
## Mitigation applies only while the enemy is deliberately guarding: `is_guarding` (public on
## `CastleEnemyBase`) is the raise-the-shield decision `_try_defensive_reaction()` rolls, so the shield
## is a defensive verb rather than a passive. A body with no such property (nothing to gate on) is
## always guarding.
func receive_hit(info: DamageInfo) -> RefCounted:
	if _owner_body == null or not is_instance_valid(_owner_body):
		_owner_body = CombatGroups.owning_body(self)
	var guarding := true
	if _owner_body is CastleEnemyBase:
		guarding = (_owner_body as CastleEnemyBase).is_guarding
	if (
		not info.ignore_guard
		and info.attack_class != "unblockable"
		and guarding
		and _owner_body
		and _is_frontal_block(info)
	):
		var reduction := _reduction_for(info.damage_type)
		var mitigated := info.copy_with(
			info.amount * (1.0 - reduction), info.poise_damage * (1.0 - reduction)
		)
		return super.receive_hit(mitigated)
	return super.receive_hit(info)

func _is_frontal_block(info: DamageInfo) -> bool:
	if info.direction.length_squared() < 0.01:
		return false
	var facing := CombatFacing.forward_of(_owner_body)
	facing.y = 0.0
	facing = facing.normalized()
	var hit_dir := info.direction
	hit_dir.y = 0.0
	hit_dir = hit_dir.normalized()
	var half_angle := deg_to_rad(block_angle_deg * 0.5)
	return facing.angle_to(-hit_dir) <= half_angle
