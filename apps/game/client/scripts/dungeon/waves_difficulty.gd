extends RefCounted
class_name WavesDifficulty

## Scaling for Umbral Waves using the current wave index.

const HP_PER_WAVE := 0.08
const DAMAGE_PER_WAVE := 0.06

## C-198: waves scaled purely linearly with no knee and no ceiling, while both sibling modes cap —
## castle at 4.0 HP / 2.6 damage, endless at 4.5 / 3.0 with a log tail past floor 120. At the
## intended wave-50 ending waves already reaches 4.92x HP and 3.94x damage, past the value the
## project chose elsewhere as "as hard as an enemy should ever hit", and it stopped there only
## because the run was supposed to end. C-191 (the hardcoded 50) was what guaranteed that, and the
## two defects compounded: one removed the terminator, the other had no ceiling, so a milestone list
## ending at 200 would have reached 16.9x HP and 12.9x damage.
##
## Capped at the endless values, which are the more permissive of the two siblings — waves is the
## endurance mode, so it should be allowed to reach the harder ceiling, not to pass it. A cap is
## correct on its own merits and does not depend on another file's literal.
const HP_CAP := 4.5
const DAMAGE_CAP := 3.0


static func hp_multiplier(wave_index: int) -> float:
	return minf(HP_CAP, 1.0 + maxi(0, wave_index - 1) * HP_PER_WAVE)


static func damage_multiplier(wave_index: int) -> float:
	return minf(DAMAGE_CAP, 1.0 + maxi(0, wave_index - 1) * DAMAGE_PER_WAVE)
