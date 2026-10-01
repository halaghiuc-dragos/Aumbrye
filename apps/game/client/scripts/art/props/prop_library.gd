class_name PropLibrary
extends RefCounted

## Places Blender-built props (tools/blender/props_*.py, assets/props/*.glb) into the world.
##
## A prop file holds one or more named objects (a chest has `Body` and `Lid`, so the lid can swing
## about its own hinge). `attach()` moves those objects under a caller-owned root, keeping their
## names and transforms, and gives each surface the diorama material its role asks for. Materials
## are chosen per instance from the biome, so one model serves every biome.
##
## Surface roles (the Blender material names):
##   wall, floor, accent   the biome's structural materials
##   timber, trim          the biome's wood and metal-trim prop materials
##   iron, darkiron, steel fixed metals
##   glow, orb, flame, ember, crystal   emissive, see `_glow_material()`
##   pulse, warn, tint     emissive, coloured from `options` ("pulse", "warn", "tint")

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const ROOT := "res://assets/props/"

static var _scenes: Dictionary = {}
static var _themed_meshes: Dictionary = {}

## Which of the six modelled styles each biome wears. The biome's own palette does the rest.
const BIOME_STYLES := {
	"forgotten_castle": "castle",
	"crystal_caverns": "crystal",
	"prism_depths": "crystal",
	"poison_swamp": "swamp",
	"venom_mire": "swamp",
	"frozen_fortress": "frozen",
	"glacial_hollow": "frozen",
	"iron_vault": "vault",
	"dark_cathedral": "cathedral",
	"umbral_chapel": "cathedral",
}


## Builds `id` under `parent`. `options` may carry Colors for "glow", "warn" and "tint".
static func attach(parent: Node3D, id: String, biome_id: String, options: Dictionary = {}) -> Node3D:
	var theme := PixelStyle.theme_from_biome(biome_id)
	return attach_themed(parent, id, theme, options)


static func attach_themed(
	parent: Node3D, id: String, theme: PixelStyle.PaletteTheme, options: Dictionary = {}
) -> Node3D:
	var scene := _scene(id)
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	var children: Array[Node] = model.get_children()
	for child in children:
		model.remove_child(child)
		_clear_owner(child)
		parent.add_child(child)
		_skin(child, theme, options)
	model.free()
	return parent


## The bare geometry of a prop's first mesh, for callers that supply their own material (a pulsing
## ground marker, say). Shared: never write to it.
static func bare_mesh(id: String) -> Mesh:
	var key := "mesh|" + id
	if _themed_meshes.has(key):
		return _themed_meshes[key]
	var scene := _scene(id)
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	var found: Mesh = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		found = (node as MeshInstance3D).mesh
		break
	model.free()
	_themed_meshes[key] = found
	return found


## The bare geometry of a prop scaled to `scale_by`, with no material, for particles and other callers
## that cannot scale a mesh per instance. Cached per size.
static func scaled_mesh(id: String, scale_by: Vector3) -> Mesh:
	var key := "scaled|%s|%s" % [id, scale_by]
	if _themed_meshes.has(key):
		return _themed_meshes[key]
	var source := bare_mesh(id)
	if source == null:
		return null
	var built := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			vertices[i] *= scale_by
		for i in normals.size():
			normals[i] = (normals[i] / scale_by).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_themed_meshes[key] = built
	return built


## One prop as a standalone node named after the file, for callers that place it themselves.
static func instance(id: String, biome_id: String, options: Dictionary = {}) -> Node3D:
	var holder := Node3D.new()
	holder.name = id.capitalize().replace(" ", "")
	if attach(holder, id, biome_id, options) == null:
		holder.free()
		return null
	return holder


## The prop id of a biome-kit piece ("pillar", "statue", "rubble_a" ...) in `biome_id`'s style.
static func biome_prop_id(biome_id: String, kind: String) -> String:
	return "biome/%s_%s" % [BIOME_STYLES.get(biome_id, "castle"), kind]


