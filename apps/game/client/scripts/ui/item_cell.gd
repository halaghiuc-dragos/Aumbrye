class_name ItemCell
extends RefCounted

## UX-03: the inventory grid's cell renderer (icon + rarity frame + stack + upgrade badge +
## durability bar), factored out so the shop, the stash and the forge can build the same cell
## instead of inventing their own. Extracted verbatim from inventory_ui.gd's
## _make_item_cell()/_set_cell_content() -- no behavior changed, only the home address.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ItemIconAtlasScript := preload("res://scripts/ui/item_icon_atlas.gd")
const BlacksmithServiceScript := preload("res://scripts/hub/blacksmith_service.gd")


static func make_cell(cell_size: int, rarity: String, upgrade_level: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(cell_size, cell_size)
	cell.focus_mode = Control.FOCUS_ALL
	var style := GameUISkinScript.make_item_cell_style(rarity, false)
	cell.add_theme_stylebox_override("panel", style)
	var icon := GameUISkinScript.make_symbol_rect(null, ItemIconAtlasScript.icon_size())
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2
	icon.offset_top = 2
	icon.offset_right = -2
	icon.offset_bottom = -2
	cell.add_child(icon)
	var stack_label := Label.new()
	stack_label.name = "StackLabel"
	stack_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stack_label.offset_left = -cell_size + 2
	stack_label.offset_bottom = -2
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack_label.add_theme_font_size_override("font_size", GameUISkinScript.FONT_SIZE_MICRO)
	stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack_label.visible = false
	cell.add_child(stack_label)
	var upgrade_label := Label.new()
	upgrade_label.name = "UpgradeLabel"
	upgrade_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	upgrade_label.offset_left = -cell_size + 2
	upgrade_label.offset_top = 0
	upgrade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	upgrade_label.add_theme_font_size_override("font_size", GameUISkinScript.FONT_SIZE_MICRO)
	upgrade_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	upgrade_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_label.text = ("+%d" % upgrade_level) if upgrade_level > 0 else ""
	cell.add_child(upgrade_label)
	var durability := TextureProgressBar.new()
	durability.name = "DurabilityBar"
	durability.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	durability.offset_top = -2
	durability.custom_minimum_size = Vector2(0, 2)
	durability.mouse_filter = Control.MOUSE_FILTER_IGNORE
	durability.visible = false
	cell.add_child(durability)
	return cell


static func set_cell_content(
	cell: PanelContainer,
	rarity: String,
	upgrade_level: int,
	slot: Dictionary = {},
	empty_slot_name: String = ""
) -> void:
	var filled := not slot.is_empty()
	var display_rarity := rarity if filled else "common"
	var style := GameUISkinScript.make_item_cell_style(display_rarity, filled)
	cell.add_theme_stylebox_override("panel", style)
	var icon: TextureRect = cell.get_node("Icon")
	var upgrade_label: Label = cell.get_node("UpgradeLabel")
	var stack_label: Label = cell.get_node("StackLabel")
	var durability_bar: TextureProgressBar = cell.get_node("DurabilityBar")
	if filled:
		var item_id: String = str(slot.get("itemId", ""))
		var def := ItemCatalog.get_definition(item_id)
		icon.texture = ItemIconAtlasScript.get_icon(item_id, str(def.get("iconPath", "")))
		var qty: int = int(slot.get("quantity", 1))
		stack_label.text = str(qty) if qty > 1 else ""
		stack_label.visible = qty > 1
		var max_dur := BlacksmithServiceScript.get_max_durability(item_id)
		var current_dur := BlacksmithServiceScript.get_slot_durability(slot)
		if max_dur > 0 and def.get("itemType", "") in BlacksmithServiceScript.UPGRADEABLE_TYPES:
			durability_bar.max_value = max_dur
			durability_bar.value = current_dur
			durability_bar.visible = current_dur < max_dur
		else:
			durability_bar.visible = false
	elif empty_slot_name != "":
		icon.texture = ItemIconAtlasScript.get_slot_icon(empty_slot_name)
		stack_label.visible = false
		durability_bar.visible = false
	else:
		icon.texture = null
		stack_label.visible = false
		durability_bar.visible = false
	upgrade_label.text = ("+%d" % upgrade_level) if upgrade_level > 0 else ""
