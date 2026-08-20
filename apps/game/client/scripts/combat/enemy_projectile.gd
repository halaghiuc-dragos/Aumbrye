extends Area3D
class_name Projectile

## Ranged projectile shared by enemies (ENEMY-2.2) and the player bow (REF-14): a real travelling
## Hitbox with a team, not a melee hitbox stretched into a box for the duration of the "shot".
## Rollable via dodge i-frames like any other hitbox. `team` picks which side it can hit — set on
## the scene root for the enemy/player variants, or via `launch()`'s optional override.

@onready var _hitbox: Hitbox = $Hitbox

@export var team: String = "enemy"

## C-47: how many targets the projectile passes *through* before stopping. It used to stop only on
## a world raycast hit or when its 4 s lifetime expired — hitting a hurtbox did nothing to it, and
## `Hitbox._hit_times` only prevents re-hitting the *same* target, so one player arrow through a
## corridor of six enemies dealt six full hits and kept flying. The enemy variant had the subtler
## version: an arrow passed through the player rather than stopping, so a blocked arrow never
## visibly *stopped*. Zero means the first target consumes it; piercing is now an authored bow
## property rather than an accident.
@export var pierce := 0

var _velocity := Vector3.ZERO
var _lifetime := 4.0
var _owner_node: Node
var _pierce_remaining := 0


func _ready() -> void:
	monitoring = true
	_hitbox.team = team
	_hitbox.disable()
	if not _hitbox.hit_landed.is_connected(_on_hit_landed):
		_hitbox.hit_landed.connect(_on_hit_landed)


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
	_pierce_remaining = maxi(0, pierce)
	_hitbox.enable()
	look_at(global_position + direction)


func _on_hit_landed(_target: Node) -> void:
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		return
	_hitbox.disable()
	queue_free()


func _physics_process(delta: float) -> void:
	var motion := _velocity * delta
	if motion.length_squared() > 0.0:
		var space := get_world_3d().direct_space_state
		if space:
			var params := PhysicsRayQueryParameters3D.create(
				global_position, global_position + motion
			)
			# C-52: `combat_layers.gd` was written specifically to stop bare `collision_mask = 1`
			# duplicating across perception, targeting and camera code, and its docstring says so.
			# The value is right today; naming it is what stops the drift its own author predicted.
			params.collision_mask = CombatLayers.WORLD_OCCLUDERS
			params.collide_with_areas = false
			params.collide_with_bodies = true
			if space.intersect_ray(params):
				queue_free()
				return
	global_position += motion
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
