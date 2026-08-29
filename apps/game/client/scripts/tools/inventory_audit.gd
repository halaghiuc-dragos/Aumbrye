extends Node

## Exercises the grid inventory and the equip/unequip path, checking the invariants
## that have to hold no matter what the player does:
##
##   - no two items ever occupy the same cell, and nothing sits outside the grid
##   - the occupancy index agrees with the slot list
##   - items are neither duplicated nor destroyed by equipping, swapping or unequipping
##   - a save/load round trip returns the same inventory
##
## Diagnostic, not a test suite: run it when you want an answer about the inventory.

const EquipmentHelper := preload("res://scripts/items/equipment.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_check_invariants_under_churn()
	_check_equip_unequip_conserves_items()
	_check_swap_conserves_items()
	_check_unequip_into_full_grid()
	_check_save_round_trip()
	_check_equip_from_stack()
	_check_stat_symmetry()
	_check_swap_stat_symmetry()

	print(
		"INVENTORY exercised %d equipment ids, %d slots, %d churn steps"
		% [_equipment_ids().size(), EquipmentHelper.SLOT_ORDER.size(), 4000]
	)
	if _failures.is_empty():
		print("INVENTORY RESULT 0 failures")
	else:
		print("INVENTORY RESULT %d failures" % _failures.size())
		for line in _failures:
			print("  " + line)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _fail(message: String) -> void:
	_failures.append(message)


# --- helpers ---------------------------------------------------------------------


func _equipment_ids() -> Array[String]:
	var out: Array[String] = []
	for item_id in ItemCatalog.get_items_by_type("armor"):
		out.append(item_id)
	for item_id in ItemCatalog.get_items_by_type("weapon"):
		out.append(item_id)
	for item_id in ItemCatalog.get_items_by_type("accessory"):
		out.append(item_id)
	out.sort()
	return out


## Total of every item held, in the grid and worn, counted by stack quantity.
func _total_items(inv: GridInventory) -> int:
	var total := 0
	for slot in inv.slots:
		total += int(slot.get("quantity", 1))
	for slot_name in EquipmentHelper.SLOT_ORDER:
		var instance: Dictionary = inv.equipped.get(slot_name, {})
		if not instance.is_empty():
			total += int(instance.get("quantity", 1))
	return total


## Re-derive occupancy from the slot list and report any collision or stray cell.
func _check_grid(inv: GridInventory, context: String) -> void:
	var seen: Dictionary = {}
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		var def := ItemCatalog.get_definition(slot.get("itemId", ""))
		if def.is_empty():
			_fail("%s: slot %d has unknown item '%s'" % [context, i, slot.get("itemId", "")])
			continue
		var x: int = int(slot.get("x", 0))
		var y: int = int(slot.get("y", 0))
		var w: int = int(def.get("gridWidth", 1))
		var h: int = int(def.get("gridHeight", 1))
		if x < 0 or y < 0 or x + w > inv.grid_width or y + h > inv.grid_height:
			_fail(
				"%s: %s at (%d,%d) size %dx%d is outside the %dx%d grid"
				% [context, slot.get("itemId", ""), x, y, w, h, inv.grid_width, inv.grid_height]
			)
			continue
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				var key := yy * inv.grid_width + xx
				if seen.has(key):
					_fail(
						"%s: %s at (%d,%d) overlaps %s at cell (%d,%d)"
						% [context, slot.get("itemId", ""), x, y, seen[key], xx, yy]
					)
					return
				seen[key] = slot.get("itemId", "")


# --- checks ----------------------------------------------------------------------


## Add, move, equip, unequip and drop at random for a long while, checking the grid
## after every operation. Most inventory corruption only shows up after churn.
func _check_invariants_under_churn() -> void:
	var ids := _equipment_ids()
	if ids.is_empty():
		_fail("churn: no equipment in the catalog")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654
	var inv := GridInventory.new()

	for step in 4000:
		match rng.randi() % 5:
			0:
				inv.add_item(ids[rng.randi() % ids.size()], 1)
			1:
				if not inv.slots.is_empty():
					inv.equip_from_index(rng.randi() % inv.slots.size())
			2:
				var slot_name: String = EquipmentHelper.SLOT_ORDER[
					rng.randi() % EquipmentHelper.SLOT_ORDER.size()
				]
				inv.unequip(slot_name)
			3:
				if not inv.slots.is_empty():
					inv.move_slot(
						rng.randi() % inv.slots.size(),
						rng.randi() % inv.grid_width,
						rng.randi() % inv.grid_height
					)
			_:
				if not inv.slots.is_empty():
					inv.remove_at(rng.randi() % inv.slots.size())
		if not _failures.is_empty():
			return
		_check_grid(inv, "churn step %d" % step)
		if not _failures.is_empty():
			return


## Equipping then unequipping must leave exactly what we started with.
func _check_equip_unequip_conserves_items() -> void:
	var ids := _equipment_ids()
	for item_id in ids:
		var inv := GridInventory.new()
		if not inv.add_item(item_id, 1):
			continue
		var before := _total_items(inv)
		var slot_name := EquipmentHelper.slot_for_item_def(ItemCatalog.get_definition(item_id))
		if slot_name == "":
			continue
		if not inv.equip_from_index(0, slot_name):
			continue
		if _total_items(inv) != before:
			_fail(
				"equip %s: item count went %d -> %d"
				% [item_id, before, _total_items(inv)]
			)
			return
		if not inv.unequip(slot_name):
			_fail("unequip %s: refused with an empty grid" % item_id)
			return
		if _total_items(inv) != before:
			_fail(
				"unequip %s: item count went %d -> %d"
				% [item_id, before, _total_items(inv)]
			)
			return
		_check_grid(inv, "equip round trip %s" % item_id)
		if not _failures.is_empty():
			return


## Equipping over an already-worn item must put the old one back in the grid --
## exactly once, and without losing the new one.
func _check_swap_conserves_items() -> void:
	var by_slot: Dictionary = {}
	for item_id in _equipment_ids():
		var slot_name := EquipmentHelper.slot_for_item_def(ItemCatalog.get_definition(item_id))
		if slot_name == "":
			continue
		if not by_slot.has(slot_name):
			by_slot[slot_name] = []
		(by_slot[slot_name] as Array).append(item_id)

	for slot_name in by_slot:
		var pair: Array = by_slot[slot_name]
		if pair.size() < 2:
			continue
		var first: String = pair[0]
		var second: String = pair[1]
		var inv := GridInventory.new()
		if not inv.add_item(first, 1) or not inv.add_item(second, 1):
			continue
		var before := _total_items(inv)
		if not inv.equip_from_index(0, slot_name):
			continue
		# Now equip the other one over the top; the first should come back to the grid.
		var index := -1
		for i in inv.slots.size():
			if inv.slots[i].get("itemId", "") == second:
				index = i
				break
		if index < 0:
			continue
		if not inv.equip_from_index(index, slot_name):
			continue
		if _total_items(inv) != before:
			_fail(
				"swap in %s (%s over %s): item count went %d -> %d"
				% [slot_name, second, first, before, _total_items(inv)]
			)
			return
		var worn: Dictionary = inv.equipped.get(slot_name, {})
		if worn.get("itemId", "") != second:
			_fail(
				"swap in %s: expected %s worn, found '%s'"
				% [slot_name, second, worn.get("itemId", "")]
			)
			return
		var back := false
		for slot in inv.slots:
			if slot.get("itemId", "") == first:
				back = true
		if not back:
			_fail("swap in %s: %s did not come back to the grid" % [slot_name, first])
			return
		_check_grid(inv, "swap %s" % slot_name)
		if not _failures.is_empty():
			return


## Unequipping with no room must not destroy the worn item.
func _check_unequip_into_full_grid() -> void:
	var inv := GridInventory.new(2, 2)
	var ids := _equipment_ids()
	var chosen := ""
	for item_id in ids:
		var def := ItemCatalog.get_definition(item_id)
		if int(def.get("gridWidth", 1)) == 1 and int(def.get("gridHeight", 1)) == 1:
			if EquipmentHelper.slot_for_item_def(def) != "":
				chosen = item_id
				break
	if chosen == "":
		return
	var slot_name := EquipmentHelper.slot_for_item_def(ItemCatalog.get_definition(chosen))
	inv.add_item(chosen, 1)
	if not inv.equip_from_index(0, slot_name):
		return
	# Fill every cell so the worn item has nowhere to return to.
	while inv.add_item(chosen, 1):
		pass
	var before := _total_items(inv)
	var ok := inv.unequip(slot_name)
	if ok:
		_fail("unequip into a full grid reported success")
	if _total_items(inv) != before:
		_fail(
			"unequip into a full grid changed the item count %d -> %d"
			% [before, _total_items(inv)]
		)
	if inv.equipped.get(slot_name, {}).is_empty():
		_fail("unequip into a full grid dropped the worn item")
	_check_grid(inv, "full grid unequip")


func _check_save_round_trip() -> void:
	var ids := _equipment_ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var inv := GridInventory.new()
	for i in 14:
		inv.add_item(ids[rng.randi() % ids.size()], 1)
	for i in 4:
		if not inv.slots.is_empty():
			inv.equip_from_index(rng.randi() % inv.slots.size())

	var saved := inv.to_save_dict()
	var restored := GridInventory.new()
	restored.from_save_dict(saved)

	if restored.slots.size() != inv.slots.size():
		_fail(
			"save round trip: %d slots became %d"
			% [inv.slots.size(), restored.slots.size()]
		)
		return
	if _total_items(restored) != _total_items(inv):
		_fail(
			"save round trip: item count %d became %d"
			% [_total_items(inv), _total_items(restored)]
		)
		return
	for slot_name in EquipmentHelper.SLOT_ORDER:
		var a: Dictionary = inv.equipped.get(slot_name, {})
		var b: Dictionary = restored.equipped.get(slot_name, {})
		if a.get("itemId", "") != b.get("itemId", ""):
			_fail(
				"save round trip: %s was '%s', restored as '%s'"
				% [slot_name, a.get("itemId", ""), b.get("itemId", "")]
			)
			return
	_check_grid(restored, "save round trip")


## Equipping one item out of a stack must not swallow the rest of the stack.
func _check_equip_from_stack() -> void:
	var stackable := ""
	for item_id in _equipment_ids():
		if int(ItemCatalog.get_definition(item_id).get("stackSize", 1)) > 1:
			stackable = item_id
			break
	if stackable == "":
		return
	var inv := GridInventory.new()
	inv.add_item(stackable, 3)
	var before := _total_items(inv)
	var slot_name := EquipmentHelper.slot_for_item_def(ItemCatalog.get_definition(stackable))
	if slot_name == "" or not inv.equip_from_index(0, slot_name):
		return
	if _total_items(inv) != before:
		_fail(
			"equipping from a stack of %s: item count went %d -> %d"
			% [stackable, before, _total_items(inv)]
		)
	_check_grid(inv, "equip from stack")


## Equipping an item then taking it off again must leave every stat exactly where it
## started. A stat that drifts is the sort of thing that reads in play as "armour is
## doing something odd on equip/unequip".
func _check_stat_symmetry() -> void:
	var resolver := Callable(AffixRoller, "get_affix_stat")
	for item_id in _equipment_ids():
		var def := ItemCatalog.get_definition(item_id)
		var slot_name := EquipmentHelper.slot_for_item_def(def)
		if slot_name == "":
			continue
		var inv := GridInventory.new()
		if not inv.add_item(item_id, 1):
			continue
		var baseline := EquipmentHelper.aggregate_stats(inv.equipped, resolver)
		if not inv.equip_from_index(0, slot_name):
			continue
		if not inv.unequip(slot_name):
			continue
		var after := EquipmentHelper.aggregate_stats(inv.equipped, resolver)
		var drift := _stat_drift(baseline, after)
		if drift != "":
			_fail("stat symmetry %s: %s" % [item_id, drift])
			return


## Swapping B over A, then taking B off, must leave the same stats as never having
## equipped anything.
func _check_swap_stat_symmetry() -> void:
	var resolver := Callable(AffixRoller, "get_affix_stat")
	var by_slot: Dictionary = {}
	for item_id in _equipment_ids():
		var slot_name := EquipmentHelper.slot_for_item_def(ItemCatalog.get_definition(item_id))
		if slot_name == "":
			continue
		if not by_slot.has(slot_name):
			by_slot[slot_name] = []
		(by_slot[slot_name] as Array).append(item_id)

	for slot_name in by_slot:
		var pair: Array = by_slot[slot_name]
		if pair.size() < 2:
			continue
		var inv := GridInventory.new()
		if not inv.add_item(pair[0], 1) or not inv.add_item(pair[1], 1):
			continue
		var baseline := EquipmentHelper.aggregate_stats(inv.equipped, resolver)
		if not inv.equip_from_index(0, slot_name):
			continue
		var index := -1
		for i in inv.slots.size():
			if inv.slots[i].get("itemId", "") == pair[1]:
				index = i
				break
		if index < 0 or not inv.equip_from_index(index, slot_name):
			continue
		if not inv.unequip(slot_name):
			continue
		var after := EquipmentHelper.aggregate_stats(inv.equipped, resolver)
		var drift := _stat_drift(baseline, after)
		if drift != "":
			_fail("swap stat symmetry in %s: %s" % [slot_name, drift])
			return


func _stat_drift(before: Dictionary, after: Dictionary) -> String:
	var keys: Dictionary = {}
	for k in before:
		keys[k] = true
	for k in after:
		keys[k] = true
	for k in keys:
		var a := float(before.get(k, 0.0))
		var b := float(after.get(k, 0.0))
		if absf(a - b) > 0.0001:
			return "%s went %.3f -> %.3f" % [k, a, b]
	return ""
