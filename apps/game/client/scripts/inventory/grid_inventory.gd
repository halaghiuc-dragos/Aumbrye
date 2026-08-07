extends RefCounted
class_name GridInventory

const EquipmentHelper := preload("res://scripts/items/equipment.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")

const DEFAULT_WIDTH := 6
const DEFAULT_HEIGHT := 4

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

## Occupancy bitmap: one entry per grid cell holding the `slots` index occupying it (-1 if
## empty). `_occupancy_dirty` is set by any mutation whose effect on the bitmap is cheaper to
## re-derive lazily than to track precisely (removals shift every later slot's index). Pure
## appends update the bitmap incrementally instead, since appending never invalidates an
## existing index.
var _occupancy: PackedInt32Array = []
var _occupancy_dirty := true

## BUG-18: single non-colliding source of instance ids, shared by every site that used to mint
## its own — _normalize_slot (was `item_id_(x+y)`, which two stacks at (0,2) and (2,0) both
## produce) and split_stack (was a millisecond timestamp, which two splits in the same
## millisecond both produce). AffixRoller uses the same helper for naturally rolled drops.
static var _next_instance_ordinal := 1


static func mint_instance_id(item_id: String) -> String:
	_next_instance_ordinal += 1
	return "%s#%d" % [item_id, _next_instance_ordinal]


## Restores the high-water mark from a save so newly minted ids cannot collide with ids already
## on disk from a prior session.
static func seed_instance_ordinal(high_water: int) -> void:
	_next_instance_ordinal = maxi(_next_instance_ordinal, high_water)


