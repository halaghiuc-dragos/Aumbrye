extends RefCounted
class_name UISymbolAtlas


var _manifest_path: String = ""
var _manifest: Dictionary = {}
var _source: Texture2D
var _cell_cache: Dictionary = {}
var _cell_size: int = 16
var _columns: int = 1
var _rows: int = 1
var _unknown: Vector2i = Vector2i.ZERO
var _has_unknown: bool = false


static func load_manifest(atlas_manifest_path: String, texture_override: String = "") -> UISymbolAtlas:
	var atlas := UISymbolAtlas.new()
	atlas._load(atlas_manifest_path, texture_override)
	return atlas


func _load(atlas_manifest_path: String, texture_override: String = "") -> void:
	_manifest_path = atlas_manifest_path
	_manifest = ContentLoader.load_json(atlas_manifest_path)
	_cell_size = int(_manifest.get("cellSize", 16))
	_columns = int(_manifest.get("columns", 1))
	_rows = int(_manifest.get("rows", 1))
	var texture_path: String = texture_override if texture_override != "" else str(_manifest.get("texture", ""))
	if texture_path.is_empty():
		push_warning("UISymbolAtlas: manifest '%s' has no texture path" % atlas_manifest_path)
		return
	if ResourceLoader.exists(texture_path):
		_source = load(texture_path) as Texture2D
	else:
		push_warning("UISymbolAtlas: missing texture %s" % texture_path)
		return
	var unknown: Variant = _manifest.get("unknown", {})
	_has_unknown = unknown is Dictionary and (unknown as Dictionary).has("col")
	if _has_unknown:
		_unknown = Vector2i(int(unknown.get("col", 0)), int(unknown.get("row", 0)))


func has_cell(key: String) -> bool:
	var cells: Variant = _manifest.get("cells", {})
	return cells is Dictionary and (cells as Dictionary).has(key)


func keys() -> PackedStringArray:
	var cells: Variant = _manifest.get("cells", {})
	if not cells is Dictionary:
		return PackedStringArray()
	return PackedStringArray((cells as Dictionary).keys())


func cell_size() -> int:
	return _cell_size


func columns() -> int:
	return _columns


func rows() -> int:
	return _rows


func cell(key: String) -> AtlasTexture:
	if _cell_cache.has(key):
		return _cell_cache[key]
	var region := _region_for_key(key)
	var tex := AtlasTexture.new()
	tex.atlas = _source
	tex.region = region
	_cell_cache[key] = tex
	return tex


func invalidate() -> void:
	_cell_cache.clear()


## A sheet that declares no "unknown" cell has no fallback marker by design: the generator refuses
## to build unless every key is drawn, so a miss here is a bug in the data rather than a hole the
## art is expected to paper over. Drawing nothing and saying so is more honest than drawing a
## placeholder a player would find in their bag.
func _region_for_key(key: String) -> Rect2:
	var cells: Variant = _manifest.get("cells", {})
	if cells is Dictionary and (cells as Dictionary).has(key):
		var entry: Dictionary = (cells as Dictionary)[key]
		return _rect_from_cell(int(entry.get("col", 0)), int(entry.get("row", 0)))
	push_error("ui symbol atlas '%s' has no cell for key '%s'" % [_manifest_path, key])
	if not _has_unknown:
		return Rect2()
	return _rect_from_cell(_unknown.x, _unknown.y)


func _rect_from_cell(col: int, row: int) -> Rect2:
	var size := float(_cell_size)
	return Rect2(float(col) * size, float(row) * size, size, size)


## Manifest-keyed cache behind the four `*_icon_atlas` facades. Each of them used to carry its own
## copy of the same lazy-load pair (`_atlas` + `_loaded` + `_ensure_loaded` + `reload`), which is
## three pieces of state per facade to express "load this manifest once".
##
## The texture override is part of the key, so the status atlas's colourblind variant is a separate
## entry rather than something a caller has to remember to invalidate.
static var _shared: Dictionary = {}


static func shared(atlas_manifest_path: String, texture_override: String = "") -> UISymbolAtlas:
	var key := "%s|%s" % [atlas_manifest_path, texture_override]
	var existing: UISymbolAtlas = _shared.get(key)
	if existing != null:
		return existing
	var made := load_manifest(atlas_manifest_path, texture_override)
	_shared[key] = made
	return made


static func drop_shared(atlas_manifest_path: String) -> void:
	for key in _shared.keys():
		if str(key).begins_with(atlas_manifest_path + "|"):
			_shared.erase(key)


static func invalidate_shared(atlas_manifest_path: String) -> void:
	for key in _shared.keys():
		if str(key).begins_with(atlas_manifest_path + "|"):
			(_shared[key] as UISymbolAtlas).invalidate()
