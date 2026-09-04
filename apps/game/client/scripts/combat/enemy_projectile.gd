extends Area3D
class_name Projectile


const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const LightEmbersScript := preload("res://scripts/art/vfx/light_embers.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")

@onready var _hitbox: Hitbox = $Hitbox
@onready var _visual: Node3D = $Visual

@export var team: String = "enemy"

@export var pierce := 0

## Lighter than real-world fall (9.8) so an arrow shot across a typical arena still reads as aimed
## rather than lobbed, while still visibly arcing instead of flying like a laser.
const GRAVITY := 9.0

## A shot launched dead level would fall short of dead-level -- the arc has to start on its way up
## to still cross the target's height by the time it gets there. Scaled off the shot's own speed so
## a slow lob and a hard draw both keep roughly the same *shape* of arc rather than the fast one
## flattening out. Only used as the fallback when `launch()` gets no target point to solve for.
const ARC_LIFT_RATIO := 0.12

## Per-second speed multiplier -- 1.0 is no drag. Applied every physics frame so a shot that
## outlives its useful range visibly loses energy rather than flying forever at launch speed.
@export var drag := 1.0

## Beyond this travelled distance the shot fades out over `FADE_DURATION` instead of vanishing at
## a hard `_lifetime` cutoff -- an arrow that quietly disappears mid-flight reads as a bug.
const MAX_RANGE := 40.0
const FADE_DURATION := 0.35

var _velocity := Vector3.ZERO
var _lifetime := 4.0
var _owner_node: Node
var _pierce_remaining := 0
var _distance_travelled := 0.0
var _fading := false
var _fade_timer := 0.0


func _ready() -> void:
	monitoring = true
	collision_layer = CombatLayers.PROJECTILE
	_hitbox.team = team
	_hitbox.collision_layer = CombatLayers.PROJECTILE
	_hitbox.is_projectile = true
	_hitbox.disable()
	if not _hitbox.hit_landed.is_connected(_on_hit_landed):
		_hitbox.hit_landed.connect(_on_hit_landed)


## `target_pos` (`Vector3.INF` when absent) enables a solved low-arc launch: given the horizontal
## distance and height difference to the target, the elevation that puts the shot through that
## point is closed-form (see `_solved_launch_velocity()`). Without a target -- a shot fired blind
## down a facing direction -- the old fixed-lift approximation is still the right fallback.
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
	crit_multiplier: float = 1.5,
	attack_class: String = "blockable",
	knockback: float = 0.0,
	target_pos: Vector3 = Vector3.INF
) -> void:
	_owner_node = shooter
	var heading := direction.normalized()
	if is_finite(target_pos.x):
		_velocity = _solved_launch_velocity(heading, speed, global_position, target_pos)
	else:
		_velocity = heading * speed
		_velocity.y += speed * ARC_LIFT_RATIO
	_lifetime = 4.0
	_distance_travelled = 0.0
	_fading = false
	_fade_timer = 0.0
	_hitbox.set_combat_owner(shooter)
	_hitbox.set_attack_values(
		damage,
		poise,
		dmg_type,
		apply_status,
		status_stacks,
		crit_chance,
		crit_multiplier,
		attack_class,
		knockback
	)
	_pierce_remaining = maxi(0, pierce)
	_hitbox.enable()
	_face_velocity()
	_build_visual(dmg_type)


## The low-arc solution for a target at horizontal distance `d` and height difference `h`, launch
## speed `v` and gravity `g`:
## `angle = atan((v^2 - sqrt(v^4 - g*(g*d^2 + 2*h*v^2))) / (g*d))`.
## A negative discriminant means the target is out of range at this speed -- clamp to 45 deg (the
## angle of maximum range) and let the shot fall short honestly rather than forcing an answer.
func _solved_launch_velocity(
	heading: Vector3, speed: float, origin: Vector3, target_pos: Vector3
) -> Vector3:
	var to_target := target_pos - origin
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var d := flat.length()
	if d < 0.05 or speed <= 0.0:
		var fallback := heading * speed
		fallback.y += speed * ARC_LIFT_RATIO
		return fallback
	var h := to_target.y
	var v2 := speed * speed
	var g := GRAVITY
	var discriminant := v2 * v2 - g * (g * d * d + 2.0 * h * v2)
	var angle: float
	if discriminant < 0.0:
		angle = deg_to_rad(45.0)
	else:
		angle = atan((v2 - sqrt(discriminant)) / (g * d))
	var flat_dir := flat / d
	return flat_dir * (speed * cos(angle)) + Vector3.UP * (speed * sin(angle))


