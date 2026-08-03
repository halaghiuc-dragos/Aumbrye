extends Node

## Aumbrye Dungeons tier progression — unlock higher tiers after 10-floor clears.

const FLAG_MAX_TIER := "dungeon_max_tier"
const MAX_TIER := 10
const HUB_LABEL_PREFIX := "Aumbrye Dungeons — Tier "

signal tier_unlocked(tier: int)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_max_unlocked_tier() -> int:
	return clampi(int(CharacterService.get_flag(FLAG_MAX_TIER, 1)), 1, MAX_TIER)


func get_hub_portal_label() -> String:
	return HUB_LABEL_PREFIX + str(get_max_unlocked_tier())


func get_menu_title(tier: int) -> String:
	return HUB_LABEL_PREFIX + str(clampi(tier, 1, MAX_TIER))


func unlock_next_tier() -> void:
	var current := get_max_unlocked_tier()
	if current >= MAX_TIER:
		return
	var next := current + 1
	CharacterService.set_flag(FLAG_MAX_TIER, next)
	tier_unlocked.emit(next)


func is_dungeon_unlocked(dungeon_id: String) -> bool:
	return DungeonCatalog.is_unlocked_at_tier(dungeon_id, get_max_unlocked_tier())


func get_unlocked_dungeon_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in DungeonCatalog.ENTRIES:
		var dungeon_id := str(entry.get("id", ""))
		if is_dungeon_unlocked(dungeon_id):
			ids.append(dungeon_id)
	return ids


func on_dungeon_cleared(dungeon_id: String) -> void:
	var cleared_tier := DungeonCatalog.get_tier_for_dungeon(dungeon_id)
	if cleared_tier >= get_max_unlocked_tier() and cleared_tier < MAX_TIER:
		unlock_next_tier()
