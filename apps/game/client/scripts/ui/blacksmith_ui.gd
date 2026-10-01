extends Control


const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ForgeServiceScript := preload("res://scripts/items/forge_service.gd")
const ItemListPresenterScript := preload("res://scripts/ui/item_list_presenter.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

signal closed

@onready var _gold_label: Label = $Panel/Margin/VBox/GoldLabel
@onready var _item_list: ItemList = $Panel/Margin/VBox/ItemList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _upgrade_button: Button = $Panel/Margin/VBox/Buttons/UpgradeButton
@onready var _close_button: Button = $Panel/Margin/VBox/Buttons/CloseButton

var _item_indices: Array = []
## Results (an error, "Salvaged for ...") live here, so choosing a row never wipes them.
var _status_label: Label
var _salvage_button: Button
var _unlock_button: Button


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self, "Panel", "Backdrop")
	ItemListPresenterScript.configure(_item_list)
	_upgrade_button.text = tr("SMITH_UPGRADE")
	_close_button.text = tr("SMITH_CLOSE")
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_close_button.pressed.connect(close)
	_item_list.item_selected.connect(_on_item_selected)
	_unlock_button = GameUISkinScript.make_button(tr("SMITH_UNLOCK_WEAPONS"))
	_unlock_button.pressed.connect(_on_unlock_pressed)
	$Panel/Margin/VBox/Buttons.add_child(_unlock_button)
	$Panel/Margin/VBox/Buttons.move_child(_unlock_button, 0)
	$Panel/Margin/VBox/Buttons.move_child(_close_button, -1)
	_refresh_unlock_button()
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(_status_label)
	_detail_label.get_parent().add_child(_status_label)
	_detail_label.get_parent().move_child(_status_label, _detail_label.get_index() + 1)
	_build_salvage_button()
	CharacterService.gold_changed.connect(_on_gold_changed)
	InventoryService.inventory_changed.connect(_refresh)


func _build_salvage_button() -> void:
	_salvage_button = GameUISkinScript.make_button(tr("SMITH_SALVAGE"))
	_salvage_button.pressed.connect(_on_salvage_pressed)
	GameUISkinScript.wire_button_sfx(_salvage_button)
	$Panel/Margin/VBox/Buttons.add_child(_salvage_button)
	$Panel/Margin/VBox/Buttons.move_child(_close_button, -1)
	for child in ($Panel/Margin/VBox/Buttons as HBoxContainer).get_children():
		var button := child as Control
		if button:
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_refresh()
	MenuStack.show_modal(self)
	_item_list.grab_focus()


func close() -> void:
	_status_label.text = ""
	MenuStack.hide_modal(self)
	closed.emit()


func _on_cancel_requested() -> void:
	close()


func _selection_key() -> Variant:
	var key: Variant = _selected_inv_index()
	if key is int and int(key) >= 0 and int(key) < InventoryService.inventory.slots.size():
		return str(InventoryService.inventory.slots[int(key)].get("instanceId", ""))
	return key


func _row_for_key(key: Variant) -> int:
	if key == null:
		return -1
	for row in _item_indices.size():
		var entry: Variant = _item_indices[row]
		if entry is int:
			var slots := InventoryService.inventory.slots
			if (
				key is String
				and int(entry) < slots.size()
				and str((slots[int(entry)] as Dictionary).get("instanceId", "")) == key
			):
				return row
		elif entry == key:
			return row
	return -1


func _refresh() -> void:
	if not visible:
		return
	var kept_key: Variant = _selection_key()
	var kept_rows := _item_list.get_selected_items()
	var kept_row: int = kept_rows[0] if not kept_rows.is_empty() else 0
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
		var rarity := inv.get_slot_rarity(slot)
		var index := ItemListPresenterScript.add_row(
			_item_list,
			item_id,
			def,
			tr("SMITH_ITEM_ROW") % [def.get("name", item_id), level, max_level],
			rarity
		)
		_item_list.set_item_tooltip(index, ItemListPresenterScript.slot_tooltip(slot))
		_item_indices.append(i)
	for slot_name in Equipment.SLOT_ORDER:
		var eq: Dictionary = inv.equipped.get(slot_name, {})
		if eq.is_empty():
			continue
		var eq_id: String = str(eq.get("itemId", ""))
		var eq_def := ItemCatalog.get_definition(eq_id)
		if eq_def.get("itemType", "") not in BlacksmithService.UPGRADEABLE_TYPES:
			continue
		var eq_level := BlacksmithService.get_slot_upgrade_level(eq)
		var eq_max_level := BlacksmithService.get_max_upgrade_level_for_slot(eq)
		var eq_index := ItemListPresenterScript.add_row(
			_item_list,
			eq_id,
			eq_def,
			tr("SMITH_ITEM_ROW_EQUIPPED") % [eq_def.get("name", eq_id), eq_level, eq_max_level],
			inv.get_slot_rarity(eq)
		)
		_item_list.set_item_tooltip(eq_index, ItemListPresenterScript.slot_tooltip(eq))
		_item_indices.append(slot_name)
	if _item_indices.is_empty():
		ItemListPresenterScript.add_plain_row(_item_list, tr("SMITH_NO_ITEMS"), false)
		_detail_label.text = ""
		_upgrade_button.disabled = true
		_refresh_forge_buttons()
	else:
		var row := _row_for_key(kept_key)
		if row < 0:
			row = clampi(kept_row, 0, _item_indices.size() - 1)
		_item_list.select(row)
		_on_item_selected(row)
	_refresh_unlock_button()


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _item_indices.size():
		return
	var inv_index: Variant = _item_indices[index]
	var slot: Dictionary = BlacksmithService.resolve_target(inv_index)
	if slot.is_empty():
		return
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
	_refresh_forge_buttons()


