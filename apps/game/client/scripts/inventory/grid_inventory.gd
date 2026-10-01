extends RefCounted
class_name GridInventory

const EquipmentHelper := preload("res://scripts/items/equipment.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const ContentTextScript := preload("res://scripts/content/content_text.gd")

const DEFAULT_WIDTH := 10
const DEFAULT_HEIGHT := 6
const MAX_WIDTH := 10
const MAX_HEIGHT := 10

const SORT_MODES: Array[String] = ["default", "name", "type", "rarity"]
const FILTER_TYPES: Array[String] = [
	"all", "weapon", "armor", "accessory", "consumable", "material"
]
const FILTER_RARITIES: Array[String] = [
	"all", "common", "magic", "rare", "epic", "legendary", "aumbral"
]

signal changed
signal item_equipped(item_id: String, slot: String)
signal item_unequipped(slot: String)

var grid_width: int = DEFAULT_WIDTH
var grid_height: int = DEFAULT_HEIGHT
var slots: Array[Dictionary] = []
var equipped: Dictionary = {}

static var _next_instance_ordinal := 1


static func mint_instance_id(item_id: String) -> String:
	_next_instance_ordinal += 1
	return "%s#%d" % [item_id, _next_instance_ordinal]


static func seed_instance_ordinal(high_water: int) -> void:
	_next_instance_ordinal = maxi(_next_instance_ordinal, high_water)


func _init(width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> void:
	grid_width = width
	grid_height = height
	equipped = EquipmentHelper.empty_equipped()


## The bag is an ordered list with a fixed number of places. A slot's cell is its position in the
## list, laid out left to right in rows of `grid_width`, so there is nothing to keep in step with it.
func capacity() -> int:
	return grid_width * grid_height


func _has_room() -> bool:
	return slots.size() < capacity()


func to_save_dict() -> Dictionary:
	return {
		"schemaVersion": 1,
		"gridWidth": grid_width,
		"gridHeight": grid_height,
		"slots": _serialize_slots(),
		"equipped": _serialize_equipped(),
	}


## Saves still carry each slot's cell, derived from its place in the list, so the file format and
## its schema do not change.
func _serialize_slots() -> Array:
	var out: Array = []
	for i in slots.size():
		var entry: Dictionary = slots[i].duplicate(true)
		entry["x"] = i % grid_width
		entry["y"] = int(i / float(grid_width))
		out.append(entry)
	return out


func from_save_dict(data: Dictionary) -> void:
	grid_width = mini(MAX_WIDTH, maxi(grid_width, int(data.get("gridWidth", DEFAULT_WIDTH))))
	grid_height = mini(MAX_HEIGHT, maxi(grid_height, int(data.get("gridHeight", DEFAULT_HEIGHT))))
	slots.clear()
	var entries: Array = []
	for entry in data.get("slots", []):
		if entry is Dictionary:
			entries.append(entry.duplicate())
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ca := int(a.get("y", 0)) * MAX_WIDTH + int(a.get("x", 0))
			var cb := int(b.get("y", 0)) * MAX_WIDTH + int(b.get("x", 0))
			return ca < cb
	)
	for entry in entries:
		slots.append(_normalize_slot(entry))
	_deserialize_equipped(data.get("equipped", {}))
	changed.emit()


func get_item_def(item_id: String) -> Dictionary:
	return ItemCatalog.get_definition(item_id)


func get_slot_rarity(slot: Dictionary) -> String:
	if slot.has("rarity"):
		return RarityRegistryScript.normalize(str(slot.get("rarity", "common")))
	var def := get_item_def(slot.get("itemId", ""))
	return RarityRegistryScript.normalize(str(def.get("rarity", "common")))


func get_slot_display_name(slot: Dictionary) -> String:
	var def := get_item_def(slot.get("itemId", ""))
	if slot.get("itemId", "") == "dungeon_key" and slot.has("keyLabel"):
		return str(slot.get("keyLabel", "Dungeon Key"))
	var name := ContentTextScript.name(def, str(slot.get("itemId", "?")))
	var rarity: String = get_slot_rarity(slot)
	if rarity != "common" and rarity != "":
		return "[%s] %s" % [RarityRegistryScript.display_name(rarity), name]
	return name


func add_slot(slot: Dictionary) -> bool:
	var item_id: String = slot.get("itemId", "")
	if item_id == "" or get_item_def(item_id).is_empty():
		return false
	if not _has_room():
		return false
	slots.append(_normalize_slot(slot.duplicate(true)))
	changed.emit()
	return true


func has_space_for(item_id: String) -> bool:
	return not get_item_def(item_id).is_empty() and _has_room()


func add_item(item_id: String, quantity: int = 1, instance_data: Dictionary = {}) -> bool:
	var def := get_item_def(item_id)
	if def.is_empty():
		return false
	# An add that runs out of room has to leave the inventory exactly as it found it. Recording just
	# the mutations costs nothing when the item fits and undoes precisely when it does not -- a
	# deep copy of every slot (affix arrays and all) would run on every successful add, and adds happen
	# on every pickup and every loot roll. Indices stay valid because this function only ever appends.
	var bumped_stacks: Array = []
	var appended := 0
	var max_stack: int = def.get("stackSize", 1)
	var at_risk := bool(instance_data.get("runLoot", false))
	if max_stack > 1 and _is_plain_instance_data(instance_data):
		for i in slots.size():
			var slot: Dictionary = slots[i]
			if slot.get("itemId", "") != item_id:
				continue
			if slot.has("affixes") and not slot.get("affixes", []).is_empty():
				continue
			# Loot picked up on this run stacks with other loot from this run, and banked stock with
			# banked stock, so dying still costs exactly what the run brought in.
			if bool(slot.get("runLoot", false)) != at_risk:
				continue
			var current_qty: int = slot.get("quantity", 1)
			if current_qty >= max_stack:
				continue
			var addable := mini(quantity, max_stack - current_qty)
			bumped_stacks.append([i, current_qty])
			slot["quantity"] = current_qty + addable
			quantity -= addable
			if quantity <= 0:
				changed.emit()
				return true
	while quantity > 0:
		if not _has_room():
			break
		var place_qty := mini(quantity, max_stack)
		var slot_data := {
			"itemId": item_id,
			"quantity": place_qty,
		}
		if not instance_data.is_empty():
			slot_data.merge(instance_data, true)
		elif def.get("rarity", "common") != "common":
			slot_data["rarity"] = def.get("rarity", "common")
		slots.append(_normalize_slot(slot_data))
		appended += 1
		quantity -= place_qty
	if quantity > 0:
		for entry in bumped_stacks:
			var restore: Array = entry
			(slots[int(restore[0])] as Dictionary)["quantity"] = int(restore[1])
		for _i in appended:
			slots.pop_back()
		return false
	changed.emit()
	return true


## `runLoot` only says "at risk on this run"; it is bookkeeping, not part of what an item is.
static func _is_plain_instance_data(instance_data: Dictionary) -> bool:
	return instance_data.is_empty() or (instance_data.size() == 1 and instance_data.has("runLoot"))


const PLAIN_SLOT_KEYS: Array[String] = ["itemId", "quantity", "instanceId", "runLoot", "rarity"]


func _is_plain_slot(slot: Dictionary) -> bool:
	for key in slot:
		if str(key) not in PLAIN_SLOT_KEYS:
			return false
	var def := get_item_def(str(slot.get("itemId", "")))
	return str(slot.get("rarity", def.get("rarity", "common"))) == str(def.get("rarity", "common"))


## Folds same-item stacks that are interchangeable (same risk status, nothing rolled on them) back
## together, so a bag is not left with a pile of part-full stacks.
func consolidate_stacks() -> void:
	var merged := false
	var i := 0
	while i < slots.size():
		var slot: Dictionary = slots[i]
		var def := get_item_def(str(slot.get("itemId", "")))
		var max_stack: int = def.get("stackSize", 1)
		if max_stack > 1 and _is_plain_slot(slot):
			var j := i + 1
			while j < slots.size() and int(slot.get("quantity", 1)) < max_stack:
				var other: Dictionary = slots[j]
				if (
					other.get("itemId", "") == slot.get("itemId", "")
					and _is_plain_slot(other)
					and bool(other.get("runLoot", false)) == bool(slot.get("runLoot", false))
				):
					var moved := mini(int(other.get("quantity", 1)), max_stack - int(slot.get("quantity", 1)))
					slot["quantity"] = int(slot.get("quantity", 1)) + moved
					other["quantity"] = int(other.get("quantity", 1)) - moved
					merged = true
					if int(other.get("quantity", 1)) <= 0:
						remove_at(j)
						continue
				j += 1
		i += 1
	if merged:
		changed.emit()


func add_rolled_item(
	item_id: String, roll_seed: int = -1, run_mode: String = "", instance_data: Dictionary = {}
) -> bool:
	var roll_context: Dictionary = instance_data.get("rollContext", {})
	var instance := AffixRoller.roll_instance(item_id, roll_seed, "", run_mode, roll_context)
	if instance.is_empty():
		return false
	if not instance_data.is_empty():
		instance.merge(instance_data, true)
	return _place_rolled_instance(instance)


func add_rolled_item_with_rarity(item_id: String, rarity: String, roll_seed: int = -1) -> bool:
	var instance := AffixRoller.roll_instance(item_id, roll_seed, rarity, RunModeConfig.MODE_WAVES)
	if instance.is_empty():
		return false
	return _place_rolled_instance(instance)


func _place_rolled_instance(instance: Dictionary) -> bool:
	if not _has_room():
		return false
	slots.append(_normalize_slot(instance))
	changed.emit()
	return true


func remove_at(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	var removed: Dictionary = slots[index]
	slots.remove_at(index)
	changed.emit()
	return removed


## Drops the slot at `index` onto cell (`to_x`, `to_y`): it takes that place in the list and the
## slots between shift along. A cell past the last item means "the end".
func move_slot(index: int, to_x: int, to_y: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
	if to_x < 0 or to_y < 0 or to_x >= grid_width or to_y >= grid_height:
		return false
	var target := mini(to_y * grid_width + to_x, slots.size() - 1)
	if target == index:
		return true
	var slot: Dictionary = slots[index]
	slots.remove_at(index)
	slots.insert(target, slot)
	changed.emit()
	return true


func find_instance_index(instance_id: String) -> int:
	if instance_id == "":
		return -1
	for i in slots.size():
		if str(slots[i].get("instanceId", "")) == instance_id:
			return i
	return -1


func split_stack(index: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
	var slot: Dictionary = slots[index]
	var qty: int = int(slot.get("quantity", 1))
	if qty < 2:
		return false
	@warning_ignore("integer_division")
	var half := qty / 2
	slot["quantity"] = qty - half
	var new_slot: Dictionary = slot.duplicate(true)
	new_slot["quantity"] = half
	var item_id: String = str(slot.get("itemId", ""))
	new_slot["instanceId"] = mint_instance_id(item_id)
	if not _has_room():
		slot["quantity"] = qty
		return false
	slots.append(_normalize_slot(new_slot))
	changed.emit()
	return true


func find_slot_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= grid_width or y >= grid_height:
		return -1
	var index := y * grid_width + x
	return index if index < slots.size() else -1


func sort_slots(mode: String) -> void:
	match mode:
		"name":
			slots.sort_custom(
				func(a: Dictionary, b: Dictionary) -> bool:
					return get_slot_display_name(a) < get_slot_display_name(b)
			)
		"type":
			slots.sort_custom(
				func(a: Dictionary, b: Dictionary) -> bool:
					var da := get_item_def(a.get("itemId", ""))
					var db := get_item_def(b.get("itemId", ""))
					return da.get("itemType", "") < db.get("itemType", "")
			)
		"rarity":
			slots.sort_custom(
				func(a: Dictionary, b: Dictionary) -> bool:
					return _rarity_weight(get_slot_rarity(a)) > _rarity_weight(get_slot_rarity(b))
			)
		_:
			pass
	changed.emit()


func filter_slots(type_filter: String, rarity_filter: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for i in slots.size():
		var slot: Dictionary = slots[i]
		if not _passes_filter(slot, type_filter, rarity_filter):
			continue
		var copy := slot.duplicate()
		copy["_index"] = i
		filtered.append(copy)
	return filtered


func equip_from_index(index: int, slot_name: String = "") -> bool:
	if index < 0 or index >= slots.size():
		return false
	var slot: Dictionary = slots[index]
	var item_id: String = slot.get("itemId", "")
	var def := get_item_def(item_id)
	var target_slot := slot_name if slot_name != "" else EquipmentHelper.slot_for_item_def(def)
	if target_slot == "" or not EquipmentHelper.can_equip_in_slot(def, target_slot):
		return false
	if (
		target_slot == "weapon"
		and CharacterService
		and CharacterService.class_id != ""
		and not ClassCatalog.is_weapon_allowed(CharacterService.class_id, item_id)
	):
		return false
	var previous: Dictionary = equipped.get(target_slot, {})
	slots.remove_at(index)
	if not previous.is_empty():
		if not _return_equipped_to_grid(target_slot, index):
			slots.insert(index, slot)
			return false
	var instance := slot.duplicate()
	equipped[target_slot] = instance
	item_equipped.emit(item_id, target_slot)
	changed.emit()
	return true


func equip_weapon(index: int) -> bool:
	return equip_from_index(index, "weapon")


func unequip(slot_name: String) -> bool:
	if not equipped.has(slot_name):
		return false
	var instance: Dictionary = equipped.get(slot_name, {})
	if instance.is_empty():
		return false
	if not _has_room():
		return false
	slots.append(_normalize_slot(instance.duplicate()))
	equipped[slot_name] = {}
	item_unequipped.emit(slot_name)
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
	var inst: Dictionary = equipped.get("weapon", {})
	return inst.get("itemId", "")


func get_equipped_instance(slot_name: String) -> Dictionary:
	return equipped.get(slot_name, {}).duplicate()


func get_equipped_weapon_data_path() -> String:
	var item_id := get_equipped_weapon_id()
	if item_id == "":
		return "content/weapons/sword_basic.json"
	var def := get_item_def(item_id)
	var base_id := str(def.get("baseId", ""))
	if base_id in ["shortbow", "longbow"]:
		return "content/weapons/%s.json" % base_id
	var weapon_id: String = def.get("weaponId", "sword_basic")
	return "content/weapons/%s.json" % weapon_id


func strip_equipped_run_loot(item_id_set: Dictionary = {}) -> void:
	var stripped := false
	for slot_name in EquipmentHelper.SLOT_ORDER:
		var inst: Dictionary = equipped.get(slot_name, {})
		if inst.is_empty():
			continue
		var should_remove: bool = bool(inst.get("runLoot", false))
		if not should_remove:
			var equipped_id := str(inst.get("itemId", ""))
			if item_id_set.has(equipped_id):
				should_remove = true
		if not should_remove:
			continue
		equipped[slot_name] = {}
		item_unequipped.emit(slot_name)
		stripped = true
	if stripped:
		changed.emit()


func remove_items_by_id(item_id: String, quantity: int = 1) -> int:
	var removed := 0
	var i := slots.size() - 1
	while i >= 0 and removed < quantity:
		var slot: Dictionary = slots[i]
		if slot.get("itemId", "") != item_id:
			i -= 1
			continue
		var qty: int = slot.get("quantity", 1)
		if qty <= quantity - removed:
			removed += qty
			slots.remove_at(i)
		else:
			slot["quantity"] = qty - (quantity - removed)
			removed = quantity
		i -= 1
	if removed > 0:
		changed.emit()
	return removed


func count_by_id(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if slot.get("itemId", "") == item_id:
			total += int(slot.get("quantity", 1))
	return total


func find_slots_where(predicate: Callable) -> Array[int]:
	var found: Array[int] = []
	for i in slots.size():
		if predicate.call(slots[i]):
			found.append(i)
	return found


func remove_all_where(predicate: Callable) -> int:
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):
		if not predicate.call(slots[i]):
			continue
		slots.remove_at(i)
		removed += 1
	if removed > 0:
		changed.emit()
	return removed


func remove_one_where(predicate: Callable) -> bool:
	var indices := find_slots_where(predicate)
	if indices.is_empty():
		return false
	var index: int = indices[-1]
	var slot: Dictionary = slots[index]
	var qty: int = int(slot.get("quantity", 1)) - 1
	if qty <= 0:
		slots.remove_at(index)
	else:
		slot["quantity"] = qty
	changed.emit()
	return true


func _normalize_slot(slot: Dictionary) -> Dictionary:
	if slot.has("quantity"):
		slot["quantity"] = int(slot.get("quantity", 1))
	slot.erase("x")
	slot.erase("y")
	if slot.has("rollSeed"):
		slot["rollSeed"] = int(slot.get("rollSeed", 0))
	if not slot.has("instanceId"):
		var item_id: String = slot.get("itemId", "")
		slot["instanceId"] = mint_instance_id(item_id)
	return slot


func _serialize_equipped() -> Dictionary:
	var out: Dictionary = {}
	for slot_name in EquipmentHelper.SLOT_ORDER:
		var inst: Dictionary = equipped.get(slot_name, {})
		out[slot_name] = inst.duplicate() if not inst.is_empty() else {}
	return out


func _deserialize_equipped(data: Variant) -> void:
	equipped = EquipmentHelper.empty_equipped()
	if not data is Dictionary:
		return
	if data.has("weapon") and data["weapon"] is String:
		var legacy_id: String = data["weapon"]
		if legacy_id != "":
			equipped["weapon"] = {"itemId": legacy_id, "quantity": 1}
	for slot_name in EquipmentHelper.SLOT_ORDER:
		var inst: Variant = data.get(slot_name, {})
		if inst is String:
			continue
		if inst is Dictionary and not inst.is_empty():
			equipped[slot_name] = _normalize_slot(inst.duplicate())


func _return_equipped_to_grid(slot_name: String, at: int = -1) -> bool:
	var instance: Dictionary = equipped.get(slot_name, {})
	if instance.is_empty():
		return true
	if not _has_room():
		return false
	var returned := _normalize_slot(instance.duplicate())
	if at >= 0:
		slots.insert(mini(at, slots.size()), returned)
	else:
		slots.append(returned)
	equipped[slot_name] = {}
	return true


func _passes_filter(slot: Dictionary, type_filter: String, rarity_filter: String) -> bool:
	var def := get_item_def(slot.get("itemId", ""))
	if type_filter != "all":
		var item_type: String = def.get("itemType", "")
		match type_filter:
			"weapon":
				if item_type != "weapon":
					return false
			"armor":
				if item_type != "armor":
					return false
			"accessory":
				if item_type != "accessory":
					return false
			"consumable":
				if item_type != "consumable":
					return false
			"material":
				if item_type != "material":
					return false
	if rarity_filter != "all":
		if get_slot_rarity(slot) != rarity_filter:
			return false
	return true


func _rarity_weight(rarity: String) -> int:
	match rarity:
		"aumbral":
			return 6
		"legendary":
			return 5
		"epic":
			return 4
		"rare":
			return 3
		"magic":
			return 2
		"common":
			return 1
		_:
			return 0
