class_name AspectCatalog
extends RefCounted

## Player-facing warden aspects from content/appearance/aspects.json.

const PixelDioramaStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

const ASPECTS_PATH := "content/appearance/aspects.json"

static var _aspects: Array[Dictionary] = []


static func get_all_aspects() -> Array[Dictionary]:
	_ensure_loaded()
	return _aspects.duplicate()


static func get_aspect(index: int) -> Dictionary:
	_ensure_loaded()
	if index < 0 or index >= _aspects.size():
		return {}
	return _aspects[index]


static func theme_for_index(index: int) -> int:
	var aspect := get_aspect(index)
	return theme_from_palette_name(str(aspect.get("paletteTheme", "castle")))


static func theme_from_palette_name(palette_name: String) -> int:
	return PixelDioramaStyle._palette_theme_from_string(palette_name)


static func index_for_theme(theme: int) -> int:
	_ensure_loaded()
	for i in _aspects.size():
		if theme_for_index(i) == theme:
			return i
	return 0


static func clear_cache() -> void:
	_aspects.clear()


static func _ensure_loaded() -> void:
	if not _aspects.is_empty():
		return
	var data: Dictionary = ContentLoader.load_json(ASPECTS_PATH)
	var raw: Variant = data.get("aspects", [])
	_aspects.clear()
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				_aspects.append(entry)
