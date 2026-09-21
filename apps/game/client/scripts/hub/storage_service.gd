extends Node


signal storage_changed

var storage: GridInventory = GridInventory.new(8, 6)
var _transaction_depth := 0


func _ready() -> void:
	storage.changed.connect(_on_storage_changed)


func _on_storage_changed() -> void:
	if _transaction_depth > 0:
		return
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
	var inv_copy := GridInventory.new(inv.grid_width, inv.grid_height)
	inv_copy.from_save_dict(inv.to_save_dict())
	var storage_copy := GridInventory.new(storage.grid_width, storage.grid_height)
	storage_copy.from_save_dict(storage.to_save_dict())
	if not storage_copy.add_slot(slot):
		return {"ok": false, "error": "storage full"}
	var instance_id := str(slot.get("instanceId", ""))
	var resolved := inv_copy.find_instance_index(instance_id)
	if resolved < 0 or inv_copy.remove_at(resolved).is_empty():
		return {"ok": false, "error": "invalid slot"}
	_commit_transfer(inv, inv_copy, storage_copy)
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
	var inv := InventoryService.inventory
	var inv_copy := GridInventory.new(inv.grid_width, inv.grid_height)
	inv_copy.from_save_dict(inv.to_save_dict())
	var storage_copy := GridInventory.new(storage.grid_width, storage.grid_height)
	storage_copy.from_save_dict(storage.to_save_dict())
	if not inv_copy.add_slot(slot):
		return {"ok": false, "error": "inventory full"}
	var resolved := storage_copy.find_instance_index(str(slot.get("instanceId", "")))
	if resolved < 0 or storage_copy.remove_at(resolved).is_empty():
		return {"ok": false, "error": "invalid slot"}
	_commit_transfer(inv, inv_copy, storage_copy)
	return {"ok": true}


func _commit_transfer(inv: GridInventory, inv_copy: GridInventory, storage_copy: GridInventory) -> void:
	_transaction_depth += 1
	inv.from_save_dict(inv_copy.to_save_dict())
	storage.from_save_dict(storage_copy.to_save_dict())
	_transaction_depth -= 1
	storage_changed.emit()
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)
