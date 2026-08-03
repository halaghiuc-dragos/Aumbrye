extends Control

## Blacksmith upgrade/repair UI (HUB-4.2).

const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")

signal closed

@onready var _gold_label: Label = $Panel/Margin/VBox/GoldLabel
@onready var _item_list: ItemList = $Panel/Margin/VBox/ItemList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _upgrade_button: Button = $Panel/Margin/VBox/Buttons/UpgradeButton
@onready var _repair_button: Button = $Panel/Margin/VBox/Buttons/RepairButton
@onready var _close_button: Button = $Panel/Margin/VBox/Buttons/CloseButton

var _item_indices: Array[int] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_repair_button.pressed.connect(_on_repair_pressed)
	_close_button.pressed.connect(close)
	_item_list.item_selected.connect(_on_item_selected)
	CharacterService.coins_changed.connect(_on_coins_changed)
	InventoryService.inventory_changed.connect(_refresh)


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
	_gold_label.text = "Coins: %d" % CharacterService.get_coins()
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
		var rarity := RarityRegistryScript.display_name(inv.get_slot_rarity(slot))
		_item_list.add_item("%s %s +%d/%d (%d/%d)" % [rarity, def.get("name", item_id), level, max_level, dur, max_dur])
		_item_indices.append(i)
	if _item_indices.is_empty():
		_detail_label.text = "No equippable items to upgrade or repair."
		_upgrade_button.disabled = true
		_repair_button.disabled = true
	elif _item_list.get_selected_items().is_empty() and not _item_indices.is_empty():
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
	var rarity := RarityRegistryScript.display_name(InventoryService.inventory.get_slot_rarity(slot))
	_detail_label.text = "%s — upgrade cost: %d coins (+%d/%d)" % [rarity, upgrade_cost, level, max_level]
	_upgrade_button.disabled = not BlacksmithService.can_upgrade(inv_index)
	_repair_button.disabled = not BlacksmithService.can_repair(inv_index)


func _on_upgrade_pressed() -> void:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return
	var result := BlacksmithService.upgrade_item(_item_indices[selected[0]])
	if not result.get("ok", false):
		_detail_label.text = str(result.get("error", "upgrade failed"))
	_refresh()


func _on_repair_pressed() -> void:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return
	var result := BlacksmithService.repair_item(_item_indices[selected[0]])
	if not result.get("ok", false):
		_detail_label.text = str(result.get("error", "repair failed"))
	_refresh()


func _on_coins_changed(_amount: int) -> void:
	_gold_label.text = "Coins: %d" % CharacterService.get_coins()
