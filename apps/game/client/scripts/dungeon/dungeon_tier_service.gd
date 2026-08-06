extends Node

## Aumbrye Dungeons progression — dungeon unlock ladder and per-dungeon difficulty tiers.

const FLAG_UNLOCKED_COUNT := "dungeon_unlocked_count"
const FLAG_MAX_TIER_LEGACY := "dungeon_max_tier"
const FLAG_DIFFICULTY_PREFIX := "dungeon_tier_"
const MAX_TIER := 10
const HUB_LABEL_PREFIX := "Aumbrye Dungeons — Tier "

signal tier_unlocked(tier: int)
signal difficulty_tier_unlocked(dungeon_id: String, tier: int)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_max_unlocked_tier() -> int:
	var count := int(CharacterService.get_flag(FLAG_UNLOCKED_COUNT))
	if count < 1:
		count = int(CharacterService.get_flag(FLAG_MAX_TIER_LEGACY))
	return clampi(count, 1, MAX_TIER)


func get_hub_portal_label() -> String:
	return HUB_LABEL_PREFIX + str(get_max_unlocked_tier())


func get_menu_title(tier: int) -> String:
	return HUB_LABEL_PREFIX + str(clampi(tier, 1, MAX_TIER))


func unlock_next_tier() -> void:
	var current := get_max_unlocked_tier()
	if current >= MAX_TIER:
		return
	var next := current + 1
	CharacterService.set_flag(FLAG_UNLOCKED_COUNT, next)
	CharacterService.set_flag(FLAG_MAX_TIER_LEGACY, next)
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


func _difficulty_flag(dungeon_id: String) -> String:
	return FLAG_DIFFICULTY_PREFIX + dungeon_id


func get_unlocked_difficulty_cap(dungeon_id: String) -> int:
	return clampi(
		int(CharacterService.get_flag(_difficulty_flag(dungeon_id))),
		1,
		DungeonCatalog.max_difficulty_tier(dungeon_id)
	)


func set_unlocked_difficulty_cap(dungeon_id: String, tier: int) -> void:
	CharacterService.set_flag(_difficulty_flag(dungeon_id), tier)


func is_difficulty_tier_unlocked(dungeon_id: String, tier: int) -> bool:
	return is_dungeon_unlocked(dungeon_id) and tier <= get_unlocked_difficulty_cap(dungeon_id)


func on_dungeon_cleared(dungeon_id: String, difficulty_tier: int = 1) -> void:
	var cleared_order := DungeonCatalog.get_order_for_dungeon(dungeon_id)
	if cleared_order >= get_max_unlocked_tier() and cleared_order < MAX_TIER:
		unlock_next_tier()
	if difficulty_tier >= get_unlocked_difficulty_cap(dungeon_id):
		var next_difficulty := mini(
			difficulty_tier + 1, DungeonCatalog.max_difficulty_tier(dungeon_id)
		)
		set_unlocked_difficulty_cap(dungeon_id, next_difficulty)
		difficulty_tier_unlocked.emit(dungeon_id, next_difficulty)
