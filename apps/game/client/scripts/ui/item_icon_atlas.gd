extends RefCounted
class_name ItemIconAtlas


const MANIFEST_PATH := "content/ui/item_icon_atlas.json"


static func get_icon(item_id: String, icon_path: String = "") -> AtlasTexture:
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var standalone := AtlasTexture.new()
		standalone.atlas = load(icon_path) as Texture2D
		if standalone.atlas:
			standalone.region = Rect2(
				0, 0, standalone.atlas.get_width(), standalone.atlas.get_height()
			)
			return standalone
	var atlas := _atlas()
	if atlas == null:
		return AtlasTexture.new()
	return atlas.cell(item_id) if atlas.has_cell(item_id) else atlas.cell("unknown")


static func get_slot_icon(slot_name: String) -> AtlasTexture:
	return get_icon("slot/%s" % slot_name)


static func icon_size() -> int:
	var atlas := _atlas()
	return atlas.cell_size() if atlas != null else 16


static func _atlas() -> UISymbolAtlas:
	return UISymbolAtlas.shared(MANIFEST_PATH)


static func reload() -> void:
	UISymbolAtlas.drop_shared(MANIFEST_PATH)


static func invalidate() -> void:
	UISymbolAtlas.invalidate_shared(MANIFEST_PATH)
