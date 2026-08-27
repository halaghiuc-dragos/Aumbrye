extends RefCounted
class_name InputGlyphAtlas


const MANIFEST_PATH := "content/ui/input_glyph_atlas.json"


static func get_glyph(cell_key: String) -> AtlasTexture:
	var sheet := _atlas()
	return AtlasTexture.new() if sheet == null else sheet.cell(cell_key)


static func atlas() -> UISymbolAtlas:
	return _atlas()


static func _atlas() -> UISymbolAtlas:
	return UISymbolAtlas.shared(MANIFEST_PATH)


static func reload() -> void:
	UISymbolAtlas.drop_shared(MANIFEST_PATH)


static func invalidate() -> void:
	UISymbolAtlas.invalidate_shared(MANIFEST_PATH)
