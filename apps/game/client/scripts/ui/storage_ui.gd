extends Control


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

## The full description of whichever row is selected.
##
## The storage panel had no way to look at an item. Its one text line was a status line -- "moved
## to storage", "select an item first" -- so the player deciding what to bank could see a name and
## nothing else: not the condition, not the stats, not what it compares against. The inventory has
## described items properly all along; this is the same description, so an item reads the same
## wherever the player meets it.
var _description: RichTextLabel


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
	_build_description()
	_inv_list.item_selected.connect(_on_inventory_row_selected)
	_storage_list.item_selected.connect(_on_storage_row_selected)


func _build_description() -> void:
	_description = RichTextLabel.new()
	_description.bbcode_enabled = true
	_description.fit_content = true
	_description.scroll_active = false
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_label.get_parent().add_child(_description)
	_detail_label.get_parent().move_child(_description, _detail_label.get_index())


## Selecting in one list clears the other, so there is never a question about which item the
## description belongs to -- and the transfer buttons already act on one list at a time.
func _on_inventory_row_selected(row: int) -> void:
	_storage_list.deselect_all()
	_describe(InventoryService.inventory.slots, _inv_indices, row)


func _on_storage_row_selected(row: int) -> void:
	_inv_list.deselect_all()
	_describe(StorageService.storage.slots, _storage_indices, row)


func _describe(slots: Array, indices: Array[int], row: int) -> void:
	if _description == null:
		return
	if row < 0 or row >= indices.size():
		_description.text = ""
		return
	var index: int = indices[row]
	if index < 0 or index >= slots.size():
		_description.text = ""
		return
	_description.text = InventoryService.format_slot_tooltip_bbcode(slots[index])
	# The status line is about the last action, not about this item; a fresh selection has no
	# action behind it yet, so leaving the old message up would attach it to the wrong thing.
	_detail_label.text = ""


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
			_inv_list, item_id, def, _row_text(slot, qty), str(slot.get("rarity", ""))
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
			_storage_list, item_id, def, _row_text(slot, qty), str(slot.get("rarity", ""))
		)
		_storage_indices.append(i)
	_refresh_empty_states()
	if _description and _inv_list.get_selected_items().is_empty() \
			and _storage_list.get_selected_items().is_empty():
		_description.text = ""


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


## The name the rest of the game uses, so a chipped ring is called a chipped ring here too rather
## than reverting to its base name the moment it is put away.
func _row_text(slot: Dictionary, quantity: int) -> String:
	var display_name := InventoryService.inventory.get_slot_display_name(slot)
	return "%s x%d" % [display_name, quantity] if quantity > 1 else display_name


func _refresh_empty_states() -> void:
	if _inv_indices.is_empty():
		ItemListPresenterScript.add_plain_row(_inv_list, tr("STORAGE_INVENTORY_EMPTY"), false)
	if _storage_indices.is_empty():
		ItemListPresenterScript.add_plain_row(_storage_list, tr("STORAGE_STORAGE_EMPTY"), false)
