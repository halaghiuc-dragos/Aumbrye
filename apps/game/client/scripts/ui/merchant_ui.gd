extends Control

## Merchant buy/sell UI (HUB-4.3).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

signal closed

@onready var _gold_label: Label = $Panel/Margin/VBox/GoldLabel
@onready var _buy_list: ItemList = $Panel/Margin/VBox/BuyList
@onready var _sell_list: ItemList = $Panel/Margin/VBox/SellList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _buy_button: Button = $Panel/Margin/VBox/Buttons/BuyButton
@onready var _sell_button: Button = $Panel/Margin/VBox/Buttons/SellButton
@onready var _close_button: Button = $Panel/Margin/VBox/Buttons/CloseButton

var _sell_qty_spin: SpinBox
var _buy_item_ids: Array[String] = []
var _sell_indices: Array[int] = []
var _merchant_id := "hub_merchant"


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self, "Panel", "Backdrop")
	_buy_button.pressed.connect(_on_buy_pressed)
	_sell_button.pressed.connect(_on_sell_pressed)
	_close_button.pressed.connect(close)
	_buy_list.item_selected.connect(
		func(_i: int) -> void: _detail_label.text = "Select Buy or Sell"
	)
	_sell_list.item_selected.connect(_on_sell_selected)
	CharacterService.gold_changed.connect(
		func(_g: int) -> void: _gold_label.text = "Gold: %d" % CharacterService.gold
	)
	InventoryService.inventory_changed.connect(_refresh)
	_sell_qty_spin = SpinBox.new()
	_sell_qty_spin.name = "SellQtySpin"
	_sell_qty_spin.min_value = 1
	_sell_qty_spin.max_value = 999
	_sell_qty_spin.value = 1
	$Panel/Margin/VBox.add_child(_sell_qty_spin)
	$Panel/Margin/VBox.move_child(_sell_qty_spin, _sell_list.get_index() + 1)


func is_open() -> bool:
	return visible


func open() -> void:
	_refresh()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_buy_list.grab_focus()


func open_for_merchant(merchant_id: String = "hub_merchant") -> void:
	_merchant_id = merchant_id
	open()


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
	_buy_list.clear()
	_buy_item_ids.clear()
	for entry in MerchantService.get_available_stock(_merchant_id):
		var item_id: String = entry.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		var price := MerchantService.get_buy_price(item_id, _merchant_id)
		_buy_list.add_item(
			"%s — %d g (%d left)" % [def.get("name", item_id), price, entry.get("remaining", 0)]
		)
		_buy_item_ids.append(item_id)
	_sell_list.clear()
	_sell_indices.clear()
	var inv := InventoryService.inventory
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		var item_id: String = slot.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		var price := MerchantService.get_slot_sell_price(slot)
		var qty := int(slot.get("quantity", 1))
		var label := "%s — sell %d g" % [def.get("name", item_id), price]
		if qty > 1:
			label = "%s x%d — sell %d g" % [def.get("name", item_id), qty, price]
		_sell_list.add_item(label)
		_sell_indices.append(i)


func _on_sell_selected(_index: int) -> void:
	var selected := _sell_list.get_selected_items()
	if selected.is_empty():
		return
	var inv_index: int = _sell_indices[selected[0]]
	var slot: Dictionary = InventoryService.inventory.slots[inv_index]
	var qty := maxi(1, int(slot.get("quantity", 1)))
	_sell_qty_spin.max_value = qty
	_sell_qty_spin.value = qty
	_detail_label.text = "Sell quantity (max %d)" % qty


func _on_buy_pressed() -> void:
	var selected := _buy_list.get_selected_items()
	if selected.is_empty():
		_detail_label.text = "Select an item to buy"
		return
	var item_id: String = _buy_item_ids[selected[0]]
	var result := MerchantService.buy_item(item_id, _merchant_id)
	if result.get("ok", false):
		_detail_label.text = "Purchased %s" % item_id
	else:
		_detail_label.text = str(result.get("error", "buy failed"))
	_refresh()


func _on_sell_pressed() -> void:
	var selected := _sell_list.get_selected_items()
	if selected.is_empty():
		_detail_label.text = "Select an item to sell"
		return
	var inv_index: int = _sell_indices[selected[0]]
	var sell_qty := int(_sell_qty_spin.value)
	var result := MerchantService.sell_item(inv_index, sell_qty)
	if result.get("ok", false):
		_detail_label.text = "Sold for %d gold" % int(result.get("gold", 0))
	else:
		_detail_label.text = str(result.get("error", "sell failed"))
	_refresh()
