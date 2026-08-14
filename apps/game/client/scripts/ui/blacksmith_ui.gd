extends Control

## Blacksmith upgrade/repair UI (HUB-4.2).

const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ForgeServiceScript := preload("res://scripts/items/forge_service.gd")
const ItemListPresenterScript := preload("res://scripts/ui/item_list_presenter.gd")

signal closed

@onready var _gold_label: Label = $Panel/Margin/VBox/GoldLabel
@onready var _item_list: ItemList = $Panel/Margin/VBox/ItemList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _upgrade_button: Button = $Panel/Margin/VBox/Buttons/UpgradeButton
@onready var _repair_button: Button = $Panel/Margin/VBox/Buttons/RepairButton
@onready var _close_button: Button = $Panel/Margin/VBox/Buttons/CloseButton

var _item_indices: Array[int] = []
var _forge_row: HBoxContainer
var _salvage_button: Button
var _reroll_button: Button
var _transmute_button: Button
var _infuse_button: Button
var _infuse_element := ""


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self, "Panel", "Backdrop")
	ItemListPresenterScript.configure(_item_list)
	_upgrade_button.text = tr("SMITH_UPGRADE")
	_repair_button.text = tr("SMITH_REPAIR")
	_close_button.text = tr("SMITH_CLOSE")
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_repair_button.pressed.connect(_on_repair_pressed)
	var respec_button := GameUISkinScript.make_button(
		tr("SMITH_RESPEC") % BlacksmithService.RESPEC_COST
	)
	respec_button.pressed.connect(_on_respec_pressed)
	$Panel/Margin/VBox/Buttons.add_child(respec_button)
	_close_button.pressed.connect(close)
	_item_list.item_selected.connect(_on_item_selected)
	var unlock_button := GameUISkinScript.make_button(tr("SMITH_UNLOCK_WEAPONS"))
	unlock_button.pressed.connect(_on_unlock_pressed)
	$Panel/Margin/VBox/Buttons.add_child(unlock_button)
	$Panel/Margin/VBox/Buttons.move_child(unlock_button, 0)
	# Close belongs at the end of the row, not in the middle of the smithing actions.
	$Panel/Margin/VBox/Buttons.move_child(_close_button, -1)
	_build_forge_row()
	CharacterService.gold_changed.connect(_on_gold_changed)
	InventoryService.inventory_changed.connect(_refresh)


