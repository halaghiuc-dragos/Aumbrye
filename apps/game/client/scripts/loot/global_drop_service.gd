extends RefCounted
class_name GlobalDropService

## Rolls rare global drops (skip-floor items) from content/loot/global_drops.json.

const DROPS_PATH := "content/loot/global_drops.json"
const EndlessDifficultyScript := preload("res://scripts/dungeon/endless_difficulty.gd")


static func roll_enemy_drop(enemy_seed: int, floor_index: int = 1) -> String:
	var data: Dictionary = ContentLoader.load_json(DROPS_PATH)
	var entries: Array = data.get("skipItems", [])
	if entries.is_empty():
		return ""
	var bonus := EndlessDifficultyScript.rare_drop_bonus(floor_index) if floor_index > 1 else 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(enemy_seed) + floor_index * 1337
	for entry in entries:
		if not entry is Dictionary:
			continue
		var item_id: String = str(entry.get("itemId", ""))
		var chance: float = float(entry.get("chance", 0.0)) * (1.0 + bonus)
		if item_id != "" and rng.randf() < chance:
			return item_id
	return ""