## Many copies of one prop as instanced meshes: one draw per surface however many copies there are.
## Copies are visual only. `transforms` place the prop's origin.
static func scatter(
	parent: Node3D, id: String, biome_id: String, transforms: Array[Transform3D], node_name: String
) -> Node3D:
	return scatter_themed(parent, id, PixelStyle.theme_from_biome(biome_id), transforms, node_name)


static func scatter_themed(
	parent: Node3D,
	id: String,
	theme: PixelStyle.PaletteTheme,
	transforms: Array[Transform3D],
	node_name: String,
	options: Dictionary = {}
) -> Node3D:
	var scene := _scene(id)
	if scene == null or transforms.is_empty():
		return null
	var holder := Node3D.new()
	holder.name = node_name
	parent.add_child(holder)
	var model := scene.instantiate() as Node3D
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		if source.mesh == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _themed_mesh(id, source, theme, options)
		multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i, transforms[i] * source.transform)
		var multi_instance := MultiMeshInstance3D.new()
		multi_instance.name = source.name
		multi_instance.multimesh = multi
		holder.add_child(multi_instance)
	model.free()
	return holder


static func _themed_mesh(
	id: String, source: MeshInstance3D, theme: PixelStyle.PaletteTheme, options: Dictionary
) -> Mesh:
	var cacheable := not options.has("materials")
	var key := "%s|%s|%d" % [id, source.name, theme]
	if cacheable and _themed_meshes.has(key):
		return _themed_meshes[key]
	var mesh := source.mesh.duplicate() as Mesh
	for surface in mesh.get_surface_count():
		var role := source.mesh.surface_get_material(surface)
		mesh.surface_set_material(surface, _material(role.resource_name if role else "", theme, options))
	if cacheable:
		_themed_meshes[key] = mesh
	return mesh


## Nodes instanced from a glTF scene remember that scene as their owner; dropping that keeps them
## from being saved with, or complaining about, the node they are re-parented under.
static func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


static func _scene(id: String) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	var path := ROOT + id + ".glb"
	var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if scene == null:
		push_error("PropLibrary: no prop '%s' at %s" % [id, path])
	_scenes[id] = scene
	return scene


static func _skin(node: Node, theme: PixelStyle.PaletteTheme, options: Dictionary) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface)
			var role := source.resource_name if source != null else ""
			mesh_instance.set_surface_override_material(surface, _material(role, theme, options))
	for child in node.get_children():
		_skin(child, theme, options)


## Materials the hub defines beyond the biome set, used by name when a caller supplies none.
const HUB_ROLES: Array[String] = [
	"wood", "roof", "canvas", "canvas_dark", "cloth", "paper", "floor_alt", "umbral", "training",
	"dragon", "cathedral", "forge",
]

static var _hub_materials: Dictionary = {}


