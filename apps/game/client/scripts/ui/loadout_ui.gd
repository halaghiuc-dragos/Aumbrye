extends Control

## Hub weapon loadout — swap between unlocked archetypes (WPN-5.5).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ItemListPresenterScript := preload("res://scripts/ui/item_list_presenter.gd")

signal closed

## C-246: this was a hardcoded list of five, against `content/items/` defining **70** items with
## `itemType: "weapon"` — five tiers of a material ladder, the biome weapons and 19 uniques. So the
## Loadout screen showed 7% of the game's weapons, and finding a unique could not change what the
## screen offered. The list is derived from the catalogue now.
##
## The three starters stay named, because `_is_weapon_unlocked` grants them unconditionally and that
## is a statement about the starting kit rather than about the catalogue.
const STARTER_WEAPONS: Array[String] = [
	"castle_sword",
	"training_greatsword",
	"rogue_dagger",
]


static func _weapon_items() -> Array[String]:
	return ItemCatalog.get_items_by_type("weapon")

@onready var _list: ItemList = $Panel/Margin/VBox/WeaponList
@onready var _info: Label = $Panel/Margin/VBox/InfoLabel
@onready var _equip_btn: Button = $Panel/Margin/VBox/EquipButton
@onready var _close_btn: Button = $Panel/Margin/VBox/CloseButton


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameUISkinScript.apply_modal_menu(self, "Panel", "Dimmer")
	ItemListPresenterScript.configure(_list)
	_equip_btn.pressed.connect(_on_equip_pressed)
	_close_btn.pressed.connect(close)
	_list.item_selected.connect(_on_item_selected)


func open() -> void:
	_refresh_list()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _list.item_count > 0:
		_list.select(0)
		_on_item_selected(0)


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Through PlayerControls: closing this panel must not grab the mouse back if another one is
	# still open behind it.
	PlayerControls.capture_mouse_if_allowed()
	closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _refresh_list() -> void:
	_list.clear()
	for item_id in _weapon_items():
		if not _is_weapon_unlocked(item_id):
			continue
		var def: Dictionary = ItemCatalog.get_definition(item_id)
		var label: String = str(def.get("name", item_id))
		var equipped := InventoryService.inventory.get_equipped_weapon_id() == item_id
		if equipped:
			label = tr("LOADOUT_EQUIPPED_ROW") % label
		var index := ItemListPresenterScript.add_row(_list, item_id, def, label)
		if equipped:
			_list.set_item_custom_fg_color(index, GameUISkinScript.TITLE_COLOR)
		_list.set_item_metadata(index, item_id)


func _is_weapon_unlocked(item_id: String) -> bool:
	var class_id := CharacterService.get_class_id() if CharacterService else ""
	if class_id != "" and not ClassCatalog.is_weapon_allowed(class_id, item_id):
		return false
	if item_id in STARTER_WEAPONS:
		return true
	# C-246: a weapon the player is actually carrying is available whether or not the blacksmith
	# has ever unlocked it — finding a unique in a run is the point of finding it. Otherwise the
	# blacksmith gate stands.
	if InventoryService and _holds_item(InventoryService.inventory, item_id):
		return true
	if StorageService and _holds_item(StorageService.storage, item_id):
		return true
	return BlacksmithService.is_unlocked(item_id)


static func _holds_item(grid: GridInventory, item_id: String) -> bool:
	if grid == null:
		return false
	return (
		not grid
		. find_slots_where(func(slot: Dictionary) -> bool: return slot.get("itemId", "") == item_id)
		. is_empty()
	)


func _on_item_selected(index: int) -> void:
	var item_id: String = _list.get_item_metadata(index)
	var def: Dictionary = ItemCatalog.get_definition(item_id)
	_info.text = str(def.get("description", item_id))
	_equip_btn.disabled = InventoryService.inventory.get_equipped_weapon_id() == item_id


func _on_equip_pressed() -> void:
	var index := _list.get_selected_items()
	if index.is_empty():
		return
	var item_id: String = _list.get_item_metadata(index[0])
	_equip_weapon_item(item_id)
	_refresh_list()


func _equip_weapon_item(item_id: String) -> void:
	var grid := InventoryService.inventory
	if grid.get_equipped_weapon_id() == item_id:
		return
	for i in grid.slots.size():
		if grid.slots[i].get("itemId", "") == item_id:
			grid.equip_weapon(i)
			return
	if grid.add_item(item_id, 1):
		grid.equip_weapon(grid.slots.size() - 1)
