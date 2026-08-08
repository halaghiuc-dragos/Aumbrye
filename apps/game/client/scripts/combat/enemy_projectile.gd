extends Area3D
class_name Projectile

## Ranged projectile shared by enemies (ENEMY-2.2) and the player bow (REF-14): a real travelling
## Hitbox with a team, not a melee hitbox stretched into a box for the duration of the "shot".
## Rollable via dodge i-frames like any other hitbox. `team` picks which side it can hit — set on
## the scene root for the enemy/player variants, or via `launch()`'s optional override.

@onready var _hitbox: Hitbox = $Hitbox

@export var team: String = "enemy"

var _velocity := Vector3.ZERO
var _lifetime := 4.0
var _owner_node: Node


func _ready() -> void:
	monitoring = true
	_hitbox.team = team
	_hitbox.disable()


func launch(
	direction: Vector3,
	speed: float,
	damage: float,
	poise: float,
	shooter: Node,
	dmg_type: String = DamageInfo.TYPE_PHYSICAL,
	apply_status: String = "",
	status_stacks: int = 1,
	crit_chance: float = 0.0,
	crit_multiplier: float = 1.5
) -> void:
	_owner_node = shooter
	_velocity = direction.normalized() * speed
	_lifetime = 4.0
	_hitbox.set_combat_owner(shooter)
	_hitbox.set_attack_values(
		damage, poise, dmg_type, apply_status, status_stacks, crit_chance, crit_multiplier
	)
	_hitbox.enable()
	look_at(global_position + direction)


func _physics_process(delta: float) -> void:
	var motion := _velocity * delta
	if motion.length_squared() > 0.0:
		var space := get_world_3d().direct_space_state
		if space:
			var params := PhysicsRayQueryParameters3D.create(
				global_position, global_position + motion
			)
			params.collision_mask = 1
			params.collide_with_areas = false
			params.collide_with_bodies = true
			if space.intersect_ray(params):
				queue_free()
				return
	global_position += motion
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
