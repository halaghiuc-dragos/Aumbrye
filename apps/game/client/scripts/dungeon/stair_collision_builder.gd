extends RefCounted
class_name StairCollisionBuilder


## The ramp is dressing for a room whose name is a naming convention, not a real change in floor
## height -- the floor stays flat and the player leaves through the lever, not by climbing. Giving
## the collider the mesh's own tilt turns it into a walkable slope shallow enough to stand on, so
## the shape here stays axis-aligned instead: solid enough that the player cannot walk through the
## prop, but flat, so there is nothing to climb.
static func ensure_stair_collision(room: RoomTemplate) -> void:
	if room == null:
		return
	var props := room.get_node_or_null("Props")
	if props == null:
		push_error("StairCollisionBuilder: room '%s' has no Props node" % room.room_id)
		return
	if props.get_node_or_null("StairCollision"):
		return
	var ramp := props.get_node_or_null("StairRamp") as MeshInstance3D
	if ramp == null:
		push_error("StairCollisionBuilder: room '%s' Props missing StairRamp" % room.room_id)
		return
	var body := StaticBody3D.new()
	body.name = "StairCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if ramp and ramp.mesh is BoxMesh:
		var mesh_size: Vector3 = (ramp.mesh as BoxMesh).size
		box.size = Vector3(mesh_size.x, 0.4, mesh_size.z)
		shape_node.position = Vector3(ramp.position.x, 0.2, ramp.position.z)
	else:
		box.size = Vector3(4.0, 0.4, 12.0)
		shape_node.position = Vector3(0.0, 0.2, 0.0)
	shape_node.shape = box
	body.add_child(shape_node)
	props.add_child(body)
