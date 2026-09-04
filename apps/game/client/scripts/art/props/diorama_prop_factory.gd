extends RefCounted
class_name DioramaPropFactory


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


static func _make_mesh_instance(
	mesh: Mesh, material: Material, mesh_name: String = "Mesh"
) -> MeshInstance3D:
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

	var plank_side := _make_mesh_instance(
		_make_box(Vector3(0.22, 0.08, 0.95)), trim_mat, "PlankSide"
	)
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
	light.light_color = PixelDioramaStyle.get_palette_color(
		theme, PixelDioramaStyle.PaletteSlot.EMISSIVE
	)
	light.light_energy = 0.55
	light.omni_range = 4.5
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.35, 0.25)
	root.add_child(light)
	LightEmbers.attach(root, Vector3(0.0, 1.42, 0.25), light.light_color)

	return root


## RM-10: replaces `DungeonBuilder._build_landmarks()`'s untextured coloured box with a built
## prop per landmark kind, batched with `PixelBoxBatch` so each one still costs about one draw call
## despite being several boxes. `height`/`half_width` come from the landmark hint's own scale, so
## the generator keeps deciding size and position; only what gets built there changes.
static func build_boss_spire(
	biome_id: String, height: float, half_width: float
) -> Node3D:
	var theme := PixelDioramaStyle.theme_from_biome(biome_id)
	var root := Node3D.new()
	root.name = "boss_spire"
	var shaft_mat := PixelDioramaStyle.make_wall_material(theme)
	var batch := PixelBoxBatch.new()
	var segments := 5
	var base_w := maxf(1.0, half_width * 2.0)
	for i in segments:
		var t := float(i) / float(segments)
		var seg_w := lerpf(base_w, base_w * 0.25, t)
		var seg_h := height / float(segments)
		batch.add(
			Vector3(seg_w, seg_h, seg_w), Vector3(0.0, seg_h * (float(i) + 0.5), 0.0), shaft_mat
		)
	batch.commit(
		root, "SpireShaft", AABB(Vector3(-base_w, 0.0, -base_w), Vector3(base_w * 2.0, height, base_w * 2.0))
	)
	var beacon_mat := PixelDioramaStyle.make_emissive_material(theme, 2.4)
	var beacon := _make_mesh_instance(_make_box(Vector3.ONE * base_w * 0.3), beacon_mat, "Beacon")
	beacon.position = Vector3(0.0, height + base_w * 0.15, 0.0)
	root.add_child(beacon)
	var light := OmniLight3D.new()
	light.name = "BeaconLight"
	light.light_color = PixelDioramaStyle.get_palette_color(theme, PixelDioramaStyle.PaletteSlot.EMISSIVE)
	light.light_energy = 1.4
	light.omni_range = 22.0
	light.shadow_enabled = false
	light.position = beacon.position
	root.add_child(light)
	return root


static func build_boss_silhouette(
	biome_id: String, height: float, half_width: float
) -> Node3D:
	var theme := PixelDioramaStyle.theme_from_biome(biome_id)
	var root := Node3D.new()
	root.name = "boss_silhouette"
	var chain_mat := PixelDioramaStyle.make_prop_material(theme, true)
	var cloth_mat := PixelDioramaStyle.make_accent_material(theme)
	var batch := PixelBoxBatch.new()
	var link_size := maxf(0.2, half_width * 0.2)
	var links := maxi(3, int(height / (link_size * 3.0)))
	for i in links:
		batch.add(
			Vector3(link_size, link_size * 1.6, link_size),
			Vector3(0.0, link_size * 1.6 * (float(i) + 0.5), 0.0),
			chain_mat
		)
	var cloth_h := height * 0.4
	batch.add(
		Vector3(half_width * 0.3, cloth_h, half_width),
		Vector3(0.0, height - cloth_h * 0.5, 0.0),
		cloth_mat
	)
	batch.commit(
		root,
		"SilhouetteBatch",
		AABB(
			Vector3(-half_width, 0.0, -half_width), Vector3(half_width * 2.0, height, half_width * 2.0)
		)
	)
	return root


static func build_orientation_spire(
	biome_id: String, height: float, half_width: float
) -> Node3D:
	var theme := PixelDioramaStyle.theme_from_biome(biome_id)
	var root := Node3D.new()
	root.name = "orientation_spire"
	var shaft_mat := PixelDioramaStyle.make_wall_material(theme)
	var cap_mat := PixelDioramaStyle.make_prop_material(theme, true)
	var batch := PixelBoxBatch.new()
	var w := maxf(0.4, half_width)
	batch.add(Vector3(w, height, w), Vector3(0.0, height * 0.5, 0.0), shaft_mat)
	batch.add(Vector3(w * 1.3, w * 0.25, w * 1.3), Vector3(0.0, height, 0.0), cap_mat)
	batch.commit(
		root, "OrientationBatch", AABB(Vector3(-w, 0.0, -w), Vector3(w * 2.0, height + w, w * 2.0))
	)
	var lantern_mat := PixelDioramaStyle.make_emissive_material(theme, 1.6)
	var lantern := _make_mesh_instance(_make_box(Vector3.ONE * w * 0.5), lantern_mat, "Lantern")
	lantern.position = Vector3(0.0, height + w, 0.0)
	root.add_child(lantern)
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.light_color = PixelDioramaStyle.get_palette_color(theme, PixelDioramaStyle.PaletteSlot.EMISSIVE)
	light.light_energy = 0.6
	light.omni_range = 8.0
	light.shadow_enabled = false
	light.position = lantern.position
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
