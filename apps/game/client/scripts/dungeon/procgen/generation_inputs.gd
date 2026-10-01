class_name GenerationInputs
extends RefCounted

## Everything a floor's generation reads from the save or the clock. Captured once at run start
## and passed in explicitly, so the same seed gives the same floor on every continue, respawn and
## save instead of depending on how much has been played since.


## A seeded or challenge run has to give every save the same floor, so it starts from a neutral
## snapshot instead of this save's history.
static func capture(neutral: bool = false) -> Dictionary:
	if neutral:
		return {"lootQuality": 0.0, "lockedItems": []}
	return {
		"lootQuality": InventoryService.total_stat("lootQuality") if InventoryService else 0.0,
		"lockedItems": VaultService.locked_item_ids() if VaultService else [],
	}
