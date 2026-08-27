extends Node


const FLAG_UNLOCKED_COUNT := "dungeon_unlocked_count"
const FLAG_MAX_TIER_LEGACY := "dungeon_max_tier"
const FLAG_DIFFICULTY_PREFIX := "dungeon_tier_"
const FLAG_BEST_PREFIX := "dungeon_best_"
const MAX_TIER := 10
const MAX_DEPTH := MAX_TIER
const HUB_LABEL_PREFIX := "Aumbrye Dungeons — Depth "

signal tier_unlocked(tier: int)
signal difficulty_tier_unlocked(dungeon_id: String, tier: int)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_max_unlocked_tier() -> int:
	var count := int(CharacterService.get_flag(FLAG_UNLOCKED_COUNT))
	if count < 1:
		count = int(CharacterService.get_flag(FLAG_MAX_TIER_LEGACY))
	return clampi(count, 1, MAX_DEPTH)


func get_hub_portal_label() -> String:
	return HUB_LABEL_PREFIX + str(get_max_unlocked_tier())


func get_menu_title(depth: int) -> String:
	return HUB_LABEL_PREFIX + str(clampi(depth, 1, MAX_DEPTH))


func unlock_next_tier() -> void:
	var current := get_max_unlocked_tier()
	if current >= MAX_DEPTH:
		return
	var next := current + 1
	CharacterService.set_flag(FLAG_UNLOCKED_COUNT, next)
	CharacterService.set_flag(FLAG_MAX_TIER_LEGACY, next)
	tier_unlocked.emit(next)


func is_dungeon_unlocked(dungeon_id: String) -> bool:
	return DungeonCatalog.is_unlocked_at_tier(dungeon_id, get_max_unlocked_tier())


func _difficulty_flag(dungeon_id: String) -> String:
	return FLAG_DIFFICULTY_PREFIX + dungeon_id


func _best_flag(dungeon_id: String) -> String:
	return FLAG_BEST_PREFIX + dungeon_id


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


func is_difficulty_tier_cleared(dungeon_id: String, tier: int) -> bool:
	return tier < get_unlocked_difficulty_cap(dungeon_id)


func get_best_results(dungeon_id: String) -> Dictionary:
	var stored: Variant = CharacterService.get_flag(_best_flag(dungeon_id), {})
	return stored if stored is Dictionary else {}


func get_best_result(dungeon_id: String, tier: int) -> Dictionary:
	var entry: Variant = get_best_results(dungeon_id).get(str(tier), {})
	return entry if entry is Dictionary else {}


func record_clear_result(dungeon_id: String, tier: int, elapsed_seconds: float) -> void:
	if dungeon_id == "" or tier < 1:
		return
	var results := get_best_results(dungeon_id).duplicate(true)
	var key := str(tier)
	var previous: Variant = results.get(key, {})
	var best_time := elapsed_seconds
	var clears := 1
	if previous is Dictionary and not (previous as Dictionary).is_empty():
		var prior_time := float((previous as Dictionary).get("bestSeconds", elapsed_seconds))
		if prior_time > 0.0:
			best_time = minf(prior_time, elapsed_seconds)
		clears = int((previous as Dictionary).get("clears", 0)) + 1
	results[key] = {"bestSeconds": maxf(0.0, best_time), "clears": clears}
	CharacterService.set_flag(_best_flag(dungeon_id), results)


func get_difficulty_ladder(dungeon_id: String) -> Array[Dictionary]:
	var cap := get_unlocked_difficulty_cap(dungeon_id)
	var unlocked := is_dungeon_unlocked(dungeon_id)
	var rows: Array[Dictionary] = []
	for tier_data in DungeonCatalog.get_difficulty_tiers(dungeon_id):
		if not tier_data is Dictionary:
			continue
		var tier_num := int(tier_data.get("tier", 1))
		var state := "locked"
		if unlocked and tier_num < cap:
			state = "cleared"
		elif unlocked and tier_num <= cap:
			state = "available"
		var best := get_best_result(dungeon_id, tier_num)
		(
			rows
			. append(
				{
					"tier": tier_num,
					"label": str(tier_data.get("label", "Tier %d" % tier_num)),
					"description": str(tier_data.get("description", "")),
					"state": state,
					"hpMult": float(tier_data.get("hpMult", 1.0)),
					"damageMult": float(tier_data.get("damageMult", 1.0)),
					"lootBonus": float(tier_data.get("lootBonus", 0.0)),
					"modifiers": tier_data.get("modifiers", []),
					"bestSeconds": float(best.get("bestSeconds", 0.0)),
					"clears": int(best.get("clears", 0)),
				}
			)
		)
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("tier", 0)) < int(b.get("tier", 0))
	)
	return rows


func on_dungeon_cleared(dungeon_id: String, difficulty_tier: int = 1) -> void:
	var cleared_order := DungeonCatalog.get_order_for_dungeon(dungeon_id)
	if cleared_order >= get_max_unlocked_tier() and cleared_order < MAX_DEPTH:
		unlock_next_tier()
	if difficulty_tier >= get_unlocked_difficulty_cap(dungeon_id):
		var next_difficulty := mini(
			difficulty_tier + 1, DungeonCatalog.max_difficulty_tier(dungeon_id)
		)
		set_unlocked_difficulty_cap(dungeon_id, next_difficulty)
		difficulty_tier_unlocked.emit(dungeon_id, next_difficulty)
