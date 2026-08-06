extends RefCounted
class_name StatusIconAtlas

## Authored status icon atlas — shared GPU texture with per-status regions.

const MANIFEST_PATH := "content/ui/status_icon_atlas.json"
const CB_TEXTURE_PATH := "res://assets/ui/status_icons_cb.png"

const AccessibilitySettingsScript := preload("res://scripts/accessibility/accessibility_settings.gd")

static var _atlas: UISymbolAtlas
static var _loaded := false


static func get_icon(status_id: String) -> AtlasTexture:
	_ensure_loaded()
	if _atlas == null:
		return AtlasTexture.new()
	if not _atlas.has_cell(status_id):
		push_warning("status icon missing for id '%s'" % status_id)
		return _atlas.cell("unknown")
	return _atlas.cell(status_id)


static func get_polarity_frame(polarity: String) -> AtlasTexture:
	var frame_key := "frame_buff" if polarity == "buff" else "frame_debuff"
	return get_icon(frame_key)


static func has_icon(status_id: String) -> bool:
	_ensure_loaded()
	return _atlas != null and _atlas.has_cell(status_id)


static func icon_size() -> int:
	_ensure_loaded()
	return _atlas.cell_size() if _atlas != null else 16


static func reload() -> void:
	_loaded = false
	_atlas = null
	_ensure_loaded()


static func invalidate() -> void:
	if _atlas != null:
		_atlas.invalidate()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_atlas = UISymbolAtlas.load_manifest(MANIFEST_PATH, _colorblind_texture_path())
	_loaded = true


static func _colorblind_texture_path() -> String:
	var mode := AccessibilitySettingsScript.colorblind_mode
	if mode in ["protanopia", "deuteranopia", "tritanopia"] and ResourceLoader.exists(CB_TEXTURE_PATH):
		return CB_TEXTURE_PATH
	return ""
