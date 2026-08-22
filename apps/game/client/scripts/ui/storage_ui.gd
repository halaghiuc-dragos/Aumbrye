extends Control

## Storage grid transfer UI (HUB-4.4).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ItemListPresenterScript := preload("res://scripts/ui/item_list_presenter.gd")

signal closed

@onready var _inv_list: ItemList = $Panel/Margin/VBox/Columns/InventoryColumn/InvList
@onready var _storage_list: ItemList = $Panel/Margin/VBox/Columns/StorageColumn/StorageList
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _to_storage_button: Button = $Panel/Margin/VBox/Buttons/ToStorageButton
@onready var _to_inv_button: Button = $Panel/Margin/VBox/Buttons/ToInvButton
@onready var _close_button: Button = $Panel/Margin/VBox/Buttons/CloseButton

var _inv_indices: Array[int] = []
var _storage_indices: Array[int] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self, "Panel", "Backdrop")
	ItemListPresenterScript.configure(_inv_list)
	ItemListPresenterScript.configure(_storage_list)
	_to_storage_button.pressed.connect(_on_to_storage)
	_to_inv_button.pressed.connect(_on_to_inv)
	_close_button.pressed.connect(close)
	InventoryService.inventory_changed.connect(_refresh)
	StorageService.storage_changed.connect(_refresh)


func is_open() -> bool:
	return visible


func open() -> void:
	_refresh()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_inv_list.grab_focus()


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Through PlayerControls: closing this panel must not grab the mouse back if another one is
	# still open behind it.
	PlayerControls.capture_mouse_if_allowed()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _refresh() -> void:
	_inv_list.clear()
	_inv_indices.clear()
	var inv := InventoryService.inventory
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		var item_id: String = slot.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		var qty: int = int(slot.get("quantity", 1))
		ItemListPresenterScript.add_row(
			_inv_list, item_id, def, _row_text(def, item_id, qty), str(slot.get("rarity", ""))
		)
		_inv_indices.append(i)
	_storage_list.clear()
	_storage_indices.clear()
	for i in StorageService.storage.slots.size():
		var slot: Dictionary = StorageService.storage.slots[i]
		var item_id: String = slot.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		var qty: int = int(slot.get("quantity", 1))
		ItemListPresenterScript.add_row(
			_storage_list, item_id, def, _row_text(def, item_id, qty), str(slot.get("rarity", ""))
		)
		_storage_indices.append(i)
	_refresh_empty_states()


func _on_to_storage() -> void:
	var selected := _inv_list.get_selected_items()
	if selected.is_empty():
		_detail_label.text = tr("STORAGE_SELECT_INVENTORY")
		return
	var result := StorageService.move_to_storage(_inv_indices[selected[0]])
	if result.get("ok", false):
		_detail_label.text = tr("STORAGE_MOVED_TO_STORAGE")
	else:
		_detail_label.text = str(result.get("error", tr("STORAGE_MOVE_FAILED"))).replace("_", " ")
	_refresh()


func _on_to_inv() -> void:
	var selected := _storage_list.get_selected_items()
	if selected.is_empty():
		_detail_label.text = tr("STORAGE_SELECT_STORAGE")
		return
	var result := StorageService.move_to_inventory(_storage_indices[selected[0]])
	if result.get("ok", false):
		_detail_label.text = tr("STORAGE_MOVED_TO_INVENTORY")
	else:
		_detail_label.text = str(result.get("error", tr("STORAGE_MOVE_FAILED"))).replace("_", " ")
	_refresh()


## A stack count is only worth showing when there is actually a stack.
func _row_text(definition: Dictionary, item_id: String, quantity: int) -> String:
	var display_name := str(definition.get("name", item_id))
	return "%s x%d" % [display_name, quantity] if quantity > 1 else display_name


## Empty-state rows, so a player looking at two blank boxes can tell the screen is working.
func _refresh_empty_states() -> void:
	if _inv_indices.is_empty():
		ItemListPresenterScript.add_plain_row(_inv_list, tr("STORAGE_INVENTORY_EMPTY"), false)
	if _storage_indices.is_empty():
		ItemListPresenterScript.add_plain_row(_storage_list, tr("STORAGE_STORAGE_EMPTY"), false)
