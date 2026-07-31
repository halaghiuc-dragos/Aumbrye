extends Control

## Blacksmith upgrade/repair UI (HUB-4.2).

signal closed

@onready var _gold_label: Label = $Panel/Margin/VBox/GoldLabel
@onready var _item_list: ItemList = $Panel/Margin/VBox/ItemList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _upgrade_button: Button = $Panel/Margin/VBox/Buttons/UpgradeButton
@onready var _repair_button: Button = $Panel/Margin/VBox/Buttons/RepairButton
@onready var _close_button: Button = $Panel/Margin/VBox/Buttons/CloseButton

var _weapon_indices: Array[int] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_repair_button.pressed.connect(_on_repair_pressed)
	_close_button.pressed.connect(close)
	_item_list.item_selected.connect(_on_item_selected)
	CharacterService.gold_changed.connect(_on_gold_changed)
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
	_gold_label.text = "Gold: %d" % CharacterService.gold
	_item_list.clear()
	_weapon_indices.clear()
	var inv := InventoryService.inventory
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		var item_id: String = slot.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		if def.get("itemType", "") != "weapon":
			continue
		var level := BlacksmithService.get_slot_upgrade_level(slot)
		var dur := BlacksmithService.get_slot_durability(slot)
		var max_dur := BlacksmithService.get_max_durability(item_id)
		_item_list.add_item("%s +%d (%d/%d)" % [def.get("name", item_id), level, dur, max_dur])
		_weapon_indices.append(i)
	if _weapon_indices.is_empty():
		_detail_label.text = "No weapons to upgrade or repair."
		_upgrade_button.disabled = true
		_repair_button.disabled = true
	elif _item_list.get_selected_items().is_empty() and not _weapon_indices.is_empty():
		_item_list.select(0)
		_on_item_selected(0)


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _weapon_indices.size():
		return
	var inv_index: int = _weapon_indices[index]
	var slot: Dictionary = InventoryService.inventory.slots[inv_index]
	var item_id: String = slot.get("itemId", "")
	var level := BlacksmithService.get_slot_upgrade_level(slot)
	var recipes := RecipeCatalog.get_upgrade_recipes(item_id, level)
	var upgrade_cost := 0
	if not recipes.is_empty():
		upgrade_cost = int(recipes[0].get("goldCost", 0))
	_detail_label.text = "Upgrade cost: %d gold" % upgrade_cost
	_upgrade_button.disabled = not BlacksmithService.can_upgrade(inv_index)
	_repair_button.disabled = not BlacksmithService.can_repair(inv_index)


func _on_upgrade_pressed() -> void:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return
	var result := BlacksmithService.upgrade_item(_weapon_indices[selected[0]])
	if not result.get("ok", false):
		_detail_label.text = str(result.get("error", "upgrade failed"))
	_refresh()


func _on_repair_pressed() -> void:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return
	var result := BlacksmithService.repair_item(_weapon_indices[selected[0]])
	if not result.get("ok", false):
		_detail_label.text = str(result.get("error", "repair failed"))
	_refresh()


func _on_gold_changed(_amount: int) -> void:
	_gold_label.text = "Gold: %d" % CharacterService.gold
