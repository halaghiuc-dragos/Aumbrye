extends Control

## Merchant buy/sell UI (HUB-4.3).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ItemListPresenterScript := preload("res://scripts/ui/item_list_presenter.gd")

signal closed

@onready var _gold_label: Label = $Panel/Margin/VBox/GoldLabel
@onready var _buy_list: ItemList = $Panel/Margin/VBox/Columns/BuyColumn/BuyList
@onready var _sell_list: ItemList = $Panel/Margin/VBox/Columns/SellColumn/SellList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _qty_row: HBoxContainer = $Panel/Margin/VBox/QtyRow
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
	ItemListPresenterScript.configure(_buy_list)
	ItemListPresenterScript.configure(_sell_list)
	_buy_button.pressed.connect(_on_buy_pressed)
	_sell_button.pressed.connect(_on_sell_pressed)
	_close_button.pressed.connect(close)
	_buy_list.item_selected.connect(_on_buy_selected)
	_sell_list.item_selected.connect(_on_sell_selected)
	CharacterService.gold_changed.connect(_on_gold_changed)
	InventoryService.inventory_changed.connect(_refresh)
	# Lives in its own labelled row rather than as a bare spinner dropped into the main column,
	# where nothing said what the number applied to.
	_sell_qty_spin = SpinBox.new()
	_sell_qty_spin.name = "SellQtySpin"
	_sell_qty_spin.min_value = 1
	_sell_qty_spin.max_value = 999
	_sell_qty_spin.value = 1
	_sell_qty_spin.custom_minimum_size = Vector2(110, 0)
	_qty_row.add_child(_sell_qty_spin)


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


func _on_gold_changed(_gold: int) -> void:
	_gold_label.text = tr("MERCHANT_GOLD") % CharacterService.gold


func _refresh() -> void:
	_gold_label.text = tr("MERCHANT_GOLD") % CharacterService.gold
	_refresh_buy_list()
	_refresh_sell_list()


func _refresh_buy_list() -> void:
	_buy_list.clear()
	_buy_item_ids.clear()
	var stock: Array = MerchantService.get_available_stock(_merchant_id)
	if stock.is_empty():
		ItemListPresenterScript.add_plain_row(_buy_list, tr("MERCHANT_STOCK_EMPTY"), false)
		return
	for entry in stock:
		var item_id: String = entry.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		var price := MerchantService.get_buy_price(item_id, _merchant_id)
		var index := ItemListPresenterScript.add_row(
			_buy_list,
			item_id,
			def,
			tr("MERCHANT_BUY_ROW")
			% [def.get("name", item_id), price, int(entry.get("remaining", 0))]
		)
		# Dimmed rather than hidden, so the player can still see what is on offer and read the
		# price they are saving towards.
		if price > CharacterService.gold:
			_buy_list.set_item_custom_fg_color(index, GameUISkinScript.HINT_COLOR.darkened(0.35))
		_buy_item_ids.append(item_id)


func _refresh_sell_list() -> void:
	_sell_list.clear()
	_sell_indices.clear()
	var inv := InventoryService.inventory
	if inv.slots.is_empty():
		ItemListPresenterScript.add_plain_row(_sell_list, tr("MERCHANT_INVENTORY_EMPTY"), false)
		_qty_row.visible = false
		return
	_qty_row.visible = true
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		var item_id: String = slot.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		var price := MerchantService.get_slot_sell_price(slot)
		var qty := int(slot.get("quantity", 1))
		var label := (
			tr("MERCHANT_SELL_ROW_STACK") % [def.get("name", item_id), qty, price]
			if qty > 1
			else tr("MERCHANT_SELL_ROW") % [def.get("name", item_id), price]
		)
		ItemListPresenterScript.add_row(
			_sell_list, item_id, def, label, str(slot.get("rarity", ""))
		)
		_sell_indices.append(i)


## Shows what the purchase actually costs and whether it is affordable, instead of the previous
## placeholder line that just said "Select Buy or Sell".
func _on_buy_selected(index: int) -> void:
	if index < 0 or index >= _buy_item_ids.size():
		return
	var item_id := _buy_item_ids[index]
	var def := ItemCatalog.get_definition(item_id)
	var price := MerchantService.get_buy_price(item_id, _merchant_id)
	if price > CharacterService.gold:
		_detail_label.text = tr("MERCHANT_CANNOT_AFFORD") % [
			def.get("name", item_id), price - CharacterService.gold
		]
	else:
		_detail_label.text = tr("MERCHANT_BUY_HINT") % [def.get("name", item_id), price]


func _on_sell_selected(_index: int) -> void:
	var selected := _sell_list.get_selected_items()
	if selected.is_empty():
		return
	var row: int = selected[0]
	if row < 0 or row >= _sell_indices.size():
		return
	var inv_index: int = _sell_indices[row]
	var slot: Dictionary = InventoryService.inventory.slots[inv_index]
	var qty := maxi(1, int(slot.get("quantity", 1)))
	var def := ItemCatalog.get_definition(str(slot.get("itemId", "")))
	_sell_qty_spin.max_value = qty
	_sell_qty_spin.value = qty
	_detail_label.text = tr("MERCHANT_SELL_HINT") % [
		def.get("name", slot.get("itemId", "")), MerchantService.get_slot_sell_price(slot)
	]


func _on_buy_pressed() -> void:
	var selected := _buy_list.get_selected_items()
	if selected.is_empty() or _buy_item_ids.is_empty():
		_detail_label.text = tr("MERCHANT_SELECT_BUY")
		return
	var row: int = selected[0]
	if row < 0 or row >= _buy_item_ids.size():
		_detail_label.text = tr("MERCHANT_SELECT_BUY")
		return
	var item_id: String = _buy_item_ids[row]
	var def := ItemCatalog.get_definition(item_id)
	var result := MerchantService.buy_item(item_id, _merchant_id)
	if result.get("ok", false):
		# Reports the item's display name; this used to print the raw catalog id at the player.
		_detail_label.text = tr("MERCHANT_PURCHASED") % def.get("name", item_id)
	else:
		_detail_label.text = str(result.get("error", tr("MERCHANT_BUY_FAILED")))
	_refresh()


func _on_sell_pressed() -> void:
	var selected := _sell_list.get_selected_items()
	if selected.is_empty() or _sell_indices.is_empty():
		_detail_label.text = tr("MERCHANT_SELECT_SELL")
		return
	var row: int = selected[0]
	if row < 0 or row >= _sell_indices.size():
		_detail_label.text = tr("MERCHANT_SELECT_SELL")
		return
	var inv_index: int = _sell_indices[row]
	var sell_qty := int(_sell_qty_spin.value)
	var result := MerchantService.sell_item(inv_index, sell_qty)
	if result.get("ok", false):
		_detail_label.text = tr("MERCHANT_SOLD") % int(result.get("gold", 0))
	else:
		_detail_label.text = str(result.get("error", tr("MERCHANT_SELL_FAILED")))
	_refresh()
