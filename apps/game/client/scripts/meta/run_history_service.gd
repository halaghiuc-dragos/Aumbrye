class_name RunHistoryService
extends RefCounted

## Account-scoped log of the last runs, with the personal bests the results screen compares against.

const META_KEY := "run_history"
const MAX_RUNS := 20
const TREND_WINDOW := 5

const OUTCOME_DIED := "died"
const OUTCOME_WAVES_FAILED := "waves_failed"


static func get_runs() -> Array:
	var stored: Variant = LocalSave.get_meta_data().get(META_KEY, {})
	if not stored is Dictionary:
		return []
	var runs: Variant = (stored as Dictionary).get("runs", [])
	if not runs is Array:
		return []
	var out: Array = []
	for entry in runs as Array:
		if entry is Dictionary:
			out.append(entry)
	return out


static func run_count() -> int:
	return get_runs().size()


static func clear() -> void:
	var meta := LocalSave.get_meta_data()
	meta.erase(META_KEY)
	LocalSave.set_meta_data(meta)


static func build_entry(results: Dictionary) -> Dictionary:
	var highlights: Variant = results.get("highlights", {})
	var highlight_dict: Dictionary = highlights if highlights is Dictionary else {}
	return {
		"outcome": str(results.get("outcome", "")),
		"runMode": str(results.get("run_mode", "castle")),
		"modeId": str(results.get("alternate_mode", "")),
		"challengeId": str(results.get("challenge_id", "")),
		"dungeonId": str(results.get("dungeon_id", "")),
		"difficultyTier": int(results.get("difficulty_tier", 1)),
		"floorReached": int(results.get("floor_reached", 0)),
		"kills": int(results.get("kills", 0)),
		"timeSeconds": float(results.get("time_seconds", 0.0)),
		"xpGained": int(results.get("xp_gained", 0)),
		"seed": int(results.get("seed", 0)),
		"bossDefeated": bool(results.get("boss_defeated", false)),
		"topRelic": str(highlight_dict.get("topRelic", "")),
		"topRelicProcs": int(highlight_dict.get("topRelicProcs", 0)),
		"offersTaken": int(highlight_dict.get("offersTaken", 0)),
		"trapCatches": int(highlight_dict.get("trapCatches", 0)),
		"recordedAt": int(Time.get_unix_time_from_system()),
	}


## Prepends the finished run and trims to the retained window. Returns the stored entry.
static func record(results: Dictionary) -> Dictionary:
	var entry := build_entry(results)
	var runs := get_runs()
	runs.push_front(entry)
	while runs.size() > MAX_RUNS:
		runs.pop_back()
	var meta := LocalSave.get_meta_data()
	meta[META_KEY] = {"runs": runs}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()
	return entry


static func _is_success(entry: Dictionary) -> bool:
	var outcome := str(entry.get("outcome", ""))
	return outcome != OUTCOME_DIED and outcome != OUTCOME_WAVES_FAILED


static func _matches(entry: Dictionary, scope: Dictionary) -> bool:
	for key in scope:
		if str(entry.get(key, "")) != str(scope[key]):
			return false
	return true


static func runs_for(scope: Dictionary, skip_newest: bool = false) -> Array:
	var runs := get_runs()
	if skip_newest and not runs.is_empty():
		runs.pop_front()
	var out: Array = []
	for entry in runs:
		if _matches(entry, scope):
			out.append(entry)
	return out


static func best_depth(scope: Dictionary, skip_newest: bool = false) -> int:
	var best := 0
	for entry in runs_for(scope, skip_newest):
		best = maxi(best, int(entry.get("floorReached", 0)))
	return best


static func best_kills(scope: Dictionary, skip_newest: bool = false) -> int:
	var best := 0
	for entry in runs_for(scope, skip_newest):
		best = maxi(best, int(entry.get("kills", 0)))
	return best


## Fastest successful run in scope, or 0.0 when none has been finished yet.
static func best_time(scope: Dictionary, skip_newest: bool = false) -> float:
	var best := 0.0
	for entry in runs_for(scope, skip_newest):
		if not _is_success(entry):
			continue
		var seconds := float(entry.get("timeSeconds", 0.0))
		if seconds <= 0.0:
			continue
		if best <= 0.0 or seconds < best:
			best = seconds
	return best


## Share of the recent window that ended in success, as a 0..1 ratio, or -1.0 when too few runs.
static func recent_success_rate(scope: Dictionary) -> float:
	var window := runs_for(scope)
	if window.size() > TREND_WINDOW:
		window = window.slice(0, TREND_WINDOW)
	if window.size() < 2:
		return -1.0
	var wins := 0
	for entry in window:
		if _is_success(entry):
			wins += 1
	return float(wins) / float(window.size())


## Compares the run that was just recorded against everything before it.
static func summarize(results: Dictionary) -> Dictionary:
	var scope := {"runMode": str(results.get("run_mode", "castle"))}
	var mode_id := str(results.get("alternate_mode", ""))
	if mode_id != "":
		scope["modeId"] = mode_id
	var previous_depth := best_depth(scope, true)
	var previous_time := best_time(scope, true)
	var previous_kills := best_kills(scope, true)
	var depth := int(results.get("floor_reached", 0))
	var kills := int(results.get("kills", 0))
	var seconds := float(results.get("time_seconds", 0.0))
	var outcome := str(results.get("outcome", ""))
	var success := outcome != OUTCOME_DIED and outcome != OUTCOME_WAVES_FAILED
	return {
		"runsRecorded": runs_for(scope).size(),
		"previousBestDepth": previous_depth,
		"previousBestKills": previous_kills,
		"previousBestTime": previous_time,
		"depthIsBest": depth > previous_depth,
		"killsIsBest": kills > previous_kills,
		"timeIsBest": success and seconds > 0.0 and (previous_time <= 0.0 or seconds < previous_time),
		"successRate": recent_success_rate(scope),
	}