## Forge work sits on its own row so the plain upgrade/repair actions stay the obvious default.
func _build_forge_row() -> void:
	var vbox := $Panel/Margin/VBox as VBoxContainer
	var heading := Label.new()
	GameUISkinScript.style_section_title(heading, tr("SMITH_FORGE_SECTION"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(heading)

	_forge_row = HBoxContainer.new()
	_forge_row.name = "ForgeButtons"
	_forge_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_forge_row)

	var elements := ForgeServiceScript.infusions()
	_infuse_element = str(elements[0]) if not elements.is_empty() else ""

	_salvage_button = GameUISkinScript.make_button(tr("SMITH_SALVAGE"))
	_salvage_button.pressed.connect(_on_salvage_pressed)
	_forge_row.add_child(_salvage_button)

	_reroll_button = GameUISkinScript.make_button(tr("SMITH_REROLL"))
	_reroll_button.pressed.connect(_on_reroll_pressed)
	_forge_row.add_child(_reroll_button)

	_transmute_button = GameUISkinScript.make_button(tr("SMITH_TRANSMUTE"))
	_transmute_button.pressed.connect(_on_transmute_pressed)
	_forge_row.add_child(_transmute_button)

	if _infuse_element != "":
		# The picker used to sit unlabelled between Transmute and Infuse, reading as a stray
		# dropdown that said "Fire" with nothing to say what it applied to.
		var infuse_label := Label.new()
		infuse_label.text = tr("SMITH_INFUSION_ELEMENT")
		GameUISkinScript.style_hint_label(infuse_label)
		infuse_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_forge_row.add_child(infuse_label)

		var infuse_picker := OptionButton.new()
		infuse_picker.name = "InfusionPicker"
		for element in elements:
			infuse_picker.add_item(str(element).capitalize())
		infuse_picker.item_selected.connect(
			func(index: int) -> void:
				_infuse_element = str(elements[index])
				_refresh_forge_buttons()
		)
		_forge_row.add_child(infuse_picker)

		_infuse_button = GameUISkinScript.make_button(tr("SMITH_INFUSE"))
		_infuse_button.pressed.connect(_on_infuse_pressed)
		_forge_row.add_child(_infuse_button)

	for child in _forge_row.get_children():
		var control := child as Control
		if control:
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if child is BaseButton:
			GameUISkinScript.wire_button_sfx(child as BaseButton)
	for child in ($Panel/Margin/VBox/Buttons as HBoxContainer).get_children():
		var button := child as Control
		if button:
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func is_open() -> bool:
	return visible


func open() -> void:
	_refresh()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_item_list.grab_focus()


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _refresh() -> void:
	_gold_label.text = tr("SMITH_COINS") % CharacterService.gold
	_item_list.clear()
	_item_indices.clear()
	var inv := InventoryService.inventory
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		var item_id: String = slot.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		if def.get("itemType", "") not in BlacksmithService.UPGRADEABLE_TYPES:
			continue
		var level := BlacksmithService.get_slot_upgrade_level(slot)
		var max_level := BlacksmithService.get_max_upgrade_level_for_slot(slot)
		var dur := BlacksmithService.get_slot_durability(slot)
		var max_dur := BlacksmithService.get_max_durability(item_id)
		var rarity := inv.get_slot_rarity(slot)
		# The rarity name used to be spelled out at the front of every row. The colour now carries
		# it, which leaves the row to say the things that differ per item: upgrade and durability.
		var index := ItemListPresenterScript.add_row(
			_item_list,
			item_id,
			def,
			tr("SMITH_ITEM_ROW") % [def.get("name", item_id), level, max_level, dur, max_dur],
			rarity
		)
		if dur <= 0:
			_item_list.set_item_custom_fg_color(index, GameUISkinScript.DANGER_COLOR)
		_item_indices.append(i)
	if _item_indices.is_empty():
		ItemListPresenterScript.add_plain_row(_item_list, tr("SMITH_NO_ITEMS"), false)
		_detail_label.text = ""
		_upgrade_button.disabled = true
		_repair_button.disabled = true
		_refresh_forge_buttons()
	elif _item_list.get_selected_items().is_empty():
		_item_list.select(0)
		_on_item_selected(0)


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _item_indices.size():
		return
	var inv_index: int = _item_indices[index]
	var slot: Dictionary = InventoryService.inventory.slots[inv_index]
	var item_id: String = slot.get("itemId", "")
	var level := BlacksmithService.get_slot_upgrade_level(slot)
	var max_level := BlacksmithService.get_max_upgrade_level_for_slot(slot)
	var upgrade_cost := BlacksmithService.get_upgrade_cost(item_id, level)
	var rarity := RarityRegistryScript.display_name(
		InventoryService.inventory.get_slot_rarity(slot)
	)
	_detail_label.text = (
		tr("SMITH_UPGRADE_DETAIL") % [rarity, upgrade_cost, level, max_level]
	)
	_upgrade_button.disabled = not BlacksmithService.can_upgrade(inv_index)
	_repair_button.disabled = not BlacksmithService.can_repair(inv_index)
	_refresh_forge_buttons()


func _on_upgrade_pressed() -> void:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return
	var result := BlacksmithService.upgrade_item(_item_indices[selected[0]])
	if not result.get("ok", false):
		_detail_label.text = str(result.get("error", tr("SMITH_UPGRADE_FAILED")))
	_refresh()


func _on_repair_pressed() -> void:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return
	var result := BlacksmithService.repair_item(_item_indices[selected[0]])
	if not result.get("ok", false):
		_detail_label.text = str(result.get("error", tr("SMITH_REPAIR_FAILED")))
	_refresh()


func _on_respec_pressed() -> void:
	var result := BlacksmithService.respec_talents()
	_detail_label.text = (
		tr("SMITH_RESPEC_DONE") if result.get("ok", false) else str(result.get("error", tr("SMITH_RESPEC_FAILED")))
	)
	_refresh()


func _on_unlock_pressed() -> void:
	var unlocks := BlacksmithService.get_available_unlocks()
	var next: Dictionary = {}
	for row in unlocks:
		if row.get("owned", false):
			continue
		next = row
		break
	if next.is_empty():
		_detail_label.text = tr("SMITH_NO_UNLOCKS")
		return
	var item_id := str(next.get("itemId", ""))
	var result := BlacksmithService.unlock_item(item_id)
	if result.get("ok", false):
		_detail_label.text = tr("SMITH_UNLOCKED") % ItemCatalog.get_definition(item_id).get("name", item_id)
	else:
		_detail_label.text = str(result.get("error", tr("SMITH_UNLOCK_FAILED")))
	_refresh()


## Index of the item currently selected in the list, or -1 when nothing is selected.
func _selected_inv_index() -> int:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return -1
	var row: int = selected[0]
	if row < 0 or row >= _item_indices.size():
		return -1
	return _item_indices[row]


func _refresh_forge_buttons() -> void:
	var inv_index := _selected_inv_index()
	var has_item := inv_index >= 0
	if _salvage_button:
		_salvage_button.disabled = not has_item
	if _reroll_button:
		_reroll_button.disabled = not has_item or not ForgeServiceScript.can_reroll(inv_index)
	if _transmute_button:
		_transmute_button.disabled = not has_item or not ForgeServiceScript.can_transmute(inv_index)
	if _infuse_button:
		_infuse_button.disabled = (
			not has_item
			or _infuse_element == ""
			or not ForgeServiceScript.can_infuse(inv_index, _infuse_element)
		)


func _report_forge(result: Dictionary, failure_text: String) -> void:
	if not result.get("ok", false):
		_detail_label.text = str(result.get("error", failure_text))
	_refresh()


func _on_salvage_pressed() -> void:
	var inv_index := _selected_inv_index()
	if inv_index < 0:
		return
	var slot: Dictionary = InventoryService.inventory.slots[inv_index]
	var preview := ForgeServiceScript.salvage_preview(slot)
	var result := ForgeServiceScript.salvage(inv_index)
	if result.get("ok", false):
		var parts: PackedStringArray = []
		for material_id in preview:
			parts.append("%s x%d" % [str(material_id), int(preview[material_id])])
		_detail_label.text = (
			tr("SMITH_SALVAGED_FOR") % ", ".join(parts) if parts.size() > 0 else tr("SMITH_SALVAGED")
		)
		_refresh()
		return
	_report_forge(result, tr("SMITH_SALVAGE_FAILED"))


func _on_reroll_pressed() -> void:
	var inv_index := _selected_inv_index()
	if inv_index < 0:
		return
	var result := ForgeServiceScript.reroll_affixes(inv_index)
	if result.get("ok", false):
		_detail_label.text = tr("SMITH_REROLLED")
		_refresh()
		return
	_report_forge(result, tr("SMITH_REROLL_FAILED"))


func _on_transmute_pressed() -> void:
	var inv_index := _selected_inv_index()
	if inv_index < 0:
		return
	var result := ForgeServiceScript.transmute_rarity(inv_index)
	if result.get("ok", false):
		_detail_label.text = tr("SMITH_TRANSMUTED") % RarityRegistryScript.display_name(
			str(result.get("rarity", ""))
		)
		_refresh()
		return
	_report_forge(result, tr("SMITH_TRANSMUTE_FAILED"))


func _on_infuse_pressed() -> void:
	var inv_index := _selected_inv_index()
	if inv_index < 0 or _infuse_element == "":
		return
	var result := ForgeServiceScript.infuse(inv_index, _infuse_element)
	if result.get("ok", false):
		_detail_label.text = tr("SMITH_INFUSED") % _infuse_element.capitalize()
		_refresh()
		return
	_report_forge(result, tr("SMITH_INFUSE_FAILED"))

func _on_gold_changed(_amount: int) -> void:
	_gold_label.text = tr("SMITH_COINS") % CharacterService.gold
