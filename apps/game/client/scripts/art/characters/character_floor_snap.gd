class_name CharacterFloorSnap
extends RefCounted


const PROBE_UP_OFFSET := 1.0
const PROBE_MAX_DROP := 6.0
const PROBE_MASK := 1
const PROBE_MAX_SLOPE_DEG := 50.0


static func collision_bottom_local(body: Node3D) -> float:
	var lowest := INF
	for child in body.find_children("*", "CollisionShape3D", true, false):
		var shape_node := child as CollisionShape3D
		if shape_node.shape == null or shape_node.disabled or _is_under_area(body, shape_node):
			continue
		lowest = minf(lowest, _collision_shape_bottom_local(body, shape_node))
	return 0.0 if lowest == INF else lowest


static func _is_under_area(body: Node3D, shape_node: CollisionShape3D) -> bool:
	var current := shape_node.get_parent()
	while current != null and current != body:
		if current is Area3D:
			return true
		current = current.get_parent()
	return false


static func _collision_shape_bottom_local(body: Node3D, shape_node: CollisionShape3D) -> float:
	var bottom_offset_y := _shape_bottom_offset_y(shape_node.shape, body, shape_node)
	var body_local := body.to_local(shape_node.to_global(Vector3(0.0, bottom_offset_y, 0.0)))
	return body_local.y


static func _shape_bottom_offset_y(shape: Shape3D, body: Node3D, _shape_node: CollisionShape3D) -> float:
	if shape is CapsuleShape3D:
		return -(shape as CapsuleShape3D).height * 0.5
	if shape is BoxShape3D:
		return -(shape as BoxShape3D).size.y * 0.5
	if shape is CylinderShape3D:
		return -(shape as CylinderShape3D).height * 0.5
	if shape is SphereShape3D:
		return -(shape as SphereShape3D).radius
	if shape is SeparationRayShape3D:
		return -(shape as SeparationRayShape3D).length
	var debug_mesh := shape.get_debug_mesh()
	if debug_mesh:
		push_warning(
			(
				"CharacterFloorSnap: unrecognized shape %s on %s, using debug mesh AABB"
				% [shape.get_class(), body.name]
			)
		)
		return debug_mesh.get_aabb().position.y
	push_warning(
		"CharacterFloorSnap: unrecognized shape %s on %s with no debug mesh" % [shape.get_class(), body.name]
	)
	return 0.0


static func snap_feet_to_world_y(body: CharacterBody3D, world_floor_y: float) -> void:
	var feet_world := body.to_global(Vector3(0.0, collision_bottom_local(body), 0.0))
	var delta_y := world_floor_y - feet_world.y
	body.global_position += Vector3(0.0, delta_y, 0.0)


static func probe_floor_y(
	world: World3D,
	from: Vector3,
	fallback: float,
	max_drop: float = PROBE_MAX_DROP,
	mask: int = PROBE_MASK,
	exclude: Array[RID] = []
) -> float:
	if world == null:
		return fallback
	var space := world.direct_space_state
	if space == null:
		return fallback
	var origin := from + Vector3(0.0, PROBE_UP_OFFSET, 0.0)
	var to := origin + Vector3(0.0, -(PROBE_UP_OFFSET + max_drop), 0.0)
	var params := PhysicsRayQueryParameters3D.create(origin, to)
	params.collision_mask = mask
	params.collide_with_areas = false
	if not exclude.is_empty():
		params.exclude = exclude
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return fallback
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var slope_deg := rad_to_deg(acos(clampf(normal.dot(Vector3.UP), -1.0, 1.0)))
	if slope_deg > PROBE_MAX_SLOPE_DEG:
		return fallback
	var hit_pos: Vector3 = hit.get("position", from)
	return hit_pos.y


static func snap_to_floor_below(body: CharacterBody3D, fallback_y: float = NAN) -> void:
	var fallback := fallback_y
	if is_nan(fallback):
		fallback = body.to_global(Vector3(0.0, collision_bottom_local(body), 0.0)).y
	var exclude: Array[RID] = [body.get_rid()]
	var floor_y := probe_floor_y(
		body.get_world_3d(), body.global_position, fallback, PROBE_MAX_DROP, PROBE_MASK, exclude
	)
	snap_feet_to_world_y(body, floor_y)


static func align_diorama_visual(body: Node3D, visual: Node3D) -> void:
	if visual == null:
		return
	var feet_y := body.to_global(Vector3(0.0, collision_bottom_local(body), 0.0)).y
	visual.global_position = Vector3(visual.global_position.x, feet_y, visual.global_position.z)


static func snap_character(body: CharacterBody3D, visual: Node3D, fallback_y: float = NAN) -> void:
	snap_to_floor_below(body, fallback_y)
	align_diorama_visual(body, visual)
