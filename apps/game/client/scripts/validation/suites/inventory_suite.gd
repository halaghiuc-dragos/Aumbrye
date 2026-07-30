extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "inventory"


func run() -> void:
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
