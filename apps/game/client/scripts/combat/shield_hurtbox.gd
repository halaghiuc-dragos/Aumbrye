extends Hurtbox


@export var block_mitigation := 0.75
@export var block_angle_deg := 100.0

var _owner_body: Node3D


func _ready() -> void:
	super._ready()
	_owner_body = CombatGroups.owning_body(self)


func receive_hit(info: DamageInfo) -> void:
	if _owner_body == null or not is_instance_valid(_owner_body):
		_owner_body = CombatGroups.owning_body(self)
	if _owner_body and _is_frontal_block(info):
		var mitigated := DamageInfo.create(
			info.amount * (1.0 - block_mitigation),
			info.poise_damage * (1.0 - block_mitigation),
			info.source,
			info.damage_type,
			info.direction
		)
		super.receive_hit(mitigated)
	else:
		super.receive_hit(info)

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
