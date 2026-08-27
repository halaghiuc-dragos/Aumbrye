class_name PixelBoxBatch
extends RefCounted


static var _unit_cube: BoxMesh = null

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
	if not _by_material.has(material):
		_by_material[material] = PackedFloat32Array()
	var buffer: PackedFloat32Array = _by_material[material]
	buffer.append_array(
		PackedFloat32Array(
			[
				xform.basis.x.x, xform.basis.y.x, xform.basis.z.x, xform.origin.x,
				xform.basis.x.y, xform.basis.y.y, xform.basis.z.y, xform.origin.y,
				xform.basis.x.z, xform.basis.y.z, xform.basis.z.z, xform.origin.z,
			]
		)
	)
	_by_material[material] = buffer


func is_empty() -> bool:
	return _by_material.is_empty()


func instance_count() -> int:
	var total := 0
	for material in _by_material:
		total += int((_by_material[material] as PackedFloat32Array).size() / 12.0)
	return total


func commit(parent: Node3D, node_name: String, visibility_aabb: AABB) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	var index := 0
	for material in _by_material:
		var buffer: PackedFloat32Array = _by_material[material]
		var count := int(buffer.size() / 12.0)
		if count <= 0:
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = unit_cube()
		multimesh.instance_count = count
		multimesh.buffer = buffer
		var node := MultiMeshInstance3D.new()
		node.name = "%sBatch%d" % [node_name, index]
		node.multimesh = multimesh
		node.material_override = material as Material
		node.custom_aabb = visibility_aabb
		root.add_child(node)
		index += 1
	_by_material.clear()
	return root
