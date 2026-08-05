extends RefCounted
class_name DioramaPropFactory

## Spawns chunky low-poly diorama props as MeshInstance3D hierarchies.

enum PropKind { CRATE, PILLAR, TORCH, BANNER }


static func create_prop(kind: PropKind, biome_id: String = BiomeRegistry.BIOME_CASTLE) -> Node3D:
	var theme := PixelDioramaStyle.theme_from_biome(biome_id)
	match kind:
		PropKind.CRATE:
			return _make_crate(theme)
		PropKind.PILLAR:
			return _make_pillar(theme)
		PropKind.TORCH:
			return _make_torch(theme)
		PropKind.BANNER:
			return _make_banner(theme)
		_:
			return Node3D.new()


static func create_prop_named(kind_name: String, biome_id: String = BiomeRegistry.BIOME_CASTLE) -> Node3D:
	match kind_name.to_lower():
		"crate":
			return create_prop(PropKind.CRATE, biome_id)
		"pillar":
			return create_prop(PropKind.PILLAR, biome_id)
		"torch":
			return create_prop(PropKind.TORCH, biome_id)
		"banner":
			return create_prop(PropKind.BANNER, biome_id)
		_:
			push_warning("DioramaPropFactory: unknown prop '%s'" % kind_name)
			return Node3D.new()


static func _make_mesh_instance(mesh: Mesh, material: Material, mesh_name: String = "Mesh") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	return instance


static func _make_box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


static func _make_crate(theme: PixelDioramaStyle.PaletteTheme) -> Node3D:
	var root := Node3D.new()
	root.name = "Crate"

	var body_mat := PixelDioramaStyle.make_prop_material(theme, false)
	var trim_mat := PixelDioramaStyle.make_prop_material(theme, true)

	var body := _make_mesh_instance(_make_box(Vector3(0.9, 0.9, 0.9)), body_mat, "Body")
	body.position.y = 0.45
	root.add_child(body)

	var plank := _make_mesh_instance(_make_box(Vector3(0.95, 0.08, 0.22)), trim_mat, "PlankFront")
	plank.position = Vector3(0.0, 0.55, 0.46)
	root.add_child(plank)

	var plank_side := _make_mesh_instance(_make_box(Vector3(0.22, 0.08, 0.95)), trim_mat, "PlankSide")
	plank_side.position = Vector3(0.46, 0.55, 0.0)
	root.add_child(plank_side)

	return root


static func _make_pillar(theme: PixelDioramaStyle.PaletteTheme) -> Node3D:
	var root := Node3D.new()
	root.name = "Pillar"

	var shaft_mat := PixelDioramaStyle.make_wall_material(theme)
	var cap_mat := PixelDioramaStyle.make_prop_material(theme, true)

	var shaft := _make_mesh_instance(_make_box(Vector3(0.65, 2.4, 0.65)), shaft_mat, "Shaft")
	shaft.position.y = 1.2
	root.add_child(shaft)

	var cap := _make_mesh_instance(_make_box(Vector3(0.85, 0.2, 0.85)), cap_mat, "Cap")
	cap.position.y = 2.5
	root.add_child(cap)

	var base := _make_mesh_instance(_make_box(Vector3(0.95, 0.18, 0.95)), cap_mat, "Base")
	base.position.y = 0.09
	root.add_child(base)

	return root


static func _make_torch(theme: PixelDioramaStyle.PaletteTheme) -> Node3D:
	var root := Node3D.new()
	root.name = "Torch"

	var pole_mat := PixelDioramaStyle.make_prop_material(theme, true)
	var flame_mat := PixelDioramaStyle.make_emissive_material(theme, 2.2)

	var pole := _make_mesh_instance(_make_box(Vector3(0.12, 1.1, 0.12)), pole_mat, "Pole")
	pole.position = Vector3(0.0, 0.55, 0.18)
	root.add_child(pole)

	var bracket := _make_mesh_instance(_make_box(Vector3(0.28, 0.1, 0.18)), pole_mat, "Bracket")
	bracket.position = Vector3(0.0, 1.05, 0.22)
	root.add_child(bracket)

	var flame := _make_mesh_instance(_make_box(Vector3(0.22, 0.28, 0.22)), flame_mat, "Flame")
	flame.position = Vector3(0.0, 1.28, 0.22)
	root.add_child(flame)

	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = PixelDioramaStyle.get_palette_color(theme, PixelDioramaStyle.PaletteSlot.EMISSIVE)
	light.light_energy = 0.55
	light.omni_range = 4.5
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.35, 0.25)
	root.add_child(light)

	return root


static func _make_banner(theme: PixelDioramaStyle.PaletteTheme) -> Node3D:
	var root := Node3D.new()
	root.name = "Banner"

	var pole_mat := PixelDioramaStyle.make_prop_material(theme, true)
	var cloth_mat := PixelDioramaStyle.make_accent_material(theme)

	var pole := _make_mesh_instance(_make_box(Vector3(0.1, 2.6, 0.1)), pole_mat, "Pole")
	pole.position = Vector3(-0.35, 1.3, 0.0)
	root.add_child(pole)

	var cloth := _make_mesh_instance(_make_box(Vector3(0.08, 1.4, 0.7)), cloth_mat, "Cloth")
	cloth.position = Vector3(0.0, 1.85, 0.0)
	root.add_child(cloth)

	var top_bar := _make_mesh_instance(_make_box(Vector3(0.75, 0.08, 0.12)), pole_mat, "TopBar")
	top_bar.position = Vector3(0.0, 2.55, 0.0)
	root.add_child(top_bar)

	return root
