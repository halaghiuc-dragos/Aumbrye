extends RefCounted
class_name WavesDifficulty

## Scaling for Umbral Waves using the current wave index.

const HP_PER_WAVE := 0.08
const DAMAGE_PER_WAVE := 0.06


static func hp_multiplier(wave_index: int) -> float:
	return 1.0 + maxi(0, wave_index - 1) * HP_PER_WAVE


static func damage_multiplier(wave_index: int) -> float:
	return 1.0 + maxi(0, wave_index - 1) * DAMAGE_PER_WAVE
