extends "res://scripts/validation/validation_suite.gd"

const EquipmentScript := preload("res://scripts/items/equipment.gd")
const AffixRollerScript := preload("res://scripts/loot/affix_roller.gd")
const ItemIconAtlasScript := preload("res://scripts/ui/item_icon_atlas.gd")
const LootTableLoaderScript := preload("res://scripts/loot/loot_table_loader.gd")

var _inventory_reject_seen := false


func _capture_inventory_rejected(_reason: String) -> void:
	_inventory_reject_seen = true


func get_category() -> String:
	return "inventory"


func run() -> void:
	_test_m2_basics()
	_test_equipment_slots()
	_test_sort_filter()
	_test_affix_roller()
	_test_add_loot()
	_test_elemental_affix_damage()
	_test_compare_stats()
	_test_move_slot()
	_test_inventory_ui_icons()
	_test_add_loot_pipeline()
	_test_add_item_is_transactional()
	_test_equip_swap_when_grid_full()
	await _test_inventory_change_does_not_heal_player()


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

	start = Time.get_ticks_msec()
	var legendary_roll: Dictionary = AffixRollerScript.roll_instance(
		"iron_sword", 99991, "legendary"
	)
	var tier_ok := true
	for entry in legendary_roll.get("affixes", []):
		if not entry is Dictionary:
			continue
		var affix_id := str(entry.get("affixId", ""))
		var value := float(entry.get("value", 0.0))
		var tier := _affix_tier_bounds(affix_id, "legendary")
		if tier.is_empty():
			continue
		if value < float(tier.get("min", 0.0)) or value > float(tier.get("max", 0.0)):
			tier_ok = false
			break
	ctx.timed_record(
		"inventory.affix_tier_values",
		get_category(),
		legendary_roll.get("rarity", "") == "legendary" and tier_ok,
		"forced legendary iron_sword affix values fall inside tiers.legendary",
		start,
		"M4.inventory.affix"
	)

	start = Time.get_ticks_msec()
	var uses_tiers: bool = ctx.script_has_method("res://scripts/loot/affix_roller.gd", "_roll_tier_value")
	ctx.timed_record(
		"inventory.affix_respects_tiers",
		get_category(),
		uses_tiers,
		"AffixRoller rolls values from content tiers",
		start,
		"M4.inventory.affix"
	)


func _test_add_loot() -> void:
	var start := Time.get_ticks_msec()
	var added := false
	if _should_roll_loot_for_test("castle_sword"):
		var instance := AffixRollerScript.roll_instance("castle_sword", 424242)
		added = not instance.is_empty() and instance.has("affixes")
	ctx.timed_record(
		"inventory.add_loot.rolls_equipment",
		get_category(),
		added,
		"equipment loot rolls affix-capable instances",
		start,
		"LOO-02"
	)

	start = Time.get_ticks_msec()
	var external: Dictionary = LootTableLoaderScript.load_for_biome("forgotten_castle")
	var has_armory: bool = (
		external.has("armory") and (external.get("armory", []) as Array).size() > 0
	)
	ctx.timed_record(
		"inventory.loot_table.external_biome",
		get_category(),
		has_armory,
		"forgotten_castle loads chest items from content/loot/tables JSON",
		start,
		"LOO-03"
	)


func _should_roll_loot_for_test(item_id: String) -> bool:
	var def := ItemCatalog.get_definition(item_id)
	return def.get("itemType", "") in ["weapon", "armor", "accessory"]


func _test_elemental_affix_damage() -> void:
	var start := Time.get_ticks_msec()
	var instance := {
		"itemId": "castle_sword",
		"affixes": [{"affixId": "of_flames", "value": 12.0}],
	}
	var stats := EquipmentScript.stats_for_instance(
		instance, Callable(AffixRollerScript, "get_affix_stat")
	)
	var bonus: float = float(stats.get("bonusDamage", 0.0))
	ctx.timed_record(
		"inventory.elemental_affix_bonus_damage",
		get_category(),
		bonus >= 12.0,
		"fireDamage affix folds into bonusDamage for combat",
		start,
		"LOO-04"
	)


