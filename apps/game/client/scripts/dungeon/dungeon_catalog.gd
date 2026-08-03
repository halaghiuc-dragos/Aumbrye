extends RefCounted
class_name DungeonCatalog

## Ten playable dungeon themes — each maps to a unique biome (10 total).

const DEFAULT_DUNGEON_ID := "forgotten_castle"

const ENTRIES: Array[Dictionary] = [
	{"id": "forgotten_castle", "name": "Forgotten Castle", "biomeId": "forgotten_castle"},
	{"id": "crystal_caverns", "name": "Crystal Caverns", "biomeId": "crystal_caverns"},
	{"id": "poison_swamp", "name": "Poison Swamp", "biomeId": "poison_swamp"},
	{"id": "frozen_fortress", "name": "Frozen Fortress", "biomeId": "frozen_fortress"},
	{"id": "dark_cathedral", "name": "Dark Cathedral", "biomeId": "dark_cathedral"},
	{"id": "iron_vault", "name": "Iron Vault", "biomeId": "iron_vault"},
	{"id": "prism_depths", "name": "Prism Depths", "biomeId": "prism_depths"},
	{"id": "venom_mire", "name": "Venom Mire", "biomeId": "venom_mire"},
	{"id": "glacial_hollow", "name": "Glacial Hollow", "biomeId": "glacial_hollow"},
	{"id": "umbral_chapel", "name": "Umbral Chapel", "biomeId": "umbral_chapel"},
]


static func all_dungeon_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in ENTRIES:
		ids.append(str(entry.get("id", "")))
	return ids


static func get_display_name(dungeon_id: String) -> String:
	for entry in ENTRIES:
		if str(entry.get("id", "")) == dungeon_id:
			return str(entry.get("name", dungeon_id))
	return dungeon_id


static func get_biome_id(dungeon_id: String) -> String:
	for entry in ENTRIES:
		if str(entry.get("id", "")) == dungeon_id:
			return str(entry.get("biomeId", BiomeRegistry.BIOME_CASTLE))
	return BiomeRegistry.BIOME_CASTLE


static func is_valid(dungeon_id: String) -> bool:
	for entry in ENTRIES:
		if str(entry.get("id", "")) == dungeon_id:
			return true
	return false


static func count() -> int:
	return ENTRIES.size()


static func get_dungeon_index(dungeon_id: String) -> int:
	for i in ENTRIES.size():
		if str(ENTRIES[i].get("id", "")) == dungeon_id:
			return i
	return -1


static func get_tier_for_dungeon(dungeon_id: String) -> int:
	var index := get_dungeon_index(dungeon_id)
	return index + 1 if index >= 0 else 1


static func get_dungeon_for_tier(tier: int) -> String:
	var index := clampi(tier - 1, 0, ENTRIES.size() - 1)
	return str(ENTRIES[index].get("id", DEFAULT_DUNGEON_ID))


static func is_unlocked_at_tier(dungeon_id: String, max_unlocked_tier: int) -> bool:
	var index := get_dungeon_index(dungeon_id)
	return index >= 0 and index < max_unlocked_tier
