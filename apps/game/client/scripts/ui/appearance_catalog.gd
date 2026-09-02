extends RefCounted
class_name AppearanceCatalog


const ASPECTS_PATH := "content/appearance/aspects.json"
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

static var _aspects: Array[Dictionary] = []
static var _titles: Array[Dictionary] = []


static func get_aspects() -> Array[Dictionary]:
	_ensure_loaded()
	return _aspects


static func get_titles() -> Array[Dictionary]:
	_ensure_loaded()
	return _titles


static func is_unlocked(entry: Dictionary) -> bool:
	var flag := str(entry.get("unlockFlag", ""))
	if flag == "":
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var svc := tree.root.get_node_or_null("CharacterService")
	if svc == null or not svc.has_method("has_flag"):
		return false
	return bool(svc.call("has_flag", flag))


static func unlocked_aspects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in get_aspects():
		if is_unlocked(entry):
			out.append(entry)
	return out


static func unlocked_aspect_count() -> int:
	return unlocked_aspects().size()


static func unlocked_aspect_label(index: int) -> String:
	var entries := unlocked_aspects()
	if entries.is_empty():
		return "?"
	return _entry_label(entries[clampi(index, 0, entries.size() - 1)])


static func unlocked_aspect_theme(index: int) -> int:
	var entries := unlocked_aspects()
	if entries.is_empty():
		return int(PixelStyle._palette_theme_from_string("castle"))
	var entry := entries[clampi(index, 0, entries.size() - 1)]
	return int(PixelStyle._palette_theme_from_string(str(entry.get("paletteTheme", "castle"))))


static func unlocked_aspect_index_for_theme(theme: int) -> int:
	var entries := unlocked_aspects()
	for i in entries.size():
		var name_str := str(entries[i].get("paletteTheme", "castle"))
		if int(PixelStyle._palette_theme_from_string(name_str)) == theme:
			return i
	return 0


static func is_title_id(title_id: String) -> bool:
	if title_id == "":
		return true
	var entries := get_titles()
	if entries.is_empty():
		return true
	for entry in entries:
		if str(entry.get("id", "")) == title_id:
			return true
	return false


static func title_label(title_id: String) -> String:
	for entry in get_titles():
		if str(entry.get("id", "")) == title_id:
			return _entry_label(entry)
	return ""


static func _entry_label(entry: Dictionary) -> String:
	var key := str(entry.get("nameKey", ""))
	if key != "":
		var translated := TranslationServer.translate(key)
		if translated != key:
			return translated
	var fallback := str(entry.get("name", ""))
	return fallback if fallback != "" else "?"


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


static func clear_cache() -> void:
	_aspects.clear()
	_titles.clear()


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
	var raw_titles: Variant = data.get("titles", [])
	_titles.clear()
	if raw_titles is Array:
		for entry in raw_titles:
			if entry is Dictionary:
				_titles.append(entry)
