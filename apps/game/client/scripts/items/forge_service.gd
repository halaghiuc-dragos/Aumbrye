extends RefCounted
class_name ForgeService


const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const BlacksmithServiceScript := preload("res://scripts/hub/blacksmith_service.gd")

const SALVAGE_YIELD: Dictionary = {
	"common": {"cinder_dust": 2},
	"magic": {"cinder_dust": 2, "glimmer_ash": 1},
	"rare": {"glimmer_ash": 2, "sable_grain": 1},
	"epic": {"sable_grain": 2, "storm_salt": 1},
	"legendary": {"storm_salt": 2, "aumbral_tear": 1},
	"aumbral": {"storm_salt": 3, "aumbral_tear": 3},
}


const AWAY_FROM_HUB_YIELD_MULT := 0.6

static func salvage_preview(slot: Dictionary, reduced: bool = false) -> Dictionary:
	var rarity := RarityRegistryScript.normalize(str(slot.get("rarity", "common")))
	var yields: Dictionary = (SALVAGE_YIELD.get(rarity, SALVAGE_YIELD["common"]) as Dictionary).duplicate()
	var upgrade_level := BlacksmithServiceScript.get_slot_upgrade_level(slot)
	if upgrade_level > 0:
		yields["iron_scrap"] = int(yields.get("iron_scrap", 0)) + upgrade_level
	if reduced:
		for material_id in yields.keys():
			yields[material_id] = maxi(1, ceili(int(yields[material_id]) * AWAY_FROM_HUB_YIELD_MULT))
	return yields


static func salvage(inv_index: Variant, reduced: bool = false) -> Dictionary:
	if BlacksmithServiceScript.is_equipment_slot(inv_index):
		return {"ok": false, "error": "unequip first"}
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return {"ok": false, "error": "invalid slot"}
	return salvage_instance(inv, str(inv.slots[inv_index].get("instanceId", "")), reduced)


static func salvage_instance(inv: GridInventory, instance_id: String, reduced: bool = false) -> Dictionary:
	var inv_index := inv.find_instance_index(instance_id)
	if inv_index < 0:
		return {"ok": false, "error": "item changed"}
	var slot: Dictionary = inv.slots[inv_index]
	var def := ItemCatalog.get_definition(str(slot.get("itemId", "")))
	if bool(slot.get("protected", false)) or bool(slot.get("favorite", false)):
		return {"ok": false, "error": "item protected"}
	if str(def.get("itemType", "")) == "quest" or bool(def.get("unique", false)):
		return {"ok": false, "error": "item cannot be salvaged"}
	if def.get("itemType", "") not in BlacksmithServiceScript.UPGRADEABLE_TYPES:
		return {"ok": false, "error": "not salvageable"}
	var yields := salvage_preview(slot, reduced)
	var working := _working_copy(inv)
	if working.remove_at(inv_index).is_empty():
		return {"ok": false, "error": "invalid slot"}
	# Materials from a piece of this run's loot are still this run's loot.
	var material_data: Dictionary = {"runLoot": true} if bool(slot.get("runLoot", false)) else {}
	for material_id in yields:
		var amount := int(yields[material_id])
		if amount <= 0:
			continue
		if not working.add_item(str(material_id), amount, material_data):
			return {"ok": false, "error": "inventory full", "materials": yields}
	_commit_inventory(inv, working)
	if inv == InventoryService.inventory and LocalSave:
		LocalSave.request_autosave()
	return {"ok": true, "materials": yields, "lost": {}}


static func _working_copy(inv: GridInventory) -> GridInventory:
	var working := GridInventory.new(inv.grid_width, inv.grid_height)
	working.from_save_dict(inv.to_save_dict())
	return working


static func _commit_inventory(inv: GridInventory, working: GridInventory) -> void:
	inv.from_save_dict(working.to_save_dict())
