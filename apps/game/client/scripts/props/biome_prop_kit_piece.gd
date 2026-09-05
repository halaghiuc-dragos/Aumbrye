extends Node3D
class_name BiomePropKitPiece

## RM-21: every authored `propKit` scene (pillar / sconce / rubble_a / rubble_b) carries its
## primitive-mesh geometry directly in the .tscn -- see the `scenes/props/<biome>/` files that use
## this script. The *material* is applied here at runtime instead, so an authored prop always gets
## the exact same `Material` resource `diorama_room_dressing.gd`'s procedural fallback would use
## for the same biome and slot, rather than a hand-copied set of shader params that can drift out
## of sync with `PixelDioramaStyle`/`BiomeRegistry`.
##
## "pillar" and "rubble" use the shared accent surface material (`BiomeRegistry.get_accent_material`,
## the same call `_add_box()` callers pass in today). "sconce" is emissive-only by design (see the
## RM-21 plan entry) -- it uses `PixelDioramaStyle.make_emissive_material()`, the
## `pixel_diorama_emissive` shader, and never an `OmniLight3D` of its own.

@export var biome_id: String = ""
@export var piece_kind: String = "pillar"  # "pillar" | "sconce" | "rubble"
@export var emissive_energy: float = 1.3


func _ready() -> void:
	_apply_material()


func _apply_material() -> void:
	if biome_id == "":
		return
	var mat: Material = null
	if piece_kind == "sconce":
		var theme := PixelDioramaStyle.theme_from_biome(biome_id)
		mat = PixelDioramaStyle.make_emissive_material(theme, emissive_energy)
	else:
		mat = BiomeRegistry.get_accent_material(biome_id)
	if mat == null:
		return
	for mesh_instance in _collect_mesh_instances(self):
		mesh_instance.material_override = mat


func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_collect_mesh_instances(child))
	return out
