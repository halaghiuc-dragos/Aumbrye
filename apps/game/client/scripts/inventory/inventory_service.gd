extends Node

## Autoload singleton — persisted grid inventory for M2.

signal inventory_changed

var inventory: GridInventory = GridInventory.new()

var _item_def_cache: Dictionary = {}


func _ready() -> void:
	inventory.changed.connect(_on_inventory_changed)


func _on_inventory_changed() -> void:
	inventory_changed.emit()


func add_item(item_id: String, quantity: int = 1) -> bool:
	return inventory.add_item(item_id, quantity)


func get_item_def(item_id: String) -> Dictionary:
	if _item_def_cache.has(item_id):
		return _item_def_cache[item_id]
	var def: Dictionary = ContentLoader.load_json("content/items/%s.json" % item_id)
	_item_def_cache[item_id] = def
	return def


func get_save_inventory() -> Dictionary:
	return inventory.to_save_dict()


func apply_save_inventory(data: Dictionary) -> void:
	inventory.from_save_dict(data)
