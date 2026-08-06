extends RefCounted
class_name StairCollisionBuilder

## FLOOR-7.3 — physical collision geometry for stair ramps.


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
		box.size = (ramp.mesh as BoxMesh).size
		shape_node.transform = ramp.transform
	else:
		box.size = Vector3(4.0, 0.4, 12.0)
		shape_node.position = Vector3(0.0, 1.2, 0.0)
	shape_node.shape = box
	body.add_child(shape_node)
	props.add_child(body)
