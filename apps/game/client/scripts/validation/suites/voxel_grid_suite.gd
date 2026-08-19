extends "res://scripts/validation/validation_suite.gd"

const VoxelGrid := preload("res://scripts/art/characters/voxel_grid.gd")
const VoxelMeshBuilder := preload("res://scripts/art/characters/voxel_mesh_builder.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_mesh_vertices_on_grid()
	_test_mesh_colors_on_palette()


func _test_mesh_vertices_on_grid() -> void:
	var start := Time.get_ticks_msec()
	var violations: PackedStringArray = []
	for path in _character_mesh_paths():
		var mesh := VoxelMeshBuilder.load_mesh(path, PixelStyle.PaletteTheme.CASTLE)
		if mesh == null:
			violations.append("%s:load_failed" % path)
			continue
		for surface_idx in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface_idx)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				if not _on_grid(vertex.x) or not _on_grid(vertex.y) or not _on_grid(vertex.z):
					violations.append("%s:off_grid" % path.get_file())
					break
	ctx.timed_record(
		"voxel_grid.vertices_on_edge",
		get_category(),
		violations.is_empty(),
		(
			"all voxel mesh vertices on VoxelGrid.EDGE"
			if violations.is_empty()
			else "violations: %s" % ", ".join(violations)
		),
		start,
		"CHA-06"
	)


func _test_mesh_colors_on_palette() -> void:
	var start := Time.get_ticks_msec()
	var violations: PackedStringArray = []
	for path in _character_mesh_paths():
		var mesh := VoxelMeshBuilder.load_mesh(path, PixelStyle.PaletteTheme.CASTLE)
		if mesh == null:
			continue
		for surface_idx in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface_idx)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for color in colors:
				if not VoxelGrid.color_matches_palette(color):
					violations.append("%s:off_palette" % path.get_file())
					break
	ctx.timed_record(
		"voxel_grid.palette_snap",
		get_category(),
		violations.is_empty(),
		(
			"vertex colours snap to theme palette"
			if violations.is_empty()
			else "violations: %s" % ", ".join(violations)
		),
		start,
		"CHA-06"
	)


static func _on_grid(value: float) -> bool:
	var snapped := VoxelGrid.snap_metres(value)
	return absf(value - snapped) <= VoxelGrid.SNAP_EPSILON


static func _character_mesh_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	var root := DirAccess.open("res://assets/characters")
	if root == null:
		return paths
	root.list_dir_begin()
	var archetype := root.get_next()
	while archetype != "":
		if root.current_is_dir() and not archetype.begins_with(".") and archetype != "_intermediate":
			var part_dir := DirAccess.open("res://assets/characters/%s" % archetype)
			if part_dir:
				part_dir.list_dir_begin()
				var entry := part_dir.get_next()
				while entry != "":
					if entry.ends_with(".tres"):
						paths.append("res://assets/characters/%s/%s" % [archetype, entry])
					entry = part_dir.get_next()
				part_dir.list_dir_end()
		archetype = root.get_next()
	root.list_dir_end()
	var equip_dir := DirAccess.open("res://assets/characters/equipment")
	if equip_dir:
		equip_dir.list_dir_begin()
		var equip_entry := equip_dir.get_next()
		while equip_entry != "":
			if equip_entry.ends_with(".tres"):
				paths.append("res://assets/characters/equipment/%s" % equip_entry)
			equip_entry = equip_dir.get_next()
		equip_dir.list_dir_end()
	return paths
