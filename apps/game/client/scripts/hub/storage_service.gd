extends Node

## Autoload — hub storage grid separate from player inventory (HUB-4.4).

signal storage_changed

var storage: GridInventory = GridInventory.new(8, 6)


func _ready() -> void:
	storage.changed.connect(_on_storage_changed)


func _on_storage_changed() -> void:
	storage_changed.emit()
	LocalSave.autosave()


func get_save_storage() -> Dictionary:
	return storage.to_save_dict()


func apply_save_storage(data: Dictionary) -> void:
	storage.from_save_dict(data)


func move_to_storage(inv_index: int) -> bool:
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return false
	var slot: Dictionary = inv.slots[inv_index]
	var item_id: String = slot.get("itemId", "")
	var qty: int = int(slot.get("quantity", 1))
	if not storage.add_item(item_id, qty):
		return false
	inv.remove_at(inv_index)
	return true


func move_to_inventory(storage_index: int) -> bool:
	if storage_index < 0 or storage_index >= storage.slots.size():
		return false
	var slot: Dictionary = storage.slots[storage_index]
	var item_id: String = slot.get("itemId", "")
	var qty: int = int(slot.get("quantity", 1))
	if not InventoryService.inventory.add_item(item_id, qty):
		return false
	storage.remove_at(storage_index)
	return true
