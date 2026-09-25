extends Node3D

const PixelBoxBatchScript := preload("res://scripts/art/style/pixel_box_batch.gd")

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _ready() -> void:
	var first_material := StandardMaterial3D.new()
	var second_material := StandardMaterial3D.new()
	var batch := PixelBoxBatchScript.new() as PixelBoxBatch
	batch.add(Vector3(2.0, 1.0, 3.0), Vector3(1.0, 0.5, 1.0), first_material)
	batch.add(
		Vector3(1.0, 2.0, 1.0),
		Vector3(2.0, 1.0, 2.0),
		first_material,
		Basis(Vector3.UP, deg_to_rad(35.0))
	)
	batch.add(Vector3.ONE, Vector3(20.0, 0.5, 1.0), first_material)
	batch.add(Vector3.ONE, Vector3(1.0, 0.5, 20.0), second_material)
	_check(batch.instance_count() == 4, "Spatial material buckets must retain every submitted box")
	var root := batch.commit(self, "SpatialBatchAudit", AABB(Vector3(-100.0, -10.0, -100.0), Vector3(200.0, 20.0, 200.0)))
	_check(root.get_child_count() == 3, "Same-material boxes must split by spatial cell, not by instance")
	var first_cell: MultiMeshInstance3D
	for child in root.get_children():
		var instance := child as MultiMeshInstance3D
		if instance == null or instance.multimesh == null:
			_check(false, "Each spatial batch must have a MultiMeshInstance3D")
			continue
		if str(instance.name).ends_with("Cell0_0"):
			first_cell = instance
		if str(instance.name).ends_with("Cell1_0"):
			_check(instance.custom_aabb.has_point(Vector3(20.0, 0.5, 1.0)), "X-adjacent cell bounds must contain their geometry")
		if str(instance.name).ends_with("Cell0_1"):
			_check(instance.custom_aabb.has_point(Vector3(1.0, 0.5, 20.0)), "Z-adjacent cell bounds must contain their geometry")
	_check(first_cell != null, "First spatial cell must exist")
	if first_cell:
		var first_transform := Transform3D(Basis().scaled_local(Vector3(2.0, 1.0, 3.0)), Vector3(1.0, 0.5, 1.0))
		var second_transform := Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)).scaled_local(Vector3(1.0, 2.0, 1.0)), Vector3(2.0, 1.0, 2.0))
		_check_bounds_contains_box(first_cell.custom_aabb, first_transform)
		_check_bounds_contains_box(first_cell.custom_aabb, second_transform)
	_check(batch.is_empty(), "Commit must release temporary CPU-side batch buffers")
	print("PIXEL BOX BATCH RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_bounds_contains_box(bounds: AABB, item_transform: Transform3D) -> void:
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				_check(
					bounds.has_point(item_transform * Vector3(x, y, z)),
					"Batch AABB must contain every submitted transformed box corner"
				)
