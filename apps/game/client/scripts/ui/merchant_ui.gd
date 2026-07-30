extends Control

## Merchant buy/sell UI (HUB-4.3).

signal closed

@onready var _gold_label: Label = $Panel/Margin/VBox/GoldLabel
@onready var _buy_list: ItemList = $Panel/Margin/VBox/BuyList
@onready var _sell_list: ItemList = $Panel/Margin/VBox/SellList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _buy_button: Button = $Panel/Margin/VBox/Buttons/BuyButton
@onready var _sell_button: Button = $Panel/Margin/VBox/Buttons/SellButton
@onready var _close_button: Button = $Panel/Margin/VBox/Buttons/CloseButton

var _buy_item_ids: Array[String] = []
var _sell_indices: Array[int] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buy_button.pressed.connect(_on_buy_pressed)
	_sell_button.pressed.connect(_on_sell_pressed)
	_close_button.pressed.connect(close)
	_buy_list.item_selected.connect(func(_i: int) -> void: _detail_label.text = "Select Buy or Sell")
	_sell_list.item_selected.connect(func(_i: int) -> void: _detail_label.text = "Select Buy or Sell")
	CharacterService.gold_changed.connect(func(_g: int) -> void: _gold_label.text = "Gold: %d" % CharacterService.gold)
	InventoryService.inventory_changed.connect(_refresh)


func is_open() -> bool:
	return visible


func open() -> void:
	MerchantService.reset_session()
	_refresh()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_buy_list.grab_focus()


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
	for entry in MerchantService.get_available_stock():
		var item_id: String = entry.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		var price := MerchantService.get_buy_price(item_id)
		_buy_list.add_item("%s — %d g (%d left)" % [def.get("name", item_id), price, entry.get("remaining", 0)])
		_buy_item_ids.append(item_id)
	_sell_list.clear()
	_sell_indices.clear()
	var inv := InventoryService.inventory
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		var item_id: String = slot.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		var price := MerchantService.get_sell_price(item_id)
		_sell_list.add_item("%s — sell %d g" % [def.get("name", item_id), price])
		_sell_indices.append(i)


func _on_buy_pressed() -> void:
	var selected := _buy_list.get_selected_items()
	if selected.is_empty():
		_detail_label.text = "Select an item to buy"
		return
	var item_id: String = _buy_item_ids[selected[0]]
	var result := MerchantService.buy_item(item_id)
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
	var result := MerchantService.sell_item(inv_index)
	if result.get("ok", false):
		_detail_label.text = "Sold for %d gold" % int(result.get("gold", 0))
	else:
		_detail_label.text = str(result.get("error", "sell failed"))
	_refresh()
