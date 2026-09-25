extends RefCounted
class_name WavesDifficulty


const HP_PER_WAVE := 0.08
const DAMAGE_PER_WAVE := 0.06

const HP_CAP := 4.5
const DAMAGE_CAP := 3.0


static func hp_multiplier(wave_index: int) -> float:
	return minf(HP_CAP, 1.0 + maxi(0, wave_index - 1) * HP_PER_WAVE)


static func damage_multiplier(wave_index: int) -> float:
	return minf(DAMAGE_CAP, 1.0 + maxi(0, wave_index - 1) * DAMAGE_PER_WAVE)


static func effective_hp_multiplier(wave_index: int, modifier_factor: float = 1.0) -> float:
	return minf(HP_CAP, hp_multiplier(wave_index) * maxf(0.0, modifier_factor))


static func effective_damage_multiplier(wave_index: int, modifier_factor: float = 1.0) -> float:
	return minf(DAMAGE_CAP, damage_multiplier(wave_index) * maxf(0.0, modifier_factor))
