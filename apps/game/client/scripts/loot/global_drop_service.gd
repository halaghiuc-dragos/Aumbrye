extends RefCounted
class_name GlobalDropService

## Rolls rare global drops (skip-floor items) from content/loot/global_drops.json.

const DROPS_PATH := "content/loot/global_drops.json"
const EndlessDifficultyScript := preload("res://scripts/dungeon/endless_difficulty.gd")

static var _entries: Array = []
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var data: Dictionary = ContentLoader.load_json(DROPS_PATH)
	_entries = data.get("skipItems", [])
	_loaded = true


static func roll_enemy_drop(
	enemy_seed: int, floor_index: int = 1, difficulty_tier: int = 1, dungeon_id: String = ""
) -> String:
	_ensure_loaded()
	var entries: Array = _entries
	if entries.is_empty():
		return ""
	var bonus := 0.0
	if floor_index > 1:
		bonus += EndlessDifficultyScript.rare_drop_bonus(floor_index)
	if difficulty_tier > 1:
		var resolved_id := dungeon_id
		if resolved_id == "" and RunFlow:
			resolved_id = RunFlow.current_dungeon_id
		if resolved_id == "":
			resolved_id = DungeonCatalog.DEFAULT_DUNGEON_ID
		bonus += CastleTierDifficulty.loot_bonus(resolved_id, difficulty_tier)
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
