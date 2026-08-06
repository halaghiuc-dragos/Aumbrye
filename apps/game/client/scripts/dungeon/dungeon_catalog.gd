extends RefCounted
class_name DungeonCatalog

## Data-driven dungeon ladder from content/dungeons/ (DCT-06, DCT-12).

const DUNGEON_DIR := "content/dungeons"
const DEFAULT_DUNGEON_ID := "forgotten_castle"

static var ENTRIES: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_by_id.clear()
	ENTRIES.clear()
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var abs_dir := ContentLoader.content_path(DUNGEON_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_error("DungeonCatalog: missing directory %s" % abs_dir)
		_loaded = true
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var relative := "%s/%s" % [DUNGEON_DIR, file_name]
			var data: Dictionary = ContentLoader.load_json(relative)
			var dungeon_id: String = str(data.get("id", ""))
			if dungeon_id.is_empty():
				push_warning("DungeonCatalog: skipping %s (missing id)" % relative)
			else:
				data["content_path"] = relative
				_by_id[dungeon_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
	var sorted: Array[Dictionary] = []
	for dungeon_id in _by_id:
		sorted.append(_by_id[dungeon_id])
	sorted.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", 99)) < int(b.get("order", 99))
	)
	ENTRIES = sorted
	_loaded = true


static func all_dungeon_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for entry in ENTRIES:
		ids.append(str(entry.get("id", "")))
	return ids


static func get_entry(dungeon_id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(dungeon_id, {})


static func get_display_name(dungeon_id: String) -> String:
	var biome_id := get_biome_id(dungeon_id)
	var biome := ContentLoader.load_json("content/biomes/%s.json" % biome_id)
	return str(biome.get("name", biome_id))


static func get_biome_id(dungeon_id: String) -> String:
	var entry := get_entry(dungeon_id)
	if entry.is_empty():
		return BiomeRegistry.BIOME_CASTLE
	return str(entry.get("biomeId", BiomeRegistry.BIOME_CASTLE))


static func get_clear_flag(dungeon_id: String) -> String:
	var entry := get_entry(dungeon_id)
	return str(entry.get("clearFlag", ""))


static func is_valid(dungeon_id: String) -> bool:
	_ensure_loaded()
	return _by_id.has(dungeon_id)


static func count() -> int:
	_ensure_loaded()
	return ENTRIES.size()


static func get_dungeon_index(dungeon_id: String) -> int:
	_ensure_loaded()
	for i in ENTRIES.size():
		if str(ENTRIES[i].get("id", "")) == dungeon_id:
			return i
	return -1


static func get_order_for_dungeon(dungeon_id: String) -> int:
	var entry := get_entry(dungeon_id)
	if entry.is_empty():
		return 1
	return int(entry.get("order", 1))


static func get_tier_for_dungeon(dungeon_id: String) -> int:
	return get_order_for_dungeon(dungeon_id)


static func get_dungeon_for_tier(tier: int) -> String:
	_ensure_loaded()
	for entry in ENTRIES:
		if int(entry.get("order", 0)) == tier:
			return str(entry.get("id", DEFAULT_DUNGEON_ID))
	var index := clampi(tier - 1, 0, ENTRIES.size() - 1)
	if ENTRIES.is_empty():
		return DEFAULT_DUNGEON_ID
	return str(ENTRIES[index].get("id", DEFAULT_DUNGEON_ID))


static func is_unlocked_at_tier(dungeon_id: String, max_unlocked_tier: int) -> bool:
	return get_order_for_dungeon(dungeon_id) <= max_unlocked_tier


static func get_difficulty_tiers(dungeon_id: String) -> Array:
	var entry := get_entry(dungeon_id)
	var tiers: Variant = entry.get("difficultyTiers", [])
	return tiers if tiers is Array else []


static func get_difficulty_tier_data(dungeon_id: String, tier: int) -> Dictionary:
	for entry in get_difficulty_tiers(dungeon_id):
		if entry is Dictionary and int(entry.get("tier", 0)) == tier:
			return entry
	var tiers := get_difficulty_tiers(dungeon_id)
	if tiers.is_empty():
		return {}
	return tiers[0] if tiers[0] is Dictionary else {}


static func get_difficulty_tier_label(dungeon_id: String, tier: int) -> String:
	return str(get_difficulty_tier_data(dungeon_id, tier).get("label", "Tier %d" % tier))


static func max_difficulty_tier(dungeon_id: String) -> int:
	var max_tier := 1
	for entry in get_difficulty_tiers(dungeon_id):
		if entry is Dictionary:
			max_tier = maxi(max_tier, int(entry.get("tier", 1)))
	return max_tier


static func get_floor_hp_growth(dungeon_id: String) -> float:
	var entry := get_entry(dungeon_id)
	return float(entry.get("floorHpGrowth", 0.06))


static func get_floor_damage_growth(dungeon_id: String) -> float:
	var entry := get_entry(dungeon_id)
	return float(entry.get("floorDamageGrowth", 0.04))


static func get_boss_door_requirement(dungeon_id: String) -> String:
	var entry := get_entry(dungeon_id)
	return str(entry.get("bossDoorRequirement", "none"))


static func get_modifiers_for_difficulty(dungeon_id: String, tier: int) -> Array:
	var data := get_difficulty_tier_data(dungeon_id, tier)
	var mods: Variant = data.get("modifiers", [])
	return mods if mods is Array else []
