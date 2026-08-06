extends Control

## Hub weapon loadout — swap between unlocked archetypes (WPN-5.5).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

signal closed

const WEAPON_ITEMS: Array[String] = [
	"castle_sword",
	"training_greatsword",
	"rogue_dagger",
	"guard_spear",
	"hunter_bow",
]

@onready var _list: ItemList = $Panel/Margin/VBox/WeaponList
@onready var _info: Label = $Panel/Margin/VBox/InfoLabel
@onready var _equip_btn: Button = $Panel/Margin/VBox/EquipButton
@onready var _close_btn: Button = $Panel/Margin/VBox/CloseButton


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameUISkinScript.apply_modal_menu(self, "Panel", "Dimmer")
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _refresh_list() -> void:
	_list.clear()
	for item_id in WEAPON_ITEMS:
		if not _is_weapon_unlocked(item_id):
			continue
		var def: Dictionary = ItemCatalog.get_definition(item_id)
		var label: String = str(def.get("name", item_id))
		if InventoryService.inventory.get_equipped_weapon_id() == item_id:
			label = "[Equipped] %s" % label
		_list.add_item(label)
		_list.set_item_metadata(_list.item_count - 1, item_id)


func _is_weapon_unlocked(item_id: String) -> bool:
	var class_id := CharacterService.get_class_id() if CharacterService else ""
	if class_id != "" and not ClassCatalog.is_weapon_allowed(class_id, item_id):
		return false
	match item_id:
		"castle_sword", "training_greatsword", "rogue_dagger":
			return true
		"guard_spear", "hunter_bow":
			return BlacksmithService.is_unlocked(item_id)
		_:
			return ItemCatalog.has_item(item_id)


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
