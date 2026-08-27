class_name RoomContentConfig
extends RefCounted


const PACING_PATH := "content/progression/room_pacing.json"
const FloorSeedMixScript := preload("res://scripts/dungeon/floor_seed_mix.gd")

const WEIGHT_KEYS := [
	"combat", "empty", "trap", "hazard", "reward", "lore", "rest", "puzzle", "npc_quest", "merchant"
]

static var _pacing: Dictionary = {}

var weight_combat := 0.45
var weight_empty := 0.14
var weight_trap := 0.09
var weight_hazard := 0.07
var weight_reward := 0.06
var weight_lore := 0.06
var weight_rest := 0.05
var weight_puzzle := 0.05
var weight_npc_quest := 0.02
var weight_merchant := 0.01
var max_assignment_attempts := 48
var min_off_path_distance := 2
var enable_locked_door := true
var enable_npc_quest := true
var min_locks_per_floor := 1
var max_locks_per_floor := 3
var min_reward_rooms := 1
var min_rest_rooms := 1
var rest_within_of_boss := 3
var max_consecutive_combat := 2
var floor_theme_id := "plain"
var floor_theme_label := ""


static func default() -> RoomContentConfig:
	return RoomContentConfig.new()


static func reload() -> void:
	_pacing.clear()


static func for_floor(floor_index: int, max_floors: int, run_seed: int) -> RoomContentConfig:
	var config := RoomContentConfig.new()
	var pacing := _load_pacing()
	if pacing.is_empty():
		return config
	var span := maxf(1.0, float(maxi(2, max_floors) - 1))
	var depth := clampf(float(maxi(1, floor_index) - 1) / span, 0.0, 1.0)
	var shallow: Dictionary = pacing.get("shallow", {})
	var deep: Dictionary = pacing.get("deep", {})
	var weights := {}
	for key in WEIGHT_KEYS:
		weights[key] = lerpf(
			float(shallow.get(key, 0.0)), float(deep.get(key, 0.0)), depth
		)
	var theme := _roll_theme(pacing, floor_index, run_seed)
	config.floor_theme_id = str(theme.get("id", "plain"))
	config.floor_theme_label = str(theme.get("label", ""))
	_apply_multipliers(weights, theme.get("multipliers", {}))
	var modifier_multipliers: Dictionary = pacing.get("modifierMultipliers", {})
	for modifier_id in modifier_multipliers:
		if RunModifierService.has_modifier(str(modifier_id)):
			_apply_multipliers(weights, modifier_multipliers[modifier_id])
	config.weight_combat = float(weights.get("combat", config.weight_combat))
	config.weight_empty = float(weights.get("empty", config.weight_empty))
	config.weight_trap = float(weights.get("trap", config.weight_trap))
	config.weight_hazard = float(weights.get("hazard", config.weight_hazard))
	config.weight_reward = float(weights.get("reward", config.weight_reward))
	config.weight_lore = float(weights.get("lore", config.weight_lore))
	config.weight_rest = float(weights.get("rest", config.weight_rest))
	config.weight_puzzle = float(weights.get("puzzle", config.weight_puzzle))
	config.weight_npc_quest = float(weights.get("npc_quest", config.weight_npc_quest))
	config.weight_merchant = float(weights.get("merchant", config.weight_merchant))
	var guarantees: Dictionary = pacing.get("guarantees", {})
	config.min_reward_rooms = int(guarantees.get("minRewardRooms", config.min_reward_rooms))
	config.min_rest_rooms = int(guarantees.get("minRestRooms", config.min_rest_rooms))
	config.rest_within_of_boss = int(
		guarantees.get("restWithinOfBoss", config.rest_within_of_boss)
	)
	config.max_consecutive_combat = int(
		guarantees.get("maxConsecutiveCombat", config.max_consecutive_combat)
	)
	if RunModifierService.has_modifier(RunModifierService.MODIFIER_NO_REST):
		config.min_rest_rooms = 0
	if RunModifierService.has_modifier(RunModifierService.MODIFIER_BARRED_WAYS):
		config.min_locks_per_floor = 2
		config.max_locks_per_floor = 4
	return config


static func _load_pacing() -> Dictionary:
	if not _pacing.is_empty():
		return _pacing
	var data := ContentLoader.load_json(PACING_PATH)
	if data is Dictionary:
		_pacing = data
	return _pacing


static func _apply_multipliers(weights: Dictionary, multipliers: Variant) -> void:
	if not multipliers is Dictionary:
		return
	for key in (multipliers as Dictionary):
		if weights.has(key):
			weights[key] = maxf(0.0, float(weights[key]) * float(multipliers[key]))


static func _roll_theme(pacing: Dictionary, floor_index: int, run_seed: int) -> Dictionary:
	var themes: Variant = pacing.get("floorThemes", [])
	if not themes is Array or (themes as Array).is_empty():
		return {}
	var total := 0.0
	for entry in (themes as Array):
		if entry is Dictionary:
			total += maxf(0.0, float((entry as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMixScript.mix(maxi(1, run_seed), maxi(1, floor_index) * 31 + 7)
	var roll := rng.randf() * total
	var acc := 0.0
	for entry in (themes as Array):
		if not entry is Dictionary:
			continue
		acc += maxf(0.0, float((entry as Dictionary).get("weight", 0.0)))
		if roll < acc:
			return entry
	return (themes as Array)[0]
