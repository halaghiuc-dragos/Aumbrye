extends "res://scripts/validation/validation_suite.gd"

const EquipmentScript := preload("res://scripts/items/equipment.gd")
const AffixRollerScript := preload("res://scripts/loot/affix_roller.gd")


func get_category() -> String:
	return "inventory"


func run() -> void:
	_test_m2_basics()
	_test_equipment_slots()
	_test_sort_filter()
	_test_affix_roller()
	_test_compare_stats()
	_test_move_slot()


func _test_m2_basics() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new()
	var placed := grid.add_item("castle_sword", 1)
	ctx.timed_record(
		"inventory.castle_sword_grid",
		get_category(),
		placed,
		"castle_sword places in grid inventory",
		start,
		"M2.inventory.grid"
	)

	start = Time.get_ticks_msec()
	var potion_placed := grid.add_item("health_potion", 2)
	ctx.timed_record(
		"inventory.health_potion_stack",
		get_category(),
		potion_placed,
		"health_potion stacks in grid inventory",
		start,
		"M2.inventory.grid"
	)

	start = Time.get_ticks_msec()
	var can_equip := grid.equip_weapon(0)
	ctx.timed_record(
		"inventory.equip_weapon",
		get_category(),
		can_equip,
		"castle_sword equips from grid slot 0",
		start,
		"M2.inventory.equip"
	)


func _test_equipment_slots() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new()
	grid.add_item("castle_helm", 1)
	var idx := grid.find_slot_at(0, 0)
	var equipped := grid.equip_from_index(idx, "helmet")
	ctx.timed_record(
		"inventory.equip_helmet_slot",
		get_category(),
		equipped and not grid.equipped.get("helmet", {}).is_empty(),
		"castle_helm equips to helmet slot",
		start,
		"M4.inventory.equip_slots"
	)

	start = Time.get_ticks_msec()
	var has_all_slots: bool = EquipmentScript.SLOT_ORDER.size() >= 9
	ctx.timed_record(
		"inventory.all_ea_slots",
		get_category(),
		has_all_slots,
		"Equipment defines full EA slot list",
		start,
		"M4.inventory.equip_slots"
	)


func _test_sort_filter() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new()
	grid.add_item("health_potion", 1)
	grid.add_item("castle_sword", 1)
	grid.sort_slots("name")
	var first_id: String = grid.slots[0].get("itemId", "") if grid.slots.size() > 0 else ""
	ctx.timed_record(
		"inventory.sort_by_name",
		get_category(),
		first_id == "castle_sword",
		"sort by name orders castle_sword first",
		start,
		"M4.inventory.sort"
	)

	start = Time.get_ticks_msec()
	var filtered := grid.filter_slots("consumable", "all")
	ctx.timed_record(
		"inventory.filter_consumable",
		get_category(),
		filtered.size() == 1 and filtered[0].get("itemId", "") == "health_potion",
		"filter by consumable type",
		start,
		"M4.inventory.filter"
	)


func _test_affix_roller() -> void:
	var start := Time.get_ticks_msec()
	var roll_a: Dictionary = AffixRollerScript.roll_identical("castle_sword", 12345)
	var roll_b: Dictionary = AffixRollerScript.roll_identical("castle_sword", 12345)
	var same: bool = roll_a.get("rarity", "") == roll_b.get("rarity", "")
	if roll_a.has("affixes") and roll_b.has("affixes"):
		same = same and str(roll_a.get("affixes", [])) == str(roll_b.get("affixes", []))
	ctx.timed_record(
		"inventory.affix_seed_deterministic",
		get_category(),
		same,
		"identical rollSeed yields identical affixes",
		start,
		"M4.inventory.affix"
	)


func _test_compare_stats() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new()
	grid.add_item("castle_plate", 1)
	var idx := grid.find_slot_at(0, 0)
	var slot: Dictionary = grid.slots[idx] if idx >= 0 else {}
	var delta: Dictionary = EquipmentScript.compare_stats(
		grid.equipped,
		slot,
		Callable(AffixRollerScript, "get_affix_stat")
	)
	var has_def: bool = delta.get("defense", 0.0) > 0.0
	ctx.timed_record(
		"inventory.compare_defense_delta",
		get_category(),
		has_def,
		"compare shows positive defense delta for plate",
		start,
		"M4.inventory.compare"
	)


func _test_move_slot() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new()
	grid.add_item("health_potion", 1)
	var moved := grid.move_slot(0, 2, 1)
	var slot: Dictionary = grid.slots[0] if grid.slots.size() > 0 else {}
	ctx.timed_record(
		"inventory.move_slot",
		get_category(),
		moved and slot.get("x", -1) == 2 and slot.get("y", -1) == 1,
		"move_slot relocates item in grid",
		start,
		"M4.inventory.drag"
	)