func _test_compare_stats() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new()
	grid.add_item("castle_plate", 1)
	var idx := grid.find_slot_at(0, 0)
	var slot: Dictionary = grid.slots[idx] if idx >= 0 else {}
	var delta: Dictionary = EquipmentScript.compare_stats(
		grid.equipped, slot, Callable(AffixRollerScript, "get_affix_stat")
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


func _test_add_loot_pipeline() -> void:
	_test_add_loot_rolls_equipment()
	_test_fetch_hook()
	_test_full_grid_rejects()
	_test_rarity_weight_aumbral()
	_test_remove_equipped_run_loot()


## BUG-13 regression: Health.configure/Poise.configure used to unconditionally refill to max,
## and the equipment path (wired to inventory.changed among other signals) called configure() on
## every add/remove/move/split/sort — so any inventory change mid-fight full-healed the player
## and cleared in-progress poise build-up. This spawns a real player, damages health and poise,
## fires inventory.changed the way a pickup or a drag would, and asserts neither moved.
func _test_inventory_change_does_not_heal_player() -> void:
	var start := Time.get_ticks_msec()
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	await ctx.await_physics(2)
	var health := player.get_node_or_null("Health") as Health
	var poise := player.get_node_or_null("Poise") as Poise
	var ok := false
	if health and poise:
		health.current = health.max_health * 0.5
		poise.current = poise.max_poise * 0.5
		var hp_before := health.current
		var poise_before := poise.current
		InventoryService.inventory.changed.emit()
		await ctx.await_frame()
		ok = (
			is_equal_approx(health.current, hp_before)
			and is_equal_approx(poise.current, poise_before)
		)
	player.queue_free()
	ctx.timed_record(
		"inventory.change_does_not_heal_player",
		get_category(),
		ok,
		"emitting inventory.changed does not refill player health or poise",
		start,
		"BUG-13"
	)


func _test_add_loot_rolls_equipment() -> void:
	var start := Time.get_ticks_msec()
	var inv_backup = InventoryService.inventory
	InventoryService.inventory = GridInventory.new()
	var added := InventoryService.add_loot("castle_sword")
	var slot: Dictionary = InventoryService.inventory.slots[0] if added else {}
	var rolls_ok := added and slot.has("rarity")
	ctx.timed_record(
		"inv.add_loot.rolls_equipment",
		get_category(),
		rolls_ok,
		"add_loot rolls equipment with rarity metadata",
		start,
		"INV.add_loot"
	)
	InventoryService.inventory = inv_backup


func _test_fetch_hook() -> void:
	var start := Time.get_ticks_msec()
	var inv_backup = InventoryService.inventory
	var quest_states_backup = CharacterService.quest_states.duplicate()
	var quest_progress_backup = CharacterService.quest_progress.duplicate()
	InventoryService.inventory = GridInventory.new()
	CharacterService.quest_states.clear()
	CharacterService.quest_progress.clear()
	QuestService.accept_quest("fetch_scrap")
	InventoryService.add_loot("iron_scrap", {"quantity": 1, "runLoot": false})
	var fetch_done := CharacterService.get_quest_state("fetch_scrap") == "completed"
	ctx.timed_record(
		"inv.fetch_hook",
		get_category(),
		fetch_done,
		"add_loot completes active fetch quest for target item",
		start,
		"INV.fetch"
	)
	InventoryService.inventory = inv_backup
	CharacterService.quest_states = quest_states_backup
	CharacterService.quest_progress = quest_progress_backup


func _test_full_grid_rejects() -> void:
	var start := Time.get_ticks_msec()
	var inv_backup = InventoryService.inventory
	_inventory_reject_seen = false
	if InventoryService.inventory_rejected.is_connected(_capture_inventory_rejected):
		InventoryService.inventory_rejected.disconnect(_capture_inventory_rejected)
	InventoryService.inventory_rejected.connect(_capture_inventory_rejected)
	InventoryService.inventory = GridInventory.new(1, 1)
	InventoryService.inventory.add_item("iron_scrap", 1)
	var failed := not InventoryService.add_item("castle_sword", 1)
	InventoryService.inventory_rejected.disconnect(_capture_inventory_rejected)
	ctx.timed_record(
		"inv.full_grid_rejects",
		get_category(),
		failed and _inventory_reject_seen,
		"full grid add_item returns false and emits inventory_rejected",
		start,
		"INV.full"
	)
	InventoryService.inventory = inv_backup


## BUG-16 regression: a stack that partially fits (fills the rest of an existing stack, then
## finds no room for the remainder) used to keep the partial stacking mutation while still
## returning false. add_item() must be all-or-nothing.
func _test_add_item_is_transactional() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new(1, 1)
	grid.add_item("health_potion", 3)
	var before_qty := int(grid.slots[0].get("quantity", 0))
	var call_ok := grid.add_item("health_potion", 4)
	var after_qty := int(grid.slots[0].get("quantity", 0)) if grid.slots.size() > 0 else -1
	var ok := not call_ok and grid.slots.size() == 1 and after_qty == before_qty
	ctx.timed_record(
		"inventory.add_item_is_transactional",
		get_category(),
		ok,
		"a partially-fitting add_item rolls back instead of keeping a partial mutation",
		start,
		"BUG-16"
	)


## BUG-17 regression: equipping from a full grid must succeed when the swap is space-neutral —
## the incoming item is about to vacate the exact cells the outgoing item needs.
func _test_equip_swap_when_grid_full() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new(2, 2)
	grid.add_item("iron_sword", 1)
	var equipped_first := grid.equip_from_index(0, "weapon")
	grid.add_item("war_hammer", 1)
	var swapped := grid.equip_from_index(0, "weapon")
	var ok := (
		equipped_first
		and swapped
		and str(grid.equipped.get("weapon", {}).get("itemId", "")) == "war_hammer"
		and grid.slots.size() == 1
		and str(grid.slots[0].get("itemId", "")) == "iron_sword"
	)
	ctx.timed_record(
		"inventory.equip_swap_succeeds_on_full_grid",
		get_category(),
		ok,
		"equip swap frees the incoming item's cells before the outgoing item looks for space",
		start,
		"BUG-17"
	)


func _test_rarity_weight_aumbral() -> void:
	var start := Time.get_ticks_msec()
	var grid := GridInventory.new()
	grid.add_item("iron_scrap", 1, {"rarity": "legendary", "x": 0, "y": 0})
	grid.add_item("iron_scrap", 1, {"rarity": "aumbral", "x": 1, "y": 0})
	grid.sort_slots("rarity")
	var first_rarity := grid.get_slot_rarity(grid.slots[0]) if grid.slots.size() > 0 else ""
	ctx.timed_record(
		"inv.rarity_weight.aumbral",
		get_category(),
		first_rarity == "aumbral",
		"rarity sort places aumbral above legendary",
		start,
		"INV.rarity"
	)


func _test_remove_equipped_run_loot() -> void:
	var start := Time.get_ticks_msec()
	var inv_backup = InventoryService.inventory
	InventoryService.inventory = GridInventory.new()
	var added := InventoryService.add_loot("castle_sword", {"runLoot": true})
	var equipped := false
	if added:
		equipped = InventoryService.inventory.equip_weapon(0)
	InventoryService.remove_run_loot(["castle_sword"])
	var weapon_cleared: bool = InventoryService.inventory.equipped.get("weapon", {}).is_empty()
	ctx.timed_record(
		"inv.remove_run_loot.equipped",
		get_category(),
		added and equipped and weapon_cleared,
		"remove_run_loot strips equipped run-tagged loot",
		start,
		"INV.run_loot"
	)
	InventoryService.inventory = inv_backup


func _test_inventory_ui_icons() -> void:
	_test_inventory_ui_no_unicode()
	_test_inventory_ui_uses_atlas()
	_test_item_icon_coverage()
	_test_item_icon_atlas_manifest()


func _test_inventory_ui_no_unicode() -> void:
	var start := Time.get_ticks_msec()
	var paths := [
		"res://scripts/ui/inventory_ui.gd",
		"res://scripts/ui/inventory_ui_layout.gd",
	]
	var has_unicode := false
	for path in paths:
		if not FileAccess.file_exists(path):
			has_unicode = true
			continue
		var text := FileAccess.get_file_as_string(path)
		for i in text.length():
			if text.unicode_at(i) > 127:
				has_unicode = true
				break
	ctx.timed_record(
		"inventory_ui.no_unicode",
		get_category(),
		not has_unicode,
		"inventory UI scripts contain no non-ASCII literals",
		start,
		"M2.inventory.icons"
	)


func _test_inventory_ui_uses_atlas() -> void:
	var start := Time.get_ticks_msec()
	var script_path := "res://scripts/ui/inventory_ui.gd"
	var uses_atlas: bool = (
		ctx.file_contains(script_path, "ItemIconAtlas")
		and ctx.file_contains(script_path, "TextureRect")
		and not ctx.file_contains(script_path, "_item_glyph")
		and not ctx.file_contains(script_path, "_slot_glyph_for_label")
		and not ctx.file_contains(script_path, "_item_abbrev")
	)
	ctx.timed_record(
		"inventory_ui.uses_item_icon_atlas",
		get_category(),
		uses_atlas,
		"inventory_ui.gd renders item cells via ItemIconAtlas TextureRect",
		start,
		"M2.inventory.icons"
	)


func _test_item_icon_coverage() -> void:
	var start := Time.get_ticks_msec()
	var catalog: Dictionary = ContentLoader.load_json("content/items/catalog.json")
	var missing: PackedStringArray = []
	for category in ["equipment", "consumables", "materials"]:
		for item_id in catalog.get(category, []):
			var item_id_str := str(item_id)
			var def := ItemCatalog.get_definition(item_id_str)
			var icon_path: String = str(def.get("iconPath", ""))
			var resolved := false
			if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
				resolved = true
			elif ItemIconAtlasScript.has_icon(item_id_str):
				resolved = true
			if not resolved:
				missing.append(item_id_str)
	ctx.timed_record(
		"inventory_ui.icon_coverage",
		get_category(),
		missing.is_empty(),
		(
			"every catalog item resolves to atlas cell or iconPath"
			if missing.is_empty()
			else "missing icons: %s" % ", ".join(missing)
		),
		start,
		"M2.inventory.icons"
	)


func _test_item_icon_atlas_manifest() -> void:
	var start := Time.get_ticks_msec()
	var manifest: Dictionary = ContentLoader.load_json("content/ui/item_icon_atlas.json")
	var texture_path: String = str(manifest.get("texture", ""))
	var cells: Variant = manifest.get("cells", {})
	var slot_keys := [
		"slot/helmet",
		"slot/chest",
		"slot/gloves",
		"slot/boots",
		"slot/weapon",
		"slot/secondary",
		"slot/ring",
		"slot/amulet",
		"slot/relic",
	]
	var slots_ok := true
	if cells is Dictionary:
		for slot_key in slot_keys:
			if not (cells as Dictionary).has(slot_key):
				slots_ok = false
				break
	else:
		slots_ok = false
	ctx.timed_record(
		"inventory_ui.slot_icon_cells",
		get_category(),
		(
			not manifest.is_empty()
			and ResourceLoader.exists(texture_path)
			and slots_ok
			and ItemIconAtlasScript.icon_size() == int(manifest.get("cellSize", 16))
		),
		"item icon atlas manifest, texture, and slot cells load",
		start,
		"M2.inventory.icons"
	)


func _affix_tier_bounds(affix_id: String, rarity: String) -> Dictionary:
	for pack_path in ["content/affixes/prefixes.json", "content/affixes/suffixes.json"]:
		var pack: Dictionary = ContentLoader.load_json(pack_path)
		for affix in pack.get("affixes", []):
			if not affix is Dictionary:
				continue
			if affix.get("id", "") != affix_id:
				continue
			var tiers: Variant = affix.get("tiers", {})
			if tiers is Dictionary:
				var tier: Variant = (tiers as Dictionary).get(rarity)
				if tier is Dictionary:
					return tier
	return {}
