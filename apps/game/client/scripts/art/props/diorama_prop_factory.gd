extends RefCounted
class_name DioramaPropFactory

## Free-standing props assembled from Blender models (tools/blender/props_*.py) through PropLibrary.


enum PropKind { CRATE, PILLAR, TORCH, BANNER }


static func create_prop(kind: PropKind, biome_id: String = BiomeRegistry.BIOME_CASTLE) -> Node3D:
	var root := Node3D.new()
	match kind:
		PropKind.CRATE:
			root.name = "Crate"
			PropLibrary.attach(root, "crate", biome_id)
		PropKind.PILLAR:
			root.name = "Pillar"
			PropLibrary.attach(root, PropLibrary.biome_prop_id(biome_id, "pillar"), biome_id)
		PropKind.TORCH:
			root.name = "Torch"
			_build_torch(root, biome_id)
		PropKind.BANNER:
			root.name = "Banner"
			PropLibrary.attach(root, PropLibrary.biome_prop_id(biome_id, "banner"), biome_id)
	return root


static func _build_torch(root: Node3D, biome_id: String) -> void:
	var theme := PixelDioramaStyle.theme_from_biome(biome_id)
	var mount := Node3D.new()
	mount.name = "Sconce"
	mount.position = Vector3(0.0, 1.05, 0.22)
	root.add_child(mount)
	PropLibrary.attach(mount, PropLibrary.biome_prop_id(biome_id, "sconce"), biome_id)
	var pole := Node3D.new()
	pole.name = "Pole"
	root.add_child(pole)
	PropLibrary.attach(pole, "torch_pole", biome_id)
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = PixelDioramaStyle.get_palette_color(theme, PixelDioramaStyle.PaletteSlot.EMISSIVE)
	light.light_energy = 0.55
	light.omni_range = 4.5
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.35, 0.25)
	root.add_child(light)
	LightEmbers.attach(root, Vector3(0.0, 1.42, 0.25), light.light_color)


## Landmark props. `height` and `half_width` come from the generator's hint, so it still decides
## size and position; the shaft models are scaled to fit and the glowing caps stay in proportion.
static func build_boss_spire(biome_id: String, height: float, half_width: float) -> Node3D:
	var theme := PixelDioramaStyle.theme_from_biome(biome_id)
	var root := Node3D.new()
	root.name = "boss_spire"
	var base_w := maxf(1.0, half_width * 2.0)
	var shaft := Node3D.new()
	shaft.name = "SpireShaft"
	shaft.scale = Vector3(base_w * 0.5, height / 10.0, base_w * 0.5)
	root.add_child(shaft)
	PropLibrary.attach(shaft, "boss_spire_shaft", biome_id)
	var beacon := Node3D.new()
	beacon.name = "Beacon"
	beacon.position = Vector3(0.0, height + base_w * 0.15, 0.0)
	beacon.scale = Vector3.ONE * base_w * 0.3
	root.add_child(beacon)
	PropLibrary.attach(beacon, "spire_beacon", biome_id)
	var light := OmniLight3D.new()
	light.name = "BeaconLight"
	light.light_color = PixelDioramaStyle.get_palette_color(theme, PixelDioramaStyle.PaletteSlot.EMISSIVE)
	light.light_energy = 1.4
	light.omni_range = 22.0
	light.shadow_enabled = false
	light.position = beacon.position
	root.add_child(light)
	return root


static func build_boss_silhouette(biome_id: String, height: float, half_width: float) -> Node3D:
	var root := Node3D.new()
	root.name = "boss_silhouette"
	root.scale = Vector3(half_width, height / 10.0, half_width)
	PropLibrary.attach(root, "boss_silhouette", biome_id)
	return root


static func build_orientation_spire(biome_id: String, height: float, half_width: float) -> Node3D:
	var theme := PixelDioramaStyle.theme_from_biome(biome_id)
	var root := Node3D.new()
	root.name = "orientation_spire"
	var w := maxf(0.4, half_width)
	var shaft := Node3D.new()
	shaft.name = "OrientationShaft"
	shaft.scale = Vector3(w, height / 10.0, w)
	root.add_child(shaft)
	PropLibrary.attach(shaft, "orientation_spire_shaft", biome_id)
	var lantern := Node3D.new()
	lantern.name = "Lantern"
	lantern.position = Vector3(0.0, height + w, 0.0)
	lantern.scale = Vector3.ONE * w * 0.5
	root.add_child(lantern)
	PropLibrary.attach(lantern, "spire_lantern", biome_id)
	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.light_color = PixelDioramaStyle.get_palette_color(theme, PixelDioramaStyle.PaletteSlot.EMISSIVE)
	light.light_energy = 0.6
	light.omni_range = 8.0
	light.shadow_enabled = false
	light.position = lantern.position
	root.add_child(light)
	return root
