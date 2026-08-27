class_name ChallengeService
extends RefCounted


const CATALOG_PATH := "content/challenges/weekly.json"
const META_KEY := "weekly_challenge"
const WEEK_SECONDS := 604800
const SEED_MASK := 0x7fffffff
const SEED_STEP := 2654435761
const SEED_MULTIPLIER := 1103515245
const SEED_INCREMENT := 12345

static var _data: Dictionary = {}
static var _loaded := false


static func clear_cache() -> void:
	_data = {}
	_loaded = false


static func get_rotation() -> Array:
	_ensure_loaded()
	var rotation: Variant = _data.get("rotation", [])
	return rotation if rotation is Array else []


static func epoch_unix() -> int:
	_ensure_loaded()
	return int(_data.get("epochUnix", 0))


static func seed_salt() -> int:
	_ensure_loaded()
	return maxi(1, int(_data.get("seedSalt", 1)))


static func week_index_for(unix_time: int) -> int:
	var elapsed := unix_time - epoch_unix()
	if elapsed < 0:
		return 0
	return floori(elapsed / float(WEEK_SECONDS))


static func current_week_index() -> int:
	return week_index_for(int(Time.get_unix_time_from_system()))


static func week_seed(week_index: int) -> int:
	var value := (seed_salt() + (week_index + 1) * SEED_STEP) & SEED_MASK
	value = (value ^ (value >> 13)) & SEED_MASK
	value = (value * SEED_MULTIPLIER + SEED_INCREMENT) & SEED_MASK
	return maxi(1, value)


static func week_start_unix(week_index: int) -> int:
	return epoch_unix() + week_index * WEEK_SECONDS


static func seconds_remaining(week_index: int) -> int:
	var ends_at := week_start_unix(week_index + 1)
	return maxi(0, ends_at - int(Time.get_unix_time_from_system()))


static func get_challenge_for_week(week_index: int) -> Dictionary:
	var rotation := get_rotation()
	if rotation.is_empty():
		return {}
	var entry: Variant = rotation[week_index % rotation.size()]
	if not entry is Dictionary:
		return {}
	var challenge: Dictionary = (entry as Dictionary).duplicate(true)
	challenge["weekIndex"] = week_index
	challenge["seed"] = week_seed(week_index)
	challenge["endsInSeconds"] = seconds_remaining(week_index)
	return challenge


static func get_active_challenge() -> Dictionary:
	return get_challenge_for_week(current_week_index())


static func describe_rules(challenge: Dictionary) -> String:
	var modifiers: Variant = challenge.get("modifiers", [])
	if not modifiers is Array or (modifiers as Array).is_empty():
		return ""
	return RunModifierService.describe_all(modifiers as Array)


static func scoring_of(challenge: Dictionary) -> String:
	return str(challenge.get("scoring", "time"))


static func score_for(challenge: Dictionary, results: Dictionary) -> int:
	match scoring_of(challenge):
		"depth":
			return int(results.get("floor_reached", 0))
		"kills":
			return int(results.get("kills", 0))
		_:
			return int(results.get("time_seconds", 0.0))


static func lower_is_better(challenge: Dictionary) -> bool:
	return scoring_of(challenge) == "time"


static func get_local_best(week_index: int) -> Dictionary:
	var stored: Variant = LocalSave.get_meta_data().get(META_KEY, {})
	if not stored is Dictionary:
		return {}
	var record: Variant = (stored as Dictionary).get(str(week_index), {})
	return record if record is Dictionary else {}


static func record_result(challenge: Dictionary, results: Dictionary) -> Dictionary:
	if challenge.is_empty():
		return {}
	var week_index := int(challenge.get("weekIndex", current_week_index()))
	var outcome := str(results.get("outcome", ""))
	var completed := outcome != "died" and outcome != "waves_failed"
	var score := score_for(challenge, results)
	if scoring_of(challenge) == "time" and not completed:
		score = 0
	var previous := get_local_best(week_index)
	var improved := previous.is_empty()
	if not improved and score > 0:
		var old_score := int(previous.get("score", 0))
		if lower_is_better(challenge):
			improved = old_score <= 0 or score < old_score
		else:
			improved = score > old_score
	if score <= 0 and not previous.is_empty():
		improved = false
	var record := previous
	if improved:
		record = {
			"challengeId": str(challenge.get("id", "")),
			"scoring": scoring_of(challenge),
			"standard": bool(challenge.get("standard", true)),
			"score": score,
			"completed": completed,
			"floorReached": int(results.get("floor_reached", 0)),
			"kills": int(results.get("kills", 0)),
			"timeSeconds": float(results.get("time_seconds", 0.0)),
			"recordedAt": int(Time.get_unix_time_from_system()),
		}
		var meta := LocalSave.get_meta_data()
		var stored: Variant = meta.get(META_KEY, {})
		var table: Dictionary = stored if stored is Dictionary else {}
		table[str(week_index)] = record
		_trim(table, week_index)
		meta[META_KEY] = table
		LocalSave.set_meta_data(meta)
		LocalSave.autosave()
	return {"improved": improved, "score": score, "best": record, "previous": previous}


static func format_score(challenge: Dictionary, score: int) -> String:
	if score <= 0:
		return "--"
	match scoring_of(challenge):
		"depth":
			return "floor %d" % score
		"kills":
			return "%d slain" % score
		_:
			return "%d:%02d" % [floori(score / 60.0), score % 60]


static func format_remaining(seconds: int) -> String:
	if seconds <= 0:
		return "closing"
	var days := floori(seconds / 86400.0)
	var hours := floori((seconds % 86400) / 3600.0)
	if days > 0:
		return "%dd %dh left" % [days, hours]
	var minutes := floori((seconds % 3600) / 60.0)
	return "%dh %dm left" % [hours, minutes]


static func _trim(table: Dictionary, current_index: int) -> void:
	var cutoff := current_index - 8
	for key in table.keys():
		if str(key).is_valid_int() and int(key) < cutoff:
			table.erase(key)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Variant = ContentLoader.load_json(CATALOG_PATH)
	if not data is Dictionary:
		push_warning("ChallengeService: missing %s" % CATALOG_PATH)
		return
	_data = data as Dictionary