func _build_visual(dmg_type: String) -> void:
	if _visual == null:
		return
	for child in _visual.get_children():
		_visual.remove_child(child)
		child.queue_free()
	var element := MaterialFlashScript.tint_for_damage_type(dmg_type)
	var shaft_mat := PixelStyleScript.make_material(Color(0.42, 0.30, 0.18))
	var head_mat := PixelStyleScript.make_glow_material(element, element.darkened(0.35), 1.9)
	var fletch_mat := PixelStyleScript.make_material(element.lightened(0.25))
	_add_part(Vector3(0.05, 0.05, 0.62), Vector3(0.0, 0.0, 0.06), shaft_mat, "Shaft")
	_add_part(Vector3(0.09, 0.09, 0.18), Vector3(0.0, 0.0, -0.32), head_mat, "Head")
	for i in 2:
		var axis: Vector3 = Vector3.RIGHT if i == 0 else Vector3.UP
		_add_part(
			Vector3(0.02, 0.02, 0.16) + axis * 0.14,
			Vector3(0.0, 0.0, 0.3),
			fletch_mat,
			"Fletch%d" % i
		)
	if dmg_type != DamageInfo.TYPE_PHYSICAL:
		LightEmbersScript.attach(_visual, Vector3(0.0, 0.0, -0.2), element, 0.7, 0.5)


func _add_part(size: Vector3, pos: Vector3, mat: Material, part_name: String) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(mesh)


func _on_hit_landed(_target: Node) -> void:
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		return
	_hitbox.disable()
	queue_free()


## `RG-04`: the hook a `ThrowableProjectile` overrides to explode on terrain instead of silently
## vanishing -- the default here is exactly the old inline `queue_free()` so every other shot
## (enemy arrows included) behaves unchanged.
func _on_world_impact() -> void:
	queue_free()


func _physics_process(delta: float) -> void:
	if _fading:
		_fade_timer -= delta
		if _visual:
			_visual.scale = Vector3.ONE * clampf(_fade_timer / FADE_DURATION, 0.0, 1.0)
		if _fade_timer <= 0.0:
			queue_free()
		return
	_velocity.y -= GRAVITY * delta
	if drag != 1.0:
		_velocity *= clampf(pow(drag, delta), 0.0, 1.0)
	var motion := _velocity * delta
	if motion.length_squared() > 0.0:
		var space := get_world_3d().direct_space_state
		if space:
			var params := PhysicsRayQueryParameters3D.create(
				global_position, global_position + motion
			)
			params.collision_mask = CombatLayers.WORLD_OCCLUDERS
			params.collide_with_areas = false
			params.collide_with_bodies = true
			if space.intersect_ray(params):
				_on_world_impact()
				return
	global_position += motion
	_distance_travelled += motion.length()
	_face_velocity()
	_lifetime -= delta
	if _lifetime <= 0.0 or _distance_travelled >= MAX_RANGE:
		_begin_fade()


## Beyond `MAX_RANGE` (or the outer `_lifetime` safety net) the shot fades rather than vanishing --
## a hard cutoff mid-flight reads as a bug, a fade reads as the shot spending itself.
func _begin_fade() -> void:
	if _fading:
		return
	_fading = true
	_fade_timer = FADE_DURATION
	_hitbox.disable()


## Points the shaft down the arrow's actual path rather than where it was aimed at launch, so the
## fall reads in the model's pitch and not just the position -- the difference between an arrow
## dropping and an arrow that visibly stops caring about gravity.
func _face_velocity() -> void:
	if _velocity.length_squared() < 0.0001:
		return
	var horizontal := Vector3(_velocity.x, 0.0, _velocity.z)
	var up := Vector3.UP if horizontal.length_squared() > 0.0001 else Vector3.FORWARD
	look_at(global_position + _velocity, up)
