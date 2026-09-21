extends Area3D
class_name Projectile


const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const LightEmbersScript := preload("res://scripts/art/vfx/light_embers.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")

@onready var _hitbox: Hitbox = $Hitbox
@onready var _visual: Node3D = $Visual

@export var team: String = "enemy"

@export var pierce := 0
@export var world_collision_radius := 0.12

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
var _world_query := PhysicsShapeQueryParameters3D.new()
var _world_shape := SphereShape3D.new()

static var _visual_variants: Dictionary = {}


func _ready() -> void:
	monitoring = true
	collision_layer = CombatLayers.PROJECTILE
	_hitbox.team = team
	_hitbox.collision_layer = CombatLayers.PROJECTILE
	_hitbox.is_projectile = true
	_hitbox.disable()
	if not _hitbox.hit_landed.is_connected(_on_hit_landed):
		_hitbox.hit_landed.connect(_on_hit_landed)
	_world_query.collision_mask = CombatLayers.WORLD_OCCLUDERS
	_world_query.collide_with_areas = false
	_world_query.collide_with_bodies = true


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
) -> bool:
	_owner_node = shooter
	var heading := direction.normalized()
	if is_finite(target_pos.x):
		var solution := solve_launch_velocity(heading, speed, global_position, target_pos, drag)
		if not bool(solution.get("reachable", false)):
			queue_free()
			return false
		_velocity = solution["velocity"]
	else:
		_velocity = heading * speed
		_velocity.y += speed * ARC_LIFT_RATIO
	_lifetime = 4.0
	_distance_travelled = 0.0
	_fading = false
	_fade_timer = 0.0
	if _visual:
		_visual.scale = Vector3.ONE
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
	call_deferred("_resolve_launch_clearance")
	return true


## The low-arc solution for a target at horizontal distance `d` and height difference `h`, launch
## speed `v` and gravity `g`:
## `angle = atan((v^2 - sqrt(v^4 - g*(g*d^2 + 2*h*v^2))) / (g*d))`.
## A negative discriminant means the target is out of range at this speed -- clamp to 45 deg (the
## angle of maximum range) and let the shot fall short honestly rather than forcing an answer.
static func solve_launch_velocity(
	heading: Vector3, speed: float, origin: Vector3, target_pos: Vector3, trajectory_drag: float = 1.0
) -> Dictionary:
	if not is_equal_approx(trajectory_drag, 1.0) or speed <= 0.0:
		return {"reachable": false}
	var to_target := target_pos - origin
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var d := flat.length()
	if d < 0.05:
		var fallback := heading * speed
		fallback.y += speed * ARC_LIFT_RATIO
		return {"reachable": true, "velocity": fallback}
	var h := to_target.y
	var v2 := speed * speed
	var g := GRAVITY
	var discriminant := v2 * v2 - g * (g * d * d + 2.0 * h * v2)
	if discriminant < 0.0:
		return {"reachable": false}
	var angle := atan((v2 - sqrt(discriminant)) / (g * d))
	var flat_dir := flat / d
	return {"reachable": true, "velocity": flat_dir * (speed * cos(angle)) + Vector3.UP * (speed * sin(angle))}


static func trajectory_is_clear(
	space: PhysicsDirectSpaceState3D,
	origin: Vector3,
	velocity: Vector3,
	target: Vector3,
	exclude: Array[RID] = []
) -> bool:
	var flat_velocity := Vector2(velocity.x, velocity.z).length()
	var flat_distance := Vector2(target.x - origin.x, target.z - origin.z).length()
	if flat_velocity <= 0.0:
		return false
	var travel_time := flat_distance / flat_velocity
	var segments := clampi(ceili(travel_time * 24.0), 1, 48)
	var previous := origin
	for index in range(1, segments + 1):
		var time := travel_time * float(index) / float(segments)
		var point := origin + velocity * time + Vector3.DOWN * (GRAVITY * time * time * 0.5)
		var query := PhysicsRayQueryParameters3D.create(previous, point)
		query.collision_mask = CombatLayers.WORLD_OCCLUDERS
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = exclude
		if not space.intersect_ray(query).is_empty():
			return false
		previous = point
	return true


func _build_visual(dmg_type: String) -> void:
	if _visual == null:
		return
	for child in _visual.get_children():
		if not child.has_meta("projectile_part"):
			_visual.remove_child(child)
			child.queue_free()
	var variant := _visual_variant(dmg_type)
	var parts: Array = variant.get("parts", [])
	for index in parts.size():
		var mesh: MeshInstance3D
		var existing := _visual.get_node_or_null("Part%d" % index) as MeshInstance3D
		if existing:
			mesh = existing
		else:
			mesh = MeshInstance3D.new()
			mesh.name = "Part%d" % index
			mesh.set_meta("projectile_part", true)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_visual.add_child(mesh)
		var part: Dictionary = parts[index]
		mesh.mesh = part["mesh"]
		mesh.position = part["position"]
		mesh.material_override = part["material"]
		mesh.show()
	if dmg_type != DamageInfo.TYPE_PHYSICAL:
		LightEmbersScript.attach(_visual, Vector3(0.0, 0.0, -0.2), variant["element"], 0.7, 0.5)


