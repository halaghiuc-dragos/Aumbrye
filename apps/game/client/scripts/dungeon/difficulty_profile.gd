extends RefCounted
class_name DifficultyProfile

## Common interface over "how much stronger are enemies here" for the three run
## modes. Each mode keeps its own scaling shape — castle reads catalog tiers, endless uses a
## continuous per-floor curve with a knee and a soft cap, waves is flat-linear — but consumers
## (DungeonBuilder, GlobalDropService) no longer need to branch on run mode themselves: they ask
## `DifficultyProfile.for_run(...)` for a profile bound to the current dungeon/tier and then call
## the same methods regardless of mode.
##
## Numbers are only half of it. `behaviour_modifiers()` returns the same profile expressed as
## reaction speed and aggression, so a deeper floor is a faster fight rather than a longer one.

const EndlessDifficultyScript := preload("res://scripts/dungeon/endless_difficulty.gd")
const CastleTierDifficultyScript := preload("res://scripts/dungeon/castle_tier_difficulty.gd")
const WavesDifficultyScript := preload("res://scripts/dungeon/waves_difficulty.gd")
const RunModifierServiceScript := preload("res://scripts/dungeon/run_modifier_service.gd")

const COOLDOWN_AT_FULL_PRESSURE := 0.72
const MOVE_SPEED_AT_FULL_PRESSURE := 1.15
const COOLDOWN_MULT_FLOOR := 0.5
const COOLDOWN_MULT_CEILING := 1.5
const MOVE_SPEED_MULT_FLOOR := 0.75
const MOVE_SPEED_MULT_CEILING := 1.4
const WAVES_FULL_PRESSURE_WAVE := 40.0


## `progress` is the mode's natural counter: floor index for castle/endless, wave index for waves.
func hp_multiplier(_progress: int) -> float:
	return 1.0


func damage_multiplier(_progress: int) -> float:
	return 1.0


func rare_drop_bonus(_progress: int) -> float:
	return 0.0


## 0..1 — how far into this mode's difficulty range the run currently sits.
func pressure(_progress: int) -> float:
	return 0.0


## Reserved for future data-driven difficulty modifiers (e.g. "enrage", "double spawns"); none of
## the three curves currently attach any, so every profile returns an empty list today.
func modifiers(_progress: int) -> Array[String]:
	return []


## Multipliers over an enemy's own tuning, shaped for `apply_phase_modifiers()`. Damage is left
## out on purpose: it is already carried by `damage_multiplier()` and would double up here.
func behaviour_modifiers(progress: int) -> Dictionary:
	var p := pressure(progress)
	var cooldown := lerpf(1.0, COOLDOWN_AT_FULL_PRESSURE, p)
	var move_speed := lerpf(1.0, MOVE_SPEED_AT_FULL_PRESSURE, p)
	if RunModifierServiceScript.has_modifier(RunModifierServiceScript.MODIFIER_ARMOURED_FOES):
		cooldown *= 1.12
		move_speed *= 0.92
	if RunModifierServiceScript.has_modifier(RunModifierServiceScript.MODIFIER_FRENZIED_FOES):
		cooldown *= 0.75
	if RunModifierServiceScript.has_modifier(RunModifierServiceScript.MODIFIER_RELENTLESS_FOES):
		move_speed *= 1.18
	return {
		"attackCooldownMult":
		clampf(cooldown, COOLDOWN_MULT_FLOOR, COOLDOWN_MULT_CEILING),
		"moveSpeedMult":
		clampf(move_speed, MOVE_SPEED_MULT_FLOOR, MOVE_SPEED_MULT_CEILING),
	}


static func modifier_hp_factor() -> float:
	var factor := 1.0
	if RunModifierServiceScript.has_modifier(RunModifierServiceScript.MODIFIER_ARMOURED_FOES):
		factor *= 1.25
	if RunModifierServiceScript.has_modifier(RunModifierServiceScript.MODIFIER_VOLATILE_FOES):
		factor *= 0.85
	return factor


static func modifier_damage_factor() -> float:
	var factor := 1.0
	if RunModifierServiceScript.has_modifier(RunModifierServiceScript.MODIFIER_ARMOURED_FOES):
		factor *= 0.92
	if RunModifierServiceScript.has_modifier(RunModifierServiceScript.MODIFIER_VOLATILE_FOES):
		factor *= 1.3
	return factor


static func for_run(run_mode: String, dungeon_id: String = "", tier: int = 1) -> DifficultyProfile:
	match run_mode:
		"endless":
			return EndlessDifficultyProfile.new()
		"waves":
			return WavesDifficultyProfile.new()
		_:
			return CastleTierDifficultyProfile.new(dungeon_id, tier)


class EndlessDifficultyProfile:
	extends DifficultyProfile

	func hp_multiplier(progress: int) -> float:
		return EndlessDifficultyScript.hp_multiplier(progress) * modifier_hp_factor()

	func damage_multiplier(progress: int) -> float:
		return EndlessDifficultyScript.damage_multiplier(progress) * modifier_damage_factor()

	func rare_drop_bonus(progress: int) -> float:
		return EndlessDifficultyScript.rare_drop_bonus(progress)

	func pressure(progress: int) -> float:
		return EndlessDifficultyScript.behaviour_progress(progress)


class CastleTierDifficultyProfile:
	extends DifficultyProfile

	var _dungeon_id: String
	var _tier: int

	func _init(dungeon_id: String, tier: int) -> void:
		_dungeon_id = dungeon_id
		_tier = tier

	func hp_multiplier(progress: int) -> float:
		return (
			CastleTierDifficultyScript.combined_hp_multiplier(_dungeon_id, _tier, progress)
			* modifier_hp_factor()
		)

	func damage_multiplier(progress: int) -> float:
		return (
			CastleTierDifficultyScript.combined_damage_multiplier(_dungeon_id, _tier, progress)
			* modifier_damage_factor()
		)

	func rare_drop_bonus(_progress: int) -> float:
		return CastleTierDifficultyScript.loot_bonus(_dungeon_id, _tier)

	func pressure(progress: int) -> float:
		return CastleTierDifficultyScript.behaviour_progress(_dungeon_id, _tier, progress)


class WavesDifficultyProfile:
	extends DifficultyProfile

	func hp_multiplier(progress: int) -> float:
		return WavesDifficultyScript.hp_multiplier(progress)

	func damage_multiplier(progress: int) -> float:
		return WavesDifficultyScript.damage_multiplier(progress)

	func pressure(progress: int) -> float:
		return clampf(float(maxi(1, progress) - 1) / WAVES_FULL_PRESSURE_WAVE, 0.0, 1.0)
