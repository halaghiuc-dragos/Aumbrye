extends Hurtbox

## Hurtbox variant for shield enemies — mitigates frontal hits (ENEMY-2.3).

@export var block_mitigation := 0.75
@export var block_angle_deg := 100.0

var _owner_body: Node3D


func _ready() -> void:
	super._ready()
	_owner_body = _find_owner_body()


func receive_hit(info: DamageInfo) -> void:
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


func _find_owner_body() -> Node3D:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node as Node3D
		node = node.get_parent()
	return null


func _is_frontal_block(info: DamageInfo) -> bool:
	if info.direction.length_squared() < 0.01:
		return false
	var facing := -_owner_body.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var hit_dir := info.direction
	hit_dir.y = 0.0
	hit_dir = hit_dir.normalized()
	var half_angle := deg_to_rad(block_angle_deg * 0.5)
	return facing.angle_to(-hit_dir) <= half_angle
