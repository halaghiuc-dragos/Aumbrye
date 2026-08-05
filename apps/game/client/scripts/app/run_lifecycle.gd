extends RefCounted
class_name RunLifecycle

## Run outcome assembly extracted from RunFlow (escape / death reporting).


static func build_escape_results(
	elapsed: float,
	kill_count: int,
	loot_collected: Array,
	xp_result: Dictionary,
	rules_summary: String
) -> Dictionary:
	return {
		"outcome": "escaped",
		"time_seconds": elapsed,
		"kills": kill_count,
		"loot": loot_collected.duplicate(),
		"xp_gained": xp_result.get("gained", 0),
		"levels_gained": xp_result.get("levels_gained", 0),
		"loot_kept": true,
		"run_relics_lost": false,
		"rules_summary": rules_summary,
	}


static func build_death_results(
	elapsed: float,
	kill_count: int,
	loot_collected: Array,
	xp_result: Dictionary,
	full_xp: int,
	rules_summary: String
) -> Dictionary:
	return {
		"outcome": "died",
		"time_seconds": elapsed,
		"kills": kill_count,
		"loot": loot_collected.duplicate(),
		"xp_gained": xp_result.get("gained", 0),
		"xp_full_would_be": full_xp,
		"levels_gained": xp_result.get("levels_gained", 0),
		"loot_kept": false,
		"run_relics_lost": true,
		"rules_summary": rules_summary,
	}
