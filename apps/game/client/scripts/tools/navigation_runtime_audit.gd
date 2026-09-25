extends Node3D


func _ready() -> void:
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([
		Vector3(-2.0, 0.0, -2.0), Vector3(-2.0, 0.0, 2.0),
		Vector3(2.0, 0.0, 2.0), Vector3(2.0, 0.0, -2.0),
	])
	mesh.add_polygon(PackedInt32Array([0, 3, 2, 1]))
	mesh.emit_changed()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	NavigationServer3D.region_set_transform(region, Transform3D.IDENTITY)
	for _frame in 4:
		await get_tree().process_frame
	NavigationServer3D.map_force_update(map)
	await get_tree().process_frame
	var closest := NavigationServer3D.map_get_closest_point(map, Vector3(1.0, 0.0, 1.0))
	var passed := closest.distance_to(Vector3(1.0, 0.0, 1.0)) < 0.1
	print("NAVIGATION RUNTIME RESULT %s regions=%d closest=%s" % ["PASS" if passed else "FAIL", NavigationServer3D.map_get_regions(map).size(), closest])
	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)
	get_tree().quit(0 if passed else 1)
