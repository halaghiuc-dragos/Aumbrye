extends Node


signal storage_changed

var storage: GridInventory = GridInventory.new(8, 6)


func _ready() -> void:
	storage.changed.connect(_on_storage_changed)


func _on_storage_changed() -> void:
	storage_changed.emit()
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)


func get_save_storage() -> Dictionary:
	return storage.to_save_dict()


func apply_save_storage(data: Dictionary) -> void:
	storage.from_save_dict(data)


func can_accept(slot: Dictionary) -> bool:
	if slot.is_empty() or not slot.has("itemId"):
		return false
	var item_id: String = slot.get("itemId", "")
	if ItemCatalog.get_definition(item_id).is_empty():
		return false
	return storage.has_space_for(item_id)


func move_to_storage(inv_index: int) -> Dictionary:
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return {"ok": false, "error": "invalid slot"}
	var slot: Dictionary = inv.slots[inv_index].duplicate(true)
	if not can_accept(slot):
		return {"ok": false, "error": "storage full"}
	if not storage.add_slot(slot):
		return {"ok": false, "error": "storage full"}
	inv.remove_at(inv_index)
	return {"ok": true}


func move_to_inventory(storage_index: int) -> Dictionary:
	if storage_index < 0 or storage_index >= storage.slots.size():
		return {"ok": false, "error": "invalid slot"}
	var slot: Dictionary = storage.slots[storage_index].duplicate(true)
	var item_id: String = slot.get("itemId", "")
	if ItemCatalog.get_definition(item_id).is_empty():
		return {"ok": false, "error": "invalid slot"}
	if not InventoryService.inventory.has_space_for(item_id):
		return {"ok": false, "error": "inventory full"}
	if not InventoryService.inventory.add_slot(slot):
		return {"ok": false, "error": "inventory full"}
	storage.remove_at(storage_index)
	return {"ok": true}
