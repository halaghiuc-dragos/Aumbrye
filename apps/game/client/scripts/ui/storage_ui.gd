extends Control

## Storage grid transfer UI (HUB-4.4).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
		_inv_list.add_item("%s x%d" % [def.get("name", item_id), qty])
		_inv_indices.append(i)
	_storage_list.clear()
	_storage_indices.clear()
	for i in StorageService.storage.slots.size():
		var slot: Dictionary = StorageService.storage.slots[i]
		var item_id: String = slot.get("itemId", "")
		var def := ItemCatalog.get_definition(item_id)
		var qty: int = int(slot.get("quantity", 1))
		_storage_list.add_item("%s x%d" % [def.get("name", item_id), qty])
		_storage_indices.append(i)


func _on_to_storage() -> void:
	var selected := _inv_list.get_selected_items()
	if selected.is_empty():
		_detail_label.text = "Select inventory item"
		return
	var result := StorageService.move_to_storage(_inv_indices[selected[0]])
	if result.get("ok", false):
		_detail_label.text = "Moved to storage"
	else:
		_detail_label.text = str(result.get("error", "move failed")).replace("_", " ")
	_refresh()


func _on_to_inv() -> void:
	var selected := _storage_list.get_selected_items()
	if selected.is_empty():
		_detail_label.text = "Select storage item"
		return
	var result := StorageService.move_to_inventory(_storage_indices[selected[0]])
	if result.get("ok", false):
		_detail_label.text = "Moved to inventory"
	else:
		_detail_label.text = str(result.get("error", "move failed")).replace("_", " ")
	_refresh()