static func _visual_variant(dmg_type: String) -> Dictionary:
	if _visual_variants.has(dmg_type):
		return _visual_variants[dmg_type]
	var element := MaterialFlashScript.tint_for_damage_type(dmg_type)
	var shaft_mat := PixelStyleScript.make_material(Color(0.42, 0.30, 0.18))
	var head_mat := PixelStyleScript.make_glow_material(element, element.darkened(0.35), 1.9)
	var fletch_mat := PixelStyleScript.make_material(element.lightened(0.25))
	var parts: Array = [
		_part_variant(Vector3(0.05, 0.05, 0.62), Vector3(0.0, 0.0, 0.06), shaft_mat),
		_part_variant(Vector3(0.09, 0.09, 0.18), Vector3(0.0, 0.0, -0.32), head_mat),
		_part_variant(Vector3(0.16, 0.02, 0.16), Vector3(0.0, 0.0, 0.3), fletch_mat),
		_part_variant(Vector3(0.02, 0.16, 0.16), Vector3(0.0, 0.0, 0.3), fletch_mat),
	]
	var variant := {"element": element, "parts": parts}
	_visual_variants[dmg_type] = variant
	return variant


static func _part_variant(size: Vector3, position: Vector3, material: Material) -> Dictionary:
	var mesh := BoxMesh.new()
	mesh.size = size
	return {"mesh": mesh, "position": position, "material": material}


func _on_hit_landed(_target: Node) -> void:
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		return
	_hitbox.disable()
	queue_free()


## `RG-04`: the hook a `ThrowableProjectile` overrides to explode on terrain instead of silently
## vanishing -- the default here is exactly the old inline `queue_free()` so every other shot
## (enemy arrows included) behaves unchanged.
func _on_world_impact(contact: Dictionary = {}) -> void:
	var position: Variant = contact.get("position")
	if position is Vector3:
		global_position = position
	if VfxService:
		var normal: Vector3 = contact.get("normal", Vector3.UP)
		VfxService.play_hit_spark(global_position, -_velocity.normalized(), normal)
	queue_free()


func _physics_process(delta: float) -> void:
	if _fading:
		_fade_timer -= delta
		if _visual:
			_visual.scale = Vector3.ONE * clampf(_fade_timer / FADE_DURATION, 0.0, 1.0)
		if _fade_timer <= 0.0:
			queue_free()
		return
	var motion: Vector3
	if is_equal_approx(drag, 1.0):
		motion = _velocity * delta + Vector3.DOWN * (GRAVITY * delta * delta * 0.5)
		_velocity.y -= GRAVITY * delta
	else:
		_velocity.y -= GRAVITY * delta
		_velocity *= clampf(pow(drag, delta), 0.0, 1.0)
		motion = _velocity * delta
	if motion.length_squared() > 0.0:
		var space := get_world_3d().direct_space_state
		if space:
			var contact := _world_contact(space, motion)
			if not contact.is_empty():
				global_position = contact.get("position", global_position)
				_on_world_impact(contact)
				return
	global_position += motion
	_distance_travelled += motion.length()
	_face_velocity()
	_lifetime -= delta
	if _lifetime <= 0.0 or _distance_travelled >= MAX_RANGE:
		_begin_fade()


func _world_contact(space: PhysicsDirectSpaceState3D, motion: Vector3) -> Dictionary:
	_world_shape.radius = _collision_radius()
	_world_query.shape = _world_shape
	_world_query.transform = Transform3D(Basis.IDENTITY, global_position)
	_world_query.motion = motion
	_world_query.exclude = []
	if _owner_node is CollisionObject3D:
		_world_query.exclude.append((_owner_node as CollisionObject3D).get_rid())
	var cast := space.cast_motion(_world_query)
	var unsafe := clampf(float(cast[1]) if cast.size() > 1 else 1.0, 0.0, 1.0)
	if unsafe >= 1.0:
		return {}
	var contact_position := global_position + motion * unsafe
	var query := PhysicsRayQueryParameters3D.create(global_position, contact_position)
	query.collision_mask = CombatLayers.WORLD_OCCLUDERS
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _world_query.exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		hit["position"] = contact_position
		hit["normal"] = -motion.normalized()
	return hit


func _collision_radius() -> float:
	var collision := _hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision and collision.shape is SphereShape3D:
		return maxf(0.01, (collision.shape as SphereShape3D).radius)
	return maxf(0.01, world_collision_radius)


func _resolve_launch_clearance() -> void:
	if not is_instance_valid(self) or _velocity.length_squared() < 0.0001:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var contact := _world_contact(space, _velocity.normalized() * _collision_radius())
	if contact.is_empty():
		return
	global_position = contact.get("position", global_position)
	_on_world_impact(contact)


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