static func _material(role: String, theme: PixelStyle.PaletteTheme, options: Dictionary) -> Material:
	var overrides: Dictionary = options.get("materials", {})
	if overrides.has(role):
		return overrides[role]
	if HUB_ROLES.has(role):
		if _hub_materials.is_empty():
			_hub_materials = PixelStyle.make_hub_materials()
		return _hub_materials[role]
	match role:
		"cresset_ember":
			return PixelStyle.make_custom_emissive(Color(0.95, 0.36, 0.12), 2.0)
		"cresset_core":
			return PixelStyle.make_custom_emissive(Color(1.0, 0.62, 0.20), 2.4)
		"cresset_tip":
			return PixelStyle.make_custom_emissive(Color(1.0, 0.86, 0.46), 2.8)
		"portal_sheet":
			return PixelStyle.make_custom_emissive(Color(0.62, 0.42, 0.95), 2.2)
		"robe":
			return PixelStyle.make_metal_material(Color(0.19, 0.16, 0.28), 0.2)
		"staff":
			return PixelStyle.make_metal_material(Color(0.32, 0.27, 0.2), 0.3)
		"staff_light":
			return PixelStyle.make_custom_emissive(Color(0.85, 0.72, 1.0), 2.8)
		"pyre_stone":
			return PixelStyle.make_material(Color(0.34, 0.33, 0.36))
		"pyre_flame":
			return PixelStyle.make_custom_emissive(Color(1.0, 0.66, 0.24), 2.2)
		"eye":
			return PixelStyle.make_material(Color(0.06, 0.06, 0.07))
		"bird":
			return PixelStyle.make_silhouette_material(Color(0.09, 0.08, 0.12))
		"hub_iron":
			return PixelStyle.make_metal_material(Color(0.23, 0.23, 0.27), 0.34)
		"leaf_dark":
			return PixelStyle.make_material(Color(0.24, 0.33, 0.22))
		"leaf_light":
			return PixelStyle.make_material(Color(0.33, 0.44, 0.26))
		"bloom":
			return PixelStyle.make_material(Color(0.76, 0.33, 0.34))
		"bark":
			return PixelStyle.make_material(Color(0.36, 0.26, 0.18))
		"bone":
			return PixelStyle.make_material(Color(0.74, 0.71, 0.62))
		"candle":
			return PixelStyle.make_custom_emissive(Color(1.0, 0.78, 0.42), 1.3)
		"glass":
			return PixelStyle.make_custom_emissive(Color(1.0, 0.72, 0.34), 1.25)
		"water":
			return PixelStyle.make_water_material(Color(0.36, 0.58, 0.82))
		"wall":
			return PixelStyle.make_wall_material(theme)
		"floor":
			return PixelStyle.make_floor_material(theme)
		"accent":
			return PixelStyle.make_accent_material(theme)
		"timber":
			return PixelStyle.make_prop_material(theme, false)
		"trim":
			return PixelStyle.make_prop_material(theme, true)
		"iron":
			return PixelStyle.make_metal_material(Color(0.22, 0.21, 0.25), 0.34)
		"darkiron":
			return PixelStyle.make_metal_material(Color(0.19, 0.18, 0.20), 0.30)
		"steel":
			return PixelStyle.make_metal_material(Color(0.58, 0.62, 0.64), 0.50)
		"crystal":
			return PixelStyle.make_emissive_material(theme, 1.1)
		"glow":
			var glow: Color = options.get("glow", PixelStyle.get_palette_color(theme, PixelStyle.PaletteSlot.EMISSIVE))
			return PixelStyle.make_material(glow, glow)
		"orb":
			var orb: Color = PixelStyle.get_palette_color(theme, PixelStyle.PaletteSlot.ACCENT)
			return PixelStyle.make_material(orb, orb)
		"flame":
			return PixelStyle.make_material(Color(1.0, 0.55, 0.15), Color(1.0, 0.55, 0.15))
		"ember":
			return PixelStyle.make_material(Color(1.0, 0.35, 0.05, 0.45), Color(1.0, 0.35, 0.05, 0.45))
		"pulse":
			var pulse: Color = options.get("pulse", Color(0.8, 0.8, 0.8))
			return PixelStyle.make_glow_material(pulse.lightened(0.18), pulse.darkened(0.22), 1.85, 1.35)
		"warn":
			var warn: Color = options.get("warn", Color(0.75, 0.12, 0.1))
			return PixelStyle.make_glow_material(warn, warn.darkened(0.5), 0.7)
		"tint":
			var tint: Color = options.get("tint", Color(0.85, 0.75, 0.4))
			return PixelStyle.make_glow_material(tint, tint * 0.5, 1.3)
		"sigil":
			return PixelStyle.make_glow_material(Color(0.95, 0.8, 0.3), Color(0.6, 0.48, 0.15), 1.4)
		"torchfire":
			return PixelStyle.make_emissive_material(theme, 2.2)
	push_warning("PropLibrary: unknown surface role '%s'" % role)
	return PixelStyle.make_wall_material(theme)