func _init(width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> void:
	grid_width = width
	grid_height = height
	equipped = EquipmentHelper.empty_equipped()
	_occupancy_dirty = true


func _cell_index(x: int, y: int) -> int:
	return y * grid_width + x


func _mark_occupancy_dirty() -> void:
	_occupancy_dirty = true


func _ensure_occupancy() -> void:
	if not _occupancy_dirty and _occupancy.size() == grid_width * grid_height:
		return
	_occupancy = PackedInt32Array()
	_occupancy.resize(grid_width * grid_height)
	_occupancy.fill(-1)
	for i in slots.size():
		_occupy_slot_rect(i)
	_occupancy_dirty = false


func _occupy_slot_rect(index: int) -> void:
	if index < 0 or index >= slots.size() or _occupancy.size() != grid_width * grid_height:
		return
	var slot: Dictionary = slots[index]
	var def := get_item_def(slot.get("itemId", ""))
	if def.is_empty():
		return
	var x: int = int(slot.get("x", 0))
	var y: int = int(slot.get("y", 0))
	var w: int = def.get("gridWidth", 1)
	var h: int = def.get("gridHeight", 1)
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx >= 0 and xx < grid_width and yy >= 0 and yy < grid_height:
				_occupancy[_cell_index(xx, yy)] = index


func _free_rect(x: int, y: int, w: int, h: int) -> void:
	if _occupancy.size() != grid_width * grid_height:
		return
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx >= 0 and xx < grid_width and yy >= 0 and yy < grid_height:
				_occupancy[_cell_index(xx, yy)] = -1


func to_save_dict() -> Dictionary:
	return {
		"schemaVersion": 1,
		"gridWidth": grid_width,
		"gridHeight": grid_height,
		"slots": slots.duplicate(true),
		"equipped": _serialize_equipped(),
	}


func from_save_dict(data: Dictionary) -> void:
	grid_width = int(data.get("gridWidth", DEFAULT_WIDTH))
	grid_height = int(data.get("gridHeight", DEFAULT_HEIGHT))
	slots.clear()
	for entry in data.get("slots", []):
		if entry is Dictionary:
			slots.append(_normalize_slot(entry.duplicate()))
	_deserialize_equipped(data.get("equipped", {}))
	_mark_occupancy_dirty()
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
	var name: String = def.get("name", slot.get("itemId", "?"))
	var rarity: String = get_slot_rarity(slot)
	if rarity != "common" and rarity != "":
		return "[%s] %s" % [RarityRegistryScript.display_name(rarity), name]
	return name


func can_place(item_id: String, x: int, y: int, ignore_index: int = -1) -> bool:
	var def := get_item_def(item_id)
	if def.is_empty():
		return false
	var w: int = def.get("gridWidth", 1)
	var h: int = def.get("gridHeight", 1)
	if x < 0 or y < 0 or x + w > grid_width or y + h > grid_height:
		return false
	_ensure_occupancy()
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			var occupant := _occupancy[_cell_index(xx, yy)]
			if occupant != -1 and occupant != ignore_index:
				return false
	return true


func add_slot(slot: Dictionary) -> bool:
	var item_id: String = slot.get("itemId", "")
	if item_id == "" or get_item_def(item_id).is_empty():
		return false
	var pos := _find_first_fit(item_id)
	if pos.x < 0:
		return false
	var copy := slot.duplicate(true)
	copy["x"] = pos.x
	copy["y"] = pos.y
	slots.append(_normalize_slot(copy))
	_occupy_slot_rect(slots.size() - 1)
	changed.emit()
	return true


func has_space_for(item_id: String) -> bool:
	return _find_first_fit(item_id).x >= 0


func remove_quantity_at(index: int, quantity: int) -> Dictionary:
	if index < 0 or index >= slots.size() or quantity <= 0:
		return {}
	var slot: Dictionary = slots[index]
	var slot_qty := maxi(1, int(slot.get("quantity", 1)))
	if quantity >= slot_qty:
		return remove_at(index)
	slot["quantity"] = slot_qty - quantity
	changed.emit()
	return slot.duplicate(true)


func add_item(item_id: String, quantity: int = 1, instance_data: Dictionary = {}) -> bool:
	var def := get_item_def(item_id)
	if def.is_empty():
		return false
	# BUG-16: snapshot before mutating. The stacking pre-pass and the grid-placement pass both
	# mutate `slots` directly; a stack that only partially fits used to leave that partial
	# mutation in place while still returning false and skipping `changed` — the player was told
	# the pickup failed while the items were, in fact, already in the grid.
	var snapshot: Array[Dictionary] = []
	for existing_slot in slots:
		snapshot.append(existing_slot.duplicate(true))
	var max_stack: int = def.get("stackSize", 1)
	if max_stack > 1 and instance_data.is_empty():
		for i in slots.size():
			var slot: Dictionary = slots[i]
			if slot.get("itemId", "") != item_id:
				continue
			if slot.has("affixes") and not slot.get("affixes", []).is_empty():
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
	while quantity > 0:
		var pos := _find_first_fit(item_id)
		if pos.x < 0:
			break
		var place_qty := mini(quantity, max_stack)
		var slot_data := {
			"itemId": item_id,
			"quantity": place_qty,
			"x": pos.x,
			"y": pos.y,
		}
		if not instance_data.is_empty():
			slot_data.merge(instance_data, true)
		elif def.get("rarity", "common") != "common":
			slot_data["rarity"] = def.get("rarity", "common")
		slots.append(_normalize_slot(slot_data))
		_occupy_slot_rect(slots.size() - 1)
		quantity -= place_qty
	if quantity > 0:
		slots = snapshot
		_mark_occupancy_dirty()
		return false
	changed.emit()
	return true


func add_rolled_item(
	item_id: String, roll_seed: int = -1, run_mode: String = "", instance_data: Dictionary = {}
) -> bool:
	var instance := AffixRoller.roll_instance(item_id, roll_seed, "", run_mode)
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
	var item_id: String = str(instance.get("itemId", ""))
	var x_y := _find_first_fit(item_id)
	if x_y.x < 0:
		return false
	instance["x"] = x_y.x
	instance["y"] = x_y.y
	slots.append(_normalize_slot(instance))
	_occupy_slot_rect(slots.size() - 1)
	changed.emit()
	return true


func remove_at(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	var removed: Dictionary = slots[index]
	slots.remove_at(index)
	_mark_occupancy_dirty()
	changed.emit()
	return removed


func move_slot(index: int, to_x: int, to_y: int) -> bool:
	if index < 0 or index >= slots.size():
		return false
	var slot: Dictionary = slots[index]
	var item_id: String = slot.get("itemId", "")
	if not can_place(item_id, to_x, to_y, index):
		return false
	var def := get_item_def(item_id)
	var w: int = def.get("gridWidth", 1)
	var h: int = def.get("gridHeight", 1)
	_free_rect(int(slot.get("x", 0)), int(slot.get("y", 0)), w, h)
	slot["x"] = to_x
	slot["y"] = to_y
	_occupy_slot_rect(index)
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
	var half := qty / 2
	slot["quantity"] = qty - half
	var new_slot: Dictionary = slot.duplicate(true)
	new_slot["quantity"] = half
	var item_id: String = str(slot.get("itemId", ""))
	new_slot["instanceId"] = mint_instance_id(item_id)
	var pos := _find_first_fit(item_id)
	if pos.x < 0:
		slot["quantity"] = qty
		return false
	new_slot["x"] = pos.x
	new_slot["y"] = pos.y
	slots.append(_normalize_slot(new_slot))
	_occupy_slot_rect(slots.size() - 1)
	changed.emit()
	return true


func find_slot_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= grid_width or y >= grid_height:
		return -1
	_ensure_occupancy()
	return _occupancy[_cell_index(x, y)]


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
	_repack_slots()
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


## BUG-17: free the incoming item's cells *before* the outgoing item looks for space. A
## same-size-or-smaller swap is space-neutral overall, but the old order called
## _return_equipped_to_grid() (which runs _find_first_fit()) while the incoming item was still
## occupying its own cells — so a full grid refused a swap that should always have succeeded,
## because the outgoing item was never given the room the incoming item was about to vacate.
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
	_mark_occupancy_dirty()
	if not previous.is_empty():
		if not _return_equipped_to_grid(target_slot):
			slots.insert(index, slot)
			_mark_occupancy_dirty()
			return false
	var instance := slot.duplicate()
	instance.erase("x")
	instance.erase("y")
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
	var item_id: String = instance.get("itemId", "")
	var pos := _find_first_fit(item_id)
	if pos.x < 0:
		return false
	var grid_slot := instance.duplicate()
	grid_slot["x"] = pos.x
	grid_slot["y"] = pos.y
	slots.append(_normalize_slot(grid_slot))
	_occupy_slot_rect(slots.size() - 1)
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
		_mark_occupancy_dirty()
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
			_mark_occupancy_dirty()
		else:
			slot["quantity"] = qty - (quantity - removed)
			removed = quantity
		i -= 1
	if removed > 0:
		changed.emit()
	return removed


func _normalize_slot(slot: Dictionary) -> Dictionary:
	if slot.has("quantity"):
		slot["quantity"] = int(slot.get("quantity", 1))
	if slot.has("x"):
		slot["x"] = int(slot.get("x", 0))
	if slot.has("y"):
		slot["y"] = int(slot.get("y", 0))
	if slot.has("rollSeed"):
		slot["rollSeed"] = int(slot.get("rollSeed", 0))
	if not slot.has("instanceId"):
		# BUG-18: was `item_id_(x+y)`, which collides for any two same-named stacks whose grid
		# coordinates sum to the same value (e.g. (0,2) and (2,0)) — a monotonic mint cannot.
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


func _return_equipped_to_grid(slot_name: String) -> bool:
	var instance: Dictionary = equipped.get(slot_name, {})
	if instance.is_empty():
		return true
	var item_id: String = instance.get("itemId", "")
	var pos := _find_first_fit(item_id)
	if pos.x < 0:
		return false
	var grid_slot := instance.duplicate()
	grid_slot["x"] = pos.x
	grid_slot["y"] = pos.y
	slots.append(_normalize_slot(grid_slot))
	_occupy_slot_rect(slots.size() - 1)
	equipped[slot_name] = {}
	return true


func _find_first_fit(item_id: String) -> Vector2i:
	for y in grid_height:
		for x in grid_width:
			if can_place(item_id, x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## BUG-16 (repack variant): a sort must never delete items. `_find_first_fit` is a greedy
## placement and a different sort order can fragment the grid enough that not everything fits
## even though the total occupied area is unchanged — the old code silently dropped whatever
## didn't fit. Abort and restore the pre-sort layout instead.
func _repack_slots() -> void:
	var original: Array[Dictionary] = []
	for slot in slots:
		original.append(slot.duplicate(true))
	var packed: Array[Dictionary] = []
	for slot in slots:
		packed.append(slot.duplicate())
	slots.clear()
	_mark_occupancy_dirty()
	for slot in packed:
		var item_id: String = slot.get("itemId", "")
		var pos := _find_first_fit(item_id)
		if pos.x < 0:
			slots = original
			_mark_occupancy_dirty()
			return
		slot["x"] = pos.x
		slot["y"] = pos.y
		slots.append(slot)
		_occupy_slot_rect(slots.size() - 1)


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
