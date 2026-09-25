extends Area3D
class_name Projectile


const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const LightEmbersScript := preload("res://scripts/art/vfx/light_embers.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const ProjectileContainerScript := preload("res://scripts/combat/projectile_container.gd")

@onready var _hitbox: Hitbox = $Hitbox
@onready var _visual: Node3D = $Visual

@export var team: String = "enemy"
@export_enum("arrow", "bolt_orb", "lobbed_item") var projectile_archetype := "arrow"

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
var _settling := false
var _settle_timer := 0.0
var _world_query := PhysicsShapeQueryParameters3D.new()
var _target_query := PhysicsShapeQueryParameters3D.new()
var _world_shape := SphereShape3D.new()
var _recycling := false

static var _visual_variants: Dictionary = {}
static var _swept_query_count := 0
static var _visual_variant_build_count := 0


func _ready() -> void:
	monitoring = false
	collision_layer = 0
	collision_mask = 0
	_hitbox.team = team
	_hitbox.collision_layer = CombatLayers.PROJECTILE
	_hitbox.is_projectile = true
	_hitbox.disable()
	_world_query.collision_mask = CombatLayers.WORLD_OCCLUDERS
	_world_query.collide_with_areas = false
	_world_query.collide_with_bodies = true
	_target_query.collision_mask = CombatLayers.HURTBOX
	_target_query.collide_with_areas = true
	_target_query.collide_with_bodies = false


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
	_recycling = false
	show()
	monitoring = false
	set_physics_process(true)
	_owner_node = shooter
	var heading := direction.normalized()
	if is_finite(target_pos.x):
		var solution := solve_launch_velocity(
			heading, speed, global_position, target_pos, drag, _gravity_for_archetype()
		)
		if not bool(solution.get("reachable", false)):
			_finish_lifecycle()
			return false
		_velocity = solution["velocity"]
	else:
		_velocity = heading * speed
		_velocity.y += speed * ARC_LIFT_RATIO
	_lifetime = 4.0
	_distance_travelled = 0.0
	_fading = false
	_fade_timer = 0.0
	_settling = false
	_settle_timer = 0.0
	if _visual:
		_visual.scale = Vector3.ONE
		_visual.show()
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
	# Projectile collision is resolved by this script's ordered swept step. Leaving the generic
	# Hitbox Area monitor active would reintroduce unordered overlap hits between those steps.
	_hitbox.monitoring = false
	_hitbox.set_physics_process(false)
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
	heading: Vector3,
	speed: float,
	origin: Vector3,
	target_pos: Vector3,
	trajectory_drag: float = 1.0,
	gravity_value: float = GRAVITY
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
	var g := maxf(0.1, gravity_value)
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
	exclude: Array[RID] = [],
	gravity_value: float = GRAVITY
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
		var point := origin + velocity * time + Vector3.DOWN * (gravity_value * time * time * 0.5)
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
		if child is GPUParticles3D and child.name == "LightEmbers":
			(child as GPUParticles3D).emitting = false
			child.hide()
			continue
		if not child.has_meta("projectile_part"):
			_visual.remove_child(child)
			child.queue_free()
	var variant := _visual_variant(dmg_type, projectile_archetype)
	var parts: Array = variant.get("parts", [])
	for child in _visual.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("Part"):
			var part_index := int(str(child.name).trim_prefix("Part"))
			if part_index >= parts.size():
				child.hide()
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


static func _visual_variant(dmg_type: String, archetype: String = "arrow") -> Dictionary:
	var cache_key := "%s:%s" % [archetype, dmg_type]
	if _visual_variants.has(cache_key):
		return _visual_variants[cache_key]
	var element := MaterialFlashScript.tint_for_damage_type(dmg_type)
	var parts: Array = []
	if archetype == "bolt_orb":
		var orb := SphereMesh.new()
		orb.radius = 0.18
		orb.height = 0.36
		var orb_mat := PixelStyleScript.make_glow_material(element.lightened(0.2), element.darkened(0.4), 1.5)
		parts.append({"mesh": orb, "position": Vector3.ZERO, "material": orb_mat})
	else:
		var shaft_mat := PixelStyleScript.make_material(Color(0.42, 0.30, 0.18))
		var head_mat := PixelStyleScript.make_glow_material(element, element.darkened(0.35), 1.9)
		var fletch_mat := PixelStyleScript.make_material(element.lightened(0.25))
		parts = [
			_part_variant(Vector3(0.05, 0.05, 0.62), Vector3(0.0, 0.0, 0.06), shaft_mat),
			_part_variant(Vector3(0.09, 0.09, 0.18), Vector3(0.0, 0.0, -0.32), head_mat),
			_part_variant(Vector3(0.16, 0.02, 0.16), Vector3(0.0, 0.0, 0.3), fletch_mat),
			_part_variant(Vector3(0.02, 0.16, 0.16), Vector3(0.0, 0.0, 0.3), fletch_mat),
		]
	var variant := {"element": element, "parts": parts}
	_visual_variants[cache_key] = variant
	_visual_variant_build_count += 1
	return variant


static func reset_metrics() -> void:
	_swept_query_count = 0
	ProjectileContainerScript.reset_metrics()


static func metrics() -> Dictionary:
	return {
		"swept_queries": _swept_query_count,
		"visual_variant_builds": _visual_variant_build_count,
		"cached_visual_variants": _visual_variants.size(),
		"projectiles_created": ProjectileContainerScript.total_created,
		"projectiles_reused": ProjectileContainerScript.total_reused,
	}


static func _part_variant(size: Vector3, part_position: Vector3, material: Material) -> Dictionary:
	var mesh := BoxMesh.new()
	mesh.size = size
	return {"mesh": mesh, "position": part_position, "material": material}


func _on_hit_landed(_target: Node) -> void:
	# Penetration is decided by `_resolve_motion_contacts()` after it has inspected the complete
	# DamageResolution. This impact hook only owns the terminal visual/lifecycle outcome.
	_hitbox.disable()
	_finish_lifecycle()


## `RG-04`: the hook a `ThrowableProjectile` overrides to explode on terrain instead of silently
## vanishing -- the default here is exactly the old inline `queue_free()` so every other shot
## (enemy arrows included) behaves unchanged.
func _on_world_impact(contact: Dictionary = {}) -> void:
	var impact_position: Variant = contact.get("position")
	if impact_position is Vector3:
		global_position = impact_position
	# Character impacts are voiced by HitFeedback through Hurtbox; terrain impacts have no
	# corresponding receiver, so close the projectile's contact with the authored stone cue here.
	var audio_director := get_node_or_null("/root/AudioDirector")
	if audio_director and audio_director.has_method("play_sfx"):
		audio_director.call("play_sfx", "hit_stone", global_position)
	if VfxService:
		var normal: Vector3 = contact.get("normal", Vector3.UP)
		VfxService.play_hit_spark(global_position, -_velocity.normalized(), normal)
	_finish_lifecycle()


func _physics_process(delta: float) -> void:
	if _settling:
		_process_settling(delta)
		return
	if _fading:
		_fade_timer -= delta
		if _visual:
			_visual.scale = Vector3.ONE * clampf(_fade_timer / FADE_DURATION, 0.0, 1.0)
		if _fade_timer <= 0.0:
			_finish_lifecycle()
		return
	var motion: Vector3
	var gravity_value := _gravity_for_archetype()
	if is_equal_approx(drag, 1.0):
		motion = _velocity * delta + Vector3.DOWN * (gravity_value * delta * delta * 0.5)
		_velocity.y -= gravity_value * delta
	else:
		_velocity.y -= gravity_value * delta
		_velocity *= clampf(pow(drag, delta), 0.0, 1.0)
		motion = _velocity * delta
	if motion.length_squared() > 0.0:
		var space := get_world_3d().direct_space_state
		if space and not _resolve_motion_contacts(space, motion):
			return
		if space == null:
			global_position += motion
	_distance_travelled += motion.length()
	_face_velocity()
	_lifetime -= delta
	if _lifetime <= 0.0 or _distance_travelled >= MAX_RANGE:
		_on_lifetime_expired()


func _on_lifetime_expired() -> void:
	_begin_fade()


func _world_contact(space: PhysicsDirectSpaceState3D, motion: Vector3) -> Dictionary:
	_world_shape.radius = _collision_radius()
	_world_query.shape = _world_shape
	_world_query.transform = Transform3D(Basis.IDENTITY, global_position)
	_world_query.motion = motion
	_world_query.exclude = []
	if is_instance_valid(_owner_node) and _owner_node is CollisionObject3D:
		_world_query.exclude.append((_owner_node as CollisionObject3D).get_rid())
	var cast := space.cast_motion(_world_query)
	_swept_query_count += 1
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


## Resolves terrain and hurtboxes from one swept sphere step. Each query yields the first safe
## fraction for its collision class; comparing those fractions gives target-before-wall and
## wall-before-target deterministic semantics. A pierced target advances the remaining segment,
## rather than waiting for the next physics frame and losing a close second target.
func _resolve_motion_contacts(space: PhysicsDirectSpaceState3D, motion: Vector3) -> bool:
	var remaining := motion
	var iterations := 0
	while remaining.length_squared() > 0.000001 and iterations < 16:
		iterations += 1
		var world_fraction := _cast_fraction(space, _world_query, remaining)
		var target_fraction := _cast_fraction(space, _target_query, remaining)
		if world_fraction >= 1.0 and target_fraction >= 1.0:
			global_position += remaining
			return true
		if world_fraction <= target_fraction:
			var world_contact := _world_contact(space, remaining)
			if world_contact.is_empty():
				global_position += remaining * world_fraction
				_on_world_impact({"position": global_position, "normal": -remaining.normalized()})
			else:
				global_position = world_contact.get("position", global_position)
				_on_world_impact(world_contact)
			return false
		var contact_position := global_position + remaining * target_fraction
		var target := _first_target_at(space, contact_position)
		if target == null:
			# A cast can identify a boundary just before an Area query includes it. Advance a tiny
			# amount so that this cannot stall the shot forever on a floating-point edge.
			var nudge := minf(0.002, remaining.length())
			global_position += remaining.normalized() * nudge
			remaining -= remaining.normalized() * nudge
			continue
		global_position = contact_position
		var resolution := _hitbox.resolve_contact(target)
		if resolution == null:
			# Ineligible candidates (same team/already hit) do not stop a projectile. Move past this
			# boundary and keep testing the remainder of the proposed segment.
			var ignored_nudge := minf(0.002, remaining.length())
			global_position += remaining.normalized() * ignored_nudge
			remaining -= remaining.normalized() * ignored_nudge
			continue
		# A physical contact consumes a shot on a dodge, block or parry too. Only an unblocked,
		# successful damage result may use a pierce charge; this prevents a multi-region body from
		# draining several charges and makes each defensive outcome explicit.
		var defensive_contact := resolution.dodged or resolution.parried or resolution.blocked
		if _pierce_remaining <= 0 or resolution.outgoing <= 0.0 or defensive_contact:
			_on_hit_landed(target)
			return false
		_pierce_remaining -= 1
		var advance := minf(0.01, remaining.length())
		global_position += remaining.normalized() * advance
		remaining -= remaining.normalized() * advance
	# Defensive guard against malformed overlapping collision setups. A bounded unresolved step
	# is safer than tunnelling through every object in a crowded frame.
	global_position += remaining
	return true


func _cast_fraction(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, motion: Vector3) -> float:
	_world_shape.radius = _collision_radius()
	query.shape = _world_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.motion = motion
	query.exclude = []
	if is_instance_valid(_owner_node) and _owner_node is CollisionObject3D:
		query.exclude.append((_owner_node as CollisionObject3D).get_rid())
	var cast := space.cast_motion(query)
	_swept_query_count += 1
	return clampf(float(cast[1]) if cast.size() > 1 else 1.0, 0.0, 1.0)


func _first_target_at(space: PhysicsDirectSpaceState3D, contact_position: Vector3) -> Area3D:
	_target_query.shape = _world_shape
	_target_query.transform = Transform3D(Basis.IDENTITY, contact_position)
	_target_query.motion = Vector3.ZERO
	var candidates: Array[Dictionary] = space.intersect_shape(_target_query, 32)
	_swept_query_count += 1
	var areas: Array[Area3D] = []
	for candidate in candidates:
		var collider: Variant = candidate.get("collider")
		if collider is Area3D:
			areas.append(collider as Area3D)
	areas.sort_custom(func(a: Area3D, b: Area3D) -> bool:
		var a_distance := a.global_position.distance_squared_to(contact_position)
		var b_distance := b.global_position.distance_squared_to(contact_position)
		return a_distance < b_distance if not is_equal_approx(a_distance, b_distance) else a.get_instance_id() < b.get_instance_id()
	)
	return areas[0] if not areas.is_empty() else null


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
	if projectile_archetype == "arrow":
		_fading = false
		_settling = true
		_settle_timer = 3.0


func _process_settling(delta: float) -> void:
	var gravity_value := _gravity_for_archetype()
	var motion := _velocity * delta + Vector3.DOWN * (gravity_value * delta * delta * 0.5)
	_velocity.y -= gravity_value * delta
	var space := get_world_3d().direct_space_state
	if space:
		var contact := _world_contact(space, motion)
		if not contact.is_empty():
			global_position = contact.get("position", global_position + motion)
			_on_world_impact(contact)
			return
	global_position += motion
	_face_velocity()
	_settle_timer -= delta
	if _settle_timer <= FADE_DURATION and _visual:
		_visual.scale = Vector3.ONE * clampf(_settle_timer / FADE_DURATION, 0.0, 1.0)
	if _settle_timer <= 0.0:
		_finish_lifecycle()


static func gravity_for_archetype(archetype: String) -> float:
	match archetype:
		"bolt_orb":
			return 2.0
		"lobbed_item":
			return 15.0
		_:
			return GRAVITY


func _gravity_for_archetype() -> float:
	return gravity_for_archetype(projectile_archetype)


## Pool only after all gameplay state is inert.  This reset is deliberately centralized so
## callers cannot accidentally reuse a faded arrow with stale ownership, pierce or hit history.
func _finish_lifecycle() -> void:
	if _recycling:
		return
	_recycling = true
	set_physics_process(false)
	monitoring = false
	_hitbox.disable()
	_hitbox.monitoring = false
	_hitbox.set_physics_process(false)
	_hitbox.set_combat_owner(null)
	_hitbox.set_attack_values(0.0, 0.0)
	_hitbox.set_root_attack_id("")
	_velocity = Vector3.ZERO
	_owner_node = null
	_pierce_remaining = 0
	_distance_travelled = 0.0
	_fading = false
	_fade_timer = 0.0
	_settling = false
	_settle_timer = 0.0
	if _visual:
		_visual.scale = Vector3.ONE
		_visual.hide()
	call_deferred("_return_to_pool")


func _return_to_pool() -> void:
	if not is_instance_valid(self):
		return
	ProjectileContainerScript.recycle(self)


## Points the shaft down the arrow's actual path rather than where it was aimed at launch, so the
## fall reads in the model's pitch and not just the position -- the difference between an arrow
## dropping and an arrow that visibly stops caring about gravity.
func _face_velocity() -> void:
	if _velocity.length_squared() < 0.0001:
		return
	var horizontal := Vector3(_velocity.x, 0.0, _velocity.z)
	var up := Vector3.UP if horizontal.length_squared() > 0.0001 else Vector3.FORWARD
	look_at(global_position + _velocity, up)
