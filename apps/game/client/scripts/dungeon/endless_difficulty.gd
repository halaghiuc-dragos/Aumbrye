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

## The Waning.
##
## The soft caps above are hard caps: past the knee the curve flattens and stops. A build that
## beats 4.5x health and 3x damage could descend forever, which is why the Long Dark had no arc —
## it was mathematically survivable without limit, so there was never a reason to stop, and
## "how deep can you go" collapsed into "when do you get bored".
##
## Beyond `WANE_FLOOR` an unbounded linear term is added on top of the capped curve. Every run now
## ends eventually. The rates are deliberately gentle: the curve below floor 150 is unchanged, so
## none of the existing tuning moves, and a strong build still reaches the floor-500 milestone.
const WANE_FLOOR := 150
const WANE_HP_PER_FLOOR := 0.02
const WANE_DAMAGE_PER_FLOOR := 0.012


static func wane_progress(floor_index: int) -> int:
	return maxi(0, maxi(1, floor_index) - WANE_FLOOR)


static func hp_multiplier(floor_index: int) -> float:
	var floor_clamped := maxi(1, floor_index)
	var waning := float(wane_progress(floor_clamped)) * WANE_HP_PER_FLOOR
	if floor_clamped <= HP_KNEE_FLOOR:
		return 1.0 + float(floor_clamped - 1) * HP_GROWTH_PER_FLOOR + waning
	var knee := 1.0 + float(HP_KNEE_FLOOR - 1) * HP_GROWTH_PER_FLOOR
	var tail := float(floor_clamped - HP_KNEE_FLOOR) / TAIL_FLOOR_SPAN
	return minf(HP_SOFT_CAP, knee + log(tail + 1.0) * HP_TAIL_RATE) + waning


static func damage_multiplier(floor_index: int) -> float:
	var floor_clamped := maxi(1, floor_index)
	var waning := float(wane_progress(floor_clamped)) * WANE_DAMAGE_PER_FLOOR
	if floor_clamped <= DAMAGE_KNEE_FLOOR:
		return 1.0 + float(floor_clamped - 1) * DAMAGE_GROWTH_PER_FLOOR + waning
	var knee := 1.0 + float(DAMAGE_KNEE_FLOOR - 1) * DAMAGE_GROWTH_PER_FLOOR
	var tail := float(floor_clamped - DAMAGE_KNEE_FLOOR) / TAIL_FLOOR_SPAN
	return minf(DAMAGE_SOFT_CAP, knee + log(tail + 1.0) * DAMAGE_TAIL_RATE) + waning


## Player-facing read on how far past the light the run has gone. Shown at the stair so the
## decision to bank the run is an informed one rather than a guess.
static func describe_pressure(floor_index: int) -> String:
	var wane := wane_progress(floor_index)
	if wane <= 0:
		return ""
	return (
		"The Waning: %d floors past the light — foes at %.1fx health, %.1fx damage."
		% [wane, hp_multiplier(floor_index), damage_multiplier(floor_index)]
	)


static func rare_drop_bonus(floor_index: int) -> float:
	var floors := float(maxi(0, floor_index - 1))
	var per_floor := RunFloorConfig.DROP_RATE_BONUS_PER_TIER / 10.0
	return minf(floors * per_floor, RunFloorConfig.DROP_RATE_BONUS_CAP)


static func behaviour_progress(floor_index: int) -> float:
	return clampf(float(maxi(1, floor_index) - 1) / BEHAVIOUR_FULL_FLOOR, 0.0, 1.0)
