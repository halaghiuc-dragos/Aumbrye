extends RefCounted
class_name GridInventory

const DEFAULT_WIDTH := 6
const DEFAULT_HEIGHT := 4

signal changed
signal item_equipped(item_id: String, slot: String)
signal item_unequipped(slot: String)

var grid_width: int = DEFAULT_WIDTH
var grid_height: int = DEFAULT_HEIGHT
var slots: Array[Dictionary] = []
var equipped: Dictionary = { "weapon": "" }


func _init(width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> void:
	grid_width = width
	grid_height = height


func to_save_dict() -> Dictionary:
	return {
		"schemaVersion": 1,
		"gridWidth": grid_width,
		"gridHeight": grid_height,
		"slots": slots.duplicate(true),
		"equipped": equipped.duplicate(),
	}


func from_save_dict(data: Dictionary) -> void:
	grid_width = int(data.get("gridWidth", DEFAULT_WIDTH))
	grid_height = int(data.get("gridHeight", DEFAULT_HEIGHT))
	slots.clear()
	for entry in data.get("slots", []):
		if entry is Dictionary:
			slots.append(entry.duplicate())
	var eq: Dictionary = data.get("equipped", {})
	equipped = { "weapon": str(eq.get("weapon", "")) }
	changed.emit()


func get_item_def(item_id: String) -> Dictionary:
	return ContentLoader.load_json("content/items/%s.json" % item_id)


func can_place(item_id: String, x: int, y: int, ignore_index: int = -1) -> bool:
	var def := get_item_def(item_id)
	if def.is_empty():
		return false
	var w: int = def.get("gridWidth", 1)
	var h: int = def.get("gridHeight", 1)
	if x < 0 or y < 0 or x + w > grid_width or y + h > grid_height:
		return false
	for i in slots.size():
		if i == ignore_index:
			continue
		var slot: Dictionary = slots[i]
		var other_def := get_item_def(slot.get("itemId", ""))
		if other_def.is_empty():
			continue
		var ox: int = slot.get("x", 0)
		var oy: int = slot.get("y", 0)
		var ow: int = other_def.get("gridWidth", 1)
		var oh: int = other_def.get("gridHeight", 1)
		if Rect2i(x, y, w, h).intersects(Rect2i(ox, oy, ow, oh)):
			return false
	return true


func add_item(item_id: String, quantity: int = 1) -> bool:
	var def := get_item_def(item_id)
	if def.is_empty():
		return false
	var max_stack: int = def.get("stackSize", 1)
	for i in slots.size():
		var slot: Dictionary = slots[i]
		if slot.get("itemId", "") != item_id:
			continue
		var current_qty: int = slot.get("quantity", 1)
		if current_qty >= max_stack:
			continue
		var addable := mini(quantity, max_stack - current_qty)
		slot["quantity"] = current_qty + addable
		quantity -= addable
		if quantity <= 0:
			changed.emit()
			return true
	for y in grid_height:
		for x in grid_width:
			if quantity <= 0:
				break
			if not can_place(item_id, x, y):
				continue
			var place_qty := mini(quantity, max_stack)
			slots.append({ "itemId": item_id, "quantity": place_qty, "x": x, "y": y })
			quantity -= place_qty
	if quantity > 0:
		return false
	changed.emit()
	return true


func remove_at(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	var removed: Dictionary = slots[index]
	slots.remove_at(index)
	changed.emit()
	return removed


func equip_weapon(index: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
	var slot: Dictionary = slots[index]
	var item_id: String = slot.get("itemId", "")
	var def := get_item_def(item_id)
	if def.get("itemType", "") != "weapon":
		return false
	var previous_id: String = equipped.get("weapon", "")
	equipped["weapon"] = item_id
	if previous_id != "" and previous_id != item_id:
		item_unequipped.emit("weapon")
	item_equipped.emit(item_id, "weapon")
	changed.emit()
	return true


func consume_at(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	var slot: Dictionary = slots[index]
	var item_id: String = slot.get("itemId", "")
	var def := get_item_def(item_id)
	if def.get("itemType", "") != "consumable":
		return {}
	var qty: int = slot.get("quantity", 1) - 1
	if qty <= 0:
		slots.remove_at(index)
	else:
		slot["quantity"] = qty
	changed.emit()
	return def


func get_equipped_weapon_id() -> String:
	return equipped.get("weapon", "")


func get_equipped_weapon_data_path() -> String:
	var item_id := get_equipped_weapon_id()
	if item_id == "":
		return "content/weapons/sword_basic.json"
	var def := get_item_def(item_id)
	var weapon_id: String = def.get("weaponId", "sword_basic")
	return "content/weapons/%s.json" % weapon_id
