class_name EnemyPerception
extends RefCounted


## Stateless sensing primitives shared by enemy actors. Lifecycle (awareness decay, alert sharing
## and AI state changes) stays on the actor; these helpers own only the physical observations.
static func distance_squared(observer: Node3D, target: Node3D) -> float:
	if observer == null or target == null or not is_instance_valid(observer) or not is_instance_valid(target):
		return INF
	return observer.global_position.distance_squared_to(target.global_position)


static func has_line_of_sight(observer: Node3D, target: Node3D, collision_mask: int) -> bool:
	if observer == null or target == null or not is_instance_valid(observer) or not is_instance_valid(target):
		return false
	var space := observer.get_world_3d().direct_space_state
	if space == null:
		return true
	var from := observer.global_position + Vector3(0.0, 1.2, 0.0)
	var to := target.global_position + Vector3(0.0, 1.0, 0.0)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = collision_mask
	params.collide_with_areas = false
	params.collide_with_bodies = true
	if observer is CollisionObject3D:
		params.exclude.append((observer as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		params.exclude.append((target as CollisionObject3D).get_rid())
	return space.intersect_ray(params).is_empty()


static func is_inside_vision_cone(observer: Node3D, target: Node3D, vision_cone_cos: float) -> bool:
	if observer == null or target == null or not is_instance_valid(observer) or not is_instance_valid(target):
		return false
	var toward := target.global_position - observer.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		return true
	var facing := CombatFacing.forward_of(observer)
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		return true
	return facing.normalized().dot(toward.normalized()) >= vision_cone_cos


static func noise_level(target: Node) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	if target.has_method("get_noise_level"):
		return clampf(float(target.call("get_noise_level")), 0.0, 1.0)
	if not target is CharacterBody3D:
		return 0.0
	var flat := (target as CharacterBody3D).velocity
	flat.y = 0.0
	return clampf((flat.length() - 2.0) / 4.5, 0.0, 1.0)
