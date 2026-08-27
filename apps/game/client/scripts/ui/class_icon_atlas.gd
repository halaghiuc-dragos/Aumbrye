class_name ClassIconAtlas
extends RefCounted


const MANIFEST_PATH := "content/ui/class_icon_atlas.json"


static func get_icon(class_id: String, icon_path: String = "") -> AtlasTexture:
	var atlas := _atlas()
	if atlas == null:
		return AtlasTexture.new()
	if icon_path.begins_with("class_icons:"):
		var key := icon_path.substr("class_icons:".length())
		if atlas.has_cell(key):
			return atlas.cell(key)
	return atlas.cell(class_id) if atlas.has_cell(class_id) else atlas.cell("unknown")


static func icon_size() -> int:
	var atlas := _atlas()
	return atlas.cell_size() if atlas != null else 64


static func _atlas() -> UISymbolAtlas:
	return UISymbolAtlas.shared(MANIFEST_PATH)


static func reload() -> void:
	UISymbolAtlas.drop_shared(MANIFEST_PATH)


static func invalidate() -> void:
	UISymbolAtlas.invalidate_shared(MANIFEST_PATH)
