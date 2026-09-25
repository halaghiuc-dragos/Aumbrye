extends Node

## Checks the inventory panel behaviour, which is easy to break and awkward to test
## by hand: it depends on which device is driving, whether an item is in the hand, and whether the
## pointer is over anything at all.
##
## Run: godot --path apps/game/client --headless res://scenes/debug/inventory_ux_audit.tscn

const ItemQualityScript := preload("res://scripts/items/item_quality.gd")
const CombatStatModifiersScript := preload("res://scripts/combat/combat_stat_modifiers.gd")
const InventoryUIScript := preload("res://scripts/ui/inventory_ui.gd")

var _failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_audit_condition_line()
	_audit_effective_damage_preview()
	_audit_empty_filter_results()
	print("INVENTORY UX RESULT %d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL %s" % message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


## Every condition an item can roll has to name itself in the description, including the neutral
## one -- that is the tier that tells the player the axis exists.
func _audit_condition_line() -> void:
	for item_type in ["weapon", "armor", "accessory"]:
		var ladder := ItemQualityScript.ladder_for(item_type)
		for quality_id in ladder:
			var slot := {"itemId": _sample_item(item_type), "quality": str(quality_id)}
			var text := InventoryService.format_slot_tooltip_bbcode(slot)
			var name_text := ItemQualityScript.display_name(str(quality_id))
			if not text.contains(name_text):
				_fail("'%s' does not name itself in the description" % quality_id)
			if not text.contains("base stats"):
				_fail("'%s' does not say what it does to the item" % quality_id)
		print("CONDITION %-10s all %d tiers named in the description" % [item_type, ladder.size()])

	# An item with no condition rolled must not grow an empty line.
	var bare := InventoryService.format_slot_tooltip_bbcode({"itemId": _sample_item("weapon")})
	if bare.contains(tr("INV_CONDITION")):
		_fail("an item with no condition still shows a condition line")


func _sample_item(item_type: String) -> String:
	var ids := ItemCatalog.get_items_by_type(item_type)
	return str(ids[0]) if not ids.is_empty() else "castle_sword"


func _audit_empty_filter_results() -> void:
	var ui := InventoryUIScript.new()
	var cell := ItemCell.make_cell(32, "common", 0)
	ui._cells = [cell]
	ui._visible_indices = []
	ui._search_text = "definitely-not-an-item"
	var inventory := InventoryService.inventory
	var original_slots: Array = inventory.slots.duplicate(true)
	inventory.slots = [
		{"itemId": "castle_sword", "quantity": 1, "x": 0, "y": 0, "instanceId": "audit-empty-filter"}
	]
	ui._refresh_grid()
	_check(
		is_equal_approx(cell.self_modulate.a, 0.35),
		"active zero-result search dims occupied inventory items"
	)
	ui._search_text = ""
	ui._rarity_filter_idx = GridInventory.FILTER_RARITIES.find("magic")
	ui._rebuild_visible_indices()
	ui._refresh_grid()
	_check(
		ui._visible_indices.is_empty()
		and is_equal_approx(cell.self_modulate.a, 0.35),
		"unmatched rarity filter dims occupied inventory items"
	)
	var label := Label.new()
	ui._filter_label = label
	ui._filter_label.text = ""
	ui._update_filter_label()
	_check(label.text.contains(tr("INV_NO_RESULTS")), "empty active filter shows localized zero-results feedback")
	ui._search_text = ""
	ui._type_filter_idx = 0
	ui._rarity_filter_idx = 0
	ui._rebuild_visible_indices()
	ui._refresh_grid()
	_check(
		not ui._has_active_filter() and is_equal_approx(cell.self_modulate.a, 1.0),
		"clearing search and rarity filter restores normal item presentation"
	)
	inventory.slots = original_slots
	ui.free()


func _audit_effective_damage_preview() -> void:
	var dagger := ContentLoader.load_json("content/weapons/dagger.json")
	var greatsword := ContentLoader.load_json("content/weapons/greatsword.json")
	var dagger_attack := (dagger.get("light_attacks", []) as Array)[0] as Dictionary
	var greatsword_attack := (greatsword.get("light_attacks", []) as Array)[0] as Dictionary
	var over_cap_stats := {"bonusDamage": 1000.0}
	var dagger_result := CombatStatModifiersScript.preview_attack_damage(
		dagger_attack, dagger, over_cap_stats, {}, {}
	)
	var greatsword_result := CombatStatModifiersScript.preview_attack_damage(
		greatsword_attack, greatsword, over_cap_stats, {}, {}
	)
	var dagger_base := float(dagger_result.get("base_damage", 0.0))
	var greatsword_base := float(greatsword_result.get("base_damage", 0.0))
	_check(
		bool(dagger_result.get("flat_capped", false))
		and is_equal_approx(float(dagger_result.get("flat_applied", 0.0)), dagger_base * 2.0),
		"dagger preview identifies the 2x opening-move flat-damage cap"
	)
	_check(
		bool(greatsword_result.get("flat_capped", false))
		and is_equal_approx(float(greatsword_result.get("flat_applied", 0.0)), greatsword_base * 2.0),
		"greatsword preview applies its own 2x opening-move cap"
	)
	var more_over_cap := CombatStatModifiersScript.preview_attack_damage(
		dagger_attack, dagger, {"bonusDamage": 2000.0}, {}, {}
	)
	_check(
		is_equal_approx(
			float(dagger_result.get("damage", 0.0)), float(more_over_cap.get("damage", 0.0))
		),
		"flat gear above the dagger cap yields no misleading preview gain"
	)
	_check(
		not is_equal_approx(
			float(dagger_result.get("damage", 0.0)), float(greatsword_result.get("damage", 0.0))
		),
		"an identical over-cap loadout retains distinct dagger and greatsword move damage"
	)
	var old_equipment: Dictionary = InventoryService.inventory.equipped.duplicate(true)
	InventoryService.inventory.equipped = Equipment.empty_equipped()
	InventoryService.inventory.equipped["weapon"] = {"itemId": "castle_sword", "instanceId": "audit-equipped"}
	var candidate := {
		"itemId": "castle_sword",
		"instanceId": "audit-candidate",
		"affixes": [{"affixId": "hungry", "value": 100.0}],
	}
	var tooltip := InventoryService.damage_comparison_tooltip_bbcode(candidate)
	_check(tooltip.contains("Opening light"), "equipment tooltip includes an effective damage comparison")
	_check(tooltip.contains("twice this move") or tooltip.contains("dublul daunelor"), "equipment tooltip explains when the flat contribution is capped")
	_check(tooltip.contains("temporary combat effects"), "equipment tooltip labels the preview's scope")
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ro")
	var romanian_tooltip := InventoryService.damage_comparison_tooltip_bbcode(candidate)
	_check(
		romanian_tooltip.contains("Lovitură ușoară inițială")
		and romanian_tooltip.contains("efecte temporare de luptă"),
		"damage preview and scope are localized in Romanian"
	)
	TranslationServer.set_locale(previous_locale)
	var alternate_inventory := GridInventory.new()
	alternate_inventory.equipped = Equipment.empty_equipped()
	alternate_inventory.equipped["weapon"] = {"itemId": "dagger", "instanceId": "waves-equipped"}
	var alternate_tooltip := InventoryService.damage_comparison_tooltip_bbcode(
		candidate, alternate_inventory
	)
	_check(
		alternate_tooltip.contains("Opening light"),
		"equipment preview reads the active inventory context rather than persistent inventory"
	)
	InventoryService.inventory.equipped = old_equipment


## The description follows one device at a time: a pointer over nothing describes nothing, a cursor
## always has somewhere to be, and an item in the hand suppresses both. That logic lives in
## InventoryUI._described_grid_index / _described_equip_slot / _is_dragging, which need the panel's
## whole node tree to exist -- the panel is embedded in the hub and the run rather than being a
## scene of its own, so it is exercised by playing those rather than from here. What is checked
## here is the part that is a pure function of the item.
