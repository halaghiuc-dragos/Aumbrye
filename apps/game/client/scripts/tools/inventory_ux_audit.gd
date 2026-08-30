extends Node

## Checks the inventory panel behaviour, which is easy to break and awkward to test
## by hand: it depends on which device is driving, whether an item is in the hand, and whether the
## pointer is over anything at all.
##
## Run: godot --path apps/game/client --headless res://scenes/debug/inventory_ux_audit.tscn

const ItemQualityScript := preload("res://scripts/items/item_quality.gd")

var _failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_audit_condition_line()
	print("INVENTORY UX RESULT %d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL %s" % message)


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


## The description follows one device at a time: a pointer over nothing describes nothing, a cursor
## always has somewhere to be, and an item in the hand suppresses both. That logic lives in
## InventoryUI._described_grid_index / _described_equip_slot / _is_dragging, which need the panel's
## whole node tree to exist -- the panel is embedded in the hub and the run rather than being a
## scene of its own, so it is exercised by playing those rather than from here. What is checked
## here is the part that is a pure function of the item.
