extends RefCounted
class_name RunLifecycle

## Unified run outcome assembly for RunFlow (escape / death / waves / respawn).

const OUTCOME_ESCAPED := "escaped"
const OUTCOME_DIED := "died"
const OUTCOME_RESPAWNED := "respawned"
const OUTCOME_RETREATED := "retreated"
const OUTCOME_ABANDONED := "abandoned"
const OUTCOME_WAVES_COMPLETE := "waves_complete"
const OUTCOME_WAVES_FAILED := "waves_failed"


static func build_results(
	outcome: String,
	elapsed: float,
	kill_count: int,
	loot_collected: Array,
	xp_result: Dictionary,
	full_xp: int,
	rules_summary: String,
	extra: Dictionary = {}
) -> Dictionary:
	var loot_lost: Array = []
	var loot_lost_raw: Variant = extra.get("loot_lost", [])
	if loot_lost_raw is Array:
		for item in loot_lost_raw:
			loot_lost.append(str(item))
	var loot: Array = []
	for item in loot_collected:
		loot.append(str(item))
	var loot_kept: bool = bool(extra.get("loot_kept", loot_lost.is_empty()))
	return {
		"outcome": outcome,
		"run_mode": str(extra.get("run_mode", "castle")),
		"time_seconds": elapsed,
		"kills": kill_count,
		"loot": loot,
		"loot_lost": loot_lost,
		"xp_gained": int(xp_result.get("gained", 0)),
		"xp_full_would_be": full_xp,
		"xp_deferred": int(extra.get("xp_deferred", 0)),
		"levels_gained": int(xp_result.get("levels_gained", 0)),
		"loot_kept": loot_kept,
		"run_relics_lost": bool(extra.get("run_relics_lost", false)),
		"floor_reached": int(extra.get("floor_reached", 1)),
		"boss_defeated": bool(extra.get("boss_defeated", false)),
		"cloud_synced": bool(extra.get("cloud_synced", false)),
		"rules_summary": rules_summary,
	}
