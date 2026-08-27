extends RefCounted
class_name EndlessDifficulty


const HP_SOFT_CAP := 4.5
const HP_GROWTH_PER_FLOOR := 0.014
const HP_KNEE_FLOOR := 120
const HP_TAIL_RATE := 0.6
const DAMAGE_SOFT_CAP := 3.0
const DAMAGE_GROWTH_PER_FLOOR := 0.011
const DAMAGE_KNEE_FLOOR := 120
const DAMAGE_TAIL_RATE := 0.35
const TAIL_FLOOR_SPAN := 10.0

const BEHAVIOUR_FULL_FLOOR := 200.0
const COOLDOWN_FLOOR_MULT := 0.75
const MOVE_SPEED_FLOOR_MULT := 1.16


static func hp_multiplier(floor_index: int) -> float:
	var floor_clamped := maxi(1, floor_index)
	if floor_clamped <= HP_KNEE_FLOOR:
		return 1.0 + float(floor_clamped - 1) * HP_GROWTH_PER_FLOOR
	var knee := 1.0 + float(HP_KNEE_FLOOR - 1) * HP_GROWTH_PER_FLOOR
	var tail := float(floor_clamped - HP_KNEE_FLOOR) / TAIL_FLOOR_SPAN
	return minf(HP_SOFT_CAP, knee + log(tail + 1.0) * HP_TAIL_RATE)


static func damage_multiplier(floor_index: int) -> float:
	var floor_clamped := maxi(1, floor_index)
	if floor_clamped <= DAMAGE_KNEE_FLOOR:
		return 1.0 + float(floor_clamped - 1) * DAMAGE_GROWTH_PER_FLOOR
	var knee := 1.0 + float(DAMAGE_KNEE_FLOOR - 1) * DAMAGE_GROWTH_PER_FLOOR
	var tail := float(floor_clamped - DAMAGE_KNEE_FLOOR) / TAIL_FLOOR_SPAN
	return minf(DAMAGE_SOFT_CAP, knee + log(tail + 1.0) * DAMAGE_TAIL_RATE)


static func rare_drop_bonus(floor_index: int) -> float:
	var floors := float(maxi(0, floor_index - 1))
	var per_floor := RunFloorConfig.DROP_RATE_BONUS_PER_TIER / 10.0
	return minf(floors * per_floor, RunFloorConfig.DROP_RATE_BONUS_CAP)


static func behaviour_progress(floor_index: int) -> float:
	return clampf(float(maxi(1, floor_index) - 1) / BEHAVIOUR_FULL_FLOOR, 0.0, 1.0)
