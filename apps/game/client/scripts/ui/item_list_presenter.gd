class_name ItemListPresenter
extends RefCounted

## Shared presentation for the ItemList-based item lists — merchant stock, sell list, storage,
## blacksmith, loadout.
##
## Every one of these screens listed items as bare text. In a game whose whole loop is finding and
## comparing gear, that throws away the two signals a player reads first: what kind of thing it is,
## and how rare it is. Routing them all through here means an item looks the same wherever it
## appears, and a screen that adds a new list gets that for free.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ItemIconAtlasScript := preload("res://scripts/ui/item_icon_atlas.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")

const ICON_SIZE := 24
const ROW_MIN_HEIGHT := 28


## Call once per list, before adding rows.
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


## Adds one item row with its icon and rarity-tinted name. Returns the row index.
##
## `definition` is the ItemCatalog entry; `text` is the full row label the screen wants to show
## (name plus price, quantity, or whatever that screen is about), since only the caller knows what
## the row is for.
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


## Row for something that is not a catalog item — an empty slot, a locked entry, a heading.
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


## Header above a list, so paired lists are never ambiguous about which side is which.
static func make_list_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	GameUISkinScript.style_section_title(label)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label
