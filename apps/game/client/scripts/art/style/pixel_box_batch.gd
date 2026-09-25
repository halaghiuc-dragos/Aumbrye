class_name PixelBoxBatch
extends RefCounted


static var _unit_cube: BoxMesh = null
const SPATIAL_CELL_SIZE := 16.0

var _by_material: Dictionary = {}


static func unit_cube() -> BoxMesh:
	if _unit_cube == null:
		_unit_cube = BoxMesh.new()
		_unit_cube.size = Vector3.ONE
	return _unit_cube


func add(size: Vector3, position: Vector3, material: Material, basis: Basis = Basis()) -> void:
	if material == null:
		return
	# `scaled_local`, not `scaled`. `Basis.scaled()` multiplies the basis' rows, applying the
	# scale in the parent frame — after the rotation. Identical for an axis-aligned box, which is
	# why it can go unnoticed; for a rotated one it flattens the box along the world axis instead
	# of its own.
	var xform := Transform3D(basis.scaled_local(size), position)
	var cell := Vector2i(floori(position.x / SPATIAL_CELL_SIZE), floori(position.z / SPATIAL_CELL_SIZE))
	if not _by_material.has(material):
		_by_material[material] = {}
	var material_cells: Dictionary = _by_material[material]
	if not material_cells.has(cell):
		material_cells[cell] = {"buffer": PackedFloat32Array(), "bounds": _transformed_unit_box_bounds(xform)}
	else:
		var existing_cell_data: Dictionary = material_cells[cell]
		existing_cell_data["bounds"] = (existing_cell_data["bounds"] as AABB).merge(_transformed_unit_box_bounds(xform))
		material_cells[cell] = existing_cell_data
	var cell_data: Dictionary = material_cells[cell]
	var buffer: PackedFloat32Array = cell_data["buffer"]
	buffer.append_array(
		PackedFloat32Array(
			[
				xform.basis.x.x, xform.basis.y.x, xform.basis.z.x, xform.origin.x,
				xform.basis.x.y, xform.basis.y.y, xform.basis.z.y, xform.origin.y,
				xform.basis.x.z, xform.basis.y.z, xform.basis.z.z, xform.origin.z,
			]
		)
	)
	cell_data["buffer"] = buffer
	material_cells[cell] = cell_data
	_by_material[material] = material_cells


func is_empty() -> bool:
	return _by_material.is_empty()


func instance_count() -> int:
	var total := 0
	for material in _by_material:
		var material_cells: Dictionary = _by_material[material]
		for cell in material_cells:
			var cell_data: Dictionary = material_cells[cell]
			total += int((cell_data["buffer"] as PackedFloat32Array).size() / 12.0)
	return total


func commit(parent: Node3D, node_name: String, _visibility_aabb: AABB) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	var index := 0
	for material in _by_material:
		var material_cells: Dictionary = _by_material[material]
		for cell in material_cells:
			var cell_data: Dictionary = material_cells[cell]
			var buffer: PackedFloat32Array = cell_data["buffer"]
			var count := int(buffer.size() / 12.0)
			if count <= 0:
				continue
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = unit_cube()
			multimesh.instance_count = count
			multimesh.buffer = buffer
			var node := MultiMeshInstance3D.new()
			node.name = "%sBatch%dCell%d_%d" % [node_name, index, cell.x, cell.y]
			node.multimesh = multimesh
			node.material_override = material as Material
			node.custom_aabb = (cell_data["bounds"] as AABB).grow(0.02)
			root.add_child(node)
			index += 1
	_by_material.clear()
	return root


func _transformed_unit_box_bounds(xform: Transform3D) -> AABB:
	var bounds := AABB()
	var first_point := true
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				var corner := xform * Vector3(x, y, z)
				if first_point:
					bounds = AABB(corner, Vector3.ZERO)
					first_point = false
				else:
					bounds = bounds.expand(corner)
	return bounds
