extends Node3D

const VillageCrowdScript := preload("res://scripts/art/world/village_crowd.gd")

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _ready() -> void:
	var crowd := VillageCrowdScript.new() as VillageCrowd
	add_child(crowd)
	var routes: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(15.0, 0.0), Vector2(45.0, 0.0)]),
		PackedVector2Array([Vector2(135.0, 0.0), Vector2(165.0, 0.0)]),
		PackedVector2Array([Vector2(285.0, 0.0), Vector2(315.0, 0.0)]),
	]
	crowd.set_routes(routes, PackedFloat32Array([4.0, 4.0, 4.0]))
	var parts: Array[Dictionary] = [{"mat": "cloth", "size": Vector3.ONE, "at": Vector3.ZERO}]
	for route_index in routes.size():
		crowd.add_agent(parts, route_index, 0.5, 1.0, 1.0, 0.1)
	crowd.commit(
		{"cloth": StandardMaterial3D.new()},
		AABB(Vector3(-400.0, -10.0, -400.0), Vector3(800.0, 20.0, 800.0))
	)
	for _frame in 5:
		crowd._step(1.0 / VillageCrowd.TICK_HZ)
	var metrics := crowd.lod_metrics()
	_check(int(metrics.get("near", 0)) == 5, "Near crowd must retain the 30 Hz update rate")
	_check(int(metrics.get("mid", 0)) == 2, "Mid-distance crowd must update at half the near rate")
	_check(int(metrics.get("far", 0)) == 1, "Far crowd must use the reduced 8 Hz transform rate")
	_check(
		int(crowd._agents[0]["lod_updates"]) > int(crowd._agents[2]["lod_updates"]),
		"Near agents must receive more transform writes than far agents"
	)
	# Route radius is only a fallback. A live camera/visibility origin must be able to suppress
	# every distant walker and restore its slots when the viewpoint returns.
	crowd.set_visibility_origin_for_testing(Vector3(1000.0, 0.0, 1000.0))
	crowd._step(1.0 / VillageCrowd.TICK_HZ)
	_check(
		int(crowd.lod_metrics().get("culled", 0)) == routes.size(),
		"Crowd must suppress agents outside the useful camera-distance cap"
	)
	crowd.set_visibility_origin_for_testing(Vector3.ZERO)
	crowd._step(1.0 / VillageCrowd.TICK_HZ)
	for agent in crowd._agents:
		_check(
			str(agent.get("visibility", "")) == "visible",
			"A returning camera must restore previously culled crowd slots"
		)
	print("VILLAGE CROWD LOD RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
