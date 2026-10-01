class_name WallCladding
extends RefCounted

## Blender masonry laid over a flat wall face: two-metre modules stretched to fit, so the bare box
## behind them only shows as mortar. Used by room walls and by the floor shell.

const MODULE := 2.0


## Module placements for a face `length` metres wide and `height` high whose surface is at `face`
## (bottom centre) and looks along `normal`.
static func face_transforms(face: Vector3, normal: Vector3, length: float, base_y: float, height: float) -> Array[Transform3D]:
	var facing := Basis(Vector3.UP, atan2(normal.x, normal.z))
	var along := facing * Vector3.RIGHT
	var columns := maxi(1, roundi(length / MODULE))
	var rows := maxi(1, roundi(height / MODULE))
	var stretch := Basis.from_scale(Vector3(length / (float(columns) * MODULE), height / (float(rows) * MODULE), 1.0))
	var out: Array[Transform3D] = []
	for column in columns:
		var offset := -length * 0.5 + (float(column) + 0.5) * length / float(columns)
		for row in rows:
			var origin := face + along * offset + Vector3(0.0, base_y + height * float(row) / float(rows), 0.0)
			out.append(Transform3D(facing * stretch, origin))
	return out


## Draws `transforms` as instanced masonry in `biome_id`'s style, optionally skinned with `materials`.
static func place(
	parent: Node3D, transforms: Array[Transform3D], biome_id: String, materials: Dictionary, node_name: String
) -> void:
	if transforms.is_empty():
		return
	var style := str(PropLibrary.BIOME_STYLES.get(biome_id, "castle"))
	var theme := PixelDioramaStyle.theme_from_biome(biome_id if biome_id != "" else BiomeRegistry.BIOME_CASTLE)
	var options := {}
	if not materials.is_empty():
		options["materials"] = materials
	PropLibrary.scatter_themed(parent, "walls/masonry_%s" % style, theme, transforms, node_name, options)
