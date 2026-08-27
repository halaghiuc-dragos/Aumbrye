class_name ItemListPresenter
extends RefCounted


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ItemIconAtlasScript := preload("res://scripts/ui/item_icon_atlas.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")

const ICON_SIZE := 24
const ROW_MIN_HEIGHT := 28


static func configure(list: ItemList) -> void:
	if list == null:
		return
	list.fixed_icon_size = Vector2i(ICON_SIZE, ICON_SIZE)
	list.icon_mode = ItemList.ICON_MODE_LEFT
	list.same_column_width = false
	list.auto_height = false
	list.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	list.add_theme_constant_override("v_separation", 4)
	list.add_theme_constant_override("h_separation", 8)


static func add_row(
	list: ItemList, item_id: String, definition: Dictionary, text: String, rarity: String = ""
) -> int:
	if list == null:
		return -1
	var icon := ItemIconAtlasScript.get_icon(item_id, str(definition.get("iconPath", "")))
	var index := list.add_item(text, icon)
	var resolved := rarity
	if resolved.is_empty():
		resolved = str(definition.get("rarity", "common"))
	list.set_item_custom_fg_color(index, RarityRegistryScript.display_color(resolved))
	list.set_item_tooltip(index, _tooltip(definition, resolved))
	return index


static func add_plain_row(list: ItemList, text: String, selectable: bool = true) -> int:
	if list == null:
		return -1
	var index := list.add_item(text, null, selectable)
	list.set_item_custom_fg_color(index, GameUISkinScript.HINT_COLOR)
	return index


static func _tooltip(definition: Dictionary, rarity: String) -> String:
	var lines: Array[String] = []
	var name := str(definition.get("name", ""))
	if not name.is_empty():
		lines.append(name)
	lines.append(RarityRegistryScript.display_name(rarity))
	var description := str(definition.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	return "\n".join(lines)