func _on_upgrade_pressed() -> void:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return
	var result := BlacksmithService.upgrade_item(_item_indices[selected[0]])
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", tr("SMITH_UPGRADE_FAILED")))
	_refresh()


func _next_unlock() -> Dictionary:
	for row in BlacksmithService.get_available_unlocks():
		if not row.get("owned", false):
			return row
	return {}


## The button names the item and its price up front, so unlocking a weapon is a choice rather than
## a surprise discovered after the gold is already spent.
func _refresh_unlock_button() -> void:
	if _unlock_button == null:
		return
	var next := _next_unlock()
	if next.is_empty():
		_unlock_button.text = tr("SMITH_UNLOCK_WEAPONS")
		_unlock_button.disabled = true
		return
	var item_name := str(
		ItemCatalog.get_definition(str(next.get("itemId", ""))).get("name", next.get("itemId", ""))
	)
	_unlock_button.text = tr("SMITH_UNLOCK_NEXT") % [item_name, int(next.get("goldCost", 0))]
	_unlock_button.disabled = false


func _on_unlock_pressed() -> void:
	var next := _next_unlock()
	if next.is_empty():
		_status_label.text = tr("SMITH_NO_UNLOCKS")
		return
	var item_id := str(next.get("itemId", ""))
	var result := BlacksmithService.unlock_item(item_id)
	if result.get("ok", false):
		_status_label.text = tr("SMITH_UNLOCKED") % ItemCatalog.get_definition(item_id).get("name", item_id)
	else:
		_status_label.text = str(result.get("error", tr("SMITH_UNLOCK_FAILED")))
	_refresh()


func _selected_inv_index() -> Variant:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return null
	var row: int = selected[0]
	if row < 0 or row >= _item_indices.size():
		return null
	return _item_indices[row]


func _refresh_forge_buttons() -> void:
	if _salvage_button:
		_salvage_button.disabled = _selected_inv_index() == null


func _report_forge(result: Dictionary, failure_text: String) -> void:
	if not result.get("ok", false):
		_status_label.text = str(result.get("error", failure_text))
	_refresh()


## Salvage destroys a specific item instance permanently -- the one action in the forge row with
## no way back at all, not even the gold a respec at least leaves you able to re-earn. It fired
## immediately on click, same gap as respec had.
func _on_salvage_pressed() -> void:
	var inv_index: Variant = _selected_inv_index()
	if inv_index == null:
		return
	var slot: Dictionary = BlacksmithService.resolve_target(inv_index)
	if slot.is_empty():
		return
	var preview := ForgeServiceScript.salvage_preview(slot)
	var item_name := str(ItemCatalog.get_definition(str(slot.get("itemId", ""))).get("name", slot.get("itemId", "")))
	var yield_text := ItemCatalog.display_amounts(preview)
	if yield_text == "":
		yield_text = tr("SMITH_SALVAGED")
	MenuStack.confirm(
		ConfirmSpec.texts(
			tr("SMITH_SALVAGE_CONFIRM_TITLE"),
			tr("SMITH_SALVAGE_CONFIRM_MESSAGE") % [item_name, yield_text],
			tr("SMITH_SALVAGE"),
			tr("UI_CANCEL"),
			_do_salvage.bind(inv_index, yield_text),
			Callable(),
			true
		)
	)


func _do_salvage(inv_index: Variant, yield_text: String) -> void:
	var result := ForgeServiceScript.salvage(inv_index)
	if result.get("ok", false):
		_status_label.text = tr("SMITH_SALVAGED_FOR") % yield_text
		_refresh()
		return
	_report_forge(result, tr("SMITH_SALVAGE_FAILED"))


func _on_gold_changed(_amount: int) -> void:
	_gold_label.text = tr("SMITH_COINS") % CharacterService.gold
