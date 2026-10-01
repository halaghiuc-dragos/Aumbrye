extends Node

const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")

var _failures := 0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("Art mesh cache audit: %s" % label)


func _ready() -> void:
	ModelLoader.clear_cache()
	var path := "res://assets/equipment/helm.glb"
	var iron: Array = [[0.3, 0.3, 0.3], [0.1, 0.1, 0.1], [0.5, 0.4, 0.2], [0.2, 0.15, 0.1]]
	var frost: Array = [[0.3, 0.4, 0.5], [0.1, 0.2, 0.3], [0.5, 0.6, 0.7], [0.2, 0.3, 0.4]]
	var first := ModelLoader.load_equipment_mesh(path, iron, false)
	var reused := ModelLoader.load_equipment_mesh(path, iron.duplicate(true), false)
	_check(first != null and first == reused, "identical model and family reuse the retained mesh")
	_check(ModelLoader.load_equipment_mesh(path, frost, false) != first, "a different material family is a separate cache entry")
	_check(ModelLoader.load_equipment_mesh(path, iron, true) != first, "the mirrored variant has an independent cache identity")
	var castle := ModelLoader.load_mesh("res://assets/characters/player_warden/armr.glb", PixelDioramaStyle.PaletteTheme.CASTLE)
	var crystal := ModelLoader.load_mesh("res://assets/characters/player_warden/armr.glb", PixelDioramaStyle.PaletteTheme.CRYSTAL)
	_check(castle != null and castle != crystal, "the biome palette is part of a character mesh's cache identity")
	_check(castle == ModelLoader.load_mesh("res://assets/characters/player_warden/armr.glb", PixelDioramaStyle.PaletteTheme.CASTLE), "the same model and palette reload from the cache")
	for variant_index in ModelLoader.CACHE_LIMIT + 12:
		var channel := float(variant_index % 255) / 255.0
		var tinted: Array = [[channel, 0.2, 0.2], [0.1, channel, 0.1], [0.3, 0.3, channel], [float(variant_index) / 1000.0, 0.5, 0.5]]
		ModelLoader.load_equipment_mesh("res://assets/equipment/helm.glb", tinted, false)
	var stats: Dictionary = ModelLoader.get_cache_stats()
	_check(int(stats.get("retained", 0)) <= int(stats.get("limit", 0)), "model cache reports a bounded retained set")
	for theme_index in 10:
		var theme: int = theme_index
		PixelStyleScript.make_floor_material(theme)
		PixelStyleScript.make_wall_material(theme)
		PixelStyleScript.make_prop_material(theme)
		PixelStyleScript.make_accent_material(theme)
		PixelStyleScript.make_emissive_material(theme)
	var art_stats: Dictionary = PixelStyleScript.get_art_cache_stats()
	var material_stats: Dictionary = art_stats.get("materials", {})
	_check(int(material_stats.get("surface", 0)) >= 20 and int(material_stats.get("accent", 0)) >= 10 and int(material_stats.get("emissive", 0)) >= 10, "material cache statistics include all exercised biome theme families")
	_check(int(stats.get("evictions", 0)) >= 1, "old cache variants are evicted when the limit is reached")
	_check(int(stats.get("hits", 0)) >= 2 and int(stats.get("misses", 0)) >= 4, "model cache reports actual hit and load activity")
	print("ART MESH CACHE STATS %s" % JSON.stringify(stats))
	print("ART FILE MESH CACHE STATS %s" % JSON.stringify(stats))
	print("ART STYLE CACHE STATS %s" % JSON.stringify(art_stats))
	print("ART MESH CACHE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
