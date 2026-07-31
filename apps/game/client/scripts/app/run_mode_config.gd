extends RefCounted
class_name RunModeConfig

## Run mode identifiers for castle, Umbral Endless, and Umbral Waves.

const MODE_CASTLE := "castle"
const MODE_ENDLESS := "endless"
const MODE_WAVES := "waves"

const ALL_MODES: Array[String] = [MODE_CASTLE, MODE_ENDLESS, MODE_WAVES]


static func is_endless(run_mode: String) -> bool:
	return run_mode == MODE_ENDLESS


static func is_waves(run_mode: String) -> bool:
	return run_mode == MODE_WAVES


static func is_multi_floor(run_mode: String) -> bool:
	return run_mode == MODE_CASTLE or run_mode == MODE_ENDLESS
