extends RefCounted
class_name AppearanceCatalog

## Player-facing warden aspects loaded from content.

const ASPECTS_PATH := "content/appearance/aspects.json"
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

static var _aspects: Array[Dictionary] = []


static func get_aspects() -> Array[Dictionary]:
	_ensure_loaded()
	return _aspects


static func aspect_count() -> int:
	return get_aspects().size()


static func aspect_at(index: int) -> Dictionary:
	var aspects := get_aspects()
	if aspects.is_empty():
		return {}
	var idx := clampi(index, 0, aspects.size() - 1)
	return aspects[idx]


static func theme_for_index(index: int) -> int:
	var aspect := aspect_at(index)
	var theme_name := str(aspect.get("paletteTheme", "castle"))
	return int(PixelStyle._palette_theme_from_string(theme_name))


static func label_for_index(index: int) -> String:
	var aspect := aspect_at(index)
	var key := str(aspect.get("nameKey", ""))
	return TranslationServer.translate(key) if key != "" else "?"


static func index_for_theme(theme: int) -> int:
	for i in get_aspects().size():
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
