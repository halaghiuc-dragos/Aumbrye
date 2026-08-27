extends RefCounted
class_name StatusIconAtlas


const MANIFEST_PATH := "content/ui/status_icon_atlas.json"
const CB_TEXTURE_PATH := "res://assets/ui/status_icons_cb.png"

const AccessibilitySettingsScript := preload("res://scripts/accessibility/accessibility_settings.gd")


static func get_icon(status_id: String) -> AtlasTexture:
	var atlas := _atlas()
	if atlas == null:
		return AtlasTexture.new()
	if not atlas.has_cell(status_id):
		push_warning("status icon missing for id '%s'" % status_id)
		return atlas.cell("unknown")
	return atlas.cell(status_id)


static func get_polarity_frame(polarity: String) -> AtlasTexture:
	return get_icon("frame_buff" if polarity == "buff" else "frame_debuff")


static func icon_size() -> int:
	var atlas := _atlas()
	return atlas.cell_size() if atlas != null else 16


## The colourblind sheet is part of the shared atlas key, so switching mode resolves to a different
## cached atlas rather than needing an explicit invalidation.
static func _colorblind_texture_path() -> String:
	var mode := AccessibilitySettingsScript.colorblind_mode
	if mode in ["protanopia", "deuteranopia", "tritanopia"] and ResourceLoader.exists(CB_TEXTURE_PATH):
		return CB_TEXTURE_PATH
	return ""


static func _atlas() -> UISymbolAtlas:
	return UISymbolAtlas.shared(MANIFEST_PATH, _colorblind_texture_path())


static func reload() -> void:
	UISymbolAtlas.drop_shared(MANIFEST_PATH)


static func invalidate() -> void:
	UISymbolAtlas.invalidate_shared(MANIFEST_PATH)
